"""Read passive image2 video diagnostics; never changes video or starts inference."""
import argparse
import json
import struct
import time
import zlib
from pathlib import Path

FIELDS = (
    "sys_ticks", "camera_frames", "camera_good_frames", "camera_words",
    "display_frame_requests", "display_buffer_changes", "write_buffer_changes",
    "bad_frames", "display_underflows", "aux_read_requests", "aux_write_requests", "status",
)


def decode(packet):
    if len(packet) != 56 or packet[:4] != b"P2D1":
        raise ValueError("Not an image2 diagnostic packet (P2D1, 56 bytes)")
    if zlib.crc32(packet[:52]) != struct.unpack_from("<I", packet, 52)[0]:
        raise ValueError("Diagnostic CRC mismatch")
    result = dict(zip(FIELDS, struct.unpack_from("<12I", packet, 4)))
    flags = result["status"]
    result["flags"] = dict(frozen=bool(flags & 1), ddr_cal_done=bool(flags & 2),
                           ddr_cal_pass=bool(flags & 4), arbiter_stalled=bool(flags & 8))
    return result


def query(port):
    port.write(b"~2D")
    port.flush()
    data = bytearray()
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        data.extend(port.read(1))
        start = data.find(b"P2D1")
        if start >= 0 and len(data) >= start + 56:
            return decode(data[start:start + 56])
    raise TimeoutError("No ~2D reply. Download the image2 video diagnostic bitstream; close other COM applications.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port")
    parser.add_argument("--decode-file", type=Path)
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--interval", type=float, default=2)
    args = parser.parse_args()
    if args.decode_file:
        print(json.dumps(decode(args.decode_file.read_bytes()), ensure_ascii=False))
        return
    if not args.port:
        parser.error("--port is required for serial diagnostics")
    if args.seconds <= 0 or not 0.1 <= args.interval <= 10:
        parser.error("seconds must be positive; interval must be 0.1..10 seconds")
    import serial
    # Configure DTR/RTS before opening; do not deliberately reset the board.
    port = serial.Serial(port=None, baudrate=115200, timeout=0.05, write_timeout=1)
    port.dtr = False
    port.rts = False
    port.port = args.port
    port.open()
    try:
        port.reset_input_buffer()
        end = time.monotonic() + args.seconds
        previous = None
        while True:
            current = query(port)
            record = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "counts": current}
            if previous:
                delta = {key: (current[key] - previous[key]) & 0xFFFFFFFF for key in FIELDS[:-1]}
                seconds = delta["sys_ticks"] / 96_000_000
                if seconds:
                    record["interval_seconds"] = round(seconds, 3)
                    record["per_second"] = {key: round(delta[key] / seconds, 2) for key in FIELDS[1:-1]}
                record["delta"] = delta
            print(json.dumps(record, ensure_ascii=False), flush=True)
            previous = current
            if time.monotonic() >= end:
                break
            time.sleep(min(args.interval, max(0, end - time.monotonic())))
    finally:
        port.close()


if __name__ == "__main__":
    main()
