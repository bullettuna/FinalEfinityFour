from __future__ import annotations

import tempfile
import time
import unittest
import struct
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import cv2

import bridge
from ft232h_source import Frame


class _FakeEngine:
    def __init__(self, config) -> None:
        self.config = config
        self.calls = 0

    def reset_motion_tracking(self) -> None:
        return None

    def process_edge(self, edge, output_dir=None) -> dict:
        self.calls += 1
        if self.calls <= 2:
            return {
                "ok": True,
                "present": True,
                "cx": 0.5,
                "pose_id": 2,
                "action": "right",
                "action_name": "右平举",
                "reason": "ok",
                "bbox_confidence": 0.9,
                "fg_ratio": 0.2,
            }
        return {
            "ok": True,
            "present": True,
            "cx": 0.5,
            "pose_id": 1,
            "action": "stand",
            "action_name": "站立",
            "reason": "no_raised_elbow",
            "bbox_confidence": 0.9,
            "fg_ratio": 0.2,
        }

    def classify_points(self, result) -> dict:
        return {
            "present": True,
            "cx": 0.5,
            "pose_id": 2,
            "action": "right",
            "action_name": "右平举",
            "attack_action": "right",
            "attack_suppressed": False,
            "body_action": "stand",
            "body_action_name": "站立",
            "reason": "ok",
            "bbox_confidence": 1.0,
            "fg_ratio": 0.2,
        }


class _FakeSource:
    instances: list["_FakeSource"] = []

    def __init__(self, **kwargs) -> None:
        self.kwargs = kwargs
        self.closed = False
        self.sequence = 0
        type(self).instances.append(self)

    def open(self) -> None:
        return None

    def read_latest_matching(self, wait_s: float):
        time.sleep(0.01)
        self.sequence += 1
        return SimpleNamespace(sequence=self.sequence, kind=3, width=640, height=360)

    def stats(self) -> dict:
        return {
            "parsed_frames": self.sequence,
            "accepted_frames": self.sequence,
            "ignored_frames": 0,
            "fpga_fps": 15.0,
        }

    def close(self) -> None:
        self.closed = True


class _FakePointSource(_FakeSource):
    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self.kind = int(kwargs["kind"])

    def read_latest_matching(self, wait_s: float):
        time.sleep(0.01)
        self.sequence += 1
        payload = struct.pack(
            "<BBBBIIII",
            2,
            11,
            3,
            0,
            6240433,
            0x1F704B5E,
            0x12345678,
            0x9ABCDEF0,
        )
        payload += b"".join(
            struct.pack("<HHH", index * 160, index * 80, 20000)
            for index in range(11)
        )
        return Frame(
            kind=5,
            sequence=self.sequence,
            width=640,
            height=360,
            payload=payload,
            version=2,
        )


class _StallThenRecoverSource(_FakePointSource):
    instances: list["_StallThenRecoverSource"] = []

    def __init__(self, **kwargs) -> None:
        self.should_stall = not type(self).instances
        super().__init__(**kwargs)

    def read_latest_matching(self, wait_s: float):
        if self.should_stall:
            time.sleep(0.01)
            return None
        return super().read_latest_matching(wait_s)


class _SquatMotionEngine(_FakeEngine):
    def process_edge(self, edge, output_dir=None) -> dict:
        self.calls += 1
        return {
            "ok": True,
            "present": True,
            "cx": 0.5,
            "pose_id": 1,
            "action": "squat",
            "action_name": "下蹲",
            "body_action": "squat",
            "attack_action": "stand",
            "attack_suppressed": True,
            "reason": "squat_detected",
            "bbox_confidence": 0.9,
            "fg_ratio": 0.2,
        }


class _DropoutEngine(_FakeEngine):
    """Attack, one no_person gap, attack again, then stand."""

    def process_edge(self, edge, output_dir=None) -> dict:
        self.calls += 1
        if 2 <= self.calls < 102:
            return {
                "ok": True,
                "present": False,
                "cx": 0.5,
                "pose_id": 1,
                "action": "stand",
                "action_name": "站立",
                "reason": "no_person",
                "bbox_confidence": 0.0,
                "fg_ratio": 0.0,
            }
        return {
            "ok": True,
            "present": True,
            "cx": 0.5,
            "pose_id": 3,
            "action": "left",
            "action_name": "左平举",
            "reason": "ok",
            "bbox_confidence": 0.9,
            "fg_ratio": 0.2,
        }


