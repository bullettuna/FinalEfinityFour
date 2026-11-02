from __future__ import annotations

import json
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from statistics import median

import cv2
import numpy as np
from PIL import Image
from ultralytics import YOLO

from elbow_tracker import ElbowRiseTracker
from pose_model import PoseModelBundle, fuse_arm_decision, rule_side_confidence
from shoulder_tracker import ShoulderMotionTracker, ShoulderWidthGate


ROOT = Path(__file__).resolve().parent
FPGA_TOOLS = ROOT / "tools" / "fpga"
if str(FPGA_TOOLS) not in sys.path:
    sys.path.insert(0, str(FPGA_TOOLS))

from fpga_canny import Config, convert, load_profile


ACTION_NAMES = {
    "stand": "站立",
    "left": "左平举",
    "right": "右平举",
    "left_overhead": "左上举",
    "right_overhead": "右上举",
    "squat": "下蹲",
}

POINT_NAME_TO_COCO = {
    "head": 0,
    "left_shoulder": 5,
    "right_shoulder": 6,
    "left_elbow": 7,
    "right_elbow": 8,
    "left_wrist": 9,
    "right_wrist": 10,
    "left_hip": 11,
    "right_hip": 12,
    "left_knee": 13,
    "right_knee": 14,
}


@dataclass
class PoseConfig:
    model: Path
    device: str = "0"
    bbox_conf: float = 0.20
    keypoint_conf: float = 0.10
    elbow_rise_pixels: float = 20.0
    elbow_release_pixels: float = 8.0
    elbow_release_frames: int = 2
    elbow_tracker_stale_s: float = 0.5
    elbow_median_frames: int = 3
    elbow_rise_shoulder_ratio: float = 0.50
    elbow_rise_min_pixels: float = 14.0
    elbow_rise_max_pixels: float = 45.0
    wrist_rise_elbow_ratio: float = 0.65
    wrist_max_below_elbow_ratio: float = 0.20
    shoulder_width_confirm_frames: int = 3
    shoulder_width_agreement_ratio: float = 0.25
    shoulder_speed_window_frames: int = 5
    shoulder_speed_threshold_ratio: float = 0.20
    shoulder_min_drop_ratio: float = 0.08
    shoulder_hip_speed_threshold_ratio: float = 0.12
    shoulder_hip_min_drop_ratio: float = 0.05
    shoulder_release_ratio: float = 0.05
    shoulder_symmetry_ratio: float = 0.06
    shoulder_confirm_frames: int = 2
    shoulder_tracker_stale_s: float = 0.8
    shoulder_upward_reanchor_ratio: float = 0.08
    shoulder_upward_reanchor_frames: int = 2
    shoulder_upward_reanchor_hold_s: float = 0.4
    shoulder_squat_recovery_ratio: float = 0.18
    shoulder_squat_release_frames: int = 2
    fpga_point_conf: float = 0.12
    lower_body_point_conf: float = 0.20
    pose_min_shoulder_width_px: float = 8.0
    pose_max_shoulder_width_px: float = 520.0
    pose_min_body_height_px: float = 30.0
    pose_max_center_jump_ratio: float = 0.18
    pose_max_width_change_ratio: float = 1.0
    pose_stable_frames: int = 2
    pose_outlier_confirm_frames: int = 2
    pose_width_median_frames: int = 3
    pose_model_path: Path = ROOT / "models" / "eleven_point_model.npz"
    human_confidence_threshold: float = 0.65
    arm_rule_weight: float = 0.70
    arm_model_weight: float = 0.30
    combined_confidence_threshold: float = 0.55
    model_side_mirrored: bool = True
    arm_model_enabled: bool = False


