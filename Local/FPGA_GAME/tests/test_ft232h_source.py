from __future__ import annotations

import struct
import unittest
import zlib
from unittest.mock import patch

import numpy as np

from ft232h_source import (
    HEADER,
    MAGIC,
    EdgeFrameSelector,
    Frame,
    FrameParser,
    PreconfiguredEdgeSource,
    decode_eleven_point_result,
    decode_four_point_result,
    decode_packed_edge,
    receive_api,
)


def wire_frame(
    kind: int,
    sequence: int,
    width: int,
    height: int,
    payload: bytes,
    version: int = 1,
) -> bytes:
    prefix = struct.pack(
        "<4sBBBBIHHI",
        MAGIC,
        version,
        kind,
        0,
        HEADER.size,
        sequence,
        width,
        height,
        len(payload),
    )
    header = prefix + struct.pack("<I", zlib.crc32(prefix))
    return header + payload + struct.pack("<I", zlib.crc32(payload))


def point_payload(
    schema: int,
    points: list[tuple[int, int, int]],
    model_crc: int,
    flags: int = 3,
    cycles: int = 6240433,
) -> bytes:
    payload = struct.pack(
        "<BBBBIIII",
        schema,
        len(points),
        flags,
        0,
        cycles,
        model_crc,
        0x12345678,
        0x9ABCDEF0,
    )
    payload += b"".join(struct.pack("<HHH", *point) for point in points)
    return payload


class FrameParserTests(unittest.TestCase):
    def test_reassembles_chunks_and_preserves_frame(self) -> None:
        payload = bytes(range(32))
        encoded = b"noise" + wire_frame(2, 9, 16, 2, payload) + b"tail"
        parser = FrameParser()
        frames = []
        for offset in range(0, len(encoded), 7):
            frames.extend(parser.feed(encoded[offset:offset + 7]))

        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].sequence, 9)
        self.assertEqual(frames[0].width, 16)
        self.assertEqual(frames[0].height, 2)
        self.assertEqual(frames[0].payload, payload)

    def test_parses_version2_kind5_eleven_point_frame(self) -> None:
        points = [(index * 40 * 4, index * 20 * 4, 20000) for index in range(11)]
        payload = point_payload(2, points, 0x1F704B5E)
        encoded = wire_frame(5, 17, 640, 360, payload, version=2)

        frames = FrameParser().feed(encoded)

        self.assertEqual(len(encoded), 114)
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].version, 2)
        self.assertEqual(frames[0].kind, 5)
        self.assertEqual(frames[0].payload, payload)

    def test_rejects_corrupt_payload_without_raising(self) -> None:
        encoded = bytearray(wire_frame(3, 1, 16, 1, b"\x00\x01"))
        encoded[HEADER.size] ^= 0xFF
        parser = FrameParser()
        self.assertEqual(parser.feed(bytes(encoded)), [])
        self.assertEqual(parser.bad_payloads, 1)


