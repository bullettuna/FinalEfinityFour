"""Read-only FT232H source for FT5 image and point packets.

The same transport can carry kind=3 packed edge images, kind=4 four-point
results, and kind=5 eleven-point results. This module never sends UART
commands and never writes to the device.
"""
from __future__ import annotations

import argparse
import ctypes as C
import dataclasses
import os
import struct
import time
import zlib
from collections.abc import Callable
from pathlib import Path

import numpy as np


MAGIC = b"FT5!"
HEADER = struct.Struct("<4sBBBBIHHII")
EXPECTED_WIDTH = 640
EXPECTED_HEIGHT = 360
EXPECTED_KIND = 3

POINT_NAMES = {
    4: (
        "left_shoulder",
        "right_shoulder",
        "left_wrist",
        "right_wrist",
    ),
    5: (
        "head",
        "left_shoulder",
        "right_shoulder",
        "left_elbow",
        "right_elbow",
        "left_wrist",
        "right_wrist",
        "left_hip",
        "right_hip",
        "left_knee",
        "right_knee",
    ),
}

POINT_EDGES = {
    4: ((0, 1), (0, 2), (1, 3)),
    5: (
        (0, 1),
        (0, 2),
        (1, 2),
        (1, 3),
        (3, 5),
        (2, 4),
        (4, 6),
        (1, 7),
        (2, 8),
        (7, 8),
        (7, 9),
        (8, 10),
    ),
}

MODEL_HEADS = {
    0xBBFFDF52: {
        "name": "image6 baseline",
        "zero": 8311.0,
        "scale": 1.8357570297666825e-05,
    },
    0x4677BBDB: {
        "name": "detail8 cleaner",
        "zero": 9574.0,
        "scale": 1.767850153555628e-05,
    },
    0x1F704B5E: {
        "name": "image7 model A",
        "zero": 16083.0,
        "scale": 2.170415609725751e-05,
    },
}


class D2XXError(OSError):
    """Preserve the driver status for callers that can recover a live stream."""

    STATUS_NAMES = {
        1: "FT_INVALID_HANDLE",
        2: "FT_DEVICE_NOT_FOUND",
        3: "FT_DEVICE_NOT_OPENED",
        4: "FT_IO_ERROR",
    }

    def __init__(self, function: str, status: int) -> None:
        self.function = function
        self.status = status
        super().__init__(
            f"{function}: D2XX status {status} "
            f"({self.STATUS_NAMES.get(status, 'FT_ERROR')})"
        )


@dataclasses.dataclass(frozen=True)
class Frame:
    kind: int
    sequence: int
    width: int
    height: int
    payload: bytes
    version: int = 1


@dataclasses.dataclass
class SourceStats:
    parsed_frames: int = 0
    accepted_frames: int = 0
    ignored_frames: int = 0
    ignored_kind: int = 0
    ignored_dimensions: int = 0
    bad_headers: int = 0
    bad_payloads: int = 0
    sequence_gaps: int = 0
    dropped_frames: int = 0
    bytes_received: int = 0

    def as_dict(self, elapsed_s: float) -> dict:
        elapsed = max(1e-6, elapsed_s)
        return {
            "parsed_frames": self.parsed_frames,
            "accepted_frames": self.accepted_frames,
            "ignored_frames": self.ignored_frames,
            "ignored_kind": self.ignored_kind,
            "ignored_dimensions": self.ignored_dimensions,
            "bad_headers": self.bad_headers,
            "bad_payloads": self.bad_payloads,
            "sequence_gaps": self.sequence_gaps,
            "dropped_frames": self.dropped_frames,
            "fpga_fps": round(self.accepted_frames / elapsed, 2),
            "usb_mb_s": round(self.bytes_received / elapsed / 1_000_000, 3),
        }


