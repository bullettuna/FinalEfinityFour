from __future__ import annotations

import time
import unittest
from collections import deque
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from elbow_tracker import ElbowRiseTracker
from pose_engine import PoseConfig, PoseEngine
from shoulder_tracker import ShoulderMotionTracker, ShoulderWidthGate


class _Tensor:
    def __init__(self, value) -> None:
        self.value = np.asarray(value)

    def cpu(self) -> "_Tensor":
        return self

    def numpy(self) -> np.ndarray:
        return self.value


class _Indexed:
    def __init__(self, value) -> None:
        self.value = value

    def __getitem__(self, index: int) -> _Tensor:
        return _Tensor(self.value[index])


class _Boxes:
    def __init__(self, confidence: float, bbox: list[float]) -> None:
        self.conf = _Tensor([confidence])
        self.xyxy = _Indexed(np.asarray([bbox], dtype=float))

    def __len__(self) -> int:
        return 1


class _Keypoints:
    def __init__(self, xy: np.ndarray, confidence: np.ndarray) -> None:
        self.xy = _Indexed(xy)
        self.conf = _Indexed(confidence)


def _result(
    left_elbow_y: float,
    right_elbow_y: float,
    left_wrist_y: float | None = None,
    right_wrist_y: float | None = None,
    left_shoulder_y: float = 150,
    right_shoulder_y: float = 150,
    left_shoulder_x: float = 200,
    right_shoulder_x: float = 400,
    left_hip_y: float = 250,
    right_hip_y: float = 250,
    left_elbow_conf: float = 0.9,
    right_elbow_conf: float = 0.9,
    left_wrist_conf: float = 0.9,
    right_wrist_conf: float = 0.9,
    left_hip_conf: float = 0.9,
    right_hip_conf: float = 0.9,
) -> SimpleNamespace:
    xy = np.zeros((1, 17, 2), dtype=float)
    confidence = np.full((1, 17), 0.9, dtype=float)

    xy[0, 5] = (left_shoulder_x, left_shoulder_y)
    xy[0, 6] = (right_shoulder_x, right_shoulder_y)
    xy[0, 7] = (180, left_elbow_y)
    xy[0, 8] = (420, right_elbow_y)
    xy[0, 9] = (
        160,
        left_elbow_y + 20 if left_wrist_y is None else left_wrist_y,
    )
    xy[0, 10] = (
        440,
        right_elbow_y + 20 if right_wrist_y is None else right_wrist_y,
    )
    xy[0, 11] = (260, left_hip_y)
    xy[0, 12] = (340, right_hip_y)
    confidence[0, 7] = left_elbow_conf
    confidence[0, 8] = right_elbow_conf
    confidence[0, 9] = left_wrist_conf
    confidence[0, 10] = right_wrist_conf
    confidence[0, 11] = left_hip_conf
    confidence[0, 12] = right_hip_conf

    return SimpleNamespace(
        boxes=_Boxes(0.9, [100, 100, 500, 300]),
        keypoints=_Keypoints(xy, confidence),
        orig_shape=(360, 640),
    )


def _eleven_point_result(
    left_elbow_y: float,
    right_elbow_y: float,
    left_wrist_y: float | None = None,
    right_wrist_y: float | None = None,
) -> dict:
    return {
        "valid": True,
        "fault": False,
        "model_ready": True,
        "width": 640,
        "height": 360,
        "points": [
            {"name": "head", "x": 320, "y": 80},
            {"name": "left_shoulder", "x": 200, "y": 150},
            {"name": "right_shoulder", "x": 400, "y": 150},
            {"name": "left_elbow", "x": 180, "y": left_elbow_y},
            {"name": "right_elbow", "x": 420, "y": right_elbow_y},
            {
                "name": "left_wrist",
                "x": 160,
                "y": left_elbow_y + 20 if left_wrist_y is None else left_wrist_y,
            },
            {
                "name": "right_wrist",
                "x": 440,
                "y": right_elbow_y + 20 if right_wrist_y is None else right_wrist_y,
            },
            {"name": "left_hip", "x": 260, "y": 240},
            {"name": "right_hip", "x": 340, "y": 240},
            {"name": "left_knee", "x": 250, "y": 310},
            {"name": "right_knee", "x": 350, "y": 310},
        ],
    }


class ElbowClassifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = object.__new__(PoseEngine)
        self.engine.config = PoseConfig(
            model=Path("unused.pt"),
            keypoint_conf=0.10,
            elbow_rise_pixels=20,
            elbow_release_pixels=8,
            elbow_release_frames=2,
            elbow_median_frames=3,
            elbow_rise_shoulder_ratio=0.0,
            shoulder_speed_window_frames=5,
            shoulder_speed_threshold_ratio=0.20,
            shoulder_min_drop_ratio=0.08,
            shoulder_release_ratio=0.05,
            shoulder_symmetry_ratio=0.06,
            shoulder_confirm_frames=1,
            pose_stable_frames=1,
        )
        self.engine.elbow_tracker = ElbowRiseTracker(
            rise_pixels=20,
            release_pixels=8,
            median_frames=3,
            release_frames=2,
        )
        self.engine.wrist_tracker = ElbowRiseTracker(
            rise_pixels=20,
            release_pixels=8,
            median_frames=3,
            release_frames=2,
            joint_name="wrist",
        )
        self.engine.shoulder_tracker = ShoulderMotionTracker(
            speed_window_frames=5,
            speed_threshold_ratio=0.20,
            min_drop_ratio=0.08,
            release_ratio=0.05,
            symmetry_ratio=0.06,
            confirm_frames=1,
        )
        self.engine.shoulder_widths = deque(maxlen=5)
        self.engine.shoulder_width_gate = ShoulderWidthGate(
            confirm_frames=3,
            tolerance_ratio=0.25,
        )

    def test_left_elbow_trigger_uses_left_pose(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        self.engine.classify(_result(left_elbow_y=139, right_elbow_y=160))
        result = self.engine.classify(_result(left_elbow_y=139, right_elbow_y=160))
        self.assertEqual(result["action"], "left")
        self.assertEqual(result["pose_id"], 3)
        self.assertAlmostEqual(result["arms"]["left"]["rise_px"], 21.0)

    def test_right_elbow_trigger_uses_right_pose(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=138))
        result = self.engine.classify(_result(left_elbow_y=160, right_elbow_y=138))
        self.assertEqual(result["action"], "right")
        self.assertEqual(result["pose_id"], 2)

    def test_higher_elbow_wins_when_both_are_raised(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        self.engine.classify(_result(left_elbow_y=135, right_elbow_y=120))
        result = self.engine.classify(_result(left_elbow_y=135, right_elbow_y=120))
        self.assertEqual(result["action"], "right")
        self.assertTrue(result["both_elbows_raised"])

    def test_elbow_below_threshold_stays_standing(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        result = self.engine.classify(_result(left_elbow_y=142, right_elbow_y=142))
        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["reason"], "no_raised_elbow")

    def test_low_confidence_elbow_is_ignored(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        result = self.engine.classify(
            _result(
                left_elbow_y=130,
                right_elbow_y=160,
                left_elbow_conf=0.05,
            )
        )
        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["arms"]["left"]["reason"], "low_keypoint_confidence")

    def test_elbow_rise_without_wrist_rise_is_rejected(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        for _ in range(3):
            result = self.engine.classify(_result(
                left_elbow_y=139,
                right_elbow_y=160,
                left_wrist_y=180,
            ))

        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["reason"], "wrist_not_raised")
        self.assertTrue(result["arms"]["left"]["elbow_valid"])
        self.assertFalse(result["arms"]["left"]["wrist_valid"])

    def test_wrist_far_below_elbow_is_rejected(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        for _ in range(3):
            result = self.engine.classify(_result(
                left_elbow_y=100,
                right_elbow_y=160,
                left_wrist_y=150,
            ))

        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["reason"], "wrist_below_elbow")
        self.assertTrue(result["arms"]["left"]["wrist_valid"])
        self.assertGreater(
            result["arms"]["left"]["wrist_below_elbow_px"],
            result["arms"]["left"]["wrist_offset_limit_px"],
        )

    def test_low_confidence_wrist_blocks_attack(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        for _ in range(3):
            result = self.engine.classify(_result(
                left_elbow_y=139,
                right_elbow_y=160,
                left_wrist_y=159,
                left_wrist_conf=0.05,
            ))

        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["reason"], "low_wrist_confidence")

    def test_symmetric_shoulder_rise_is_ignored(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        for _ in range(5):
            result = self.engine.classify(
                _result(
                    left_elbow_y=160,
                    right_elbow_y=160,
                    left_shoulder_y=120,
                    right_shoulder_y=120,
                )
            )

        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["body_action"], "stand")
        self.assertEqual(result["attack_action"], "stand")
        self.assertFalse(result["attack_suppressed"])

    def test_symmetric_shoulder_drop_is_squat(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        for _ in range(5):
            result = self.engine.classify(
                _result(
                    left_elbow_y=160,
                    right_elbow_y=160,
                    left_shoulder_y=180,
                    right_shoulder_y=180,
                    left_hip_y=280,
                    right_hip_y=280,
                )
            )

        self.assertEqual(result["action"], "squat")
        self.assertEqual(result["attack_action"], "stand")

    def test_shoulder_drop_without_hip_drop_is_not_squat(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        results = []
        for _ in range(5):
            results.append(self.engine.classify(
                _result(
                    left_elbow_y=160,
                    right_elbow_y=160,
                    left_shoulder_y=180,
                    right_shoulder_y=180,
                    left_hip_y=250,
                    right_hip_y=250,
                )
            ))

        self.assertTrue(all(
            result["body_action"] == "stand" for result in results
        ))
        self.assertTrue(any(
            result["shoulder_motion"]["shoulder_candidate"]
            for result in results
        ))
        self.assertFalse(any(
            result["shoulder_motion"]["lower_body_confirmed"]
            for result in results
        ))
        self.assertTrue(any(
            result["shoulder_motion"]["reason"]
            == "hip_motion_below_threshold"
            for result in results
        ))

    def test_low_confidence_hips_disable_squat_only(self) -> None:
        self.engine.classify(_result(left_elbow_y=160, right_elbow_y=160))
        results = []
        for _ in range(5):
            results.append(self.engine.classify(
                _result(
                    left_elbow_y=160,
                    right_elbow_y=160,
                    left_shoulder_y=180,
                    right_shoulder_y=180,
                    left_hip_y=280,
                    right_hip_y=280,
                    left_hip_conf=0.05,
                )
            ))

        self.assertTrue(all(
            result["body_action"] == "stand" for result in results
        ))
        self.assertFalse(any(
            result["shoulder_motion"]["hips_available"]
            for result in results
        ))
        self.assertTrue(any(
            result["shoulder_motion"]["reason"]
            == "lower_body_unavailable"
            for result in results
        ))


class ShoulderScaledElbowThresholdTests(unittest.TestCase):
    def _engine(self, ratio: float, min_px: float = 14.0,
                max_px: float = 45.0) -> PoseEngine:
        engine = object.__new__(PoseEngine)
        engine.config = PoseConfig(
            model=Path("unused.pt"),
            keypoint_conf=0.10,
            elbow_rise_pixels=20,
            elbow_release_pixels=8,
            elbow_release_frames=2,
            elbow_median_frames=3,
            elbow_rise_shoulder_ratio=ratio,
            elbow_rise_min_pixels=min_px,
            elbow_rise_max_pixels=max_px,
            shoulder_speed_window_frames=5,
            shoulder_speed_threshold_ratio=0.20,
            shoulder_min_drop_ratio=0.08,
            shoulder_release_ratio=0.05,
            shoulder_symmetry_ratio=0.06,
            shoulder_confirm_frames=1,
            pose_stable_frames=1,
        )
        engine.elbow_tracker = ElbowRiseTracker(
            rise_pixels=20,
            release_pixels=8,
            median_frames=3,
            release_frames=2,
        )
        engine.wrist_tracker = ElbowRiseTracker(
            rise_pixels=20,
            release_pixels=8,
            median_frames=3,
            release_frames=2,
            joint_name="wrist",
        )
        engine.shoulder_tracker = ShoulderMotionTracker(
            speed_window_frames=5,
            speed_threshold_ratio=0.20,
            min_drop_ratio=0.08,
            release_ratio=0.05,
            symmetry_ratio=0.06,
            confirm_frames=1,
        )
        engine.shoulder_widths = deque(maxlen=5)
        engine.shoulder_width_gate = ShoulderWidthGate(
            confirm_frames=3,
            tolerance_ratio=0.25,
        )
        return engine

    def test_threshold_scales_with_shoulder_width(self) -> None:
        # Fixture shoulders sit 200 px apart, so ratio 0.2 gives 40 px.
        strict = self._engine(ratio=0.2)
        strict.classify(_result(left_elbow_y=160, right_elbow_y=160))
        strict.classify(_result(left_elbow_y=140, right_elbow_y=160))
        result = strict.classify(_result(left_elbow_y=139, right_elbow_y=160))
        self.assertEqual(result["action"], "stand")
        self.assertAlmostEqual(result["elbow_rise_threshold_px"], 40.0)
        self.assertAlmostEqual(result["shoulder_width_px"], 200.0)

        lenient = self._engine(ratio=0.1)
        lenient.classify(_result(left_elbow_y=160, right_elbow_y=160))
        lenient.classify(_result(left_elbow_y=140, right_elbow_y=160))
        result = lenient.classify(_result(left_elbow_y=139, right_elbow_y=160))
        self.assertEqual(result["action"], "left")
        self.assertAlmostEqual(result["elbow_rise_threshold_px"], 20.0)

    def test_threshold_is_clamped_to_min_and_max(self) -> None:
        narrow = self._engine(ratio=0.01, min_px=14.0, max_px=45.0)
        result = None
        for _ in range(3):
            result = narrow.classify(_result(left_elbow_y=160, right_elbow_y=160))
        self.assertAlmostEqual(result["elbow_rise_threshold_px"], 14.0)

        wide = self._engine(ratio=1.0, min_px=14.0, max_px=45.0)
        result = None
        for _ in range(3):
            result = wide.classify(_result(left_elbow_y=160, right_elbow_y=160))
        self.assertAlmostEqual(result["elbow_rise_threshold_px"], 45.0)

    def test_single_frame_width_outlier_is_ignored(self) -> None:
        engine = self._engine(ratio=0.2)
        for _ in range(3):
            engine.classify(_result(left_elbow_y=160, right_elbow_y=160))

        outlier = engine.classify(_result(
            left_elbow_y=160,
            right_elbow_y=160,
            left_shoulder_x=280,
            right_shoulder_x=300,
        ))
        self.assertAlmostEqual(outlier["shoulder_width_px"], 20.0)
        self.assertAlmostEqual(outlier["shoulder_width_stable_px"], 200.0)
        self.assertAlmostEqual(outlier["elbow_rise_threshold_px"], 40.0)

        for _ in range(3):
            result = engine.classify(_result(
                left_elbow_y=160,
                right_elbow_y=160,
                left_shoulder_x=280,
                right_shoulder_x=300,
            ))
        self.assertAlmostEqual(result["shoulder_width_stable_px"], 20.0)
        self.assertAlmostEqual(result["elbow_rise_threshold_px"], 14.0)

    def test_eleven_point_result_reuses_elbow_classifier(self) -> None:
        engine = self._engine(ratio=0.0)
        engine.classify_points(_eleven_point_result(160, 160))
        engine.classify_points(_eleven_point_result(139, 160))
        result = engine.classify_points(_eleven_point_result(139, 160))
        self.assertEqual(result["action"], "left")
        self.assertEqual(result["pose_id"], 3)
        self.assertAlmostEqual(result["arms"]["left"]["rise_px"], 21.0)

    def test_model_warmup_remains_usable_for_calibration(self) -> None:
        engine = self._engine(ratio=0.0)
        engine.pose_model_bundle = SimpleNamespace(window_size=18)
        engine._pose_model_coordinates = deque(maxlen=18)
        engine._pose_model_scores = deque(maxlen=18)

        result = engine.classify_points(_eleven_point_result(160, 160))

        self.assertEqual(result["reason"], "no_raised_elbow")
        self.assertTrue(result["present"])
        self.assertTrue(result["stable_valid"])
        self.assertEqual(result["model_gate_reason"], "model_warming_up")
        self.assertFalse(result["model_gate_passed"])
        self.assertEqual(result["classifier_frames"], 1)

    def test_low_human_confidence_does_not_override_confirmed_squat(self) -> None:
        engine = self._engine(ratio=0.0)

        class _LowHumanBundle:
            window_size = 1

            @staticmethod
            def predict(_coordinates, _scores):
                return {
                    "human_confidence": 0.0,
                    "raise_confidence": 0.1,
                    "arm_probabilities": {
                        "left_raise": 0.05,
                        "right_raise": 0.05,
                        "no_raise": 0.90,
                    },
                }

        engine.pose_model_bundle = _LowHumanBundle()
        engine.pose_model_error = ""
        engine._pose_model_coordinates = deque(maxlen=1)
        engine._pose_model_scores = deque(maxlen=1)
        state = engine.shoulder_tracker.state
        state.baseline_left_y = 100.0
        state.baseline_right_y = 100.0
        state.baseline_left_hip_y = 140.0
        state.baseline_right_hip_y = 140.0
        state.last_seen = time.monotonic()
        state.action = "squat"
        state.squat_floor_y = 100.0

        result = engine.classify_points(_eleven_point_result(160, 160))

        self.assertEqual(result["body_action"], "squat")
        self.assertEqual(result["action"], "squat")
        self.assertEqual(result["human_confidence"], 0.0)

    def test_disabled_arm_model_does_not_block_mature_rule_direction(self) -> None:
        engine = self._engine(ratio=0.0)
        engine.config.arm_model_enabled = False

        class _OppositeArmBundle:
            window_size = 1

            @staticmethod
            def predict(_coordinates, _scores):
                return {
                    "human_confidence": 1.0,
                    "raise_confidence": 0.9,
                    "arm_probabilities": {
                        "left_raise": 0.9,
                        "right_raise": 0.05,
                        "no_raise": 0.05,
                    },
                }

        engine.pose_model_bundle = _OppositeArmBundle()
        engine.pose_model_error = ""
        engine._pose_model_coordinates = deque(maxlen=1)
        engine._pose_model_scores = deque(maxlen=1)
        engine.classify_points(_eleven_point_result(160, 160))
        engine.classify_points(_eleven_point_result(160, 138))
        result = engine.classify_points(_eleven_point_result(160, 138))

        self.assertEqual(result["action"], "right")
        self.assertFalse(result["model_rule_conflict"])
        self.assertEqual(result["model_decision_reason"], "arm_model_disabled")

    def test_eleven_point_elbow_only_is_rejected(self) -> None:
        engine = self._engine(ratio=0.0)
        engine.classify_points(_eleven_point_result(160, 160))
        for _ in range(3):
            result = engine.classify_points(
                _eleven_point_result(139, 160, left_wrist_y=180)
            )

        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["reason"], "wrist_not_raised")
        self.assertFalse(result["arms"]["left"]["wrist_valid"])

    def test_eleven_point_shoulder_drop_with_stable_hips_is_not_squat(
        self,
    ) -> None:
        engine = self._engine(ratio=0.0)
        engine.classify_points(_eleven_point_result(160, 160))
        results = []
        for _ in range(5):
            frame = _eleven_point_result(160, 160)
            for point in frame["points"]:
                if point["name"] in {"left_shoulder", "right_shoulder"}:
                    point["y"] = 170
            results.append(engine.classify_points(frame))

        self.assertTrue(all(
            result["body_action"] == "stand" for result in results
        ))
        self.assertTrue(any(
            result["shoulder_motion"]["shoulder_candidate"]
            for result in results
        ))
        self.assertFalse(any(
            result["shoulder_motion"]["lower_body_confirmed"]
            for result in results
        ))

    def test_eleven_point_invalid_result_is_not_present(self) -> None:
        engine = self._engine(ratio=0.0)
        result = _eleven_point_result(160, 160)
        result["valid"] = False
        classification = engine.classify_points(result)
        self.assertFalse(classification["present"])
        self.assertEqual(classification["reason"], "result_flags_invalid")

    def test_eleven_point_low_required_score_rejects_frame(self) -> None:
        result = _eleven_point_result(160, 160)
        for point in result["points"]:
            point["score"] = 0.05

        engine = self._engine(ratio=0.0)
        classification = engine.classify_points(result)
        self.assertTrue(classification["present"])
        self.assertEqual(
            classification["reason"],
            "pose_outlier_skipped",
        )
        classification = engine.classify_points(result)

        self.assertFalse(classification["present"])
        self.assertEqual(
            classification["reason"],
            "low_required_point_score",
        )
        self.assertFalse(classification["stable_valid"])

    def test_eleven_point_implausible_shoulder_width_rejects_frame(self) -> None:
        result = _eleven_point_result(160, 160)
        for point in result["points"]:
            if point["name"] == "left_shoulder":
                point["x"] = 200
            elif point["name"] == "right_shoulder":
                point["x"] = 201
            point["score"] = 0.8

        engine = self._engine(ratio=0.0)
        classification = engine.classify_points(result)
        self.assertTrue(classification["present"])
        self.assertEqual(
            classification["reason"],
            "pose_outlier_skipped",
        )
        classification = engine.classify_points(result)

        self.assertFalse(classification["present"])
        self.assertEqual(
            classification["reason"],
            "implausible_shoulder_width",
        )


if __name__ == "__main__":
    unittest.main()