class PoseEngine:
    def __init__(self, config: PoseConfig):
        self.config = config
        self.model = YOLO(str(config.model))
        self.pose_model_bundle: PoseModelBundle | None = None
        self.pose_model_error = ""
        self._pose_model_coordinates: deque[np.ndarray] = deque()
        self._pose_model_scores: deque[np.ndarray] = deque()
        model_path = Path(config.pose_model_path)
        if not model_path.is_absolute():
            model_path = ROOT / model_path
        try:
            if model_path.is_file():
                self.pose_model_bundle = PoseModelBundle(model_path)
                self._pose_model_coordinates = deque(
                    maxlen=self.pose_model_bundle.window_size
                )
                self._pose_model_scores = deque(
                    maxlen=self.pose_model_bundle.window_size
                )
            else:
                self.pose_model_error = f"model_not_found: {model_path}"
        except Exception as exc:
            self.pose_model_error = f"model_load_failed: {exc}"
        self.elbow_tracker = ElbowRiseTracker(
            rise_pixels=config.elbow_rise_pixels,
            release_pixels=config.elbow_release_pixels,
            stale_seconds=config.elbow_tracker_stale_s,
            median_frames=config.elbow_median_frames,
            release_frames=config.elbow_release_frames,
        )
        self.wrist_tracker = ElbowRiseTracker(
            rise_pixels=config.elbow_rise_pixels,
            release_pixels=config.elbow_release_pixels,
            stale_seconds=config.elbow_tracker_stale_s,
            median_frames=config.elbow_median_frames,
            release_frames=config.elbow_release_frames,
            joint_name="wrist",
        )
        self.shoulder_tracker = ShoulderMotionTracker(
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
        self.shoulder_widths: deque[float] = deque(maxlen=5)
        self.shoulder_width_gate = ShoulderWidthGate(
            confirm_frames=config.shoulder_width_confirm_frames,
            tolerance_ratio=config.shoulder_width_agreement_ratio,
        )
        self._pose_valid_streak = 0
        self._pose_abnormal_streak = 0
        self._last_pose_center_x: float | None = None
        self._last_pose_shoulder_width: float | None = None
        self._pose_width_samples: deque[float] = deque(maxlen=3)
        self._pose_center_samples: deque[float] = deque(maxlen=3)
        self._pose_height_samples: deque[float] = deque(maxlen=3)
        self.profile = load_profile()
        self.image5_config = Config()
        self.image5_config.validate()

    def _update_pose_model(
        self,
        keypoints: np.ndarray,
        keypoint_conf: np.ndarray,
    ) -> dict | None:
        bundle = getattr(self, "pose_model_bundle", None)
        if bundle is None:
            return None
        coordinates = getattr(self, "_pose_model_coordinates", None)
        scores = getattr(self, "_pose_model_scores", None)
        if coordinates is None or scores is None:
            return None
        indices = (0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)
        coordinates.append(
            np.asarray([keypoints[index] for index in indices], dtype=np.float64)
        )
        scores.append(
            np.asarray([keypoint_conf[index] for index in indices], dtype=np.float64)
        )
        if len(coordinates) < bundle.window_size:
            return None
        return bundle.predict(
            np.stack(coordinates),
            np.stack(scores),
        )

    def _pose_model_status(self) -> dict:
        bundle = getattr(self, "pose_model_bundle", None)
        return {
            "model_available": bundle is not None,
            "model_error": getattr(self, "pose_model_error", ""),
            "model_window_size": bundle.window_size if bundle is not None else None,
            "model_window_frames": len(
                getattr(self, "_pose_model_coordinates", ())
            ),
        }

    def _elbow_rise_threshold(self) -> float:
        """Scale the elbow rise threshold by the smoothed shoulder width."""
        ratio = float(self.config.elbow_rise_shoulder_ratio)
        if ratio <= 0.0 or not self.shoulder_widths:
            return float(self.config.elbow_rise_pixels)
        width = median(self.shoulder_widths)
        return float(np.clip(
            width * ratio,
            self.config.elbow_rise_min_pixels,
            self.config.elbow_rise_max_pixels,
        ))

    def _wrist_rise_threshold(self, elbow_threshold_px: float) -> float:
        """Couple wrist confirmation to the current distance-scaled arm threshold."""
        ratio = max(0.0, float(self.config.wrist_rise_elbow_ratio))
        return max(4.0, float(elbow_threshold_px) * ratio)

    def _wrist_offset_limit(self) -> float | None:
        """Limit how far the wrist may lag below the elbow for an attack."""
        ratio = float(self.config.wrist_max_below_elbow_ratio)
        if ratio <= 0.0 or not self.shoulder_widths:
            return None
        return max(8.0, median(self.shoulder_widths) * ratio)

    def _classify_arm(
        self,
        elbow,
        wrist,
        elbow_conf: float,
        wrist_conf: float,
        bbox: np.ndarray,
        body_center_x: float,
        elbow_threshold_px: float,
    ) -> dict:
        side = "left" if elbow[0] < body_center_x else "right"
        result = {
            "valid": False,
            "side": side,
            "rise_px": 0.0,
            "reason": "not_evaluated",
        }
        if elbow_conf < self.config.keypoint_conf:
            result["reason"] = "low_keypoint_confidence"
            return result

        elbow_result = self.elbow_tracker.update(
            side,
            float(elbow[1] - bbox[1]),
            threshold_px=elbow_threshold_px,
        )
        wrist_threshold_px = self._wrist_rise_threshold(elbow_threshold_px)
        if wrist_conf < self.config.keypoint_conf:
            wrist_result = {
                "valid": False,
                "side": side,
                "rise_px": 0.0,
                "rise_threshold_px": round(wrist_threshold_px, 1),
                "reason": "low_wrist_confidence",
            }
        else:
            wrist_result = self.wrist_tracker.update(
                side,
                float(wrist[1] - bbox[1]),
                threshold_px=wrist_threshold_px,
            )

        wrist_below_elbow_px = float(wrist[1] - elbow[1])
        wrist_offset_limit_px = self._wrist_offset_limit()
        result.update(elbow_result)
        result.update({
            "valid": False,
            "elbow_valid": bool(elbow_result.get("valid")),
            "elbow_rise_px": float(elbow_result.get("rise_px", 0.0)),
            "wrist_valid": bool(wrist_result.get("valid")),
            "wrist_rise_px": float(wrist_result.get("rise_px", 0.0)),
            "wrist_rise_threshold_px": round(wrist_threshold_px, 1),
            "wrist_baseline_y_px": wrist_result.get("baseline_y_px"),
            "wrist_filtered_y_px": wrist_result.get("filtered_y_px"),
            "wrist_below_elbow_px": round(wrist_below_elbow_px, 1),
            "wrist_offset_limit_px": (
                round(wrist_offset_limit_px, 1)
                if wrist_offset_limit_px is not None else None
            ),
            "wrist_reason": wrist_result.get("reason"),
        })
        if not result["elbow_valid"]:
            result["reason"] = elbow_result.get("reason", "elbow_not_raised")
        elif not result["wrist_valid"]:
            result["reason"] = wrist_result.get("reason", "wrist_not_raised")
        elif (
            wrist_offset_limit_px is not None
            and wrist_below_elbow_px > wrist_offset_limit_px
        ):
            result["reason"] = "wrist_below_elbow"
        else:
            result.update({"valid": True, "reason": "ok"})
        return result

    def _missing_classification(
        self,
        reason: str,
        bbox_confidence: float = 0.0,
    ) -> dict:
        return {
            "action": "stand",
            "pose_id": 1,
            "reason": reason,
            "cx": 0.5,
            "present": False,
            "bbox_confidence": bbox_confidence,
            "body_action": "stand",
            "attack_action": "stand",
            "attack_suppressed": False,
            "stable_valid": False,
            "validity_reason": reason,
        }

    def _assess_pose_validity(
        self,
        keypoints: np.ndarray,
        keypoint_conf: np.ndarray,
        bbox: np.ndarray,
        width: int,
        height: int,
        score_threshold: float,
    ) -> dict:
        valid_streak = int(getattr(self, "_pose_valid_streak", 0))
        abnormal_streak = int(
            getattr(self, "_pose_abnormal_streak", 0)
        )
        last_center_x = getattr(
            self,
            "_last_pose_center_x",
            None,
        )
        last_shoulder_width = getattr(
            self,
            "_last_pose_shoulder_width",
            None,
        )
        width_samples = getattr(self, "_pose_width_samples", None)
        if width_samples is None:
            width_samples = deque(maxlen=self.config.pose_width_median_frames)
            self._pose_width_samples = width_samples
        center_samples = getattr(self, "_pose_center_samples", None)
        if center_samples is None:
            center_samples = deque(maxlen=self.config.pose_width_median_frames)
            self._pose_center_samples = center_samples
        height_samples = getattr(self, "_pose_height_samples", None)
        if height_samples is None:
            height_samples = deque(maxlen=self.config.pose_width_median_frames)
            self._pose_height_samples = height_samples
        required = (5, 6)
        invalid_points = [
            index
            for index in required
            if float(keypoint_conf[index]) < score_threshold
        ]
        raw_shoulder_width = float(
            np.linalg.norm(keypoints[6] - keypoints[5])
        )
        raw_body_height = float(max(0.0, bbox[3] - bbox[1]))
        raw_center_x = float(np.clip(
            (bbox[0] + bbox[2]) / (2.0 * max(1, width)),
            0.0,
            1.0,
        ))

        abnormal_reason = ""
        if invalid_points:
            abnormal_reason = "low_required_point_score"
        elif (
            raw_shoulder_width < self.config.pose_min_shoulder_width_px
            or raw_shoulder_width > self.config.pose_max_shoulder_width_px
        ):
            abnormal_reason = "implausible_shoulder_width"
        elif raw_body_height < self.config.pose_min_body_height_px:
            abnormal_reason = "implausible_body_height"

        if not abnormal_reason:
            width_samples.append(raw_shoulder_width)
            center_samples.append(raw_center_x)
            height_samples.append(raw_body_height)

        shoulder_width = (
            float(np.median(width_samples))
            if width_samples else raw_shoulder_width
        )
        center_x = (
            float(np.median(center_samples))
            if center_samples else raw_center_x
        )
        body_height = (
            float(np.median(height_samples))
            if height_samples else raw_body_height
        )

        stable_now = not bool(abnormal_reason)
        if last_center_x is not None:
            stable_now = stable_now and (
                abs(center_x - last_center_x)
                <= self.config.pose_max_center_jump_ratio
            )
        if (
            last_shoulder_width is not None
            and last_shoulder_width > 1e-6
        ):
            width_change = abs(
                shoulder_width - last_shoulder_width
            ) / last_shoulder_width
            stable_now = stable_now and (
                width_change <= self.config.pose_max_width_change_ratio
            )

        if stable_now is False and not abnormal_reason:
            abnormal_reason = "pose_position_jump"

        if abnormal_reason:
            abnormal_streak += 1
            valid_streak = 0
            self._pose_abnormal_streak = abnormal_streak
            self._pose_valid_streak = 0
            rejected = (
                abnormal_streak
                >= self.config.pose_outlier_confirm_frames
            )
            return {
                "geometry_valid": not rejected,
                "stable": False,
                "reason": (
                    abnormal_reason
                    if rejected
                    else "pose_outlier_skipped"
                ),
                "underlying_reason": abnormal_reason,
                "invalid_points": invalid_points,
                "score_threshold": score_threshold,
                "stable_frames": 0,
                "abnormal_frames": abnormal_streak,
                "shoulder_width_px": round(shoulder_width, 1),
                "body_height_px": round(body_height, 1),
            }

        self._pose_abnormal_streak = 0
        self._last_pose_center_x = center_x
        self._last_pose_shoulder_width = shoulder_width
        if stable_now:
            valid_streak += 1
        else:
            valid_streak = 1
        self._pose_valid_streak = valid_streak
        stable = (
            valid_streak >= self.config.pose_stable_frames
        )
        return {
            "geometry_valid": True,
            "stable": stable,
            "reason": "pose_stable" if stable else "pose_not_stable",
            "invalid_points": [],
            "score_threshold": score_threshold,
            "stable_frames": valid_streak,
            "abnormal_frames": 0,
            "shoulder_width_px": round(shoulder_width, 1),
            "body_height_px": round(body_height, 1),
            "center_x": round(center_x, 4),
        }

    def _classify_landmarks(
        self,
        keypoints: np.ndarray,
        keypoint_conf: np.ndarray,
        bbox: np.ndarray,
        bbox_confidence: float,
        width: int,
        height: int,
        score_threshold: float | None = None,
        use_pose_model: bool = False,
    ) -> dict:
        body_center_x = float((bbox[0] + bbox[2]) / 2.0)
        threshold = (
            float(self.config.keypoint_conf)
            if score_threshold is None else float(score_threshold)
        )
        validity = self._assess_pose_validity(
            keypoints,
            keypoint_conf,
            bbox,
            width,
            height,
            threshold,
        )
        if not validity["geometry_valid"]:
            result = self._missing_classification(
                str(validity["reason"]),
                bbox_confidence,
            )
            result.update({
                "validity": validity,
                "keypoints_xy": [
                    [round(float(x), 1), round(float(y), 1)]
                    for x, y in keypoints
                ],
                "keypoint_confidence": [
                    round(float(value), 4) for value in keypoint_conf
                ],
            })
            return result
        model_snapshot = None
        model_bundle = getattr(self, "pose_model_bundle", None)
        model_fields = self._pose_model_status() if use_pose_model else {}
        human_gate_failed = False
        if use_pose_model:
            model_snapshot = self._update_pose_model(keypoints, keypoint_conf)
            model_fields["classifier_frames"] = len(
                getattr(self, "_pose_model_coordinates", ())
            )
            model_fields["classifier_window_size"] = (
                model_bundle.window_size
                if model_bundle is not None else None
            )
            if model_snapshot is not None:
                model_fields.update({
                    "human_confidence": model_snapshot["human_confidence"],
                    "raise_confidence": model_snapshot["raise_confidence"],
                    "arm_probabilities": model_snapshot["arm_probabilities"],
                })
            if (
                model_snapshot is not None
                and validity["stable"]
                and model_snapshot["human_confidence"]
                < float(getattr(self.config, "human_confidence_threshold", 0.65))
            ):
                human_gate_failed = True
                model_fields["human_gate_failed"] = True
        if not validity["stable"]:
            return {
                "present": True,
                "stable_valid": False,
                "validity_reason": str(validity["reason"]),
                "validity": validity,
                "cx": float(np.clip(body_center_x / width, 0.0, 1.0)),
                "bbox_confidence": round(bbox_confidence, 4),
                "bbox_xyxy": [
                    round(float(value), 1) for value in bbox
                ],
                "fg_ratio": round(
                    float((bbox[2] - bbox[0]) * (bbox[3] - bbox[1]))
                    / (width * height),
                    4,
                ),
                "arms": {
                    "left": {
                        "valid": False,
                        "side": "left",
                        "rise_px": 0.0,
                        "wrist_valid": False,
                        "wrist_rise_px": 0.0,
                        "filter_ready": False,
                        "reason": "pose_not_stable",
                    },
                    "right": {
                        "valid": False,
                        "side": "right",
                        "rise_px": 0.0,
                        "wrist_valid": False,
                        "wrist_rise_px": 0.0,
                        "filter_ready": False,
                        "reason": "pose_not_stable",
                    },
                },
                "body_action": "stand",
                "attack_action": "stand",
                "attack_suppressed": False,
                "action": "stand",
                "pose_id": 1,
                "reason": str(validity["reason"]),
                "keypoints_xy": [
                    [round(float(x), 1), round(float(y), 1)]
                    for x, y in keypoints
                ],
                "keypoint_confidence": [
                    round(float(value), 4) for value in keypoint_conf
                ],
                "model_gate_passed": (
                    model_bundle is None
                    or (
                        model_snapshot is not None
                        and model_snapshot["human_confidence"]
                        >= float(getattr(self.config, "human_confidence_threshold", 0.65))
                    )
                ),
                "model_gate_reason": (
                    "model_warming_up"
                    if model_bundle is not None and model_snapshot is None
                    else None
                ),
                **model_fields,
            }
        shoulder_confidence = min(float(keypoint_conf[5]), float(keypoint_conf[6]))
        shoulder_width_px: float | None = None
        if shoulder_confidence >= self.config.keypoint_conf:
            shoulder_width_px = float(
                np.linalg.norm(keypoints[6] - keypoints[5])
            )
            accepted_width = self.shoulder_width_gate.update(shoulder_width_px)
            if accepted_width is not None:
                self.shoulder_widths.append(accepted_width)
            hip_confidence = min(
                float(keypoint_conf[11]),
                float(keypoint_conf[12]),
            )
            hips_available = (
                hip_confidence >= self.config.lower_body_point_conf
            )
            shoulder_motion = self.shoulder_tracker.update(
                keypoints[5],
                keypoints[6],
                left_hip=keypoints[11] if hips_available else None,
                right_hip=keypoints[12] if hips_available else None,
                hip_confidence=hip_confidence,
            )
        else:
            shoulder_motion = {
                "action": "stand",
                "candidate": "stand",
                "confirmed": False,
                "reason": "low_shoulder_confidence",
            }
        body_action = shoulder_motion["action"]
        rise_threshold_px = self._elbow_rise_threshold()

        if human_gate_failed and body_action != "squat":
            blocked = self._missing_classification(
                "human_confidence_below_threshold",
                bbox_confidence,
            )
            blocked.update({
                "present": False,
                "stable_valid": True,
                "validity": validity,
                "validity_reason": str(validity["reason"]),
                "action": "stand",
                "attack_action": "stand",
                "attack_suppressed": True,
                "body_action": body_action,
                "shoulder_motion": shoulder_motion,
                "model_gate_passed": False,
                "model_gate_reason": "human_confidence_below_threshold",
                **model_fields,
            })
            return blocked

        if body_action == "squat":
            # Do not carry an arm trigger across a body-motion state.
            self.elbow_tracker.reset()
            self.wrist_tracker.reset()
            left = {
                "valid": False,
                "side": "left",
                "rise_px": 0.0,
                "wrist_valid": False,
                "wrist_rise_px": 0.0,
                "reason": "suppressed_by_body_motion",
            }
            right = {
                "valid": False,
                "side": "right",
                "rise_px": 0.0,
                "wrist_valid": False,
                "wrist_rise_px": 0.0,
                "reason": "suppressed_by_body_motion",
            }
            candidates = []
        else:
            left = self._classify_arm(
                keypoints[7], keypoints[9],
                float(keypoint_conf[7]), float(keypoint_conf[9]),
                bbox, body_center_x, rise_threshold_px,
            )
            right = self._classify_arm(
                keypoints[8], keypoints[10],
                float(keypoint_conf[8]), float(keypoint_conf[10]),
                bbox, body_center_x, rise_threshold_px,
            )
            candidates = [arm for arm in (left, right) if arm["valid"]]
        base = {
            "present": True,
            "stable_valid": True,
            "validity_reason": str(validity["reason"]),
            "validity": validity,
            "cx": float(np.clip((bbox[0] + bbox[2]) / (2.0 * width), 0.0, 1.0)),
            "bbox_confidence": round(bbox_confidence, 4),
            "bbox_xyxy": [round(float(value), 1) for value in bbox],
            "fg_ratio": round(float(((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / (width * height)), 4),
            "arms": {"left": left, "right": right},
            "elbow_rise_threshold_px": round(float(rise_threshold_px), 1),
            "shoulder_width_px": (
                round(shoulder_width_px, 1)
                if shoulder_width_px is not None else None
            ),
            "shoulder_width_stable_px": (
                round(self.shoulder_width_gate.value, 1)
                if self.shoulder_width_gate.value is not None else None
            ),
            "body_action": body_action,
            "shoulder_motion": shoulder_motion,
            "model_gate_passed": (
                model_bundle is None
                or (
                    model_snapshot is not None
                    and model_snapshot["human_confidence"]
                    >= float(getattr(self.config, "human_confidence_threshold", 0.65))
                )
            ),
            "model_gate_reason": (
                "model_warming_up"
                if model_bundle is not None and model_snapshot is None
                else None
            ),
            "arm_model_enabled": bool(
                getattr(self.config, "arm_model_enabled", False)
            ),
            "keypoints_xy": [[round(float(x), 1), round(float(y), 1)] for x, y in keypoints],
            "keypoint_confidence": [round(float(value), 4) for value in keypoint_conf],
            **model_fields,
        }
        if body_action == "squat":
            base.update({
                "action": body_action,
                "attack_action": "stand",
                "attack_suppressed": True,
                "pose_id": 1,
                "reason": f"{body_action}_detected",
            })
            return base
        if not candidates:
            wrist_reasons = {
                left.get("reason"), right.get("reason")
            } & {
                "wrist_not_raised",
                "wrist_below_elbow",
                "low_wrist_confidence",
            }
            reason = sorted(wrist_reasons)[0] if wrist_reasons else "no_raised_elbow"
            base.update({
                "action": "stand",
                "attack_action": "stand",
                "attack_suppressed": False,
                "pose_id": 1,
                "reason": reason,
                "effective_raise_confidence": 0.0,
            })
            return base

        rule_confidences = {
            "left": rule_side_confidence(left),
            "right": rule_side_confidence(right),
        }
        model_probabilities = model_fields.get("arm_probabilities") or {}
        fusion = None
        arm_model_enabled = bool(
            getattr(self.config, "arm_model_enabled", False)
        )
        if (
            arm_model_enabled
            and model_bundle is not None
            and model_snapshot is not None
        ):
            base.update({"arm_rule_confidences": rule_confidences})
            fusion = fuse_arm_decision(
                max(candidates, key=lambda candidate: candidate["rise_px"])["side"],
                rule_confidences,
                model_probabilities,
                float(getattr(self.config, "arm_rule_weight", 0.70)),
                float(getattr(self.config, "arm_model_weight", 0.30)),
                bool(getattr(self.config, "model_side_mirrored", True)),
            )
            base.update({
                "arm_rule_confidences": rule_confidences,
                "model_side": fusion.get("model_side"),
                "rule_side": fusion.get("rule_side"),
                "model_rule_conflict": bool(fusion.get("conflict")),
                "combined_arm_confidence": float(
                    fusion.get("combined_confidence", 0.0)
                ),
                "model_decision_reason": fusion.get("reason"),
            })
        else:
            rule_side = max(
                candidates,
                key=lambda candidate: candidate["rise_px"],
            )["side"]
            base.update({
                "arm_rule_confidences": rule_confidences,
                "model_side": None,
                "rule_side": rule_side,
                "model_rule_conflict": False,
                "combined_arm_confidence": float(
                    rule_confidences[rule_side]
                ),
                "model_decision_reason": "arm_model_disabled",
            })
        arm = max(candidates, key=lambda candidate: candidate["rise_px"])
        action = arm["side"]
        pose_id = 3 if action == "left" else 2
        if fusion is not None:
            action = str(fusion["action"])
            if action == "stand":
                pose_id = 1
            elif (
                float(fusion.get("combined_confidence", 0.0))
                < float(getattr(self.config, "combined_confidence_threshold", 0.55))
            ):
                action = "stand"
                pose_id = 1
                fusion["reason"] = "combined_confidence_below_threshold"
        base.update({
            "action": action,
            "attack_action": action,
            "attack_suppressed": action == "stand",
            "pose_id": pose_id,
            "reason": "ok" if action != "stand" else str(fusion["reason"]),
            "both_elbows_raised": len(candidates) == 2,
            "effective_raise_confidence": (
                float(fusion.get("combined_confidence", 0.0))
                if fusion is not None
                else max(rule_confidences.values())
            ),
        })
        return base

    def classify(self, result) -> dict:
        if result.boxes is None or len(result.boxes) == 0:
            return self._missing_classification("no_person")

        confidences = result.boxes.conf.cpu().numpy()
        person_index = int(np.argmax(confidences))
        bbox_confidence = float(confidences[person_index])
        if bbox_confidence < self.config.bbox_conf:
            return self._missing_classification(
                "low_bbox_confidence",
                bbox_confidence,
            )

        bbox = result.boxes.xyxy[person_index].cpu().numpy()
        keypoints = result.keypoints.xy[person_index].cpu().numpy()
        keypoint_conf = result.keypoints.conf[person_index].cpu().numpy()
        height, width = result.orig_shape
        return self._classify_landmarks(
            keypoints,
            keypoint_conf,
            bbox,
            bbox_confidence,
            int(width),
            int(height),
            self.config.keypoint_conf,
        )

    def classify_points(self, result: dict) -> dict:
        """Classify an FPGA multi-point result using the YOLO action rules."""
        if not result.get("valid") or result.get("fault") or not result.get("model_ready", True):
            reason = (
                "fault"
                if result.get("fault")
                else "model_not_ready"
                if not result.get("model_ready", True)
                else "result_flags_invalid"
            )
            return self._missing_classification(reason)

        source_points = result.get("points") or []
        width = int(result.get("width", 640))
        height = int(result.get("height", 360))
        keypoints = np.zeros((17, 2), dtype=np.float32)
        keypoint_conf = np.zeros((17,), dtype=np.float32)
        available = []
        trusted = []

        for point in source_points:
            if not isinstance(point, dict):
                continue
            coco_index = POINT_NAME_TO_COCO.get(str(point.get("name", "")))
            if coco_index is None:
                continue
            x = float(point.get("x", 0.0))
            y = float(point.get("y", 0.0))
            score = point.get("score")
            confidence = (
                1.0
                if score is None
                else max(0.0, min(1.0, float(score)))
            )
            keypoints[coco_index] = (x, y)
            keypoint_conf[coco_index] = confidence
            available.append((x, y))
            if confidence >= self.config.fpga_point_conf:
                trusted.append((x, y))

        required = (5, 6, 7, 8)
        if not available or any(keypoint_conf[index] <= 0.0 for index in required):
            return self._missing_classification("missing_required_points")

        bbox_points = trusted or available
        xs = [point[0] for point in bbox_points]
        ys = [point[1] for point in bbox_points]
        bbox = np.asarray([
            max(0.0, min(xs) - 8.0),
            max(0.0, min(ys) - 8.0),
            min(float(width), max(xs) + 8.0),
            min(float(height), max(ys) + 8.0),
        ], dtype=np.float32)
        return self._classify_landmarks(
            keypoints,
            keypoint_conf,
            bbox,
            1.0,
            width,
            height,
            self.config.fpga_point_conf,
            use_pose_model=True,
        )

    def reset_motion_tracking(self) -> None:
        self.elbow_tracker.reset()
        self.wrist_tracker.reset()
        self.shoulder_tracker.reset()
        self.shoulder_widths.clear()
        self.shoulder_width_gate.reset()
        self._pose_valid_streak = 0
        self._pose_abnormal_streak = 0
        self._last_pose_center_x = None
        self._last_pose_shoulder_width = None
        self._pose_width_samples.clear()
        self._pose_center_samples.clear()
        self._pose_height_samples.clear()
        coordinates = getattr(self, "_pose_model_coordinates", None)
        scores = getattr(self, "_pose_model_scores", None)
        if coordinates is not None:
            coordinates.clear()
        if scores is not None:
            scores.clear()

    def process_edge(self, edge: np.ndarray, output_dir: Path | None = None) -> dict:
        """Run pose inference on an edge image already produced by the FPGA."""
        edge = np.asarray(edge)
        if edge.ndim == 3:
            edge = cv2.cvtColor(edge, cv2.COLOR_BGR2GRAY)
        if edge.ndim != 2:
            raise ValueError(f"edge image must be 2D, got shape={edge.shape}")
        if edge.dtype != np.uint8:
            edge = np.clip(edge, 0, 255).astype(np.uint8)
        edge = np.ascontiguousarray(edge)

        if output_dir is not None:
            output_dir = Path(output_dir)
            output_dir.mkdir(parents=True, exist_ok=True)

        edge_rgb = np.repeat(edge[..., None], 3, axis=2)
        result = self.model.predict(
            source=edge_rgb,
            conf=self.config.bbox_conf,
            device=self.config.device,
            verbose=False,
        )[0]
        classification = self.classify(result)

        if output_dir is not None:
            cv2.imwrite(str(output_dir / "current_edge.png"), edge)
            pose_image = result.plot()
            cv2.imwrite(
                str(output_dir / "current_pose.jpg"),
                pose_image,
                [cv2.IMWRITE_JPEG_QUALITY, 94],
            )
        classification.update({
            "ok": True,
            "action_name": ACTION_NAMES[classification["action"]],
            "body_action_name": ACTION_NAMES[classification["body_action"]],
            "width": int(edge.shape[1]),
            "height": int(edge.shape[0]),
        })
        return classification

    def process(self, image_path: Path, output_dir: Path) -> dict:
        output_dir.mkdir(parents=True, exist_ok=True)
        with Image.open(image_path) as opened:
            rgb_image = opened.convert("RGB")
            rgb = np.array(rgb_image)

        stages = convert(rgb, self.image5_config, self.profile["gamma_lut"])
        edge = stages["edges"]
        classification = self.process_edge(edge, output_dir)
        cv2.imwrite(str(output_dir / "current_input.jpg"),
                    cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR),
                    [cv2.IMWRITE_JPEG_QUALITY, 92])
        classification["image"] = image_path.name
        return classification
