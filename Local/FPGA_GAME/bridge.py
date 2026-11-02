from __future__ import annotations

import argparse
import base64
import ctypes
import csv
import hashlib
import json
import mimetypes
import os
import re
import shutil
import threading
import time
import webbrowser
from collections import deque
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse
from urllib.request import urlopen

import cv2
import numpy as np

from elbow_tracker import ElbowRiseTracker
from ft232h_source import (
    PreconfiguredEdgeSource,
    decode_eleven_point_result,
    decode_four_point_result,
    decode_packed_edge,
)
from gesture_filter import GestureFilter, PostSquatAttackGate
from pose_engine import ACTION_NAMES, PoseConfig, PoseEngine
from shoulder_tracker import ShoulderMotionTracker, ShoulderWidthGate


ROOT = Path(__file__).resolve().parent
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SOURCE_MODES = {"folder", "ft232h"}
SINGLE_INSTANCE_MUTEX = r"Local\SoulRiderBridge.FT232H"
ERROR_ALREADY_EXISTS = 183
SESSION_DIR_PATTERN = re.compile(r"^session_(\d+)_")
DETECTION_MODE_KINDS = {
    "yolo": 3,
    "four_point": 4,
    "eleven_point": 5,
}
DETECTION_MODE_NAMES = {
    "yolo": "YOLO",
    "four_point": "四点检测",
    "eleven_point": "十一点检测",
}
DEBUG_TUNING_SPECS = {
    "elbow_rise_shoulder_ratio": {
        "label": "肘部抬升比例",
        "type": "float",
        "min": 0.1,
        "max": 2.0,
        "step": 0.05,
    },
    "elbow_rise_min_pixels": {
        "label": "最小抬升像素",
        "type": "float",
        "min": 2.0,
        "max": 100.0,
        "step": 1.0,
    },
    "elbow_rise_max_pixels": {
        "label": "最大抬升像素",
        "type": "float",
        "min": 5.0,
        "max": 200.0,
        "step": 1.0,
    },
    "elbow_release_pixels": {
        "label": "释放回落像素",
        "type": "float",
        "min": 0.0,
        "max": 60.0,
        "step": 1.0,
    },
    "elbow_release_frames": {
        "label": "释放确认帧",
        "type": "int",
        "min": 1,
        "max": 10,
        "step": 1,
    },
    "wrist_rise_elbow_ratio": {
        "label": "腕部抬升/肘部阈值",
        "type": "float",
        "min": 0.1,
        "max": 1.5,
        "step": 0.05,
    },
    "wrist_max_below_elbow_ratio": {
        "label": "腕部低于肘部上限",
        "type": "float",
        "min": 0.0,
        "max": 1.0,
        "step": 0.05,
    },
    "attack_keypoint_median_frames": {
        "label": "肘部中值帧数",
        "type": "int",
        "min": 1,
        "max": 9,
        "step": 1,
    },
    "fpga_point_conf": {
        "label": "FPGA 点有效阈值",
        "type": "float",
        "min": 0.01,
        "max": 0.9,
        "step": 0.01,
    },
    "lower_body_point_conf": {
        "label": "髋部关键点阈值",
        "type": "float",
        "min": 0.05,
        "max": 0.9,
        "step": 0.01,
    },
    "pose_max_shoulder_width_px": {
        "label": "最大有效肩宽",
        "type": "float",
        "min": 100.0,
        "max": 1000.0,
        "step": 10.0,
    },
    "pose_max_width_change_ratio": {
        "label": "肩宽跳变容忍比例",
        "type": "float",
        "min": 0.1,
        "max": 3.0,
        "step": 0.05,
    },
    "attack_confirm_window_frames": {
        "label": "投票窗口帧数",
        "type": "int",
        "min": 1,
        "max": 12,
        "step": 1,
    },
    "attack_confirm_min_votes": {
        "label": "最少确认票数",
        "type": "int",
        "min": 1,
        "max": 12,
        "step": 1,
    },
    "attack_cooldown_ms": {
        "label": "攻击冷却",
        "type": "int",
        "min": 0,
        "max": 5000,
        "step": 50,
    },
    "shoulder_speed_window_frames": {
        "label": "下蹲速度窗口",
        "type": "int",
        "min": 3,
        "max": 15,
        "step": 1,
    },
    "shoulder_speed_threshold_ratio": {
        "label": "下蹲速度阈值",
        "type": "float",
        "min": 0.01,
        "max": 2.0,
        "step": 0.01,
    },
    "shoulder_min_drop_ratio": {
        "label": "下蹲位移阈值",
        "type": "float",
        "min": 0.01,
        "max": 0.5,
        "step": 0.01,
    },
    "shoulder_hip_speed_threshold_ratio": {
        "label": "髋部下降速度阈值",
        "type": "float",
        "min": 0.01,
        "max": 1.0,
        "step": 0.01,
    },
    "shoulder_hip_min_drop_ratio": {
        "label": "髋部下降位移阈值",
        "type": "float",
        "min": 0.01,
        "max": 0.5,
        "step": 0.01,
    },
    "shoulder_symmetry_ratio": {
        "label": "左右肩对称阈值",
        "type": "float",
        "min": 0.01,
        "max": 0.5,
        "step": 0.01,
    },
    "shoulder_confirm_frames": {
        "label": "下蹲确认帧",
        "type": "int",
        "min": 1,
        "max": 10,
        "step": 1,
    },
    "shoulder_upward_reanchor_ratio": {
        "label": "肩部上移回锚比例",
        "type": "float",
        "min": 0.01,
        "max": 0.5,
        "step": 0.01,
    },
    "shoulder_upward_reanchor_frames": {
        "label": "肩部上移回锚帧",
        "type": "int",
        "min": 1,
        "max": 10,
        "step": 1,
    },
    "shoulder_upward_reanchor_hold_ms": {
        "label": "肩部稳定回锚时间",
        "type": "int",
        "min": 100,
        "max": 2000,
        "step": 50,
    },
    "shoulder_squat_recovery_ratio": {
        "label": "下蹲恢复比例",
        "type": "float",
        "min": 0.05,
        "max": 0.8,
        "step": 0.01,
    },
    "shoulder_squat_release_frames": {
        "label": "下蹲恢复确认帧",
        "type": "int",
        "min": 1,
        "max": 10,
        "step": 1,
    },
    "post_squat_suppress_ms": {
        "label": "下蹲后抑制时间",
        "type": "int",
        "min": 0,
        "max": 3000,
        "step": 50,
    },
    "post_squat_confirm_frames": {
        "label": "下蹲门控确认帧",
        "type": "int",
        "min": 1,
        "max": 10,
        "step": 1,
    },
    "post_squat_max_gate_ms": {
        "label": "下蹲门控最长时间",
        "type": "int",
        "min": 100,
        "max": 5000,
        "step": 50,
    },
    "post_squat_neutral_frames": {
        "label": "下蹲后中立帧",
        "type": "int",
        "min": 0,
        "max": 15,
        "step": 1,
    },
    "calibration_timeout_ms": {
        "label": "校准最长时间",
        "type": "int",
        "min": 500,
        "max": 10000,
        "step": 100,
    },
    "calibration_hold_ms": {
        "label": "校准滑动窗口",
        "type": "int",
        "min": 200,
        "max": 3000,
        "step": 100,
    },
    "calibration_neutral_ratio": {
        "label": "窗口内中立帧比例",
        "type": "float",
        "min": 0.5,
        "max": 0.95,
        "step": 0.05,
    },
    "invalid_reset_ms": {
        "label": "异常状态清理时间",
        "type": "int",
        "min": 200,
        "max": 3000,
        "step": 100,
    },
    "human_confidence_threshold": {
        "label": "人体置信度阈值",
        "type": "float",
        "min": 0.30,
        "max": 0.99,
        "step": 0.01,
    },
    "arm_rule_weight": {
        "label": "成熟抬手规则权重",
        "type": "float",
        "min": 0.0,
        "max": 1.0,
        "step": 0.05,
    },
    "arm_model_weight": {
        "label": "左右手模型权重",
        "type": "float",
        "min": 0.0,
        "max": 1.0,
        "step": 0.05,
    },
    "combined_confidence_threshold": {
        "label": "融合抬手阈值",
        "type": "float",
        "min": 0.10,
        "max": 0.99,
        "step": 0.01,
    },
    "model_side_mirrored": {
        "label": "模型左右镜像(0/1)",
        "type": "int",
        "min": 0,
        "max": 1,
        "step": 1,
    },
    "arm_model_enabled": {
        "label": "启用左右手模型",
        "type": "bool",
        "min": 0,
        "max": 1,
        "step": 1,
    },
}
DEBUG_TUNING_DEFAULTS = {
    "elbow_rise_shoulder_ratio": 0.5,
    "elbow_rise_min_pixels": 14.0,
    "elbow_rise_max_pixels": 45.0,
    "elbow_release_pixels": 8.0,
    "elbow_release_frames": 2,
    "wrist_rise_elbow_ratio": 0.65,
    "wrist_max_below_elbow_ratio": 0.20,
    "attack_keypoint_median_frames": 3,
    "fpga_point_conf": 0.12,
    "lower_body_point_conf": 0.20,
    "pose_max_shoulder_width_px": 520.0,
    "pose_max_width_change_ratio": 1.0,
    "pose_stable_frames": 2,
    "pose_outlier_confirm_frames": 2,
    "pose_width_median_frames": 3,
    "attack_confirm_window_frames": 4,
    "attack_confirm_min_votes": 2,
    "attack_cooldown_ms": 600,
    "shoulder_speed_window_frames": 5,
    "shoulder_speed_threshold_ratio": 0.2,
    "shoulder_min_drop_ratio": 0.08,
    "shoulder_hip_speed_threshold_ratio": 0.12,
    "shoulder_hip_min_drop_ratio": 0.05,
    "shoulder_symmetry_ratio": 0.50,
    "shoulder_confirm_frames": 2,
    "shoulder_upward_reanchor_ratio": 0.08,
    "shoulder_upward_reanchor_frames": 2,
    "shoulder_upward_reanchor_hold_ms": 400,
    "shoulder_squat_recovery_ratio": 0.18,
    "shoulder_squat_release_frames": 2,
    "post_squat_suppress_ms": 300,
    "post_squat_confirm_frames": 2,
    "post_squat_max_gate_ms": 1000,
    "post_squat_neutral_frames": 3,
    "calibration_timeout_ms": 5000,
    "calibration_hold_ms": 1000,
    "calibration_neutral_ratio": 0.7,
    "invalid_reset_ms": 1500,
    "human_confidence_threshold": 0.65,
    "arm_rule_weight": 0.70,
    "arm_model_weight": 0.30,
    "combined_confidence_threshold": 0.10,
    "model_side_mirrored": 1,
    "arm_model_enabled": 0,
}
DEBUG_POINT_COLORS = (
    (255, 221, 73),
    (255, 204, 85),
    (153, 255, 89),
    (255, 119, 153),
    (137, 221, 255),
    (89, 239, 255),
    (255, 190, 120),
    (180, 140, 255),
    (115, 210, 255),
    (160, 255, 190),
    (255, 155, 210),
)
COCO_KEYPOINT_NAMES = [
    "nose",
    "left_eye",
    "right_eye",
    "left_ear",
    "right_ear",
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
    "left_ankle",
    "right_ankle",
]
POINT_SHORT_NAMES = {
    "head": "head",
    "left_shoulder": "L.sh",
    "right_shoulder": "R.sh",
    "left_elbow": "L.el",
    "right_elbow": "R.el",
    "left_wrist": "L.wr",
    "right_wrist": "R.wr",
    "left_hip": "L.hip",
    "right_hip": "R.hip",
    "left_knee": "L.kn",
    "right_knee": "R.kn",
}


