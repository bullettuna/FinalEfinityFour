"""Image5 FT245 D2XX receiver. No EEPROM writes and no FT_Write calls."""
from __future__ import annotations
import argparse
import ctypes as C
import dataclasses
import json
import os
import queue
import threading
from pathlib import Path
import struct
import time
import zlib

MAGIC = b"FT5!"
HEADER = struct.Struct("<4sBBBBIHHII")

@dataclasses.dataclass
class Frame:
    kind: int
    sequence: int
    width: int
    height: int
    payload: bytes

class Parser:
    def __init__(self):
        self.buffer = bytearray()
        self.bad_headers = self.bad_payloads = self.discarded = 0

    def feed(self, chunk):
        self.buffer.extend(chunk)
        frames = []
        while True:
            at = self.buffer.find(MAGIC)
            if at < 0:
                count = max(0, len(self.buffer) - 3)
                self.discarded += count
                del self.buffer[:count]
                break
            if at:
                self.discarded += at
                del self.buffer[:at]
            if len(self.buffer) < HEADER.size:
                break
            magic, version, kind, flags, size, seq, w, h, length, crc = HEADER.unpack_from(self.buffer)
            if (version != 1 or kind > 3 or flags or size != 24 or
                not 0 < length <= 2_073_600 or
                (kind == 0 and (w or h or length != 4096)) or (kind != 0 and (not w or not h or ((w+7)//8*h if kind==3 else w*h) != length)) or
                zlib.crc32(self.buffer[:20]) != crc):
                self.bad_headers += 1
                del self.buffer[0]
                continue
            total = 24 + length + 4
            if len(self.buffer) < total:
                break
            payload = bytes(self.buffer[24:24+length])
            if zlib.crc32(payload) != struct.unpack_from("<I", self.buffer, 24+length)[0]:
                self.bad_payloads += 1
                del self.buffer[0]
                continue
            frames.append(Frame(kind, seq, w, h, payload))
            del self.buffer[:total]
        return frames

class D2XX:
    def __init__(self):
        if os.name != "nt":
            raise RuntimeError("Live D2XX capture requires Windows; offline --self-test/--input are portable")
        self.dll = C.WinDLL(str(Path(os.environ.get("SystemRoot", "C:/Windows"))/"System32/ftd2xx.dll"))
        specs = {
            "FT_CreateDeviceInfoList": [C.POINTER(C.c_ulong)],
            "FT_GetDeviceInfoDetail": [C.c_ulong]+[C.POINTER(C.c_ulong)]*4+[C.c_void_p,C.c_void_p,C.POINTER(C.c_void_p)],
            "FT_OpenEx": [C.c_void_p,C.c_ulong,C.POINTER(C.c_void_p)],
            "FT_Close": [C.c_void_p],
            "FT_SetBitMode": [C.c_void_p,C.c_ubyte,C.c_ubyte],
            "FT_SetUSBParameters": [C.c_void_p,C.c_ulong,C.c_ulong],
            "FT_SetTimeouts": [C.c_void_p,C.c_ulong,C.c_ulong],
            "FT_SetLatencyTimer": [C.c_void_p,C.c_ubyte],
            "FT_Purge": [C.c_void_p,C.c_ulong],
            "FT_Read": [C.c_void_p,C.c_void_p,C.c_ulong,C.POINTER(C.c_ulong)],
            "FT_ReadEE": [C.c_void_p,C.c_ulong,C.POINTER(C.c_ushort)],
        }
        for name, args in specs.items():
            fn = getattr(self.dll, name)
            fn.argtypes, fn.restype = args, C.c_ulong

    def call(self, name, *args):
        status = getattr(self.dll, name)(*args)
        if status:
            raise RuntimeError(f"{name}: D2XX status {status}")

    def devices(self):
        count = C.c_ulong()
        self.call("FT_CreateDeviceInfoList", C.byref(count))
        result = []
        for i in range(count.value):
            flags, kind, identity, location = (C.c_ulong() for _ in range(4))
            serial, description, handle = C.create_string_buffer(16), C.create_string_buffer(64), C.c_void_p()
            self.call("FT_GetDeviceInfoDetail", i, C.byref(flags), C.byref(kind), C.byref(identity), C.byref(location), serial, description, C.byref(handle))
            result.append(dict(type=kind.value, serial=serial.value.decode(), description=description.value.decode(), flags=flags.value))
        return result

    def open(self, serial):
        candidates = [d for d in self.devices() if d["serial"] == serial and d["type"] == 8]
        if len(candidates) != 1:
            raise RuntimeError("Specify exactly one enumerated FT232H serial (type 8); never open a downloader by index")
        handle = C.c_void_p()
        self.call("FT_OpenEx", C.cast(C.c_char_p(serial.encode()), C.c_void_p), 1, C.byref(handle))
        return handle

def check_frame(frame):
    if frame.kind == 0:
        expected = (bytes(range(256))*((len(frame.payload)+255)//256))[:len(frame.payload)]
        if frame.payload != expected:
            raise RuntimeError(f"Counter payload mismatch in frame {frame.sequence}")
    elif frame.kind == 2 and any(v not in (0,255) for v in frame.payload):
        raise RuntimeError("Edge payload contains a non-binary value")

    elif frame.kind == 3 and frame.width%8:
        # Padding belongs to each row and must be zero, never spill into the
        # next row. Current FPGA widths are all byte aligned.
        row_bytes=(frame.width+7)//8
        mask=(1<<(8-frame.width%8))-1
        if any(frame.payload[(y+1)*row_bytes-1]&mask for y in range(frame.height)):
            raise RuntimeError("Packed edge row contains nonzero padding")

_EDGE_BYTES=tuple(bytes(255 if b&(1<<(7-i)) else 0 for i in range(8)) for b in range(256))

def image_bytes(frame):
    """Return 8-bit display/PGM pixels; wire kind=3 remains packed in Frame."""
    if frame.kind in (1,2):return frame.payload
    if frame.kind!=3:raise RuntimeError("Counter packet has no image")
    if frame.width%8==0:return b"".join(_EDGE_BYTES[b] for b in frame.payload)
    stride=(frame.width+7)//8
    return b"".join(b"".join(_EDGE_BYTES[b] for b in frame.payload[y*stride:(y+1)*stride])[:frame.width] for y in range(frame.height))


def serial_command(port, command, expected):
    port.reset_input_buffer()
    port.write(command)
    port.flush()
    reply = port.read(1)
    if reply != expected:
        if command==b"!P":
            raise RuntimeError("Firmware does not confirm packing capability (!P=1); download the new image5 bit before selecting edge format")
        raise RuntimeError(f"UART {command!r} replied {reply!r}, expected {expected!r}; !?=N means internal asynchronous logic is not ready")

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--transport", choices=["async"], help="Required for live capture; replaces the synchronous version")
    ap.add_argument("--width", type=int, choices=[320,640,1920], default=320)
    ap.add_argument("--fifo-eeprom-confirmed", action="store_true", help="FT_PROG readback confirmed FT245 FIFO in this module EEPROM")
    ap.add_argument("--stopped-confirmed", action="store_true", help="Without --uart: confirms !V=A and completed !0=0 before mode setup")
    ap.add_argument("--serial", help="Exact FT232H serial; never a COM name")
    ap.add_argument("--uart", help="Separate existing FPGA control UART COM port (optional; needs pyserial)")
    ap.add_argument("--mode", choices=["counter","gray","edge"], default="counter")
    ap.add_argument("--edge-format", choices=["packed","byte"], default="packed", help="Packed 1bpp (default) or legacy 8bpp edge payload")
    ap.add_argument("--seconds", type=float, default=10)
    ap.add_argument("--save-last", type=Path, help="Save final valid image as PGM")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--input", type=Path, help="Validate a previously captured stream, including RTL simulation output")
    ap.add_argument("--eeprom-backup", type=Path, help="Read first 128 EEPROM words to JSON; does not change configuration")
    args = ap.parse_args()
    if args.seconds <= 0:
        ap.error("--seconds must be positive")
    parser = Parser()
    received = frames = payload_bytes = 0
    last = None
    previous = None
    gaps = 0
    gui = None
    if args.preview:
        import tkinter as tk
        gui = tk.Tk()
        gui.title("image5 FT232H — CRC checked snapshots")
        label = tk.Label(gui)
        label.pack()
    started = time.monotonic()
    def consume(chunk):
        nonlocal received, frames, last, previous, gaps, payload_bytes
        received += len(chunk)
        for frame in parser.feed(chunk):
            check_frame(frame)
            if not args.input:
                expected_kind={"counter":0,"gray":1,"edge":3 if args.edge_format=="packed" else 2}[args.mode]
                if frame.kind!=expected_kind or (frame.kind and (frame.width!=args.width or frame.height!=args.width*9//16)):
                    raise RuntimeError("Received mode/edge format/dimensions differ from selection; stop and restart the session")
            payload_bytes+=len(frame.payload)
            if previous is not None and frame.sequence != (previous+1)&0xffffffff:
                gaps += 1
            previous = frame.sequence
            frames += 1
            last = frame
            if gui is not None and frame.kind:
                label.image = tk.PhotoImage(data=f"P5\n{frame.width} {frame.height}\n255\n".encode()+image_bytes(frame))
                factor=max(1,(frame.width+959)//960,(frame.height+539)//540)
                if factor>1: label.image=label.image.subsample(factor,factor)
                label.configure(image=label.image)
            if gui is not None:
                gui.update()
    if args.input:
        with args.input.open("rb") as f:
            while chunk := f.read(997):
                consume(chunk)
    else:
        api = D2XX()
        if args.list:
            print(json.dumps(api.devices(), indent=2))
            return
        if not args.serial:
            ap.error("Use --list then choose --serial; no automatic index-0 selection")
        if args.transport!="async": ap.error("Live capture requires --transport async")
        if not args.fifo_eeprom_confirmed:
            ap.error("Confirm FT245 FIFO EEPROM readback, then add --fifo-eeprom-confirmed")
        if not args.uart and not args.stopped_confirmed:
            ap.error("Manually query !V=A and wait for !0=0, then add --stopped-confirmed")
        port = handle = worker = None
        quit_reader=threading.Event();chunks=queue.Queue(maxsize=16)
        def read_usb():
            storage=C.create_string_buffer(4096)
            try:
                while not quit_reader.is_set():
                    count=C.c_ulong();api.call("FT_Read",handle,storage,len(storage),C.byref(count))
                    if count.value:
                        item=storage.raw[:count.value]
                        while not quit_reader.is_set():
                            try: chunks.put(item,timeout=.05);break
                            except queue.Full: pass
            except Exception as error:
                while not quit_reader.is_set():
                    try: chunks.put(error,timeout=.05);break
                    except queue.Full: pass
        try:
            if args.uart:
                import serial
                port=serial.Serial(args.uart,115200,timeout=2)
                serial_command(port,b"!V",b"A")
                if args.mode=="edge":serial_command(port,b"!P",b"1")
                serial_command(port,b"!0",b"0")
            handle=api.open(args.serial)
            if args.eeprom_backup:
                words=[]
                for i in range(128):
                    value=C.c_ushort();api.call("FT_ReadEE",handle,i,C.byref(value));words.append(value.value)
                with args.eeprom_backup.open("x",encoding="utf-8") as f:
                    json.dump(dict(serial=args.serial,words=words),f,indent=2)
            # Restore EEPROM-selected asynchronous FIFO only AFTER FPGA stop.
            # This does not configure a UART EEPROM to FIFO.
            api.call("FT_SetBitMode",handle,0,0x00)
            api.call("FT_SetUSBParameters",handle,65536,65536)
            api.call("FT_SetTimeouts",handle,100,100)
            api.call("FT_SetLatencyTimer",handle,2)
            api.call("FT_Purge",handle,3);time.sleep(.1)
            if port:
                serial_command(port,b"!?",b"A")
                size={320:b"4",640:b"5",1920:b"6"}[args.width]
                serial_command(port,b"!"+size,size)
                mode={"counter":b"1","gray":b"2","edge":b"3" if args.edge_format=="packed" else b"7"}[args.mode]
                serial_command(port,b"!"+mode,mode)
            else:
                size={320:"4",640:"5",1920:"6"}[args.width];mode={"counter":"1","gray":"2","edge":"3" if args.edge_format=="packed" else "7"}[args.mode]
                print(f"D2XX async ready. UART: !P => 1 for edges, !? => A, !{size} => {size}, then !{mode} => {mode}. Stop with !0 before closing.")
            started=time.monotonic()
            worker=threading.Thread(target=read_usb,daemon=True);worker.start()
            while time.monotonic()-started<args.seconds:
                try:
                    chunk=chunks.get(timeout=.01)
                    if isinstance(chunk,Exception): raise chunk
                    consume(chunk)
                except queue.Empty: pass
                if gui is not None: gui.update()
        finally:
            # No mode changes or purge here, even when the stop command fails.
            try:
                if port: serial_command(port,b"!0",b"0")
                elif handle: print("Manual control: send !0 and wait for 0 before disconnecting.")
            finally:
                quit_reader.set()
                if worker: worker.join(timeout=2)
                if port: port.close()
                if handle: api.call("FT_Close",handle)
    elapsed=time.monotonic()-started
    print(json.dumps(dict(bytes=received,frames=frames,crc_header_errors=parser.bad_headers,crc_payload_errors=parser.bad_payloads,sequence_discontinuities=gaps,elapsed_s=round(elapsed,3),fps=round(frames/max(elapsed,.001),3),valid_payload_MB_s=round(payload_bytes/max(elapsed,.001)/1e6,3),MB_s=round(received/max(elapsed,.001)/1e6,3)),indent=2))
    if args.save_last:
        if last is None or last.kind==0:
            raise RuntimeError("No complete image received; no image file written")
        args.save_last.write_bytes(f"P5\n{last.width} {last.height}\n255\n".encode()+image_bytes(last))
    if not frames or parser.bad_headers or parser.bad_payloads or gaps:
        raise RuntimeError("No complete frames, corruption, or discontinuity detected; inspect reported counters")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError,OSError,ImportError) as error:
        raise SystemExit(str(error))
