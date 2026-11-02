"""Independent pixel/CRC/orientation checks of packets written by RTL tests."""
import argparse
import importlib.util
from pathlib import Path
import struct
import tempfile
import zlib

spec = importlib.util.spec_from_file_location("receiver", Path(__file__).with_name("image2_uart_receive.py"))
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


def must_reject(packet):
    try:
        receiver.decode_packet(packet)
    except ValueError:
        return
    raise AssertionError("Bad packet accepted")


def check(directory, integration=False):
    names = ("integration_edge_packet.bin", "integration_gray_packet.bin") if integration else ("edge_packet.bin", "gray_packet.bin")
    for edge, name in zip((True, False), names):
        packet = (directory / name).read_bytes()
        meta, pixels = receiver.decode_packet(packet)
        w, h = meta["width"], meta["height"]
        assert (meta["median"], meta["cleanup"], meta["min_pixels"], meta["high"], meta["low"]) == (True, 1, 20, 60, 30)
        if integration:
            hexname = "integration_edge.hex" if edge else "integration_gray.hex"
            rgb = [int(v, 16) for v in (directory / hexname).read_text().split()]
            expected = bytes((255 if rgb[y*w+x] else 0) if edge else (((rgb[y*w+x] >> 5) & 63) << 2) | ((rgb[y*w+x] >> 9) & 3)
                             for y in range(h - 1, -1, -1) for x in range(w))
        else:
            expected = bytes((255 if n % 13 == 0 or n % 31 == 1 else 0) if edge else ((n % 64) << 2) | ((n % 64) >> 4)
                             for y in range(h - 1, -1, -1) for x in range(w) for n in (y*w+x,))
        assert pixels == expected, f"Pixel/order/orientation mismatch: {name}"
        for damaged in (packet[:-1], packet + b"x", packet[:35] + bytes([packet[35] ^ 1]) + packet[36:]):
            must_reject(damaged)
        # Serial reads can stop at arbitrary boundaries and status text may precede magic.
        class FragmentedSerial:
            def __init__(self):
                self.data = b"PROCESSING\r\nI2PI2PX" + packet[4:]
            def read(self, count):
                piece, self.data = self.data[:min(count, 17)], self.data[min(count, 17):]
                return piece
        assert receiver.receive_packet(FragmentedSerial(), 10, progress=False) == packet
        with tempfile.TemporaryDirectory() as temp:
            saved = receiver.save_sample(Path(temp), "pose1", packet)
            png = saved.read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
            at = 8
            idat = b""
            while at < len(png):
                size, kind = struct.unpack_from(">I4s", png, at)
                data = png[at+8:at+8+size]
                assert zlib.crc32(kind + data) == struct.unpack_from(">I", png, at+8+size)[0]
                if kind == b"IDAT":
                    idat += data
                at += size + 12
            assert zlib.decompress(idat) == b"".join(b"\0" + expected[y*w:(y+1)*w] for y in range(h))
            assert saved.with_suffix(".json").is_file()
        print(f"PASS {name}: {w}x{h}, every pixel, CRC, orientation, fragmented serial and PNG")
    if not integration:
        must_reject((directory / "failed_packet.bin").read_bytes())
        print("PASS FPGA DDR-failure frame rejected")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--integration", action="store_true")
    args = parser.parse_args()
    check(args.directory, args.integration)