class FrameParser:
    """Incrementally parse length-delimited FT5! frames from arbitrary chunks."""

    def __init__(self) -> None:
        self.buffer = bytearray()
        self.bad_headers = 0
        self.bad_payloads = 0
        self.discarded = 0

    def feed(self, chunk: bytes) -> list[Frame]:
        self.buffer.extend(chunk)
        frames: list[Frame] = []
        while True:
            at = self.buffer.find(MAGIC)
            if at < 0:
                keep = min(3, len(self.buffer))
                discard = len(self.buffer) - keep
                if discard:
                    self.discarded += discard
                    del self.buffer[:discard]
                break
            if at:
                self.discarded += at
                del self.buffer[:at]
            if len(self.buffer) < HEADER.size:
                break

            magic, version, kind, flags, size, seq, width, height, length, crc = (
                HEADER.unpack_from(self.buffer)
            )
            packed_length = ((width + 7) // 8) * height
            image_length = width * height
            length_valid = (
                (kind == 0 and width == 0 and height == 0 and length == 4096)
                or (kind == 1 and width > 0 and height > 0 and length == image_length)
                or (kind == 2 and width > 0 and height > 0 and length == image_length)
                or (kind == 3 and width > 0 and height > 0 and length == packed_length)
                or (kind == 4 and width == 640 and height == 360 and length == 44)
                or (kind == 5 and width == 640 and height == 360 and length == 86)
            )
            header_valid = (
                magic == MAGIC
                and (
                    (version == 1 and kind <= 4)
                    or (version == 2 and kind == 5)
                )
                and flags == 0
                and size == HEADER.size
                and 0 < length <= 2_073_600
                and length_valid
                and zlib.crc32(self.buffer[:20]) == crc
            )
            if not header_valid:
                self.bad_headers += 1
                del self.buffer[0]
                continue

            total = HEADER.size + length + 4
            if len(self.buffer) < total:
                break
            payload = bytes(self.buffer[HEADER.size:HEADER.size + length])
            payload_crc = struct.unpack_from("<I", self.buffer, HEADER.size + length)[0]
            if zlib.crc32(payload) != payload_crc:
                self.bad_payloads += 1
                del self.buffer[0]
                continue

            frames.append(Frame(kind, seq, width, height, payload, version))
            del self.buffer[:total]
        return frames


class EdgeFrameSelector:
    """Track stream diagnostics and retain the configured packet type."""

    def __init__(
        self,
        width: int = EXPECTED_WIDTH,
        height: int = EXPECTED_HEIGHT,
        kind: int = EXPECTED_KIND,
    ) -> None:
        self.width = width
        self.height = height
        self.kind = kind
        self.stats = SourceStats()
        self.last_raw_sequence: int | None = None
        self.started_at: float | None = None

    def start(self) -> None:
        self.started_at = time.monotonic()

    def accept(self, frame: Frame) -> bool:
        self.stats.parsed_frames += 1
        if (
            self.last_raw_sequence is not None
            and frame.sequence != ((self.last_raw_sequence + 1) & 0xFFFFFFFF)
        ):
            self.stats.sequence_gaps += 1
        self.last_raw_sequence = frame.sequence

        if frame.kind != self.kind:
            self.stats.ignored_frames += 1
            self.stats.ignored_kind += 1
            return False
        if frame.width != self.width or frame.height != self.height:
            self.stats.ignored_frames += 1
            self.stats.ignored_dimensions += 1
            return False
        self.stats.accepted_frames += 1
        return True

    def snapshot(self, now: float | None = None) -> dict:
        if self.started_at is None:
            elapsed = 0.0
        else:
            elapsed = (now if now is not None else time.monotonic()) - self.started_at
        return self.stats.as_dict(elapsed)


def decode_packed_edge(frame: Frame) -> np.ndarray:
    """Decode a kind=3 MSB-first payload into a 0/255 grayscale edge image."""
    if frame.kind != 3:
        raise ValueError(f"expected kind=3 packed edge frame, got kind={frame.kind}")
    row_bytes = (frame.width + 7) // 8
    expected = row_bytes * frame.height
    if len(frame.payload) != expected:
        raise ValueError(
            f"packed payload is {len(frame.payload)} bytes, expected {expected}"
        )
    packed = np.frombuffer(frame.payload, dtype=np.uint8)
    bits = np.unpackbits(packed, bitorder="big")
    rows = bits.reshape(frame.height, row_bytes * 8)[:, :frame.width]
    return np.ascontiguousarray(rows, dtype=np.uint8) * 255


def decode_four_point_result(frame: Frame) -> dict:
    """Decode a version-1 kind-4 four-point result packet."""
    return _decode_point_result(frame, expected_version=1, expected_kind=4)


def decode_eleven_point_result(frame: Frame) -> dict:
    """Decode a version-2 kind-5 eleven-point result packet."""
    return _decode_point_result(frame, expected_version=2, expected_kind=5)


def _decode_point_result(
    frame: Frame,
    expected_version: int,
    expected_kind: int,
) -> dict:
    if frame.version != expected_version or frame.kind != expected_kind:
        raise ValueError(
            f"expected version={expected_version} kind={expected_kind}, "
            f"got version={frame.version} kind={frame.kind}"
        )
    if frame.width != 640 or frame.height != 360:
        raise ValueError(
            f"expected 640x360 result frame, got {frame.width}x{frame.height}"
        )

    names = POINT_NAMES[expected_kind]
    expected_payload = 20 + 6 * len(names)
    if len(frame.payload) != expected_payload:
        raise ValueError(
            f"kind={expected_kind} payload is {len(frame.payload)} bytes, "
            f"expected {expected_payload}"
        )

    schema, count, flags, reserved, cycles, model_crc, input_crc, heatmap_crc = (
        struct.unpack_from("<BBBBIIII", frame.payload, 0)
    )
    expected_schema = 1 if expected_kind == 4 else 2
    if schema != expected_schema:
        raise ValueError(f"unsupported schema {schema}, expected {expected_schema}")
    if count != len(names):
        raise ValueError(f"expected {len(names)} points, got {count}")
    if reserved != 0:
        raise ValueError(f"reserved byte must be 0, got {reserved}")

    meta = MODEL_HEADS.get(
        model_crc,
        {"name": "unknown", "zero": None, "scale": None},
    )
    points = []
    for index, name in enumerate(names):
        x_q14_2, y_q14_2, peak = struct.unpack_from(
            "<HHH",
            frame.payload,
            20 + index * 6,
        )
        if x_q14_2 > 2560 or y_q14_2 > 1440:
            raise ValueError(
                f"point {index} outside 640x360: x_q={x_q14_2}, y_q={y_q14_2}"
            )
        score = None
        if meta["zero"] is not None:
            score = (peak - meta["zero"]) * meta["scale"]
        points.append(
            {
                "index": index,
                "name": name,
                "x": x_q14_2 / 4.0,
                "y": y_q14_2 / 4.0,
                "x_q14_2": x_q14_2,
                "y_q14_2": y_q14_2,
                "peak": peak,
                "score": score,
            }
        )

    return {
        "version": frame.version,
        "kind": frame.kind,
        "width": frame.width,
        "height": frame.height,
        "schema": schema,
        "point_count": count,
        "flags": flags,
        "model_ready": bool(flags & 0x01),
        "fault": bool(flags & 0x04),
        "deterministic": bool(flags & 0x08),
        "is_live": not bool(flags & 0x08),
        "valid": (flags & 0x07) == 0x03,
        "cycles": cycles,
        "inference_ms": cycles / 96000.0,
        "model_crc": model_crc,
        "model_crc_hex": f"{model_crc:08x}",
        "model_name": meta["name"],
        "input_crc_hex": f"{input_crc:08x}",
        "heatmap_crc_hex": f"{heatmap_crc:08x}",
        "points": points,
        "skeleton_edges": [list(edge) for edge in POINT_EDGES[expected_kind]],
    }


class D2XX:
    """Minimal read-only D2XX binding."""

    FT_OPEN_BY_SERIAL_NUMBER = 1
    FT_OPEN_BY_DESCRIPTION = 2
    FT_DEVICE_232H = 8
    FT_FLAGS_OPENED = 0x01

    def __init__(self, dll_path: Path | None = None) -> None:
        if os.name != "nt":
            raise RuntimeError("FT232H live capture requires Windows")
        if dll_path is None:
            dll_path = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32" / "ftd2xx.dll"
        self.dll = C.WinDLL(str(dll_path))
        specs = {
            "FT_CreateDeviceInfoList": [C.POINTER(C.c_ulong)],
            "FT_GetDeviceInfoDetail": [C.c_ulong] + [C.POINTER(C.c_ulong)] * 4
            + [C.c_void_p, C.c_void_p, C.POINTER(C.c_void_p)],
            "FT_Open": [C.c_ulong, C.POINTER(C.c_void_p)],
            "FT_OpenEx": [C.c_void_p, C.c_ulong, C.POINTER(C.c_void_p)],
            "FT_Close": [C.c_void_p],
            "FT_SetBitMode": [C.c_void_p, C.c_ubyte, C.c_ubyte],
            "FT_SetUSBParameters": [C.c_void_p, C.c_ulong, C.c_ulong],
            "FT_SetTimeouts": [C.c_void_p, C.c_ulong, C.c_ulong],
            "FT_SetLatencyTimer": [C.c_void_p, C.c_ubyte],
            "FT_Purge": [C.c_void_p, C.c_ulong],
            "FT_Read": [C.c_void_p, C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong)],
        }
        for name, args in specs.items():
            fn = getattr(self.dll, name)
            fn.argtypes = args
            fn.restype = C.c_ulong

    def call(self, name: str, *args) -> int:
        status = int(getattr(self.dll, name)(*args))
        if status:
            raise D2XXError(name, status)
        return status

    def devices(self) -> list[dict]:
        count = C.c_ulong()
        self.call("FT_CreateDeviceInfoList", C.byref(count))
        result = []
        for index in range(count.value):
            flags, kind, identity, location = (C.c_ulong() for _ in range(4))
            serial = C.create_string_buffer(16)
            description = C.create_string_buffer(64)
            handle = C.c_void_p()
            self.call(
                "FT_GetDeviceInfoDetail",
                index,
                C.byref(flags),
                C.byref(kind),
                C.byref(identity),
                C.byref(location),
                serial,
                description,
                C.byref(handle),
            )
            result.append(
                {
                    "index": index,
                    "type": int(kind.value),
                    "serial": serial.value.decode(errors="replace"),
                    "description": description.value.decode(errors="replace"),
                    "flags": int(flags.value),
                }
            )
        return result

    def open(self, serial: str = "") -> C.c_void_p:
        devices = self.devices()
        candidates = [
            d for d in devices if d["type"] == self.FT_DEVICE_232H
        ]
        if serial:
            candidates = [d for d in candidates if d["serial"] == serial]
            if len(candidates) != 1:
                if not candidates and any(
                    d["flags"] & self.FT_FLAGS_OPENED for d in devices
                ):
                    raise RuntimeError(
                        "FT232H is already opened by another process. "
                        "Use the running SoulRiderBridge HTTP endpoint instead."
                    )
                raise RuntimeError(
                    f"expected exactly one FT232H with serial {serial!r}; found {len(candidates)}"
                )
            selected = candidates[0]
        else:
            if len(candidates) != 1:
                if not candidates and any(
                    d["flags"] & self.FT_FLAGS_OPENED for d in devices
                ):
                    raise RuntimeError(
                        "FT232H is already opened by another process. "
                        "Use the running SoulRiderBridge HTTP endpoint instead."
                    )
                raise RuntimeError(
                    f"expected exactly one FT232H; found {len(candidates)}. "
                    "Check USB/driver, or specify the serial if multiple devices are connected."
                )
            selected = candidates[0]

        handle = C.c_void_p()
        if selected["serial"]:
            self.call(
                "FT_OpenEx",
                C.cast(C.c_char_p(selected["serial"].encode()), C.c_void_p),
                self.FT_OPEN_BY_SERIAL_NUMBER,
                C.byref(handle),
            )
        else:
            # Some FT232H modules have an empty EEPROM serial. Selecting the
            # only enumerated type-8 device is safe only after the check above.
            self.call("FT_Open", selected["index"], C.byref(handle))
        return handle

    def configure_read_only(self, handle: C.c_void_p) -> None:
        self.call("FT_SetBitMode", handle, 0, 0x00)
        self.call("FT_SetUSBParameters", handle, 65536, 65536)
        self.call("FT_SetTimeouts", handle, 100, 100)
        self.call("FT_SetLatencyTimer", handle, 2)
        self.call("FT_Purge", handle, 3)
        time.sleep(0.05)

    def read(self, handle: C.c_void_p, size: int = 65536) -> bytes:
        storage = C.create_string_buffer(size)
        count = C.c_ulong()
        self.call("FT_Read", handle, storage, size, C.byref(count))
        return storage.raw[:count.value]

    def close(self, handle: C.c_void_p) -> None:
        self.call("FT_Close", handle)