class _SingleSquatThenLeftEngine(_FakeEngine):
    """A one-frame false squat must not block later real arm attacks."""

    def process_edge(self, edge, output_dir=None) -> dict:
        self.calls += 1
        if self.calls == 1:
            return {
                "ok": True,
                "present": True,
                "cx": 0.5,
                "pose_id": 1,
                "action": "squat",
                "action_name": "下蹲",
                "body_action": "squat",
                "attack_action": "stand",
                "attack_suppressed": True,
                "reason": "squat_detected",
                "bbox_confidence": 0.9,
                "fg_ratio": 0.2,
            }
        return {
            "ok": True,
            "present": True,
            "cx": 0.5,
            "pose_id": 3,
            "action": "left",
            "action_name": "左平举",
            "body_action": "stand",
            "attack_action": "left",
            "attack_suppressed": False,
            "reason": "ok",
            "bbox_confidence": 0.9,
            "fg_ratio": 0.2,
        }


class LiveControllerTests(unittest.TestCase):
    @staticmethod
    def _force_calibration_ready(controller) -> None:
        with controller.condition:
            controller.calibration_ready = True
            controller.calibration_status = "ready"
            controller.calibration_reason = "neutral_confirmed"
            controller.state["calibration_ready"] = True
            controller.state["calibration_state"] = "ready"

    def test_debug_config_apply_and_invalid_relationship(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                config = controller.debug_config()
                self.assertIn(
                    "attack_confirm_min_votes",
                    config["values"],
                )
                self.assertIn(
                    "wrist_rise_elbow_ratio",
                    config["values"],
                )
                self.assertIn(
                    "lower_body_point_conf",
                    config["values"],
                )
                self.assertIn(
                    "human_confidence_threshold",
                    config["values"],
                )
                self.assertIn("arm_rule_weight", config["values"])
                self.assertIn("arm_model_weight", config["values"])
                self.assertIn(
                    "combined_confidence_threshold",
                    config["values"],
                )
                self.assertIn("model_side_mirrored", config["values"])
                self.assertIn("arm_model_enabled", config["values"])
                self.assertTrue(config["controls"])

                result = controller.apply_debug_tuning({
                    "attack_confirm_window_frames": 6,
                    "attack_confirm_min_votes": 3,
                    "attack_cooldown_ms": 750,
                    "wrist_rise_elbow_ratio": 0.75,
                    "wrist_max_below_elbow_ratio": 0.25,
                    "shoulder_hip_speed_threshold_ratio": 0.15,
                    "shoulder_hip_min_drop_ratio": 0.06,
                    "human_confidence_threshold": 0.70,
                    "arm_rule_weight": 0.65,
                    "arm_model_weight": 0.35,
                    "combined_confidence_threshold": 0.60,
                    "model_side_mirrored": 0,
                    "arm_model_enabled": 1,
                })
                self.assertTrue(result["ok"])
                self.assertEqual(
                    result["values"]["attack_confirm_window_frames"],
                    6,
                )
                self.assertEqual(
                    result["values"]["attack_confirm_min_votes"],
                    3,
                )
                self.assertEqual(
                    result["values"]["wrist_rise_elbow_ratio"],
                    0.75,
                )
                self.assertEqual(
                    result["values"]["shoulder_hip_min_drop_ratio"],
                    0.06,
                )
                self.assertEqual(
                    result["values"]["human_confidence_threshold"],
                    0.70,
                )
                self.assertEqual(result["values"]["arm_rule_weight"], 0.65)
                self.assertEqual(result["values"]["arm_model_weight"], 0.35)
                self.assertEqual(result["values"]["model_side_mirrored"], 0)
                self.assertEqual(result["values"]["arm_model_enabled"], 1)

                with self.assertRaises(ValueError):
                    controller.apply_debug_tuning({
                        "elbow_rise_min_pixels": 50,
                        "elbow_rise_max_pixels": 20,
                    })
                with self.assertRaises(ValueError):
                    controller.apply_debug_tuning({
                        "arm_rule_weight": 0.0,
                        "arm_model_weight": 0.0,
                    })
            finally:
                controller.shutdown()

    def test_manual_recalibration_exposes_state(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                result = controller.recalibrate("unit_test")
                self.assertTrue(result["ok"])
                controller.calibration_hold_s = 0.0
                self.assertEqual(
                    result["calibration"]["state"],
                    "collecting",
                )
                self.assertFalse(result["calibration"]["ready"])
                self.assertEqual(
                    controller.snapshot()["calibration"]["reason"],
                    "waiting_for_neutral",
                )
                with controller.condition:
                    for _ in range(3):
                        calibration = controller._update_calibration_locked({
                            "present": True,
                            "body_action": "stand",
                            "arms": {
                                "left": {
                                    "filter_ready": True,
                                    "valid": False,
                                },
                                "right": {
                                    "filter_ready": True,
                                    "valid": False,
                                },
                            },
                        })
                self.assertTrue(calibration["ready"])
                self.assertEqual(calibration["state"], "ready")
                self.assertTrue(controller.snapshot()["calibration_ready"])
            finally:
                controller.shutdown()

    def test_persistent_invalid_pose_resets_tracking_after_timeout(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                controller.invalid_reset_s = 0.5
                with controller.condition:
                    controller.calibration_ready = True
                    controller.calibration_status = "ready"
                    controller.gesture_filter.update("left", now=0.0)
                    controller.pose_invalid_since = time.monotonic() - 1.0
                    calibration = controller._update_calibration_locked({
                        "present": False,
                        "reason": "no_person",
                        "stable_valid": False,
                        "arms": {},
                    })

                self.assertFalse(calibration["ready"])
                self.assertFalse(controller.snapshot()["calibration_ready"])
                self.assertEqual(
                    controller.gesture_filter.candidate_frames,
                    0,
                )
                self.assertEqual(len(controller.gesture_filter.history), 0)
            finally:
                controller.shutdown()

    def test_calibration_window_tolerates_single_pose_twitch(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                controller.calibration_hold_s = 0.05
                controller.calibration_neutral_ratio = 0.7
                controller.recalibrate("window_test")
                neutral = {
                    "present": True,
                    "stable_valid": True,
                    "body_action": "stand",
                    "arms": {
                        "left": {
                            "filter_ready": True,
                            "valid": False,
                        },
                        "right": {
                            "filter_ready": True,
                            "valid": False,
                        },
                    },
                }
                twitch = {
                    **neutral,
                    "stable_valid": False,
                    "reason": "pose_outlier_skipped",
                    "validity_reason": "pose_position_jump",
                }
                with controller.condition:
                    for index in range(9):
                        controller._update_calibration_locked(
                            twitch if index == 4 else neutral
                        )
                        time.sleep(0.01)
                    calibration = controller._update_calibration_locked(
                        neutral
                    )

                self.assertTrue(calibration["ready"])
                self.assertGreaterEqual(calibration["neutral_ratio"], 0.7)
                self.assertLessEqual(
                    calibration["consecutive_neutral_misses"],
                    2,
                )
            finally:
                controller.shutdown()

    def test_calibration_ready_as_soon_as_stable_action_starts(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                controller.calibration_timeout_s = 5.0
                controller.calibration_hold_s = 1.0
                controller.recalibrate("action_ready_test")
                active_pose = {
                    "present": True,
                    "stable_valid": True,
                    "body_action": "squat",
                    "attack_action": "stand",
                    "arms": {
                        "left": {"filter_ready": True, "valid": True},
                        "right": {"filter_ready": True, "valid": True},
                    },
                }
                with controller.condition:
                    for _ in range(3):
                        calibration = controller._update_calibration_locked(
                            active_pose
                        )

                self.assertTrue(calibration["ready"])
                self.assertEqual(calibration["state"], "ready")
                self.assertEqual(
                    calibration["reason"],
                    "action_started",
                )
            finally:
                controller.shutdown()

    def test_calibration_falls_back_to_ready_after_bounded_timeout(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                controller.calibration_timeout_s = 0.05
                controller.calibration_hold_s = 1.0
                controller.recalibrate("auto_ready_test")
                warmup_pose = {
                    "present": True,
                    "stable_valid": True,
                    "body_action": "stand",
                    "attack_action": "stand",
                    "arms": {
                        "left": {"filter_ready": False, "valid": False},
                        "right": {"filter_ready": False, "valid": False},
                    },
                }
                with controller.condition:
                    controller._update_calibration_locked(warmup_pose)
                    time.sleep(0.06)
                    calibration = controller._update_calibration_locked(warmup_pose)

                self.assertTrue(calibration["ready"])
                self.assertEqual(calibration["state"], "ready")
                self.assertEqual(
                    calibration["reason"],
                    "timeout_auto_ready",
                )
            finally:
                controller.shutdown()

    def test_model_warmup_geometry_can_complete_calibration(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "folder",
                "input_dir": "",
            })
            try:
                controller.calibration_timeout_s = 0.05
                controller.calibration_hold_s = 1.0
                controller.recalibrate("model_warmup_test")
                warmup_pose = {
                    "present": False,
                    "stable_valid": True,
                    "calibration_usable": True,
                    "reason": "model_warming_up",
                    "validity_reason": "pose_stable",
                    "body_action": "stand",
                    "attack_action": "stand",
                    "arms": {
                        "left": {"filter_ready": False, "valid": False},
                        "right": {"filter_ready": False, "valid": False},
                    },
                }
                with controller.condition:
                    controller._update_calibration_locked(warmup_pose)
                    time.sleep(0.06)
                    calibration = controller._update_calibration_locked(
                        warmup_pose
                    )

                self.assertTrue(calibration["ready"])
                self.assertEqual(calibration["state"], "ready")
                self.assertEqual(
                    calibration["reason"],
                    "timeout_auto_ready",
                )
            finally:
                controller.shutdown()

    def test_stream_waiting_clears_stale_pose_state(self) -> None:
        with patch.object(bridge, "PoseEngine", _FakeEngine):
            controller = bridge.DemoController({
                "source_mode": "ft232h",
                "detection_mode": "eleven_point",
            })
            try:
                with controller.condition:
                    controller.state.update({
                        "valid": True,
                        "present": True,
                        "points": [{"name": "head"}],
                        "classifier_frames": 7,
                        "model_gate_passed": True,
                    })
                    controller._set_live_waiting("stream_lost_test", {})
                    state = controller.snapshot()

                self.assertFalse(state["valid"])
                self.assertFalse(state["present"])
                self.assertEqual(state["points"], [])
                self.assertEqual(state["classifier_frames"], 0)
                self.assertFalse(state["model_gate_passed"])
                self.assertEqual(state["model_gate_reason"], "stream_lost")
                self.assertEqual(state["calibration_state"], "stream_lost")
            finally:
                controller.shutdown()

    def test_eleven_point_renderer_writes_nonblank_640x360_image(self) -> None:
        points = [
            {
                "index": index,
                "name": name,
                "x": 80.0 + index * 40,
                "y": 60.0 + (index % 3) * 80,
            }
            for index, name in enumerate((
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
            ))
        ]
        result = {
            "sequence": 8,
            "width": 640,
            "height": 360,
            "model_crc_hex": "1f704b5e",
            "flags": 3,
            "valid": True,
            "is_live": True,
            "inference_ms": 65.0,
            "points": points,
            "skeleton_edges": [
                [0, 1], [0, 2], [1, 2], [1, 3], [3, 5],
                [2, 4], [4, 6], [1, 7], [2, 8], [7, 8],
                [7, 9], [8, 10],
            ],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            path = bridge.render_point_debug(result, Path(temp_dir))
            image = cv2.imread(str(path))

        self.assertEqual(image.shape, (360, 640, 3))
        self.assertGreater(float(np.std(image)), 1.0)

    def test_eleven_point_debug_mode_runs_without_game_start(self) -> None:
        _FakePointSource.instances.clear()
        with (
            patch.object(bridge, "PoseEngine", _FakeEngine),
            patch.object(bridge, "PreconfiguredEdgeSource", _FakePointSource),
            patch.object(bridge, "render_point_debug", return_value=Path("unused.jpg")),
        ):
            controller = bridge.DemoController({
                "source_mode": "ft232h",
                "detection_mode": "eleven_point",
            })
            try:
                controller.set_game_active(True)
                self._force_calibration_ready(controller)
                deadline = time.monotonic() + 2.0
                state = {}
                while time.monotonic() < deadline:
                    state = controller.snapshot()
                    if len(state.get("points", [])) == 11:
                        break
                    time.sleep(0.01)

                self.assertEqual(state.get("detection_mode"), "eleven_point")
                self.assertEqual(state.get("kind"), 5)
                self.assertEqual(state.get("point_count"), 11)
                self.assertEqual(state.get("points")[0]["name"], "head")
                self.assertTrue(state.get("valid"))
                self.assertEqual(state.get("action"), "right")
                self.assertEqual(state.get("action_name"), "右平举")
                self.assertEqual(_FakePointSource.instances[0].kwargs["kind"], 5)
            finally:
                controller.shutdown()

    def test_two_matching_frames_trigger_one_action_and_keep_source_alive(self) -> None:
        _FakeSource.instances.clear()
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                patch.object(bridge, "PoseEngine", _FakeEngine),
                patch.object(bridge, "PreconfiguredEdgeSource", _FakeSource),
                patch.object(
                    bridge,
                    "decode_packed_edge",
                    return_value=np.zeros((360, 640), dtype=np.uint8),
                ),
            ):
                controller = bridge.DemoController({
                    "source_mode": "ft232h",
                    "detection_mode": "yolo",
                })
                controller.history_path = Path(temp_dir) / "history.csv"
                try:
                    controller.set_game_active(True)
                    self._force_calibration_ready(controller)
                    deadline = time.monotonic() + 2.0
                    state = {}
                    while time.monotonic() < deadline:
                        state = controller.snapshot()
                        if (
                            state.get("action_seq", 0) >= 1
                            and state.get("action") == "stand"
                        ):
                            break
                        time.sleep(0.01)

                    self.assertEqual(state.get("action"), "stand")
                    self.assertEqual(state.get("trigger_action"), "right")
                    self.assertEqual(state.get("action_seq"), 1)
                    self.assertGreaterEqual(state.get("frame_seq", 0), 3)
                    self.assertEqual(state.get("source_mode"), "ft232h")
                    self.assertIn("calibration", state)
                    self.assertIn("debug", state)
                    self.assertIn("gesture", state["debug"])
                    self.assertIn("post_squat_gate", state["debug"])
                    self.assertEqual(
                        state["debug"]["pipeline"]["action_seq"],
                        state.get("action_seq"),
                    )

                    controller.set_game_active(False)
                    frame_before = state.get("frame_seq", 0)
                    deadline = time.monotonic() + 1.0
                    while time.monotonic() < deadline:
                        state = controller.snapshot()
                        if state.get("frame_seq", 0) > frame_before:
                            break
                        time.sleep(0.01)
                    self.assertTrue(
                        any(not source.closed for source in _FakeSource.instances)
                    )
                    self.assertGreater(state.get("frame_seq", 0), frame_before)
                finally:
                    controller.set_game_active(False)
                    controller.shutdown()

    def test_yolo_stream_opens_before_game_start(self) -> None:
        _FakeSource.instances.clear()
        with (
            patch.object(bridge, "PoseEngine", _FakeEngine),
            patch.object(bridge, "PreconfiguredEdgeSource", _FakeSource),
            patch.object(
                bridge,
                "decode_packed_edge",
                return_value=np.zeros((360, 640), dtype=np.uint8),
            ),
        ):
            controller = bridge.DemoController({
                "source_mode": "ft232h",
                "detection_mode": "yolo",
            })
            try:
                deadline = time.monotonic() + 1.0
                state = {}
                while time.monotonic() < deadline:
                    state = controller.snapshot()
                    if state.get("frame_seq", 0) > 0:
                        break
                    time.sleep(0.01)

                self.assertFalse(controller.game_active)
                self.assertGreater(state.get("frame_seq", 0), 0)
                self.assertTrue(_FakeSource.instances)
                self.assertFalse(_FakeSource.instances[0].closed)
            finally:
                controller.shutdown()

    def test_stalled_source_is_reopened_by_frame_watchdog(self) -> None:
        _StallThenRecoverSource.instances.clear()
        with (
            patch.object(bridge, "PoseEngine", _FakeEngine),
            patch.object(bridge, "PreconfiguredEdgeSource", _StallThenRecoverSource),
            patch.object(bridge, "render_point_debug", return_value=Path("unused.jpg")),
        ):
            controller = bridge.DemoController({
                "source_mode": "ft232h",
                "detection_mode": "eleven_point",
                "ft232h_stall_timeout_ms": 120,
            })
            try:
                deadline = time.monotonic() + 2.0
                state = {}
                while time.monotonic() < deadline:
                    state = controller.snapshot()
                    if (
                        state.get("stream_reopen_count", 0) >= 1
                        and state.get("stream_healthy")
                    ):
                        break
                    time.sleep(0.01)

                self.assertGreaterEqual(len(_StallThenRecoverSource.instances), 2)
                self.assertTrue(_StallThenRecoverSource.instances[0].closed)
                self.assertEqual(state.get("stream_reopen_count"), 1)
                self.assertTrue(state.get("stream_healthy"))
                self.assertTrue(
                    str(state.get("last_stream_recovery", "")).startswith(
                        "no_valid_frames:"
                    )
                )
            finally:
                controller.shutdown()

    def test_squat_updates_state_without_triggering_attack(self) -> None:
        _FakeSource.instances.clear()
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                patch.object(bridge, "PoseEngine", _SquatMotionEngine),
                patch.object(bridge, "PreconfiguredEdgeSource", _FakeSource),
                patch.object(
                    bridge,
                    "decode_packed_edge",
                    return_value=np.zeros((360, 640), dtype=np.uint8),
                ),
            ):
                controller = bridge.DemoController({
                    "source_mode": "ft232h",
                    "detection_mode": "yolo",
                })
                controller.history_path = Path(temp_dir) / "history.csv"
                try:
                    controller.set_game_active(True)
                    self._force_calibration_ready(controller)
                    deadline = time.monotonic() + 2.0
                    state = {}
                    while time.monotonic() < deadline:
                        state = controller.snapshot()
                        if (
                            state.get("body_action") == "squat"
                            and state.get("frame_seq", 0) >= 3
                        ):
                            break
                        time.sleep(0.01)

                    self.assertEqual(state.get("body_action"), "squat")
                    self.assertEqual(state.get("action"), "squat")
                    self.assertEqual(state.get("attack_action"), "stand")
                    self.assertEqual(state.get("action_seq"), 0)
                    self.assertEqual(state.get("trigger_action"), "stand")
                    self.assertEqual(state.get("body_action_seq"), 1)
                    self.assertEqual(state.get("trigger_body_action"), "squat")
                finally:
                    controller.set_game_active(False)
                    controller.shutdown()

    def test_no_person_gap_blocks_until_calibration_ready(self) -> None:
        _FakeSource.instances.clear()
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                patch.object(bridge, "PoseEngine", _DropoutEngine),
                patch.object(bridge, "PreconfiguredEdgeSource", _FakeSource),
                patch.object(
                    bridge,
                    "decode_packed_edge",
                    return_value=np.zeros((360, 640), dtype=np.uint8),
                ),
            ):
                controller = bridge.DemoController({
                    "source_mode": "ft232h",
                    "detection_mode": "yolo",
                })
                controller.history_path = Path(temp_dir) / "history.csv"
                try:
                    controller.set_game_active(True)
                    self._force_calibration_ready(controller)
                    deadline = time.monotonic() + 2.0
                    state = {}
                    while time.monotonic() < deadline:
                        state = controller.snapshot()
                        if state.get("calibration_ready") is False:
                            break
                        time.sleep(0.01)

                    self.assertFalse(state.get("calibration_ready"))
                    self.assertEqual(state.get("action_seq"), 0)
                finally:
                    controller.set_game_active(False)
                    controller.shutdown()

    def test_single_false_squat_frame_does_not_block_later_attack(self) -> None:
        _FakeSource.instances.clear()
        with tempfile.TemporaryDirectory() as temp_dir:
            with (
                patch.object(bridge, "PoseEngine", _SingleSquatThenLeftEngine),
                patch.object(bridge, "PreconfiguredEdgeSource", _FakeSource),
                patch.object(
                    bridge,
                    "decode_packed_edge",
                    return_value=np.zeros((360, 640), dtype=np.uint8),
                ),
            ):
                controller = bridge.DemoController({
                    "source_mode": "ft232h",
                    "detection_mode": "yolo",
                })
                controller.history_path = Path(temp_dir) / "history.csv"
                try:
                    controller.set_game_active(True)
                    self._force_calibration_ready(controller)
                    deadline = time.monotonic() + 2.0
                    state = {}
                    while time.monotonic() < deadline:
                        state = controller.snapshot()
                        if state.get("action_seq", 0) >= 1:
                            break
                        time.sleep(0.01)

                    self.assertEqual(state.get("action_seq"), 1)
                    self.assertEqual(state.get("trigger_action"), "left")
                    self.assertFalse(state.get("attack_gated"))
                finally:
                    controller.set_game_active(False)
                    controller.shutdown()


if __name__ == "__main__":
    unittest.main()
