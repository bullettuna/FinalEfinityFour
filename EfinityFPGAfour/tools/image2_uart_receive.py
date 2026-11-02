"""Collect image2's actual processed camera frames as labelled PNG samples.

Only pyserial is needed for hardware capture; decoding/PNG writing use stdlib.
E: lossless 1-bit Canny pixels. G: 6-bit green expanded from processed RGB565.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import time
import zlib

HEADER = struct.Struct("<4sBBHHIIBBBBHHHI")
MAGIC = b"I2PX"


def parse_header(raw: bytes) -> dict:
    magic, version, fmt, width, height, length, seq, mode, median, cleanup, flags, minimum, high, low, reserved = HEADER.unpack(raw)
    if magic != MAGIC or version != 1 or fmt not in (1, 2):
        raise ValueError("Unsupported image2 frame header")
    if not (0 < width <= 1920 and 0 < height <= 1080) or flags != 1 or reserved:
        raise ValueError("Invalid dimensions, orientation, or reserved fields")
    if (fmt == 1 and (width % 8 or mode != 2)) or (fmt == 2 and mode != 1):
        raise ValueError("Invalid pixel format/mode")
    expected = width * height // 8 if fmt == 1 else width * height
    if length != expected or median > 1 or cleanup > 2 or not 0 <= low <= high <= 2047 or minimum > 2047:
        raise ValueError("Invalid payload length or processing settings")
    return dict(version=version, format="canny1" if fmt == 1 else "gray8_from_rgb565",
                width=width, height=height, payload_bytes=length, sequence=seq,
                mode=mode, median=bool(median), cleanup=cleanup, min_pixels=minimum,
                high=high, low=low, bottom_up=True)


def decode_packet(packet: bytes) -> tuple[dict, bytes]:
    if len(packet) < HEADER.size + 8:
        raise ValueError("Truncated image2 packet")
    meta = parse_header(packet[:HEADER.size])
    size = HEADER.size + meta["payload_bytes"]
    if len(packet) != size + 8:
        raise ValueError("Truncated or extra pixel data")
    if packet[-4:] != b"DONE":
        raise ValueError("FPGA reported a DDR read failure; sample rejected")
    expected_crc = struct.unpack_from("<I", packet, size)[0]
    if zlib.crc32(packet[:size]) != expected_crc:
        raise ValueError("CRC mismatch; sample rejected")
    payload = packet[HEADER.size:size]
    width, height = meta["width"], meta["height"]
    stride = width // 8 if meta["format"] == "canny1" else width
    rows = []
    for y in range(height - 1, -1, -1):
        row = payload[y * stride:(y + 1) * stride]
        if meta["format"] == "canny1":
            row = bytes(255 if b & (1 << bit) else 0 for b in row for bit in range(7, -1, -1))
        rows.append(row)
    meta["crc32"] = f"{expected_crc:08x}"
    return meta, b"".join(rows)


def png_bytes(width: int, height: int, pixels: bytes) -> bytes:
    if len(pixels) != width * height:
        raise ValueError("PNG pixel count mismatch")
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width:(y + 1) * width] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def receive_packet(port, timeout: float = 180, progress=True) -> bytes:
    deadline = time.monotonic() + timeout
    window = bytearray()
    status = bytearray()
    while bytes(window) != MAGIC:
        if time.monotonic() >= deadline:
            raise TimeoutError("No I2PX frame header. Check image2 bitstream, E/G mode, COM port and board status.")
        byte = port.read(1)
        if byte:
            status.extend(byte)
            if len(status) > 256:
                del status[0]
            if byte == b"\n":
                line = bytes(status).strip()
                if line.startswith((b"BUSY ", b"FAULT:", b"DDR_FAIL", b"PROCESS_FAIL:")):
                    raise RuntimeError(f"FPGA: {line.decode('ascii', errors='replace')}; nothing saved")
                status.clear()
            window.extend(byte)
            if len(window) > len(MAGIC):
                del window[0]
    def exact(n):
        data = bytearray()
        last_update = time.monotonic()
        while len(data) < n:
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Incomplete frame ({len(data)}/{n} bytes); nothing saved")
            data.extend(port.read(min(4096, n - len(data))))
            if progress and n > 4096 and time.monotonic() - last_update >= 1:
                print(f"\rReceiving {len(data):,}/{n:,} bytes", end="", flush=True)
                last_update = time.monotonic()
        return bytes(data)
    header = MAGIC + exact(HEADER.size - len(MAGIC))
    meta = parse_header(header)
    packet = header + exact(meta["payload_bytes"] + 8)
    if progress:
        print()
    # Always validate before returning anything that could be saved.
    decode_packet(packet)
    return packet


def command(port, data: bytes, expected: bytes, timeout=3):
    port.write(data)
    port.flush()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = port.read(1)
        if value == expected:
            return
        if value == b"!":
            raise RuntimeError(f"FPGA rejected {data!r}; check the downloaded image2 UART-export bitstream")
    raise TimeoutError(f"No reply to {data!r}; close other serial programs and verify the bitstream/baud rate")


def save_sample(output: Path, label: str, packet: bytes) -> Path:
    meta, pixels = decode_packet(packet)
    directory = output / label
    directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().astimezone()
    stem = f"{stamp:%Y%m%d_%H%M%S_%f}_s{meta['sequence']:06d}_{meta['format']}"
    destination = directory / (stem + ".png")
    encoded = png_bytes(meta["width"], meta["height"], pixels)
    meta.update(label=label, captured_at=stamp.isoformat(), image=destination.name,
                png_sha256=hashlib.sha256(encoded).hexdigest(),
                source="image2 camera -> 2x2 gray mean -> photo_frame_process -> UART",
                isp_note="WB/Gamma/exposure not recorded in packet; keep capture conditions fixed")
    with destination.open("xb") as file:
        file.write(encoded)
    with destination.with_suffix(".json").open("x", encoding="utf-8") as file:
        json.dump(meta, file, ensure_ascii=False, indent=2)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Serial port, e.g. COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--label", default="pose1", help="Action label / output subdirectory")
    parser.add_argument("--output", type=Path, default=Path("samples/image2_uart"))
    parser.add_argument("--mode", choices=("edge", "gray"), default="edge")
    parser.add_argument("--count", type=int, default=0, help="0: press Enter per image; >0: automatic batch")
    parser.add_argument("--interval", type=float, default=1, help="Seconds between completed captures in batch")
    parser.add_argument("--timeout", type=float, default=180, help="Maximum seconds for one complete capture")
    parser.add_argument("--high", type=int)
    parser.add_argument("--low", type=int)
    parser.add_argument("--min-pixels", type=int)
    parser.add_argument("--list-ports", action="store_true")
    parser.add_argument("--decode", type=Path, help="Validate a saved binary test packet instead of opening serial")
    args = parser.parse_args()
    if not re.fullmatch(r"[\w-]{1,64}", args.label) or args.label.endswith("."):
        parser.error("Use a simple action label (letters, digits, underscore, hyphen)")
    if args.count < 0 or args.interval < 0 or args.timeout <= 0:
        parser.error("Invalid count/interval/timeout")
    for key in ("high", "low", "min_pixels"):
        if (value := getattr(args, key)) is not None and not 0 <= value <= 2047:
            parser.error(f"{key} must be 0..2047")
    if args.decode:
        print(save_sample(args.output, args.label, args.decode.read_bytes()))
        return
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        parser.error("Install pyserial: python -m pip install pyserial")
    if args.list_ports:
        for item in list_ports.comports():
            print(f"{item.device}: {item.description}")
        return
    if not args.port:
        parser.error("Provide --port COMx or use --list-ports")
    port = serial.Serial(port=None, baudrate=args.baud, timeout=0.2, write_timeout=2)
    port.dtr = False
    port.rts = False
    port.port = args.port
    with port:
        time.sleep(0.5)
        port.reset_input_buffer()
        command(port, b"V", b"2")
        command(port, b":", b"U")
        command(port, b"E" if args.mode == "edge" else b"G", b"2" if args.mode == "edge" else b"1")
        for prefix, value in (("H", args.high), ("L", args.low), ("N", args.min_pixels)):
            if value is not None:
                command(port, f"{prefix}{value}\r".encode(), b"K")
        print(f"{args.port}, {args.baud} 8N1; {args.mode}; label={args.label}")
        print("Each capture uses a new complete camera frame; no TF card required.")
        completed = 0
        while not args.count or completed < args.count:
            if not args.count and input("Pose ready: Enter to capture, q to quit > ").strip().lower() == "q":
                break
            # No other commands are sent while a binary packet owns the UART.
            port.write(b"@")
            port.flush()
            packet = receive_packet(port, args.timeout)
            path = save_sample(args.output, args.label, packet)
            meta = parse_header(packet[:HEADER.size])
            completed += 1
            print(f"Saved {path.resolve()} ({meta['width']}x{meta['height']}, CRC OK)")
            if args.count and completed < args.count:
                time.sleep(args.interval)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, TimeoutError, RuntimeError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nStopped; incomplete frame was not saved.")