class PreconfiguredEdgeSource:
    """Read and filter an already-running 640x360 kind=3 FPGA stream."""

    def __init__(
        self,
        serial: str = "",
        width: int = EXPECTED_WIDTH,
        height: int = EXPECTED_HEIGHT,
        kind: int = EXPECTED_KIND,
        chunk_callback: Callable[[bytes], None] | None = None,
        frame_callback: Callable[[Frame], None] | None = None,
        diagnostic_callback: Callable[[str, dict], None] | None = None,
    ) -> None:
        self.serial = serial
        self.width = width
        self.height = height
        self.kind = kind
        self.chunk_callback = chunk_callback
        self.frame_callback = frame_callback
        self.diagnostic_callback = diagnostic_callback
        self.api: D2XX | None = None
        self.handle: C.c_void_p | None = None
        self.parser = FrameParser()
        self.selector = EdgeFrameSelector(width, height, kind)
        self.last_frame: Frame | None = None

    def open(self) -> None:
        if self.handle is not None:
            return
        self.api = receive_api(self.serial)
        self.handle = self.api.open(self.serial)
        try:
            self.api.configure_read_only(self.handle)
            if self.kind in {4, 5}:
                set_timeouts = getattr(self.api, "call", None)
                if set_timeouts is not None:
                    set_timeouts("FT_SetTimeouts", self.handle, 10, 100)
        except Exception:
            self.close()
            raise
        self.parser = FrameParser()
        self.selector = EdgeFrameSelector(self.width, self.height, self.kind)
        self.selector.start()
        self.last_frame = None

    def close(self) -> None:
        handle, api = self.handle, self.api
        self.handle = None
        self.api = None
        if handle is not None and api is not None:
            try:
                api.close(handle)
            except OSError:
                pass

    def read_latest_matching(self, wait_s: float = 0.15) -> Frame | None:
        if self.api is None or self.handle is None:
            raise RuntimeError("FT232H source is not open")
        deadline = time.monotonic() + wait_s
        matches: list[Frame] = []
        while True:
            chunk = self.api.read(self.handle)
            if chunk and self.chunk_callback is not None:
                try:
                    self.chunk_callback(chunk)
                except Exception:
                    pass
            self.selector.stats.bytes_received += len(chunk)
            bad_headers_before = self.parser.bad_headers
            bad_payloads_before = self.parser.bad_payloads
            discarded_before = self.parser.discarded
            parsed_frames = self.parser.feed(chunk)
            if (
                self.diagnostic_callback is not None
                and (
                    self.parser.bad_headers > bad_headers_before
                    or self.parser.bad_payloads > bad_payloads_before
                    or self.parser.discarded > discarded_before
                )
            ):
                try:
                    self.diagnostic_callback(
                        "parser_errors",
                        {
                            "bad_headers": self.parser.bad_headers,
                            "bad_payloads": self.parser.bad_payloads,
                            "discarded_bytes": self.parser.discarded,
                        },
                    )
                except Exception:
                    pass
            for frame in parsed_frames:
                if self.frame_callback is not None:
                    try:
                        self.frame_callback(frame)
                    except Exception:
                        pass
                if self.selector.accept(frame):
                    matches.append(frame)
            self.selector.stats.bad_headers = self.parser.bad_headers
            self.selector.stats.bad_payloads = self.parser.bad_payloads
            if matches:
                if len(matches) > 1:
                    self.selector.stats.dropped_frames += len(matches) - 1
                self.last_frame = matches[-1]
                return self.last_frame
            if time.monotonic() >= deadline:
                return None

    def stats(self) -> dict:
        return self.selector.snapshot()

    def __enter__(self) -> "PreconfiguredEdgeSource":
        self.open()
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list D2XX devices")
    parser.add_argument("--serial", default="", help="exact FT232H serial")
    parser.add_argument("--kind", type=int, choices=range(6), default=3)
    parser.add_argument("--seconds", type=float, default=5.0)
    args = parser.parse_args()

    if args.list:
        try:
            devices = D2XX().devices()
        except Exception as exc:
            print(f"D2XX enumeration failed: {exc}")
            return
        print(devices)
        if not devices:
            print(
                "D2XX enumerated no FTDI devices. "
                "Check USB connection and FTDI driver."
            )
            return
        opened = [
            device
            for device in devices
            if device["flags"] & D2XX.FT_FLAGS_OPENED
        ]
        if opened:
            print(
                "FTDI device is already opened by another process. "
                "Use http://127.0.0.1:8765/state instead of opening it again."
            )
        return

    source = PreconfiguredEdgeSource(args.serial, kind=args.kind)
    try:
        source.open()
        started = time.monotonic()
        while time.monotonic() - started < args.seconds:
            frame = source.read_latest_matching(0.2)
            if frame is not None:
                print(
                    f"accepted seq={frame.sequence} width={frame.width} "
                    f"height={frame.height} kind={frame.kind}"
                )
        print(source.stats())
    finally:
        source.close()


def receive_api(serial: str = ""):
    """Prefer D2XX and fall back to the project's libusbK transport."""
    try:
        api = D2XX()
        all_devices = api.devices()
    except OSError:
        pass
    else:
        if not all_devices:
            raise RuntimeError(
                "D2XX enumerated no FTDI devices. "
                "Check the USB connection and FTDI driver."
            )
        devices = [
            device
            for device in all_devices
            if device["type"] == api.FT_DEVICE_232H
            and (not serial or device["serial"] == serial)
        ]
        if devices:
            return api
        if any(
            device["flags"] & api.FT_FLAGS_OPENED
            for device in all_devices
        ):
            raise RuntimeError(
                "FT232H is already opened by another process. "
                "Use the running SoulRiderBridge HTTP endpoint instead."
            )
        if serial:
            raise RuntimeError(
                f"no FT232H with serial {serial!r} is available"
            )
        raise RuntimeError(
            "no unopened FT232H is available; check USB/driver or device ownership"
        )

    try:
        from ft232h_usbk import Libusb232H
    except ImportError as exc:
        raise RuntimeError(
            "D2XX was unavailable and ft232h_usbk.py could not be imported"
        ) from exc
    return Libusb232H()


if __name__ == "__main__":
    main()