class SessionLogger:
    """Write session-scoped bridge and browser events and retain recent runs."""

    def __init__(self, root: Path, keep_sessions: int = 3) -> None:
        self.root = Path(root)
        self.keep_sessions = max(1, int(keep_sessions))
        self.lock = threading.RLock()
        self.current: dict | None = None
        self.event_counts: dict[str, int] = {}
        self.recent_events: deque[dict] = deque(maxlen=500)
        self.next_event_id = 1
        self._bridge_handle = None
        self._game_handle = None

    def current_info(self) -> dict:
        with self.lock:
            if self.current is None:
                return {
                    "test_session_id": None,
                    "test_session_name": "",
                    "test_session_dir": "",
                    "test_session_started_at": "",
                    "test_session_event_counts": {},
                }
            return {
                "test_session_id": self.current["session_id"],
                "test_session_name": self.current["name"],
                "test_session_dir": str(self.current["path"]),
                "test_session_started_at": self.current["started_at"],
                "test_session_event_counts": dict(self.event_counts),
            }

    def start_session(
        self,
        reason: str,
        metadata: dict | None = None,
    ) -> dict:
        with self.lock:
            if self.current is not None:
                self._end_locked("replaced")

            self.root.mkdir(parents=True, exist_ok=True)
            existing_ids = []
            for path in self.root.iterdir():
                if not path.is_dir():
                    continue
                match = SESSION_DIR_PATTERN.match(path.name)
                if match:
                    existing_ids.append(int(match.group(1)))
            session_id = max(existing_ids, default=0) + 1

            now = time.time()
            local_time = datetime.fromtimestamp(now).astimezone()
            session_name = (
                f"session_{session_id:04d}_"
                f"{local_time.strftime('%Y%m%d_%H%M%S')}"
            )
            session_path = self.root / session_name
            suffix = 1
            while session_path.exists():
                suffix += 1
                session_path = self.root / f"{session_name}_{suffix}"
            session_path.mkdir(parents=True)
            self._bridge_handle = (session_path / "bridge.jsonl").open(
                "a",
                encoding="utf-8",
            )
            self._game_handle = (session_path / "game.jsonl").open(
                "a",
                encoding="utf-8",
            )
            self.current = {
                "session_id": session_id,
                "name": session_name,
                "path": session_path,
                "started_at": local_time.isoformat(timespec="milliseconds"),
                "started_unix": now,
                "reason": reason,
                "metadata": metadata or {},
            }
            self.event_counts = {}
            self.recent_events.clear()
            self._write_session_metadata_locked()
            self.log_event(
                "bridge",
                "session_started",
                {
                    "reason": reason,
                    "pid": os.getpid(),
                    "metadata": metadata or {},
                },
            )
            self._write_latest_pointer_locked()
            self._prune_locked()
            return self.current_info()

    def end_session(
        self,
        session_id: int | None = None,
        reason: str = "webpage_closed",
    ) -> dict:
        with self.lock:
            if self.current is None:
                return {
                    "ok": False,
                    "error": "no active log session",
                    **self.current_info(),
                }
            if (
                session_id is not None
                and int(session_id) != self.current["session_id"]
            ):
                return {
                    "ok": False,
                    "error": "stale log session",
                    **self.current_info(),
                }
            info = self.current_info()
            self._end_locked(reason)
            return {"ok": True, **info, "end_reason": reason}

    def close(self) -> None:
        with self.lock:
            if self.current is not None:
                self._end_locked("bridge_shutdown")

    def log_event(
        self,
        stream: str,
        event: str,
        fields: dict | None = None,
    ) -> bool:
        with self.lock:
            if self.current is None:
                return False
            handle = self._game_handle if stream == "game" else self._bridge_handle
            if handle is None:
                return False
            now = time.time()
            record = {
                "event_id": self.next_event_id,
                "ts": datetime.fromtimestamp(now).astimezone().isoformat(
                    timespec="milliseconds"
                ),
                "ts_unix": round(now, 6),
                "session_id": self.current["session_id"],
                "stream": stream,
                "event": str(event or "unknown")[:96],
            }
            self.next_event_id += 1
            if fields:
                record.update(fields)
            handle.write(
                json.dumps(
                    record,
                    ensure_ascii=False,
                    default=str,
                )
                + "\n"
            )
            handle.flush()
            count_key = f"{stream}:{record['event']}"
            self.event_counts[count_key] = self.event_counts.get(count_key, 0) + 1
            self.recent_events.append(record)
            return True

    def recent_events_since(
        self,
        after_event_id: int = 0,
        limit: int = 250,
    ) -> list[dict]:
        with self.lock:
            result = [
                dict(event)
                for event in self.recent_events
                if int(event.get("event_id", 0)) > after_event_id
            ]
            return result[-max(1, min(int(limit), 500)):]

    def _end_locked(self, reason: str) -> None:
        if self.current is None:
            return
        self.log_event(
            "bridge",
            "session_ended",
            {
                "reason": reason,
                "event_counts": dict(self.event_counts),
            },
        )
        self.current["ended_at"] = datetime.now().astimezone().isoformat(
            timespec="milliseconds"
        )
        self.current["ended_unix"] = time.time()
        self.current["end_reason"] = reason
        self._write_session_metadata_locked()
        if self._bridge_handle is not None:
            self._bridge_handle.close()
        if self._game_handle is not None:
            self._game_handle.close()
        self._bridge_handle = None
        self._game_handle = None
        self.current = None
        self.event_counts = {}

    def _write_session_metadata_locked(self) -> None:
        if self.current is None:
            return
        metadata = {
            "session_id": self.current["session_id"],
            "name": self.current["name"],
            "started_at": self.current["started_at"],
            "started_unix": self.current["started_unix"],
            "reason": self.current["reason"],
            "metadata": self.current["metadata"],
            "ended_at": self.current.get("ended_at"),
            "ended_unix": self.current.get("ended_unix"),
            "end_reason": self.current.get("end_reason"),
            "event_counts": dict(self.event_counts),
        }
        (self.current["path"] / "session.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2, default=str) + "\n",
            encoding="utf-8",
        )

    def _write_latest_pointer_locked(self) -> None:
        if self.current is None:
            return
        (self.root / "latest_session.txt").write_text(
            str(self.current["path"]) + "\n",
            encoding="utf-8",
        )

    def _prune_locked(self) -> None:
        sessions: list[tuple[int, Path]] = []
        for path in self.root.iterdir():
            if not path.is_dir():
                continue
            match = SESSION_DIR_PATTERN.match(path.name)
            if match:
                sessions.append((int(match.group(1)), path))
        sessions.sort(key=lambda item: item[0])
        while len(sessions) > self.keep_sessions:
            _, oldest = sessions.pop(0)
            resolved = oldest.resolve()
            if resolved.parent != self.root.resolve():
                continue
            shutil.rmtree(resolved)


class AlreadyRunningError(RuntimeError):
    """Raised when another SoulRider bridge already owns the process lock."""


class SingleInstanceGuard:
    """Hold a Windows named mutex for the lifetime of the bridge process."""

    def __init__(self, name: str = SINGLE_INSTANCE_MUTEX) -> None:
        self.name = name
        self.handle: int | None = None
        self._kernel32 = None

    def acquire(self) -> None:
        if os.name != "nt":
            return
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CreateMutexW.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_wchar_p,
        ]
        kernel32.CreateMutexW.restype = ctypes.c_void_p
        kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
        kernel32.CloseHandle.restype = ctypes.c_int

        ctypes.set_last_error(0)
        handle = kernel32.CreateMutexW(None, 0, self.name)
        error = ctypes.get_last_error()
        if not handle:
            raise ctypes.WinError(error)
        if error == ERROR_ALREADY_EXISTS:
            kernel32.CloseHandle(handle)
            raise AlreadyRunningError(
                "another SoulRiderBridge process is already running"
            )
        self._kernel32 = kernel32
        self.handle = int(handle)

    def release(self) -> None:
        if self.handle is None or self._kernel32 is None:
            return
        handle = self.handle
        kernel32 = self._kernel32
        self.handle = None
        self._kernel32 = None
        kernel32.CloseHandle(handle)

    def __enter__(self) -> "SingleInstanceGuard":
        self.acquire()
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        self.release()


def existing_bridge_state(port: int, timeout_s: float = 0.75) -> dict | None:
    """Return /state from an already-running bridge, or None when absent."""
    try:
        with urlopen(
            f"http://127.0.0.1:{port}/state",
            timeout=timeout_s,
        ) as response:
            state = json.loads(response.read().decode("utf-8"))
    except (OSError, ValueError):
        return None
    if isinstance(state, dict) and "source_mode" in state:
        return state
    return None