class FrameFilterTests(unittest.TestCase):
    def test_only_exact_kind3_dimensions_are_accepted(self) -> None:
        selector = EdgeFrameSelector()
        frames = [
            Frame(0, 1, 0, 0, bytes(4096)),
            Frame(2, 2, 640, 360, bytes(640 * 360)),
            Frame(3, 3, 320, 180, bytes(320 * 180 // 8)),
            Frame(3, 4, 640, 360, bytes(640 * 360 // 8)),
        ]
        accepted = [frame for frame in frames if selector.accept(frame)]

        self.assertEqual(len(accepted), 1)
        self.assertEqual(accepted[0].sequence, 4)
        self.assertEqual(selector.stats.ignored_kind, 2)
        self.assertEqual(selector.stats.ignored_dimensions, 1)
        self.assertEqual(selector.stats.accepted_frames, 1)

    def test_decodes_msb_first_packed_pixels(self) -> None:
        frame = Frame(3, 1, 10, 1, bytes([0b10110000, 0b01000000]))
        edge = decode_packed_edge(frame)
        expected = np.array(
            [[255, 0, 255, 255, 0, 0, 0, 0, 0, 255]],
            dtype=np.uint8,
        )
        np.testing.assert_array_equal(edge, expected)

    def test_decodes_four_point_result(self) -> None:
        points = [
            (1200, 480, 12000),
            (1600, 480, 12000),
            (800, 800, 11000),
            (2000, 800, 11000),
        ]
        frame = Frame(
            4,
            1,
            640,
            360,
            point_payload(1, points, 0x4677BBDB),
        )

        result = decode_four_point_result(frame)

        self.assertTrue(result["valid"])
        self.assertEqual(result["point_count"], 4)
        self.assertEqual(result["points"][0]["name"], "left_shoulder")
        self.assertEqual(result["points"][0]["x"], 300.0)
        self.assertAlmostEqual(result["points"][0]["score"], 0.04288804472525953)

    def test_decodes_eleven_point_result(self) -> None:
        points = [(index * 160, index * 80, 20000) for index in range(11)]
        frame = Frame(
            5,
            2,
            640,
            360,
            point_payload(2, points, 0x1F704B5E),
            version=2,
        )

        result = decode_eleven_point_result(frame)

        self.assertTrue(result["valid"])
        self.assertTrue(result["is_live"])
        self.assertEqual(result["schema"], 2)
        self.assertEqual(result["point_count"], 11)
        self.assertEqual(result["points"][0]["name"], "head")
        self.assertEqual(result["points"][10]["name"], "right_knee")
        self.assertAlmostEqual(result["points"][0]["score"], 0.08501517943295767)


class _FakeApi:
    def __init__(self, chunks: list[bytes]) -> None:
        self.chunks = chunks

    def read(self, handle, size: int = 65536) -> bytes:
        return self.chunks.pop(0) if self.chunks else b""


class SourceReadTests(unittest.TestCase):
    def test_source_reports_raw_chunks_and_parsed_frames(self) -> None:
        encoded = wire_frame(3, 7, 640, 360, bytes(640 * 360 // 8))
        chunks: list[bytes] = []
        frames: list[Frame] = []
        source = PreconfiguredEdgeSource(
            chunk_callback=chunks.append,
            frame_callback=frames.append,
        )
        source.api = _FakeApi([encoded])
        source.handle = object()
        source.selector.start()

        frame = source.read_latest_matching(0.01)

        self.assertEqual(chunks, [encoded])
        self.assertEqual(len(frames), 1)
        self.assertIs(frame, frames[0])

    def test_source_ignores_wrong_frames_and_returns_latest_match(self) -> None:
        wrong = wire_frame(3, 1, 320, 180, bytes(320 * 180 // 8))
        accepted = wire_frame(3, 2, 640, 360, bytes(640 * 360 // 8))
        source = PreconfiguredEdgeSource()
        source.api = _FakeApi([wrong + accepted])
        source.handle = object()
        source.selector.start()

        frame = source.read_latest_matching(0.01)

        self.assertIsNotNone(frame)
        self.assertEqual(frame.sequence, 2)
        self.assertEqual(source.stats()["accepted_frames"], 1)
        self.assertEqual(source.stats()["ignored_dimensions"], 1)

    def test_source_returns_none_when_only_nonmatching_frames_arrive(self) -> None:
        counter = wire_frame(0, 1, 0, 0, bytes(4096))
        source = PreconfiguredEdgeSource()
        source.api = _FakeApi([counter])
        source.handle = object()
        source.selector.start()

        self.assertIsNone(source.read_latest_matching(0.01))
        self.assertEqual(source.stats()["accepted_frames"], 0)
        self.assertEqual(source.stats()["ignored_kind"], 1)


class D2XXOwnershipTests(unittest.TestCase):
    def test_receive_api_reports_device_opened_by_another_process(self) -> None:
        class OpenedApi:
            FT_DEVICE_232H = 8
            FT_FLAGS_OPENED = 0x01

            def devices(self) -> list[dict]:
                return [
                    {
                        "index": 0,
                        "type": 3,
                        "serial": "",
                        "description": "",
                        "flags": self.FT_FLAGS_OPENED,
                    }
                ]

        with patch("ft232h_source.D2XX", return_value=OpenedApi()):
            with self.assertRaisesRegex(RuntimeError, "already opened"):
                receive_api()


if __name__ == "__main__":
    unittest.main()