def render_point_debug(result: dict, output_dir: Path) -> Path:
    """Render a point-result packet on a 640x360 debug canvas."""
    width = int(result.get("width", 640))
    height = int(result.get("height", 360))
    canvas = np.full((height, width, 3), (30, 22, 16), dtype=np.uint8)

    points = result["points"]
    for start, end in result["skeleton_edges"]:
        start_point = points[start]
        end_point = points[end]
        cv2.line(
            canvas,
            (int(round(start_point["x"])), int(round(start_point["y"]))),
            (int(round(end_point["x"])), int(round(end_point["y"]))),
            (170, 153, 136),
            2,
            cv2.LINE_AA,
        )

    for index, point in enumerate(points):
        center = (int(round(point["x"])), int(round(point["y"])))
        color = DEBUG_POINT_COLORS[index % len(DEBUG_POINT_COLORS)]
        radius = 7 if point["name"] == "head" else 5
        cv2.circle(canvas, center, radius, color, -1, cv2.LINE_AA)
        cv2.circle(canvas, center, radius, (245, 245, 245), 1, cv2.LINE_AA)
        label = POINT_SHORT_NAMES.get(point["name"], point["name"])
        cv2.putText(
            canvas,
            label,
            (center[0] + 7, center[1] - 7),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38,
            color,
            1,
            cv2.LINE_AA,
        )

    status = (
        f"seq={result.get('sequence', '?')}  "
        f"model={result['model_crc_hex']}  "
        f"flags={result['flags']:02x}  "
        f"valid={int(result['valid'])} live={int(result['is_live'])}  "
        f"net={result['inference_ms']:.2f} ms"
    )
    cv2.putText(
        canvas,
        status,
        (12, 22),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.46,
        (242, 237, 232),
        1,
        cv2.LINE_AA,
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "current_pose.jpg"
    cv2.imwrite(
        str(output_path),
        canvas,
        [cv2.IMWRITE_JPEG_QUALITY, 94],
    )
    return output_path


class DemoController:
    def __init__(
        self,
        config: dict,
        event_logger: SessionLogger | None = None,
    ):
        self.lock = threading.RLock()
        self.condition = threading.Condition(self.lock)
        self.stop_event = threading.Event()
        self.event_logger = event_logger
        self.config = {**DEBUG_TUNING_DEFAULTS, **dict(config)}
        self.ft232_log_payload_bytes = max(
            0,
            int(self.config.get("ft232_log_payload_bytes", 512)),
        )
        self._last_ft232_error_key: str | None = None
        self._last_ft232_error_at = 0.0
        self._ft232_error_repeat_count = 0
        self.source_mode = str(self.config.get("source_mode", "ft232h")).lower()
        if self.source_mode not in SOURCE_MODES:
            raise ValueError(f"unsupported source_mode: {self.source_mode}")
        self.engine = PoseEngine(
            PoseConfig(
                model=ROOT / "models" / "fpga_image5_best.pt",
                device=str(self.config.get("device", "0")),
                bbox_conf=float(self.config.get("bbox_conf", 0.20)),
                keypoint_conf=float(self.config.get("keypoint_conf", 0.10)),
                fpga_point_conf=float(
                    self.config.get("fpga_point_conf", 0.12)
                ),
                lower_body_point_conf=float(
                    self.config.get("lower_body_point_conf", 0.20)
                ),
                pose_max_shoulder_width_px=float(
                    self.config.get("pose_max_shoulder_width_px", 520.0)
                ),
                pose_max_width_change_ratio=float(
                    self.config.get("pose_max_width_change_ratio", 1.0)
                ),
                pose_stable_frames=int(
                    self.config.get("pose_stable_frames", 2)
                ),
                pose_outlier_confirm_frames=int(
                    self.config.get("pose_outlier_confirm_frames", 2)
                ),
                pose_width_median_frames=int(
                    self.config.get("pose_width_median_frames", 3)
                ),
                elbow_rise_pixels=float(self.config.get("elbow_rise_pixels", 20.0)),
                elbow_release_pixels=float(
                    self.config.get("elbow_release_pixels", 8.0)
                ),
                elbow_release_frames=int(
                    self.config.get("elbow_release_frames", 2)
                ),
                elbow_tracker_stale_s=float(
                    self.config.get("elbow_tracker_stale_s", 0.5)
                ),
                elbow_median_frames=int(
                    self.config.get("attack_keypoint_median_frames", 3)
                ),
                elbow_rise_shoulder_ratio=float(
                    self.config.get("elbow_rise_shoulder_ratio", 0.50)
                ),
                elbow_rise_min_pixels=float(
                    self.config.get("elbow_rise_min_pixels", 14.0)
                ),
                elbow_rise_max_pixels=float(
                    self.config.get("elbow_rise_max_pixels", 45.0)
                ),
                wrist_rise_elbow_ratio=float(
                    self.config.get("wrist_rise_elbow_ratio", 0.65)
                ),
                wrist_max_below_elbow_ratio=float(
                    self.config.get("wrist_max_below_elbow_ratio", 0.20)
                ),
                shoulder_width_confirm_frames=int(
                    self.config.get("shoulder_width_confirm_frames", 3)
                ),
                shoulder_width_agreement_ratio=float(
                    self.config.get("shoulder_width_agreement_ratio", 0.25)
                ),
                shoulder_speed_window_frames=int(
                    self.config.get("shoulder_speed_window_frames", 5)
                ),
                shoulder_speed_threshold_ratio=float(
                    self.config.get("shoulder_speed_threshold_ratio", 0.20)
                ),
                shoulder_min_drop_ratio=float(
                    self.config.get("shoulder_min_drop_ratio", 0.08)
                ),
                shoulder_hip_speed_threshold_ratio=float(
                    self.config.get("shoulder_hip_speed_threshold_ratio", 0.12)
                ),
                shoulder_hip_min_drop_ratio=float(
                    self.config.get("shoulder_hip_min_drop_ratio", 0.05)
                ),
                shoulder_release_ratio=float(
                    self.config.get("shoulder_release_ratio", 0.05)
                ),
                shoulder_symmetry_ratio=float(
                    self.config.get("shoulder_symmetry_ratio", 0.06)
                ),
                shoulder_confirm_frames=int(
                    self.config.get("shoulder_confirm_frames", 2)
                ),
                shoulder_tracker_stale_s=float(
                    self.config.get("shoulder_tracker_stale_s", 0.8)
                ),
                shoulder_upward_reanchor_ratio=float(
                    self.config.get("shoulder_upward_reanchor_ratio", 0.08)
                ),
                shoulder_upward_reanchor_frames=int(
                    self.config.get("shoulder_upward_reanchor_frames", 2)
                ),
                shoulder_upward_reanchor_hold_s=float(
                    self.config.get(
                        "shoulder_upward_reanchor_hold_ms",
                        400,
                    )
                ) / 1000.0,
                shoulder_squat_recovery_ratio=float(
                    self.config.get("shoulder_squat_recovery_ratio", 0.18)
                ),
                shoulder_squat_release_frames=int(
                    self.config.get("shoulder_squat_release_frames", 2)
                ),
                pose_model_path=Path(
                    self.config.get(
                        "pose_model_path",
                        "models/eleven_point_model.npz",
                    )
                ),
                human_confidence_threshold=float(
                    self.config.get("human_confidence_threshold", 0.65)
                ),
                arm_rule_weight=float(
                    self.config.get("arm_rule_weight", 0.70)
                ),
                arm_model_weight=float(
                    self.config.get("arm_model_weight", 0.30)
                ),
                combined_confidence_threshold=float(
                    self.config.get("combined_confidence_threshold", 0.55)
                ),
                model_side_mirrored=bool(
                    int(self.config.get("model_side_mirrored", 1))
                ),
                arm_model_enabled=bool(
                    int(self.config.get("arm_model_enabled", 0))
                ),
            )
        )
        self.input_dir = Path(self.config.get("input_dir", "")).expanduser()
        self.interval_ms = int(self.config.get("interval_ms", 1000))
        self.ft232h_serial = str(self.config.get("ft232h_serial", ""))
        self.live_width = int(self.config.get("ft232h_width", 640))
        self.live_height = int(
            self.config.get("ft232h_height", self.live_width * 9 // 16)
        )
        self.live_target_fps = max(1, int(self.config.get("live_target_fps", 30)))
        configured_mode = str(self.config.get("detection_mode", "")).lower()
        if not configured_mode:
            configured_mode = {
                3: "yolo",
                4: "four_point",
                5: "eleven_point",
            }.get(
                int(self.config.get("ft232h_kind", 5)),
                "eleven_point",
            )
        if configured_mode not in DETECTION_MODE_KINDS:
            raise ValueError(f"unsupported detection_mode: {configured_mode}")
        if self.source_mode == "folder":
            configured_mode = "yolo"
        self.detection_mode = configured_mode
        self.live_kind = DETECTION_MODE_KINDS[self.detection_mode]
        self.mode_generation = 0
        self.live_wait_s = max(
            0.05,
            float(self.config.get("ft232h_wait_ms", 150)) / 1000.0,
        )
        self.live_stall_timeout_s = max(
            0.5,
            float(self.config.get("ft232h_stall_timeout_ms", 3000)) / 1000.0,
        )
        self.gesture_confirm_frames = int(
            self.config.get("gesture_confirm_frames", 2)
        )
        self.attack_confirm_window_frames = int(
            self.config.get("attack_confirm_window_frames", 4)
        )
        self.attack_confirm_min_votes = int(
            self.config.get("attack_confirm_min_votes", 2)
        )
        self.attack_cooldown_ms = int(
            self.config.get("attack_cooldown_ms", 1000)
        )
        self.gesture_filter = GestureFilter(
            self.gesture_confirm_frames,
            self.attack_cooldown_ms / 1000.0,
            window_frames=self.attack_confirm_window_frames,
            min_votes=self.attack_confirm_min_votes,
        )
        self.post_squat_gate = PostSquatAttackGate(
            suppress_s=(
                float(self.config.get("post_squat_suppress_ms", 300)) / 1000.0
            ),
            neutral_frames=int(
                self.config.get("post_squat_neutral_frames", 3)
            ),
            squat_confirm_frames=int(
                self.config.get("post_squat_confirm_frames", 2)
            ),
            max_gate_s=(
                float(self.config.get("post_squat_max_gate_ms", 1000)) / 1000.0
            ),
        )
        self.output_dir = ROOT / "outputs" / "live"
        self.history_path = ROOT / "outputs" / "history.csv"
        self.files: list[Path] = []
        self.index = 0
        self.paused = False
        self.game_active = False
        self.skip_wait = False
        self.frame_seq = 0
        self.action_seq = 0
        self.last_trigger_action = "stand"
        self.body_action_seq = 0
        self.last_trigger_body_action = "stand"
        self.last_body_action = "stand"
        self.session_id = 0
        self.last_history_write = 0.0
        self.last_live_valid_at = 0.0
        self.last_live_frame_at = 0.0
        self.last_live_wait_update = 0.0
        self.live_reopen_count = 0
        self.last_live_recovery = ""
        self.calibration_timeout_s = max(
            0.5,
            float(self.config.get("calibration_timeout_ms", 3000)) / 1000.0,
        )
        self.calibration_hold_s = max(
            0.2,
            float(self.config.get("calibration_hold_ms", 1000)) / 1000.0,
        )
        self.calibration_neutral_ratio = max(
            0.5,
            min(
                0.95,
                float(self.config.get("calibration_neutral_ratio", 0.7)),
            ),
        )
        self.calibration_samples: deque[tuple[float, bool, bool, str]] = (
            deque()
        )
        self.invalid_reset_s = max(
            0.2,
            float(self.config.get("invalid_reset_ms", 1500)) / 1000.0,
        )
        self.calibration_required_frames = 3
        self.calibration_started_at = 0.0
        self.calibration_neutral_started_at = 0.0
        self.calibration_status = "idle"
        self.calibration_reason = "not_started"
        self.calibration_neutral_frames = 0
        self.calibration_ready = False
        self.pose_invalid_since = 0.0
        self.pose_invalid_reason = ""
        self.inference_fps = 0.0
        self.history: list[dict] = []
        self.state = {
            "ok": False,
            "err": "waiting_game_start",
            "present": False,
            "cx": 0.5,
            "pose_id": 1,
            "action": "stand",
            "action_name": "站立",
            "body_action": "stand",
            "body_action_name": "站立",
            "attack_action": "stand",
            "attack_suppressed": False,
            "attack_gated": False,
            "action_seq": 0,
            "trigger_action": "stand",
            "body_action_seq": 0,
            "trigger_body_action": "stand",
            "frame_seq": 0,
            "hold_ms": 0,
            "input_dir": "",
            "paused": False,
            "game_active": False,
            "source_mode": self.source_mode,
            "detection_mode": self.detection_mode,
            "detection_mode_name": DETECTION_MODE_NAMES[self.detection_mode],
            "session_id": self.session_id,
            "expected_width": self.live_width if self.source_mode == "ft232h" else None,
            "expected_height": self.live_height if self.source_mode == "ft232h" else None,
            "expected_kind": self.live_kind if self.source_mode == "ft232h" else None,
            "stream_healthy": False,
            "stream_watchdog_timeout_s": self.live_stall_timeout_s,
            "stream_reopen_count": self.live_reopen_count,
            "last_stream_recovery": self.last_live_recovery,
            "attack_cooldown_ms": self.attack_cooldown_ms,
            "attack_confirm_window_frames": self.attack_confirm_window_frames,
            "attack_confirm_min_votes": self.attack_confirm_min_votes,
            "attack_keypoint_median_frames": (
                self.engine.config.elbow_median_frames
                if hasattr(self.engine, "config") else 3
            ),
            "elbow_release_frames": (
                self.engine.config.elbow_release_frames
                if hasattr(self.engine, "config") else 2
            ),
            "wrist_rise_elbow_ratio": (
                self.engine.config.wrist_rise_elbow_ratio
                if hasattr(self.engine, "config") else 0.65
            ),
            "wrist_max_below_elbow_ratio": (
                self.engine.config.wrist_max_below_elbow_ratio
                if hasattr(self.engine, "config") else 0.20
            ),
            "calibration": {
                "state": self.calibration_status,
                "reason": self.calibration_reason,
                "ready": self.calibration_ready,
                "progress": 0.0,
                "neutral_frames": 0,
                "required_frames": self.calibration_required_frames,
                "elapsed_ms": 0,
                "timeout_ms": round(self.calibration_timeout_s * 1000),
            },
            "calibration_ready": False,
            "calibration_state": "idle",
            "debug": {
                "trace_id": f"s{self.session_id}-f0",
                "keypoint_threshold": self.engine.config.keypoint_conf,
                "bbox_threshold": self.engine.config.bbox_conf,
            },
            "stream": {},
        }
        target = self.worker if self.source_mode == "folder" else self.live_worker
        name = "folder-pose-worker" if self.source_mode == "folder" else "ft232h-pose-worker"
        self.thread = threading.Thread(target=target, name=name, daemon=True)
        self.thread.start()
        if self.source_mode == "folder" and self.config.get("input_dir"):
            self.set_input_dir(self.config["input_dir"])

    def scan(self) -> None:
        self.files = sorted(
            path for path in self.input_dir.iterdir()
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        )
        self.index = 0
        self.frame_seq = 0
        self.action_seq = 0
        self.last_trigger_action = "stand"
        self.body_action_seq = 0
        self.last_trigger_body_action = "stand"
        self.last_body_action = "stand"
        self.history.clear()
        self.state.update({
            "index": 0,
            "total": len(self.files),
            "frame_seq": 0,
            "action_seq": 0,
            "trigger_action": "stand",
            "body_action_seq": 0,
            "trigger_body_action": "stand",
            "body_action": "stand",
            "body_action_name": "站立",
            "attack_action": "stand",
            "attack_suppressed": False,
            "game_active": self.game_active,
        })
        if not self.files:
            self.state.update({
                "ok": False,
                "err": "no_supported_images",
                "present": False,
                "pose_id": 1,
                "action": "stand",
                "action_name": "站立",
                "body_action": "stand",
                "body_action_name": "站立",
                "attack_action": "stand",
                "attack_suppressed": False,
                "input_dir": str(self.input_dir),
            })
        else:
            self.state.update({
                "ok": False,
                "err": "waiting_game_start",
                "present": False,
                "pose_id": 1,
                "action": "stand",
                "action_name": "站立",
                "body_action": "stand",
                "body_action_name": "站立",
                "attack_action": "stand",
                "attack_suppressed": False,
                "input_dir": str(self.input_dir),
                "game_active": self.game_active,
            })

    def set_input_dir(self, value: str) -> dict:
        if self.source_mode != "folder":
            return {
                "ok": False,
                "error": "当前为 FT232H preconfigured 模式，不能切换图片目录",
            }
        path = Path(value).expanduser()
        if not path.is_absolute():
            path = (ROOT / path).resolve()
        if not path.is_dir():
            return {"ok": False, "error": f"目录不存在: {path}"}
        with self.condition:
            self.input_dir = path
            self.paused = False
            self.skip_wait = True
            self.scan()
            self.condition.notify_all()
        try:
            config_path = ROOT / "config.json"
            config = json.loads(config_path.read_text(encoding="utf-8")) if config_path.is_file() else {}
            config["input_dir"] = str(path)
            config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        except OSError:
            pass
        return {"ok": True, "input_dir": str(path), "images": len(self.files)}

    def set_detection_mode(self, value: str) -> dict:
        mode = value.strip().lower()
        if mode not in DETECTION_MODE_KINDS:
            return {"ok": False, "error": f"不支持的模式: {value}"}
        if self.source_mode != "ft232h":
            return {
                "ok": False,
                "error": "四点/十一点调试模式只支持 FT232H 输入",
            }

        with self.condition:
            if mode == self.detection_mode:
                return {
                    "ok": True,
                    "detection_mode": self.detection_mode,
                    "detection_mode_name": DETECTION_MODE_NAMES[mode],
                }
            previous_mode = self.detection_mode
            self.detection_mode = mode
            self.live_kind = DETECTION_MODE_KINDS[mode]
            self.mode_generation += 1
            self.session_id += 1
            self.frame_seq = 0
            self.action_seq = 0
            self.body_action_seq = 0
            self.last_trigger_action = "stand"
            self.last_trigger_body_action = "stand"
            self.last_body_action = "stand"
            self.inference_fps = 0.0
            self.last_live_valid_at = 0.0
            self.last_live_frame_at = 0.0
            self.last_live_wait_update = 0.0
            self.gesture_filter = GestureFilter(
                self.gesture_confirm_frames,
                self.attack_cooldown_ms / 1000.0,
                window_frames=self.attack_confirm_window_frames,
                min_votes=self.attack_confirm_min_votes,
            )
            self.post_squat_gate.reset()
            self.engine.reset_motion_tracking()
            self.state = {
                "ok": False,
                "err": f"waiting_640x360_kind{self.live_kind}",
                "present": False,
                "cx": 0.5,
                "pose_id": 1,
                "action": "stand",
                "action_name": "站立",
                "body_action": "stand",
                "body_action_name": "站立",
                "attack_action": "stand",
                "attack_suppressed": False,
                "action_seq": 0,
                "trigger_action": "stand",
                "body_action_seq": 0,
                "trigger_body_action": "stand",
                "frame_seq": 0,
                "hold_ms": 0,
                "paused": self.paused,
                "game_active": self.game_active,
                "source_mode": self.source_mode,
                "detection_mode": self.detection_mode,
                "detection_mode_name": DETECTION_MODE_NAMES[mode],
                "session_id": self.session_id,
                "expected_width": self.live_width,
                "expected_height": self.live_height,
                "expected_kind": self.live_kind,
                "stream_healthy": False,
                "stream_watchdog_timeout_s": self.live_stall_timeout_s,
                "stream_reopen_count": self.live_reopen_count,
                "last_stream_recovery": self.last_live_recovery,
                "stream": {},
            }
            self.state["calibration"] = self._start_calibration_locked(
                "mode_changed"
            )
            self.state["calibration_ready"] = False
            self.state["calibration_state"] = self.state["calibration"]["state"]
            self.condition.notify_all()
        self.log_event(
            "bridge",
            "detection_mode_changed",
            {
                "previous_mode": previous_mode,
                "detection_mode": mode,
                "expected_kind": DETECTION_MODE_KINDS[mode],
            },
        )

        try:
            config_path = ROOT / "config.json"
            config = (
                json.loads(config_path.read_text(encoding="utf-8"))
                if config_path.is_file()
                else {}
            )
            self.config["detection_mode"] = mode
            self.config["ft232h_kind"] = DETECTION_MODE_KINDS[mode]
            config["detection_mode"] = mode
            config["ft232h_kind"] = DETECTION_MODE_KINDS[mode]
            config_path.write_text(
                json.dumps(config, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        except OSError:
            pass
        return {
            "ok": True,
            "detection_mode": self.detection_mode,
            "detection_mode_name": DETECTION_MODE_NAMES[mode],
            "expected_kind": self.live_kind,
        }

    def control(self, command: str) -> dict:
        with self.condition:
            if self.source_mode == "ft232h" and command in {"next", "prev", "restart"}:
                return {"ok": False, "error": f"FT232H 模式不支持命令: {command}"}
            if command == "pause":
                self.paused = True
            elif command == "resume":
                self.paused = False
                self.skip_wait = True
            elif command == "next":
                if self.files:
                    self.index = (self.index + 1) % len(self.files)
                self.paused = False
                self.skip_wait = True
            elif command == "prev":
                if self.files:
                    self.index = (self.index - 1) % len(self.files)
                self.paused = False
                self.skip_wait = True
            elif command == "restart":
                self.index = 0
                self.paused = False
                self.skip_wait = True
            else:
                return {"ok": False, "error": f"未知命令: {command}"}
            self.state["paused"] = self.paused
            self.state["game_active"] = self.game_active
            self.condition.notify_all()
        self.log_event(
            "bridge",
            "control_command",
            {
                "command": command,
                "paused": self.paused,
                "game_active": self.game_active,
            },
        )
        return {"ok": True, "command": command, "paused": self.paused, "index": self.index}

    def set_game_active(self, active: bool) -> dict:
        with self.condition:
            previous_active = self.game_active
            self.game_active = active
            self.state["game_active"] = active
            if active:
                self.session_id += 1
                self.index = 0
                self.frame_seq = 0
                self.action_seq = 0
                self.last_trigger_action = "stand"
                self.body_action_seq = 0
                self.last_trigger_body_action = "stand"
                self.last_body_action = "stand"
                self.inference_fps = 0.0
                self.last_live_valid_at = 0.0
                self.last_live_frame_at = 0.0
                self.last_live_wait_update = 0.0
                self.gesture_filter = GestureFilter(
                    self.gesture_confirm_frames,
                    self.attack_cooldown_ms / 1000.0,
                    window_frames=self.attack_confirm_window_frames,
                    min_votes=self.attack_confirm_min_votes,
                )
                self.paused = False
                self.skip_wait = True
                self.history.clear()
                self.state.update({
                    "ok": False,
                    "err": (
                        "opening_ft232h"
                        if self.source_mode == "ft232h"
                        else "waiting_game_start"
                    ),
                    "present": False,
                    "pose_id": 1,
                    "action": "stand",
                    "action_name": "站立",
                    "body_action": "stand",
                    "body_action_name": "站立",
                    "attack_action": "stand",
                    "attack_suppressed": False,
                    "trigger_action": "stand",
                    "body_action_seq": 0,
                    "trigger_body_action": "stand",
                    "paused": False,
                    "session_id": self.session_id,
                    "source_mode": self.source_mode,
                })
                self.state["calibration"] = self._start_calibration_locked(
                    "game_start"
                )
            else:
                self.calibration_status = "idle"
                self.calibration_reason = "game_inactive"
                self.calibration_neutral_frames = 0
                self.calibration_ready = False
                self.state.update({
                    "ok": False,
                    "err": "waiting_game_start",
                    "present": False,
                    "pose_id": 1,
                    "action": "stand",
                    "action_name": "站立",
                    "body_action": "stand",
                    "body_action_name": "站立",
                    "attack_action": "stand",
                    "attack_suppressed": False,
                    "body_action_seq": self.body_action_seq,
                    "trigger_body_action": self.last_trigger_body_action,
                    "session_id": self.session_id,
                    "calibration": self._calibration_snapshot_locked(),
                    "calibration_ready": False,
                    "calibration_state": "idle",
                })
            self.condition.notify_all()
        self.log_event(
            "bridge",
            "game_activity_changed",
            {
                "previous_active": previous_active,
                "game_active": active,
                "session_id": self.session_id,
                "detection_mode": self.detection_mode,
            },
        )
        return {
            "ok": True,
            "game_active": active,
            "session_id": self.session_id,
            "source_mode": self.source_mode,
        }

    def snapshot(self) -> dict:
        with self.lock:
            snapshot = dict(self.state)
        if self.event_logger is not None:
            snapshot.update(self.event_logger.current_info())
        return snapshot

    def _calibration_snapshot_locked(self, now: float | None = None) -> dict:
        timestamp = time.monotonic() if now is None else float(now)
        elapsed_s = (
            max(0.0, timestamp - self.calibration_started_at)
            if self.calibration_started_at
            else 0.0
        )
        window_started = timestamp - self.calibration_hold_s
        while (
            self.calibration_samples
            and self.calibration_samples[0][0] < window_started
        ):
            self.calibration_samples.popleft()
        window_frames = len(self.calibration_samples)
        valid_frames = sum(
            1 for sample in self.calibration_samples if sample[1]
        )
        neutral_frames = sum(
            1 for sample in self.calibration_samples if sample[2]
        )
        valid_ratio = (
            valid_frames / window_frames if window_frames else 0.0
        )
        neutral_ratio = (
            neutral_frames / window_frames if window_frames else 0.0
        )
        consecutive_neutral_misses = 0
        for sample in reversed(self.calibration_samples):
            if sample[2]:
                break
            consecutive_neutral_misses += 1
        coverage_s = 0.0
        if window_frames >= 2:
            coverage_s = max(
                0.0,
                self.calibration_samples[-1][0]
                - self.calibration_samples[0][0],
            )
        coverage_ratio = min(
            1.0,
            coverage_s / max(0.2, self.calibration_hold_s),
        )
        self.calibration_neutral_frames = neutral_frames
        if self.calibration_ready:
            progress = 1.0
        elif self.calibration_status == "timeout":
            progress = 1.0
        else:
            progress = min(
                0.95,
                coverage_ratio * neutral_ratio,
            )
        return {
            "state": self.calibration_status,
            "reason": self.calibration_reason,
            "ready": self.calibration_ready,
            "progress": round(progress, 3),
            "neutral_frames": self.calibration_neutral_frames,
            "required_frames": self.calibration_required_frames,
            "window_frames": window_frames,
            "valid_frames": valid_frames,
            "valid_ratio": round(valid_ratio, 3),
            "neutral_ratio": round(neutral_ratio, 3),
            "neutral_ratio_required": self.calibration_neutral_ratio,
            "consecutive_neutral_misses": consecutive_neutral_misses,
            "window_coverage_ms": round(coverage_s * 1000.0),
            "elapsed_ms": round(elapsed_s * 1000.0),
            "timeout_ms": round(self.calibration_timeout_s * 1000.0),
            "window_ms": round(self.calibration_hold_s * 1000.0),
            "hold_ms": round(self.calibration_hold_s * 1000.0),
            "neutral_elapsed_ms": round(coverage_s * 1000.0),
            "invalid_elapsed_ms": round(
                max(0.0, timestamp - self.pose_invalid_since) * 1000.0
            ) if self.pose_invalid_since else 0,
        }

    def _start_calibration_locked(self, reason: str) -> dict:
        now = time.monotonic()
        self.engine.reset_motion_tracking()
        self.gesture_filter.reset_candidate()
        self.post_squat_gate.reset()
        self.calibration_started_at = now
        self.calibration_neutral_started_at = 0.0
        self.calibration_samples.clear()
        self.calibration_status = "collecting"
        self.calibration_reason = "waiting_for_neutral"
        self.calibration_neutral_frames = 0
        self.calibration_ready = False
        self.pose_invalid_since = 0.0
        self.pose_invalid_reason = ""
        calibration = self._calibration_snapshot_locked()
        calibration["started_by"] = reason
        self.state["calibration"] = calibration
        self.state["calibration_ready"] = False
        self.state["calibration_state"] = calibration["state"]
        return calibration

    def _invalidate_pose_tracking_locked(self, reason: str) -> None:
        self.engine.reset_motion_tracking()
        self.gesture_filter.reset_candidate()
        self.post_squat_gate.invalidate()
        self.calibration_started_at = time.monotonic()
        self.calibration_neutral_started_at = 0.0
        self.calibration_samples.clear()
        self.calibration_status = "collecting"
        self.calibration_reason = reason or "pose_invalid"
        self.calibration_neutral_frames = 0
        self.calibration_ready = False
        self.pose_invalid_since = 0.0
        self.pose_invalid_reason = ""
        self.state.update({
            "present": False,
            "action": "stand",
            "body_action": "stand",
            "attack_action": "stand",
            "calibration_ready": False,
            "calibration_state": "collecting",
        })

    def _update_calibration_locked(self, result: dict) -> dict:
        now = time.monotonic()
        present = bool(result.get("present"))
        stable_valid = bool(
            result.get("stable_valid", present)
        )
        calibration_usable = bool(
            result.get("calibration_usable", present)
        )
        pose_usable = calibration_usable and stable_valid
        invalid_reason = str(
            result.get("validity_reason")
            or result.get("reason")
            or "pose_invalid"
        )
        arms = result.get("arms") or {}
        left = arms.get("left") or {}
        right = arms.get("right") or {}
        both_ready = bool(left.get("filter_ready") and right.get("filter_ready"))
        both_neutral = not bool(left.get("valid")) and not bool(right.get("valid"))
        standing = result.get("body_action", "stand") == "stand"
        neutral_frame = (
            pose_usable
            and standing
            and both_ready
            and both_neutral
        )

        if self.calibration_started_at <= 0.0:
            self.calibration_started_at = now
        self.calibration_samples.append((
            now,
            pose_usable,
            neutral_frame,
            invalid_reason if not pose_usable else (
                "arms_not_neutral"
                if both_ready and not both_neutral
                else ""
            ),
        ))
        calibration = self._calibration_snapshot_locked(now)

        if pose_usable:
            self.pose_invalid_since = 0.0
            self.pose_invalid_reason = ""
        elif self.pose_invalid_since <= 0.0:
            self.pose_invalid_since = now
            self.pose_invalid_reason = invalid_reason

        invalid_elapsed = (
            now - self.pose_invalid_since
            if self.pose_invalid_since
            else 0.0
        )
        if invalid_elapsed >= self.invalid_reset_s:
            self._invalidate_pose_tracking_locked(invalid_reason)
            calibration = self._calibration_snapshot_locked(now)
            self.state["calibration"] = calibration
            self.state["calibration_ready"] = False
            self.state["calibration_state"] = calibration["state"]
            return calibration

        if self.calibration_ready and not pose_usable:
            self.calibration_status = "ready"
            self.calibration_reason = "pose_temporarily_invalid"
            calibration = self._calibration_snapshot_locked(now)
            self.state["calibration"] = calibration
            self.state["calibration_ready"] = True
            self.state["calibration_state"] = "ready"
            return calibration

        if self.calibration_ready and pose_usable:
            self.calibration_status = "ready"
            self.calibration_reason = "ready"
            calibration = self._calibration_snapshot_locked(now)
            self.state["calibration"] = calibration
            self.state["calibration_ready"] = True
            self.state["calibration_state"] = "ready"
            return calibration

        coverage_ok = (
            calibration["window_coverage_ms"]
            >= self.calibration_hold_s * 800.0
        )
        ratios_ok = (
            calibration["valid_ratio"] >= self.calibration_neutral_ratio
            and calibration["neutral_ratio"] >= self.calibration_neutral_ratio
            and calibration["consecutive_neutral_misses"] <= 2
        )
        action_started = (
            str(result.get("body_action", "stand")) != "stand"
            or str(result.get("attack_action", "stand")) != "stand"
            or (both_ready and not both_neutral)
        )
        if (
            pose_usable
            and action_started
            and calibration["valid_frames"] >= self.calibration_required_frames
        ):
            # A stable action is more useful than waiting for a neutral pose.
            # Keep the motion tracker state so the action can trigger now.
            self.calibration_status = "ready"
            self.calibration_reason = "action_started"
            self.calibration_ready = True
            self.post_squat_gate.reset()
        elif coverage_ok and ratios_ok:
            self.calibration_status = "ready"
            self.calibration_reason = "neutral_confirmed"
            self.calibration_ready = True
        elif now - self.calibration_started_at >= self.calibration_timeout_s:
            if pose_usable:
                # Startup must not depend on finding a perfect neutral pose.
                # Once a valid person is present, fall back to the current pose
                # after the bounded warm-up instead of recalibrating forever.
                self.calibration_status = "ready"
                self.calibration_reason = "timeout_auto_ready"
                self.calibration_ready = True
                self.engine.reset_motion_tracking()
                self.gesture_filter.reset_candidate()
                self.post_squat_gate.reset()
            else:
                self.calibration_status = "timeout"
                self.calibration_reason = "calibration_timeout"
                self.calibration_ready = False
        elif not pose_usable:
            self.calibration_status = (
                "waiting_for_person" if not present else "collecting"
            )
            self.calibration_reason = invalid_reason
        elif not standing:
            self.calibration_status = "waiting_for_neutral"
            self.calibration_reason = "body_motion_detected"
        elif not both_ready:
            self.calibration_status = "collecting"
            self.calibration_reason = "insufficient_frames"
        elif calibration["consecutive_neutral_misses"] > 2:
            self.calibration_status = "collecting"
            self.calibration_reason = "pose_not_stable"
        elif not both_neutral:
            self.calibration_status = "waiting_for_neutral"
            self.calibration_reason = "arms_not_neutral"
        else:
            self.calibration_status = "collecting"
            self.calibration_reason = "confirming_neutral"

        calibration = self._calibration_snapshot_locked(now)
        self.state["calibration"] = calibration
        self.state["calibration_ready"] = bool(calibration["ready"])
        self.state["calibration_state"] = calibration["state"]
        return calibration

    def _debug_state_locked(
        self,
        result: dict,
        triggered: bool,
        attack_gated: bool,
        stream: dict,
        mode: str,
    ) -> dict:
        now = time.monotonic()
        gesture = self.gesture_filter.snapshot(now)
        gate = self.post_squat_gate.snapshot(now)
        arms = result.get("arms") or {}
        left = arms.get("left") or {}
        right = arms.get("right") or {}
        attack_action = result.get("attack_action", result.get("action", "stand"))
        body_action = result.get("body_action", "stand")
        present = bool(result.get("present"))
        stable_valid = bool(result.get("stable_valid", present))
        calibration_ready = bool(self._calibration_snapshot_locked(now)["ready"])
        result_reason = str(result.get("reason", ""))
        if result_reason == "human_confidence_below_threshold":
            blocked_stage = "human_confidence_below_threshold"
        elif result_reason == "model_warming_up":
            blocked_stage = "model_warming_up"
        elif not present:
            blocked_stage = "person_not_detected"
        elif not stable_valid:
            blocked_stage = "pose_not_stable"
        elif not calibration_ready:
            blocked_stage = "calibrating"
        elif body_action == "squat":
            blocked_stage = "squat_active"
        elif bool(result.get("model_rule_conflict")):
            blocked_stage = "model_rule_conflict"
        elif result_reason == "combined_confidence_below_threshold":
            blocked_stage = "combined_confidence_below_threshold"
        elif attack_gated:
            blocked_stage = "post_squat_gate"
        elif (
            attack_action != "stand"
            and gesture["cooldown_remaining_ms"] > 0
        ):
            blocked_stage = "attack_cooldown"
        elif (
            attack_action != "stand"
            and gesture["candidate_frames"] < gesture["min_votes"]
        ):
            blocked_stage = "gesture_votes"
        elif triggered:
            blocked_stage = "event_emitted"
        elif not bool(result.get("ok")):
            blocked_stage = "frame_invalid"
        else:
            blocked_stage = "none"
        return {
            "trace_id": f"s{self.session_id}-f{self.frame_seq}",
            "mode": mode,
            "left_arm": left,
            "right_arm": right,
            "gesture": gesture,
            "post_squat_gate": gate,
            "quality": {
                "classifier_reason": result.get("reason"),
                "valid": result.get("valid"),
                "present": present,
                "stable_valid": stable_valid,
                "validity_reason": result.get("validity_reason"),
                "bbox_confidence": result.get("bbox_confidence"),
                "keypoint_threshold": (
                    self.engine.config.fpga_point_conf
                    if mode == "eleven_point"
                    else self.engine.config.keypoint_conf
                ),
                "bbox_threshold": self.engine.config.bbox_conf,
                "required_indices": [5, 6, 7, 8],
                "lower_body_indices": [11, 12],
                "lower_body_threshold": (
                    self.engine.config.lower_body_point_conf
                ),
                "keypoint_names": list(COCO_KEYPOINT_NAMES),
            },
            "link": {
                "healthy": bool(result.get("stream_healthy")),
                "kind": result.get("kind"),
                "expected_kind": self.live_kind,
                "kind_matches": result.get("kind") == self.live_kind,
                "frame_seq": self.frame_seq,
                "fpga_seq": result.get("fpga_seq"),
                "stream": stream,
                "reopen_count": self.live_reopen_count,
                "last_recovery": self.last_live_recovery,
            },
            "pipeline": {
                "present": present,
                "attack_action": attack_action,
                "body_action": body_action,
                "gesture_triggered": bool(triggered),
                "attack_gated": bool(attack_gated),
                "calibration_ready": calibration_ready,
                "attack_ready": (
                    calibration_ready
                    and stable_valid
                    and bool(result.get("model_gate_passed", True))
                    and body_action != "squat"
                    and not attack_gated
                    and not bool(result.get("model_rule_conflict"))
                ),
                "blocked_stage": blocked_stage,
                "action_seq": self.action_seq,
            },
            "model": {
                "available": result.get("model_available"),
                "error": result.get("model_error"),
                "gate_passed": result.get("model_gate_passed"),
                "gate_reason": result.get("model_gate_reason"),
                "human_confidence": result.get("human_confidence"),
                "raise_confidence": result.get("raise_confidence"),
                "effective_raise_confidence": result.get(
                    "effective_raise_confidence"
                ),
                "arm_probabilities": result.get("arm_probabilities"),
                "rule_side": result.get("rule_side"),
                "model_side": result.get("model_side"),
                "conflict": result.get("model_rule_conflict"),
                "combined_confidence": result.get("combined_arm_confidence"),
                "window_frames": result.get("classifier_frames"),
                "window_size": result.get("classifier_window_size"),
            },
            "calibration": self._calibration_snapshot_locked(now),
        }

    def recalibrate(self, reason: str = "manual") -> dict:
        with self.condition:
            calibration = self._start_calibration_locked(reason)
            self.condition.notify_all()
        self.log_event(
            "bridge",
            "calibration_requested",
            {"reason": reason, **calibration},
        )
        return {"ok": True, "calibration": calibration}

    def _current_debug_tuning_locked(self) -> dict:
        values = {}
        for key, spec in DEBUG_TUNING_SPECS.items():
            raw = self.config.get(key, DEBUG_TUNING_DEFAULTS[key])
            values[key] = (
                int(raw)
                if spec["type"] in {"int", "bool"}
                else float(raw)
            )
        return values

    def debug_config(self) -> dict:
        with self.lock:
            values = self._current_debug_tuning_locked()
            controls = [
                {
                    "key": key,
                    **spec,
                    "value": values[key],
                    "default": DEBUG_TUNING_DEFAULTS[key],
                }
                for key, spec in DEBUG_TUNING_SPECS.items()
            ]
        return {
            "ok": True,
            "values": values,
            "controls": controls,
            "defaults": dict(DEBUG_TUNING_DEFAULTS),
        }

    def _validate_tuning_locked(self, updates: dict) -> dict:
        candidate = dict(self.config)
        candidate.update(updates)
        if (
            float(candidate["elbow_rise_min_pixels"])
            > float(candidate["elbow_rise_max_pixels"])
        ):
            raise ValueError("最小抬升像素不能大于最大抬升像素")
        if (
            int(candidate["attack_confirm_min_votes"])
            > int(candidate["attack_confirm_window_frames"])
        ):
            raise ValueError("最少确认票数不能大于投票窗口帧数")
        if (
            float(candidate["elbow_release_pixels"])
            > float(candidate["elbow_rise_max_pixels"])
        ):
            raise ValueError("释放回落像素不能大于最大抬升像素")
        if (
            float(candidate["arm_rule_weight"])
            + float(candidate["arm_model_weight"])
            <= 1e-6
        ):
            raise ValueError("成熟规则权重和模型权重不能同时为 0")
        return candidate

    def _write_config_locked(self) -> None:
        config_path = ROOT / "config.json"
        temporary = config_path.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(self.config, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, config_path)

    def _rebuild_motion_tracking_locked(self) -> None:
        config = self.engine.config
        config.elbow_rise_pixels = float(
            self.config.get("elbow_rise_pixels", 20.0)
        )
        config.elbow_release_pixels = float(
            self.config["elbow_release_pixels"]
        )
        config.elbow_release_frames = int(
            self.config["elbow_release_frames"]
        )
        config.elbow_median_frames = int(
            self.config["attack_keypoint_median_frames"]
        )
        config.elbow_rise_shoulder_ratio = float(
            self.config["elbow_rise_shoulder_ratio"]
        )
        config.elbow_rise_min_pixels = float(
            self.config["elbow_rise_min_pixels"]
        )
        config.elbow_rise_max_pixels = float(
            self.config["elbow_rise_max_pixels"]
        )
        config.wrist_rise_elbow_ratio = float(
            self.config["wrist_rise_elbow_ratio"]
        )
        config.wrist_max_below_elbow_ratio = float(
            self.config["wrist_max_below_elbow_ratio"]
        )
        config.fpga_point_conf = float(self.config["fpga_point_conf"])
        config.lower_body_point_conf = float(
            self.config["lower_body_point_conf"]
        )
        config.pose_max_shoulder_width_px = float(
            self.config["pose_max_shoulder_width_px"]
        )
        config.pose_max_width_change_ratio = float(
            self.config["pose_max_width_change_ratio"]
        )
        config.pose_stable_frames = int(self.config["pose_stable_frames"])
        config.pose_outlier_confirm_frames = int(
            self.config["pose_outlier_confirm_frames"]
        )
        config.pose_width_median_frames = int(
            self.config["pose_width_median_frames"]
        )
        config.shoulder_speed_window_frames = int(
            self.config["shoulder_speed_window_frames"]
        )
        config.shoulder_speed_threshold_ratio = float(
            self.config["shoulder_speed_threshold_ratio"]
        )
        config.shoulder_min_drop_ratio = float(
            self.config["shoulder_min_drop_ratio"]
        )
        config.shoulder_hip_speed_threshold_ratio = float(
            self.config["shoulder_hip_speed_threshold_ratio"]
        )
        config.shoulder_hip_min_drop_ratio = float(
            self.config["shoulder_hip_min_drop_ratio"]
        )
        config.shoulder_symmetry_ratio = float(
            self.config["shoulder_symmetry_ratio"]
        )
        config.shoulder_confirm_frames = int(
            self.config["shoulder_confirm_frames"]
        )
        config.shoulder_upward_reanchor_ratio = float(
            self.config["shoulder_upward_reanchor_ratio"]
        )
        config.shoulder_upward_reanchor_frames = int(
            self.config["shoulder_upward_reanchor_frames"]
        )
        config.shoulder_upward_reanchor_hold_s = (
            float(self.config["shoulder_upward_reanchor_hold_ms"]) / 1000.0
        )
        config.shoulder_squat_recovery_ratio = float(
            self.config["shoulder_squat_recovery_ratio"]
        )
        config.shoulder_squat_release_frames = int(
            self.config["shoulder_squat_release_frames"]
        )
        config.human_confidence_threshold = float(
            self.config["human_confidence_threshold"]
        )
        config.arm_rule_weight = float(self.config["arm_rule_weight"])
        config.arm_model_weight = float(self.config["arm_model_weight"])
        config.combined_confidence_threshold = float(
            self.config["combined_confidence_threshold"]
        )
        config.model_side_mirrored = bool(
            int(self.config["model_side_mirrored"])
        )
        config.arm_model_enabled = bool(
            int(self.config["arm_model_enabled"])
        )
        self.engine.elbow_tracker = ElbowRiseTracker(
            rise_pixels=config.elbow_rise_pixels,
            release_pixels=config.elbow_release_pixels,
            stale_seconds=config.elbow_tracker_stale_s,
            median_frames=config.elbow_median_frames,
            release_frames=config.elbow_release_frames,
        )
        self.engine.wrist_tracker = ElbowRiseTracker(
            rise_pixels=config.elbow_rise_pixels,
            release_pixels=config.elbow_release_pixels,
            stale_seconds=config.elbow_tracker_stale_s,
            median_frames=config.elbow_median_frames,
            release_frames=config.elbow_release_frames,
            joint_name="wrist",
        )
        self.engine.shoulder_tracker = ShoulderMotionTracker(
            speed_window_frames=config.shoulder_speed_window_frames,
            speed_threshold_ratio=config.shoulder_speed_threshold_ratio,
            min_drop_ratio=config.shoulder_min_drop_ratio,
            hip_speed_threshold_ratio=config.shoulder_hip_speed_threshold_ratio,
            hip_min_drop_ratio=config.shoulder_hip_min_drop_ratio,
            release_ratio=config.shoulder_release_ratio,
            symmetry_ratio=config.shoulder_symmetry_ratio,
            confirm_frames=config.shoulder_confirm_frames,
            stale_seconds=config.shoulder_tracker_stale_s,
            upward_reanchor_ratio=config.shoulder_upward_reanchor_ratio,
            upward_reanchor_frames=config.shoulder_upward_reanchor_frames,
            upward_reanchor_hold_seconds=(
                config.shoulder_upward_reanchor_hold_s
            ),
            squat_recovery_ratio=config.shoulder_squat_recovery_ratio,
            squat_release_frames=config.shoulder_squat_release_frames,
        )
        shoulder_widths = getattr(self.engine, "shoulder_widths", None)
        if shoulder_widths is not None:
            shoulder_widths.clear()
        self.engine.shoulder_width_gate = ShoulderWidthGate(
            confirm_frames=config.shoulder_width_confirm_frames,
            tolerance_ratio=config.shoulder_width_agreement_ratio,
        )
        self.attack_confirm_window_frames = int(
            self.config["attack_confirm_window_frames"]
        )
        self.attack_confirm_min_votes = int(
            self.config["attack_confirm_min_votes"]
        )
        self.attack_cooldown_ms = int(self.config["attack_cooldown_ms"])
        self.gesture_confirm_frames = min(
            self.attack_confirm_window_frames,
            max(1, self.attack_confirm_min_votes),
        )
        self.gesture_filter = GestureFilter(
            self.gesture_confirm_frames,
            self.attack_cooldown_ms / 1000.0,
            window_frames=self.attack_confirm_window_frames,
            min_votes=self.attack_confirm_min_votes,
        )
        self.post_squat_gate = PostSquatAttackGate(
            suppress_s=float(self.config["post_squat_suppress_ms"]) / 1000.0,
            neutral_frames=int(self.config["post_squat_neutral_frames"]),
            squat_confirm_frames=int(
                self.config["post_squat_confirm_frames"]
            ),
            max_gate_s=(
                float(self.config["post_squat_max_gate_ms"]) / 1000.0
            ),
        )
        self.calibration_timeout_s = max(
            0.5,
            float(self.config["calibration_timeout_ms"]) / 1000.0,
        )
        self.calibration_hold_s = max(
            0.2,
            float(self.config["calibration_hold_ms"]) / 1000.0,
        )
        self.calibration_neutral_ratio = max(
            0.5,
            min(
                0.95,
                float(self.config["calibration_neutral_ratio"]),
            ),
        )
        self.invalid_reset_s = max(
            0.2,
            float(self.config["invalid_reset_ms"]) / 1000.0,
        )

    def apply_debug_tuning(self, payload: dict, persist: bool = False) -> dict:
        updates: dict = {}
        for key, spec in DEBUG_TUNING_SPECS.items():
            if key not in payload:
                continue
            try:
                if spec["type"] == "bool":
                    value = 1 if bool(int(payload[key])) else 0
                elif spec["type"] == "int":
                    value = int(payload[key])
                else:
                    value = float(payload[key])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{key} 不是有效数字") from exc
            if value < spec["min"] or value > spec["max"]:
                raise ValueError(
                    f"{spec['label']} 必须在 {spec['min']}～{spec['max']} 之间"
                )
            updates[key] = value
        if not updates:
            raise ValueError("没有可应用的参数")

        with self.condition:
            candidate = self._validate_tuning_locked(updates)
            self.config.update(candidate)
            self._rebuild_motion_tracking_locked()
            calibration = self._start_calibration_locked("tuning_applied")
            if persist:
                self._write_config_locked()
            values = self._current_debug_tuning_locked()
            self.condition.notify_all()
        self.log_event(
            "bridge",
            "debug_tuning_applied",
            {
                "updates": updates,
                "persist": bool(persist),
                "calibration": calibration,
            },
        )
        return {
            "ok": True,
            "values": values,
            "persist": bool(persist),
            "calibration": calibration,
        }

    def reset_debug_tuning(self, persist: bool = False) -> dict:
        result = self.apply_debug_tuning(
            dict(DEBUG_TUNING_DEFAULTS),
            persist=persist,
        )
        result["reset"] = True
        return result

    def debug_events_since(
        self,
        after_event_id: int = 0,
        limit: int = 250,
    ) -> dict:
        if self.event_logger is None:
            return {"ok": True, "events": [], "test_session_id": None}
        info = self.event_logger.current_info()
        return {
            "ok": True,
            "events": self.event_logger.recent_events_since(
                after_event_id,
                limit,
            ),
            **info,
        }

    def debug_export(self, window_s: float = 10.0) -> dict:
        window_s = max(1.0, min(float(window_s), 120.0))
        cutoff = time.time() - window_s
        with self.lock:
            state = dict(self.state)
            config = {
                key: self.config.get(key)
                for key in DEBUG_TUNING_SPECS
            }
        events = (
            self.event_logger.recent_events_since(0, 500)
            if self.event_logger is not None
            else []
        )
        events = [
            event
            for event in events
            if float(event.get("ts_unix", 0.0)) >= cutoff
        ]
        images = {}
        for name, path in {
            "pose_jpeg": self.output_dir / "current_pose.jpg",
            "edge_png": self.output_dir / "current_edge.png",
        }.items():
            if path.is_file():
                try:
                    images[name] = {
                        "content_type": (
                            "image/jpeg" if path.suffix == ".jpg" else "image/png"
                        ),
                        "base64": base64.b64encode(path.read_bytes()).decode(
                            "ascii"
                        ),
                    }
                except OSError:
                    pass
        session = (
            self.event_logger.current_info()
            if self.event_logger is not None
            else {}
        )
        return {
            "ok": True,
            "generated_at": datetime.now().astimezone().isoformat(
                timespec="milliseconds"
            ),
            "window_s": window_s,
            "session": session,
            "config": config,
            "state": state,
            "events": events,
            "images": images,
        }

    def log_event(
        self,
        stream: str,
        event: str,
        fields: dict | None = None,
    ) -> bool:
        if self.event_logger is None:
            return False
        return self.event_logger.log_event(stream, event, fields)

    def start_log_session(self, reason: str = "launcher") -> dict:
        if self.event_logger is None:
            return {"ok": False, "error": "event logging is disabled"}
        self._last_ft232_error_key = None
        self._last_ft232_error_at = 0.0
        self._ft232_error_repeat_count = 0
        self.log_event(
            "bridge",
            "session_restart_requested",
            {
                "reason": reason,
                "game_active": self.game_active,
                "detection_mode": self.detection_mode,
            },
        )
        info = self.event_logger.start_session(
            reason,
            {
                "source_mode": self.source_mode,
                "detection_mode": self.detection_mode,
                "game_active": self.game_active,
            },
        )
        return {"ok": True, **info}

    def attach_log_session(self) -> dict:
        if self.event_logger is None:
            return {"ok": False, "error": "event logging is disabled"}
        info = self.event_logger.current_info()
        if info["test_session_id"] is None:
            info = self.event_logger.start_session(
                "webpage_attached",
                {
                    "source_mode": self.source_mode,
                    "detection_mode": self.detection_mode,
                    "game_active": self.game_active,
                },
            )
        return {"ok": True, **info}

    def end_log_session(self, session_id: int | None, reason: str) -> dict:
        if self.event_logger is None:
            return {"ok": False, "error": "event logging is disabled"}
        self.log_event(
            "bridge",
            "session_end_requested",
            {
                "requested_session_id": session_id,
                "reason": reason,
            },
        )
        return self.event_logger.end_session(session_id, reason)

    def log_game_event(self, payload: dict) -> dict:
        if self.event_logger is None:
            return {"ok": False, "error": "event logging is disabled"}
        session_id = payload.get("log_session_id")
        info = self.event_logger.current_info()
        if info["test_session_id"] is None:
            return {"ok": False, "error": "no active log session"}
        if (
            session_id is not None
            and int(session_id) != info["test_session_id"]
        ):
            return {"ok": False, "error": "stale log session"}
        data = payload.get("data")
        if not isinstance(data, dict):
            data = {}
        fields = {
            "client_ts": payload.get("client_ts"),
            "client_perf_ms": payload.get("client_perf_ms"),
            "log_session_id": session_id,
            "data": data,
        }
        ok = self.event_logger.log_event(
            "game",
            str(payload.get("event", "unknown")),
            fields,
        )
        return {"ok": ok}

    def history_snapshot(self) -> list[dict]:
        with self.lock:
            return list(self.history)

    def _write_history(self) -> None:
        self.history_path.parent.mkdir(parents=True, exist_ok=True)
        fields = [
            "index", "image", "action", "action_name", "pose_id",
            "bbox_confidence", "reason", "cx", "width", "height",
            "action_seq", "fpga_seq", "left_side", "left_rise_px",
            "left_conf", "right_side", "right_rise_px", "right_conf",
            "body_action", "body_action_seq", "attack_action", "shoulder_shift_px",
            "shoulder_width_px", "shoulder_drop_ratio",
            "left_speed_ratio_s", "right_speed_ratio_s", "mean_speed_ratio_s",
            "hip_drop_ratio", "left_hip_speed_ratio_s",
            "right_hip_speed_ratio_s", "hip_confidence",
            "lower_body_confirmed", "speed_window_s",
            "human_confidence", "raise_confidence",
            "arm_rule_weight", "arm_model_weight",
            "combined_arm_confidence", "model_rule_conflict",
        ]
        with self.history_path.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for row in self.history:
                writer.writerow({field: row.get(field, "") for field in fields})

    def _track_body_action_event(self, body_action: str) -> None:
        if body_action == "squat" and body_action != self.last_body_action:
            self.body_action_seq += 1
            self.last_trigger_body_action = body_action
        self.last_body_action = body_action

    def process_current(self) -> None:
        with self.lock:
            if not self.files:
                self.state.update({"ok": False, "err": "no_supported_images"})
                return
            image_path = self.files[self.index]
            index = self.index
            total = len(self.files)
        started = time.perf_counter()
        try:
            result = self.engine.process(image_path, self.output_dir)
            elapsed = max(1e-6, time.perf_counter() - started)
            with self.condition:
                self.frame_seq += 1
                attack_action = result.get("attack_action", result["action"])
                if attack_action != "stand":
                    self.action_seq += 1
                    self.last_trigger_action = attack_action
                body_action = result.get("body_action", "stand")
                self._track_body_action_event(body_action)
                result.update({
                    "ok": True,
                    "err": "",
                    "action_seq": self.action_seq,
                    "trigger_action": self.last_trigger_action,
                    "body_action_seq": self.body_action_seq,
                    "trigger_body_action": self.last_trigger_body_action,
                    "frame_seq": self.frame_seq,
                    "hold_ms": max(350, min(self.interval_ms - 100, 900)),
                    "index": index + 1,
                    "total": total,
                    "input_dir": str(self.input_dir),
                    "paused": self.paused,
                    "game_active": self.game_active,
                    "processing_fps": round(1.0 / elapsed, 2),
                    "source_mode": "folder",
                    "session_id": self.session_id,
                })
                self.state = result
                history_row = {key: result.get(key) for key in (
                    "index", "image", "action", "action_name", "pose_id",
                    "bbox_confidence", "reason", "cx", "width", "height",
                    "action_seq", "body_action", "body_action_seq",
                    "attack_action",
                )}
                shoulder_motion = result.get("shoulder_motion") or {}
                history_row.update({
                    "shoulder_shift_px": shoulder_motion.get("mean_shift_px"),
                    "shoulder_width_px": shoulder_motion.get("shoulder_width_px"),
                    "shoulder_drop_ratio": shoulder_motion.get("drop_ratio"),
                    "left_speed_ratio_s": shoulder_motion.get("left_speed_ratio_s"),
                    "right_speed_ratio_s": shoulder_motion.get("right_speed_ratio_s"),
                    "mean_speed_ratio_s": shoulder_motion.get("mean_speed_ratio_s"),
                    "hip_drop_ratio": shoulder_motion.get("hip_drop_ratio"),
                    "left_hip_speed_ratio_s": shoulder_motion.get(
                        "left_hip_speed_ratio_s"
                    ),
                    "right_hip_speed_ratio_s": shoulder_motion.get(
                        "right_hip_speed_ratio_s"
                    ),
                    "hip_confidence": shoulder_motion.get("hip_confidence"),
                    "lower_body_confirmed": shoulder_motion.get(
                        "lower_body_confirmed"
                    ),
                    "speed_window_s": shoulder_motion.get("speed_window_s"),
                    "human_confidence": result.get("human_confidence"),
                    "raise_confidence": result.get("raise_confidence"),
                    "arm_rule_weight": self.config.get("arm_rule_weight"),
                    "arm_model_weight": self.config.get("arm_model_weight"),
                    "combined_arm_confidence": result.get(
                        "combined_arm_confidence"
                    ),
                    "model_rule_conflict": result.get("model_rule_conflict"),
                })
                self.history.append(history_row)
                self.history = self.history[-1000:]
                self._write_history()
        except Exception as exc:
            with self.condition:
                self.state.update({
                    "ok": False,
                    "err": str(exc),
                    "present": False,
                    "pose_id": 1,
                    "action": "stand",
                    "action_name": "站立",
                    "body_action": "stand",
                    "body_action_name": "站立",
                    "attack_action": "stand",
                    "attack_suppressed": False,
                    "body_action_seq": self.body_action_seq,
                    "trigger_body_action": self.last_trigger_body_action,
                    "index": index + 1,
                    "total": total,
                })

    def worker(self) -> None:
        while not self.stop_event.is_set():
            with self.condition:
                while not self.stop_event.is_set() and (
                    self.paused or not self.files or not self.game_active
                ):
                    self.condition.wait(0.5)
                if self.stop_event.is_set():
                    break
            frame_started = time.monotonic()
            self.process_current()
            # The requested interval is the display time per image, including
            # image5 conversion and YOLO inference rather than time after it.
            deadline = frame_started + self.interval_ms / 1000.0
            with self.condition:
                self.index = (self.index + 1) % len(self.files) if self.files else 0
                while not self.stop_event.is_set() and not self.skip_wait:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        break
                    self.condition.wait(remaining)
                self.skip_wait = False

    def _set_live_waiting(self, error: str, stream: dict) -> None:
        """Update live status without promoting an unaccepted frame."""
        calibration = self._calibration_snapshot_locked()
        calibration["ready"] = False
        calibration["state"] = "stream_lost"
        calibration["reason"] = error
        calibration["progress"] = 0.0
        self.state.update({
            "ok": False,
            "err": error,
            "valid": False,
            "present": False,
            "cx": 0.5,
            "pose_id": 1,
            "action": "stand",
            "action_name": "站立",
            "body_action": "stand",
            "body_action_name": "站立",
            "attack_action": "stand",
            "attack_suppressed": False,
            "reason": error,
            "validity_reason": error,
            "points": [],
            "skeleton_edges": [],
            "classifier_frames": 0,
            "model_window_frames": 0,
            "model_gate_passed": False,
            "model_gate_reason": "stream_lost",
            "human_confidence": None,
            "raise_confidence": None,
            "arm_probabilities": {},
            "action_seq": self.action_seq,
            "trigger_action": self.last_trigger_action,
            "body_action_seq": self.body_action_seq,
            "trigger_body_action": self.last_trigger_body_action,
            "frame_seq": self.frame_seq,
            "index": self.frame_seq,
            "total": 0,
            "hold_ms": 0,
            "paused": self.paused,
            "game_active": self.game_active,
            "source_mode": "ft232h",
            "detection_mode": self.detection_mode,
            "detection_mode_name": DETECTION_MODE_NAMES[self.detection_mode],
            "session_id": self.session_id,
            "expected_width": self.live_width,
            "expected_height": self.live_height,
            "expected_kind": self.live_kind,
            "stream_healthy": False,
            "stream_watchdog_timeout_s": self.live_stall_timeout_s,
            "stream_reopen_count": self.live_reopen_count,
            "last_stream_recovery": self.last_live_recovery,
            "attack_cooldown_ms": self.attack_cooldown_ms,
            "calibration": calibration,
            "calibration_ready": bool(calibration.get("ready")),
            "calibration_state": calibration.get("state"),
            "debug": {
                "trace_id": f"s{self.session_id}-f{self.frame_seq}",
                "link": {
                    "healthy": False,
                    "kind": None,
                    "expected_kind": self.live_kind,
                    "kind_matches": False,
                    "frame_seq": self.frame_seq,
                    "fpga_seq": None,
                    "stream": stream,
                    "reopen_count": self.live_reopen_count,
                    "last_recovery": self.last_live_recovery,
                },
                "pipeline": {
                    "present": False,
                    "attack_action": "stand",
                    "body_action": "stand",
                    "gesture_triggered": False,
                    "attack_gated": False,
                    "blocked_stage": "stream_waiting",
                    "action_seq": self.action_seq,
                },
                "calibration": calibration,
            },
            "stream": stream,
        })

    def _binary_trace_fields(self, payload: bytes) -> dict:
        size = len(payload)
        digest = hashlib.sha256(payload).hexdigest()
        fields = {
            "byte_count": size,
            "sha256": digest,
        }
        if self.ft232_log_payload_bytes <= 0:
            return fields
        if size <= self.ft232_log_payload_bytes:
            fields["content_encoding"] = "hex"
            fields["content_hex"] = payload.hex()
        else:
            preview = min(64, size)
            fields["content_encoding"] = "sha256+preview"
            fields["content_prefix_hex"] = payload[:preview].hex()
            fields["content_suffix_hex"] = payload[-preview:].hex()
        return fields

    def _log_ft232_chunk(self, chunk: bytes) -> None:
        fields = self._binary_trace_fields(chunk)
        fields["direction"] = "FPGA->PC"
        self.log_event("ft232", "rx_chunk", fields)

    def _log_ft232_frame(self, frame) -> None:
        fields = {
            "direction": "FPGA->PC",
            "version": frame.version,
            "kind": frame.kind,
            "sequence": frame.sequence,
            "width": frame.width,
            "height": frame.height,
            "payload_bytes": len(frame.payload),
        }
        fields.update(self._binary_trace_fields(frame.payload))
        self.log_event("ft232", "rx_frame", fields)

    def _log_ft232_exception(self, event: str, exc: Exception) -> None:
        error_key = (
            f"{event}|{type(exc).__name__}|{exc}|"
            f"{getattr(exc, 'function', '')}|{getattr(exc, 'status', '')}"
        )
        now = time.monotonic()
        if (
            error_key == self._last_ft232_error_key
            and now - self._last_ft232_error_at < 5.0
        ):
            self._ft232_error_repeat_count += 1
            return
        repeated = (
            self._ft232_error_repeat_count
            if error_key == self._last_ft232_error_key
            else 0
        )
        self._last_ft232_error_key = error_key
        self._last_ft232_error_at = now
        self._ft232_error_repeat_count = 0
        self.log_event(
            "ft232",
            event,
            {
                "direction": "FPGA->PC",
                "error_type": type(exc).__name__,
                "error": str(exc),
                "d2xx_function": getattr(exc, "function", None),
                "d2xx_status": getattr(exc, "status", None),
                "repeated_since_last_log": repeated,
            },
        )

    def _log_ft232_diagnostic(self, event: str, fields: dict) -> None:
        self.log_event(
            "ft232",
            event,
            {
                "direction": "FPGA->PC",
                **fields,
            },
        )

    def _live_mode_runnable(self, mode: str) -> bool:
        # The USB receiver must stay alive outside an active game too. Otherwise
        # kind3 cannot even open its video stream on the start/debug pages, and a
        # USB reconnect cannot complete until game_active happens to flip on.
        return not self.paused

    def _live_session_current(
        self,
        session_id: int,
        mode: str,
        mode_generation: int,
    ) -> bool:
        return (
            self.session_id == session_id
            and self.detection_mode == mode
            and self.mode_generation == mode_generation
            and self._live_mode_runnable(mode)
        )

    def live_worker(self) -> None:
        source: PreconfiguredEdgeSource | None = None
        source_opened_at = 0.0
        retry_at = 0.0
        try:
            while not self.stop_event.is_set():
                close_source = False
                with self.condition:
                    while not self.stop_event.is_set():
                        mode = self.detection_mode
                        kind = DETECTION_MODE_KINDS[mode]
                        runnable = self._live_mode_runnable(mode)
                        if source is not None and (
                            getattr(source, "kind", kind) != kind or not runnable
                        ):
                            close_source = True
                            break
                        if runnable:
                            break
                        self.condition.wait(0.5)
                    if self.stop_event.is_set():
                        break
                    session_id = self.session_id
                    mode_generation = self.mode_generation
                    mode = self.detection_mode
                    kind = DETECTION_MODE_KINDS[mode]

                if close_source:
                    source.close()
                    source = None
                    source_opened_at = 0.0
                    continue

                if source is None:
                    now = time.monotonic()
                    if now < retry_at:
                        self.stop_event.wait(min(0.2, retry_at - now))
                        continue
                    try:
                        candidate = PreconfiguredEdgeSource(
                            serial=self.ft232h_serial,
                            width=self.live_width,
                            height=self.live_height,
                            kind=kind,
                            chunk_callback=self._log_ft232_chunk,
                            frame_callback=self._log_ft232_frame,
                            diagnostic_callback=self._log_ft232_diagnostic,
                        )
                        candidate.open()
                    except Exception as exc:
                        self._log_ft232_exception("open_failed", exc)
                        with self.condition:
                            if self._live_session_current(
                                session_id,
                                mode,
                                mode_generation,
                            ):
                                self._set_live_waiting(
                                    f"ft232h_open_failed: {exc}",
                                    {},
                                )
                        retry_at = time.monotonic() + 1.0
                        self.stop_event.wait(0.1)
                        continue

                    with self.condition:
                        if not self._live_session_current(
                            session_id,
                            mode,
                            mode_generation,
                        ):
                            candidate.close()
                            continue
                        source = candidate
                        source_opened_at = time.monotonic()
                        self._last_ft232_error_key = None
                        self._last_ft232_error_at = 0.0
                        self._ft232_error_repeat_count = 0
                        self.last_live_frame_at = 0.0
                        self.log_event(
                            "ft232",
                            "source_opened",
                            {
                                "serial": self.ft232h_serial,
                                "kind": kind,
                                "width": self.live_width,
                                "height": self.live_height,
                            },
                        )
                        self._set_live_waiting(
                            f"waiting_640x360_kind{kind}",
                            source.stats(),
                        )

                try:
                    frame = source.read_latest_matching(self.live_wait_s)
                except Exception as exc:
                    self._log_ft232_exception("read_failed", exc)
                    source.close()
                    source = None
                    source_opened_at = 0.0
                    self.last_live_frame_at = 0.0
                    with self.condition:
                        if self._live_session_current(
                            session_id,
                            mode,
                            mode_generation,
                        ):
                            self.live_reopen_count += 1
                            self.last_live_recovery = f"read_failed: {exc}"
                            self._set_live_waiting(
                                f"ft232h_read_failed: {exc}",
                                {},
                            )
                    retry_at = time.monotonic() + 1.0
                    continue

                with self.condition:
                    active = self._live_session_current(
                        session_id,
                        mode,
                        mode_generation,
                    )
                if not active:
                    source.close()
                    source = None
                    source_opened_at = 0.0
                    continue

                stream = source.stats()
                if frame is None:
                    now = time.monotonic()
                    if (
                        self.last_live_valid_at > 0.0
                        and now - self.last_live_valid_at >= self.invalid_reset_s
                        and self.calibration_ready
                    ):
                        with self.condition:
                            if self._live_session_current(
                                session_id,
                                mode,
                                mode_generation,
                            ):
                                self._invalidate_pose_tracking_locked(
                                    "no_valid_frames"
                                )
                                self.log_event(
                                    "bridge",
                                    "pose_state_invalidated",
                                    {
                                        "reason": "no_valid_frames",
                                        "frame_seq": self.frame_seq,
                                    },
                                )
                    last_progress_at = max(
                        source_opened_at,
                        self.last_live_frame_at,
                    )
                    if now - last_progress_at >= self.live_stall_timeout_s:
                        self.log_event(
                            "ft232",
                            "stream_stalled",
                            {
                                "timeout_s": self.live_stall_timeout_s,
                                "last_frame_at": self.last_live_frame_at,
                                "source_opened_at": source_opened_at,
                                "stream": stream,
                            },
                        )
                        source.close()
                        source = None
                        source_opened_at = 0.0
                        self.last_live_frame_at = 0.0
                        retry_at = now + 0.5
                        with self.condition:
                            if self._live_session_current(
                                session_id,
                                mode,
                                mode_generation,
                            ):
                                self.live_reopen_count += 1
                                self.last_live_recovery = (
                                    "no_valid_frames:"
                                    f"{self.live_stall_timeout_s:.1f}s"
                                )
                                self._set_live_waiting(
                                    "ft232h_stalled_reopening: "
                                    f"no valid frame for "
                                    f"{self.live_stall_timeout_s:.1f}s",
                                    stream,
                                )
                        continue
                    if (
                        now - self.last_live_valid_at >= 0.75
                        and now - self.last_live_wait_update >= 0.25
                    ):
                        with self.condition:
                            if self._live_session_current(
                                session_id,
                                mode,
                                mode_generation,
                            ):
                                self._set_live_waiting(
                                    f"waiting_640x360_kind{kind}",
                                    stream,
                                )
                        self.last_live_wait_update = now
                    continue

                # A matching transport frame is stream liveness. Decode or
                # inference failures must not make the watchdog reopen a
                # healthy FT232H stream in a tight loop.
                self.last_live_frame_at = time.monotonic()
                started = time.perf_counter()
                try:
                    if mode == "yolo":
                        edge = decode_packed_edge(frame)
                        result = self.engine.process_edge(edge, self.output_dir)
                        result.update({"ok": True, "err": ""})
                    elif mode == "four_point":
                        result = decode_four_point_result(frame)
                        render_point_debug(
                            dict(result, sequence=frame.sequence),
                            self.output_dir,
                        )
                    else:
                        result = decode_eleven_point_result(frame)
                        render_point_debug(
                            dict(result, sequence=frame.sequence),
                            self.output_dir,
                        )
                except Exception as exc:
                    self.log_event(
                        "bridge",
                        "decode_failed",
                        {
                            "mode": mode,
                            "fpga_sequence": frame.sequence,
                            "kind": frame.kind,
                            "error_type": type(exc).__name__,
                            "error": str(exc),
                        },
                    )
                    with self.condition:
                        if self._live_session_current(
                            session_id,
                            mode,
                            mode_generation,
                        ):
                            self._set_live_waiting(
                                f"{mode}_failed: {exc}",
                                stream,
                            )
                    self.stop_event.wait(0.1)
                    continue

                elapsed = max(1e-6, time.perf_counter() - started)
                write_history = False
                with self.condition:
                    if not self._live_session_current(
                        session_id,
                        mode,
                        mode_generation,
                    ):
                        source.close()
                        source = None
                        continue
                    self.frame_seq += 1
                    if mode in {"yolo", "eleven_point"}:
                        if mode == "eleven_point":
                            classification = self.engine.classify_points(result)
                            result.update(classification)
                            valid = bool(result.get("valid"))
                            result.update({
                                "ok": valid,
                                "err": "" if valid else classification["reason"],
                                "action_name": ACTION_NAMES[classification["action"]],
                                "body_action_name": ACTION_NAMES[
                                    classification["body_action"]
                                ],
                            })
                        attack_action = result.get(
                            "attack_action",
                            result["action"],
                        )
                        body_action = result.get("body_action", "stand")
                        calibration = self._update_calibration_locked(result)
                        pose_usable = bool(
                            result.get(
                                "stable_valid",
                                result.get("present", False),
                            )
                        )
                        calibration_ready = bool(calibration.get("ready"))
                        if not pose_usable:
                            self.post_squat_gate.invalidate()
                            attack_gated = False
                            triggered = self.gesture_filter.age()
                        elif not calibration_ready:
                            self.gesture_filter.reset_candidate()
                            attack_gated = False
                            triggered = False
                        else:
                            attack_gated = self.post_squat_gate.update(
                                body_action,
                                attack_action,
                            )
                            gate_state = self.post_squat_gate.snapshot()
                            if gate_state.get("recovery_required"):
                                calibration = self._start_calibration_locked(
                                    "post_squat_gate_timeout"
                                )
                                calibration_ready = False
                                attack_gated = True
                                triggered = False
                            elif body_action == "squat" or attack_gated:
                                self.gesture_filter.reset_candidate()
                                triggered = False
                            else:
                                triggered = self.gesture_filter.update(
                                    attack_action
                                )
                        if triggered:
                            self.action_seq += 1
                            self.last_trigger_action = attack_action
                        if pose_usable:
                            self._track_body_action_event(body_action)
                        if mode == "yolo":
                            host_inference_ms = round(elapsed * 1000.0, 1)
                    else:
                        calibration = self._calibration_snapshot_locked()
                        triggered = False
                        attack_gated = False
                        attack_action = "stand"
                        body_action = "stand"
                        valid = bool(result["valid"])
                        is_live = bool(result["is_live"])
                        if result["fault"]:
                            reason = "fault"
                        elif not result["model_ready"]:
                            reason = "model_not_ready"
                        elif valid and is_live:
                            reason = "debug_live_result"
                        elif valid:
                            reason = "deterministic_test_frame"
                        else:
                            reason = "result_flags_invalid"
                        result.update({
                            "ok": valid,
                            "err": "" if valid else reason,
                            "present": valid,
                            "cx": 0.5,
                            "pose_id": 1,
                            "action": "stand",
                            "action_name": DETECTION_MODE_NAMES[mode],
                            "body_action": "stand",
                            "body_action_name": "站立",
                            "attack_action": "stand",
                            "attack_suppressed": False,
                            "reason": reason,
                            "bbox_confidence": None,
                            "processing_ms": round(elapsed * 1000.0, 1),
                        })
                    self.inference_fps = (
                        self.inference_fps * 0.8 + (1.0 / elapsed) * 0.2
                        if self.inference_fps
                        else 1.0 / elapsed
                    )
                    self.log_event(
                        "bridge",
                        "action_recognized",
                        {
                            "mode": mode,
                            "fpga_sequence": frame.sequence,
                            "frame_seq": self.frame_seq,
                            "action": result.get("action"),
                            "attack_action": result.get("attack_action"),
                            "body_action": result.get("body_action"),
                            "present": result.get("present"),
                            "valid": result.get("valid"),
                            "ok": result.get("ok"),
                            "reason": result.get("reason"),
                            "human_confidence": result.get(
                                "human_confidence"
                            ),
                            "raise_confidence": result.get(
                                "raise_confidence"
                            ),
                            "model_rule_conflict": result.get(
                                "model_rule_conflict"
                            ),
                            "combined_arm_confidence": result.get(
                                "combined_arm_confidence"
                            ),
                            "model_gate_passed": result.get(
                                "model_gate_passed"
                            ),
                            "classifier_frames": result.get(
                                "classifier_frames"
                            ),
                            "classifier_window_size": result.get(
                                "classifier_window_size"
                            ),
                            "model_gate_reason": result.get(
                                "model_gate_reason"
                            ),
                            "attack_gated": attack_gated,
                            "triggered": triggered,
                            "processing_ms": round(elapsed * 1000.0, 1),
                        },
                    )
                    if (
                        attack_action
                        and attack_action != "stand"
                        and (attack_gated or body_action == "squat")
                    ):
                        self.log_event(
                            "bridge",
                            "attack_blocked",
                            {
                                "stage": "post_squat_gate",
                                "fpga_sequence": frame.sequence,
                                "frame_seq": self.frame_seq,
                                "attack_action": attack_action,
                                "body_action": body_action,
                                "attack_gated": attack_gated,
                                "reason": (
                                    "squat_active"
                                    if body_action == "squat"
                                    else "post_squat_attack_gate"
                                ),
                            },
                        )
                    if triggered:
                        self.log_event(
                            "bridge",
                            "event_emitted",
                            {
                                "event_type": "action_seq",
                                "fpga_sequence": frame.sequence,
                                "frame_seq": self.frame_seq,
                                "action_seq": self.action_seq,
                                "trigger_action": attack_action,
                                "body_action": body_action,
                                "reason": "gesture_confirmed",
                            },
                        )
                    result.update({
                        "image": f"fpga:{frame.sequence}",
                        "action_seq": self.action_seq,
                        "trigger_action": self.last_trigger_action,
                        "body_action_seq": self.body_action_seq,
                        "trigger_body_action": self.last_trigger_body_action,
                        "frame_seq": self.frame_seq,
                        "hold_ms": 420,
                        "index": self.frame_seq,
                        "total": 0,
                        "paused": self.paused,
                        "game_active": self.game_active,
                        "source_mode": "ft232h",
                        "detection_mode": mode,
                        "detection_mode_name": DETECTION_MODE_NAMES[mode],
                        "session_id": self.session_id,
                        "fpga_seq": frame.sequence,
                        "version": getattr(frame, "version", 1),
                        "kind": frame.kind,
                        "stream_healthy": True,
                        "stream_watchdog_timeout_s": (
                            self.live_stall_timeout_s
                        ),
                        "stream_reopen_count": self.live_reopen_count,
                        "last_stream_recovery": self.last_live_recovery,
                        "processing_fps": round(1.0 / elapsed, 2),
                        "inference_fps": round(self.inference_fps, 2),
                        "gesture_triggered": triggered,
                        "attack_gated": attack_gated,
                        "attack_cooldown_ms": self.attack_cooldown_ms,
                        "attack_confirm_window_frames": (
                            self.attack_confirm_window_frames
                        ),
                        "attack_confirm_min_votes": self.attack_confirm_min_votes,
                        "attack_keypoint_median_frames": (
                            self.engine.config.elbow_median_frames
                        ),
                        "post_squat_suppress_ms": int(
                            self.post_squat_gate.suppress_s * 1000.0
                        ),
                        "post_squat_neutral_frames": (
                            self.post_squat_gate.neutral_frames
                        ),
                        "elbow_release_frames": (
                            self.engine.config.elbow_release_frames
                        ),
                        "wrist_rise_elbow_ratio": (
                            self.engine.config.wrist_rise_elbow_ratio
                        ),
                        "wrist_max_below_elbow_ratio": (
                            self.engine.config.wrist_max_below_elbow_ratio
                        ),
                        "stream": stream,
                    })
                    result["calibration"] = calibration
                    result["calibration_ready"] = bool(
                        result["calibration"].get("ready")
                    )
                    result["calibration_state"] = result["calibration"].get(
                        "state"
                    )
                    result["debug"] = self._debug_state_locked(
                        result,
                        bool(triggered),
                        bool(attack_gated),
                        stream,
                        mode,
                    )
                    if mode == "yolo":
                        result["inference_ms"] = host_inference_ms
                    self.state = result
                    self.last_live_valid_at = time.monotonic()
                    arms = result.get("arms") or {}
                    keypoint_confidence = result.get("keypoint_confidence") or []
                    left_arm = arms.get("left") or {}
                    right_arm = arms.get("right") or {}
                    shoulder_motion = result.get("shoulder_motion") or {}
                    self.history.append({
                        "index": result.get("index"),
                        "image": result.get("image"),
                        "action": result.get("action"),
                        "action_name": result.get("action_name"),
                        "pose_id": result.get("pose_id"),
                        "bbox_confidence": result.get("bbox_confidence"),
                        "reason": result.get("reason"),
                        "cx": result.get("cx"),
                        "width": result.get("width"),
                        "height": result.get("height"),
                        "action_seq": result.get("action_seq"),
                        "fpga_seq": result.get("fpga_seq"),
                        "left_side": left_arm.get("side"),
                        "left_rise_px": left_arm.get("rise_px"),
                        "left_conf": (
                            keypoint_confidence[7]
                            if len(keypoint_confidence) > 7 else None
                        ),
                        "right_side": right_arm.get("side"),
                        "right_rise_px": right_arm.get("rise_px"),
                        "right_conf": (
                            keypoint_confidence[8]
                            if len(keypoint_confidence) > 8 else None
                        ),
                        "body_action": result.get("body_action"),
                        "body_action_seq": result.get("body_action_seq"),
                        "attack_action": result.get("attack_action"),
                        "shoulder_shift_px": shoulder_motion.get("mean_shift_px"),
                        "shoulder_width_px": shoulder_motion.get("shoulder_width_px"),
                        "shoulder_drop_ratio": shoulder_motion.get("drop_ratio"),
                        "left_speed_ratio_s": shoulder_motion.get(
                            "left_speed_ratio_s"
                        ),
                        "right_speed_ratio_s": shoulder_motion.get(
                            "right_speed_ratio_s"
                        ),
                        "mean_speed_ratio_s": shoulder_motion.get(
                            "mean_speed_ratio_s"
                        ),
                        "hip_drop_ratio": shoulder_motion.get(
                            "hip_drop_ratio"
                        ),
                        "left_hip_speed_ratio_s": shoulder_motion.get(
                            "left_hip_speed_ratio_s"
                        ),
                        "right_hip_speed_ratio_s": shoulder_motion.get(
                            "right_hip_speed_ratio_s"
                        ),
                        "hip_confidence": shoulder_motion.get(
                            "hip_confidence"
                        ),
                        "lower_body_confirmed": shoulder_motion.get(
                            "lower_body_confirmed"
                        ),
                        "speed_window_s": shoulder_motion.get("speed_window_s"),
                    })
                    self.history = self.history[-1000:]
                    now = time.monotonic()
                    if now - self.last_history_write >= 1.0:
                        self.last_history_write = now
                        write_history = True
                if write_history:
                    try:
                        self._write_history()
                    except OSError:
                        pass
                frame_budget = 1.0 / float(self.live_target_fps)
                remaining = frame_budget - (time.perf_counter() - started)
                if remaining > 0:
                    self.stop_event.wait(remaining)
        finally:
            if source is not None:
                source.close()

    def shutdown(self) -> None:
        self.stop_event.set()
        with self.condition:
            self.condition.notify_all()
        if self.thread.is_alive() and threading.current_thread() is not self.thread:
            self.thread.join(timeout=3.0)


class DemoHandler(BaseHTTPRequestHandler):
    controller: DemoController
    server_version = "SoulRiderDemo/1.0"

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")

    def _json(self, payload: dict | list, status: int = 200) -> None:
        def json_default(value):
            if hasattr(value, "item"):
                return value.item()
            return str(value)

        data = json.dumps(payload, ensure_ascii=False, default=json_default).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _file(self, path: Path, content_type: str | None = None) -> None:
        if not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:
        parsed_url = urlparse(self.path)
        path = unquote(parsed_url.path)
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/game/")
            self._cors()
            self.end_headers()
            return
        if path == "/state":
            self._json(self.controller.snapshot())
            return
        if path == "/history":
            self._json(self.controller.history_snapshot()[-200:])
            return
        if path == "/api/debug/config":
            self._json(self.controller.debug_config())
            return
        if path == "/api/debug/events":
            query = parse_qs(parsed_url.query)
            try:
                after_event_id = int(query.get("after_event_id", ["0"])[0])
                limit = int(query.get("limit", ["250"])[0])
            except ValueError:
                self._json({"ok": False, "error": "invalid query"}, 400)
                return
            self._json(
                self.controller.debug_events_since(after_event_id, limit)
            )
            return
        if path == "/api/debug/export":
            query = parse_qs(parsed_url.query)
            try:
                window_s = float(query.get("window_s", ["10"])[0])
            except ValueError:
                self._json({"ok": False, "error": "invalid window_s"}, 400)
                return
            self._json(self.controller.debug_export(window_s))
            return
        if path in ("/panel", "/panel.html"):
            self._file(ROOT / "panel.html", "text/html; charset=utf-8")
            return
        live_files = {
            "/original.jpg": "current_input.jpg",
            "/edge.png": "current_edge.png",
            "/frame.png": "current_pose.jpg",
        }
        if path in live_files:
            self._file(ROOT / "outputs" / "live" / live_files[path])
            return
        if path.startswith("/game/"):
            relative = path[len("/game/"):] or "index.html"
            candidate = (ROOT / "game" / relative).resolve()
            game_root = (ROOT / "game").resolve()
            if game_root not in candidate.parents and candidate != game_root:
                self.send_error(403)
                return
            self._file(candidate)
            return
        self.send_error(404)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        if length > 1_048_576:
            self._json({"ok": False, "error": "request too large"}, 413)
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
        except json.JSONDecodeError:
            self._json({"ok": False, "error": "invalid json"}, 400)
            return
        if path == "/api/session/start":
            self._json(
                self.controller.start_log_session(
                    str(payload.get("reason", "launcher"))
                )
            )
            return
        if path == "/api/session/attach":
            self._json(self.controller.attach_log_session())
            return
        if path == "/api/session/end":
            try:
                session_id = payload.get("session_id")
                session_id = int(session_id) if session_id is not None else None
            except (TypeError, ValueError):
                self._json({"ok": False, "error": "invalid session_id"}, 400)
                return
            self._json(
                self.controller.end_log_session(
                    session_id,
                    str(payload.get("reason", "webpage_closed")),
                )
            )
            return
        if path == "/api/log/game":
            self._json(self.controller.log_game_event(payload))
            return
        if path == "/api/debug/recalibrate":
            self._json(
                self.controller.recalibrate(
                    str(payload.get("reason", "debug_page"))
                )
            )
            return
        if path == "/api/debug/config/apply":
            values = payload.get("values")
            if not isinstance(values, dict):
                values = {
                    key: payload[key]
                    for key in DEBUG_TUNING_SPECS
                    if key in payload
                }
            try:
                self._json(
                    self.controller.apply_debug_tuning(
                        values,
                        persist=bool(payload.get("persist", False)),
                    )
                )
            except ValueError as exc:
                self._json({"ok": False, "error": str(exc)}, 400)
            return
        if path == "/api/debug/config/reset":
            try:
                self._json(
                    self.controller.reset_debug_tuning(
                        persist=bool(payload.get("persist", False))
                    )
                )
            except ValueError as exc:
                self._json({"ok": False, "error": str(exc)}, 400)
            return
        if path == "/api/control":
            self._json(self.controller.control(str(payload.get("command", ""))))
            return
        if path == "/api/detection-mode":
            self._json(
                self.controller.set_detection_mode(
                    str(payload.get("mode", ""))
                )
            )
            return
        if path == "/api/input-dir":
            self._json(self.controller.set_input_dir(str(payload.get("path", ""))))
            return
        if path == "/api/game-start":
            self._json(self.controller.set_game_active(True))
            return
        if path == "/api/game-stop":
            self._json(self.controller.set_game_active(False))
            return
        self.send_error(404)

    def log_message(self, fmt: str, *args) -> None:
        # The game polls /state about 30 times per second; request logs would
        # drown the terminal, while startup errors are already printed above.
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Soul Rider pose game bridge")
    parser.add_argument("--input-dir", default="")
    parser.add_argument("--source", choices=sorted(SOURCE_MODES))
    parser.add_argument("--detection-mode", choices=sorted(DETECTION_MODE_KINDS))
    parser.add_argument("--ft232h-serial", default="")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config_path = ROOT / "config.json"
    config = json.loads(config_path.read_text(encoding="utf-8")) if config_path.is_file() else {}
    if args.input_dir:
        config["input_dir"] = args.input_dir
        config["source_mode"] = "folder"
    if args.source:
        config["source_mode"] = args.source
    if args.detection_mode:
        config["detection_mode"] = args.detection_mode
        config["ft232h_kind"] = DETECTION_MODE_KINDS[args.detection_mode]
    if args.ft232h_serial:
        config["ft232h_serial"] = args.ft232h_serial
    if args.port:
        config["port"] = args.port

    port = int(config.get("port", 8765))
    url = f"http://127.0.0.1:{port}/"
    running_state = existing_bridge_state(port)
    if running_state is not None:
        print(f"SoulRiderBridge is already running at {url}")
        print("Reusing the existing process; no second FT232H handle was opened.")
        if not args.no_browser:
            webbrowser.open(url + "game/")
        return

    instance_guard = SingleInstanceGuard()
    try:
        instance_guard.acquire()
    except AlreadyRunningError:
        print(f"SoulRiderBridge is already starting at {url}")
        print("Reusing the existing process; no second FT232H handle was opened.")
        if not args.no_browser:
            webbrowser.open(url + "game/")
        return

    controller: DemoController | None = None
    event_logger: SessionLogger | None = None
    server: ThreadingHTTPServer | None = None
    try:
        try:
            server = ThreadingHTTPServer(("127.0.0.1", port), DemoHandler)
        except OSError as exc:
            if getattr(exc, "winerror", None) == 10048 or exc.errno == 98:
                print(f"Port {port} is already in use at {url}")
                print("Use the existing bridge instead of starting another FT232H reader.")
                if not args.no_browser:
                    webbrowser.open(url + "game/")
                return
            raise

        event_logger = SessionLogger(
            ROOT / "logs" / "sessions",
            keep_sessions=int(config.get("log_keep_sessions", 3)),
        )
        event_logger.start_session(
            "bridge_start",
            {
                "source_mode": config.get("source_mode"),
                "detection_mode": config.get("detection_mode"),
                "port": port,
                "log_keep_sessions": event_logger.keep_sessions,
            },
        )
        controller = DemoController(config, event_logger=event_logger)
        DemoHandler.controller = controller
        print(f"Soul Rider demo running at {url}")
        print(f"Input mode: {controller.source_mode}")
        print(f"Detection mode: {controller.detection_mode}")
        print(f"Control panel: {url}panel")
        print(f"Session log: {event_logger.current_info()['test_session_dir']}")
        if not args.no_browser:
            threading.Timer(1.0, lambda: webbrowser.open(url + "game/")).start()
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
    finally:
        if controller is not None:
            controller.shutdown()
        if event_logger is not None:
            event_logger.close()
        if server is not None:
            server.server_close()
        instance_guard.release()


if __name__ == "__main__":
    main()
