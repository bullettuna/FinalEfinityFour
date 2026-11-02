"""Detect symmetric downward shoulder movement for the squat state."""
from __future__ import annotations

import time
from dataclasses import dataclass, field


@dataclass
class _ShoulderState:
    baseline_left_y: float | None = None
    baseline_right_y: float | None = None
    baseline_left_hip_y: float | None = None
    baseline_right_hip_y: float | None = None
    last_seen: float = 0.0
    action: str = "stand"
    candidate: str = "stand"
    candidate_frames: int = 0
    neutral_candidate_frames: int = 0
    neutral_candidate_started_at: float = 0.0
    neutral_stable_frames: int = 0
    neutral_reanchor_pending: bool = False
    squat_floor_y: float | None = None
    recovery_candidate_frames: int = 0
    samples: list[tuple[float, float, float, float]] = field(default_factory=list)
    hip_samples: list[tuple[float, float, float]] = field(
        default_factory=list
    )


class ShoulderWidthGate:
    """Only adopt a shoulder width that stays consistent for several frames.

    Keypoints on edge images occasionally jump, producing widths of a few
    pixels or hundreds of pixels. A candidate width replaces the current value
    only after ``confirm_frames`` consecutive frames agree with it (relative
    tolerance ``tolerance_ratio``); single-frame outliers are ignored.
    """

    def __init__(self, confirm_frames: int = 3,
                 tolerance_ratio: float = 0.25) -> None:
        self.confirm_frames = max(1, int(confirm_frames))
        self.tolerance_ratio = max(0.01, float(tolerance_ratio))
        self.value: float | None = None
        self._candidate: float | None = None
        self._candidate_frames = 0

    def reset(self) -> None:
        self.value = None
        self._candidate = None
        self._candidate_frames = 0

    def _agrees(self, first: float, second: float) -> bool:
        larger = max(abs(first), abs(second))
        if larger <= 1e-9:
            return True
        return abs(first - second) <= larger * self.tolerance_ratio

    def update(self, width: float) -> float | None:
        """Return the accepted width, or None while a new value is unconfirmed."""
        value = float(width)
        if self.value is not None and self._agrees(value, self.value):
            self.value = value
            self._candidate = None
            self._candidate_frames = 0
            return self.value
        if self._candidate is not None and self._agrees(value, self._candidate):
            self._candidate_frames += 1
            self._candidate = (
                self._candidate * (self._candidate_frames - 1) + value
            ) / self._candidate_frames
        else:
            self._candidate = value
            self._candidate_frames = 1
        if self._candidate_frames >= self.confirm_frames:
            self.value = self._candidate
            self._candidate = None
            self._candidate_frames = 0
            return self.value
        return None


class ShoulderMotionTracker:
    """Classify a symmetric squat while rejecting asymmetric shoulder motion."""

    def __init__(
        self,
        speed_window_frames: int = 5,
        speed_threshold_ratio: float = 0.20,
        min_drop_ratio: float = 0.08,
        hip_speed_threshold_ratio: float = 0.12,
        hip_min_drop_ratio: float = 0.05,
        release_ratio: float = 0.05,
        symmetry_ratio: float = 0.06,
        confirm_frames: int = 1,
        stale_seconds: float = 0.8,
        baseline_alpha: float = 0.04,
        upward_reanchor_ratio: float = 0.08,
        upward_reanchor_frames: int = 2,
        upward_reanchor_hold_seconds: float = 0.4,
        squat_recovery_ratio: float = 0.18,
        squat_release_frames: int = 2,
    ) -> None:
        self.speed_window_frames = max(3, int(speed_window_frames))
        self.speed_threshold_ratio = max(0.01, float(speed_threshold_ratio))
        self.min_drop_ratio = max(0.01, float(min_drop_ratio))
        self.hip_speed_threshold_ratio = max(
            0.01,
            float(hip_speed_threshold_ratio),
        )
        self.hip_min_drop_ratio = max(0.01, float(hip_min_drop_ratio))
        self.release_ratio = max(
            0.005,
            min(float(release_ratio), self.min_drop_ratio * 0.8),
        )
        self.symmetry_ratio = max(0.01, float(symmetry_ratio))
        self.confirm_frames = max(1, int(confirm_frames))
        self.stale_seconds = max(0.1, float(stale_seconds))
        self.baseline_alpha = max(0.0, min(0.2, float(baseline_alpha)))
        self.upward_reanchor_ratio = max(
            0.01,
            float(upward_reanchor_ratio),
        )
        self.upward_reanchor_frames = max(
            1,
            int(upward_reanchor_frames),
        )
        self.upward_reanchor_hold_seconds = max(
            0.1,
            float(upward_reanchor_hold_seconds),
        )
        self.squat_recovery_ratio = max(
            self.release_ratio,
            min(1.0, float(squat_recovery_ratio)),
        )
        self.squat_release_frames = max(1, int(squat_release_frames))
        self.state = _ShoulderState()

    def reset(self) -> None:
        self.state = _ShoulderState()

    def _reset_baseline(
        self,
        left_shoulder: tuple[float, float],
        right_shoulder: tuple[float, float],
        timestamp: float,
        left_hip: tuple[float, float] | None = None,
        right_hip: tuple[float, float] | None = None,
    ) -> None:
        self.state.baseline_left_y = float(left_shoulder[1])
        self.state.baseline_right_y = float(right_shoulder[1])
        self.state.baseline_left_hip_y = (
            float(left_hip[1]) if left_hip is not None else None
        )
        self.state.baseline_right_hip_y = (
            float(right_hip[1]) if right_hip is not None else None
        )
        self.state.last_seen = timestamp
        self.state.action = "stand"
        self.state.candidate = "stand"
        self.state.candidate_frames = 0
        self.state.neutral_candidate_frames = 0
        self.state.neutral_candidate_started_at = 0.0
        self.state.neutral_stable_frames = 0
        self.state.neutral_reanchor_pending = False
        self.state.squat_floor_y = None
        self.state.recovery_candidate_frames = 0
        self.state.samples.clear()
        self.state.hip_samples.clear()

    @staticmethod
    def _slope_per_second(
        timestamps: list[float],
        values: list[float],
    ) -> float:
        if len(timestamps) < 2:
            return 0.0
        mean_t = sum(timestamps) / len(timestamps)
        mean_v = sum(values) / len(values)
        denominator = sum((value - mean_t) ** 2 for value in timestamps)
        if denominator <= 1e-9:
            return 0.0
        numerator = sum(
            (timestamp - mean_t) * (value - mean_v)
            for timestamp, value in zip(timestamps, values)
        )
        return numerator / denominator

    def update(
        self,
        left_shoulder: tuple[float, float],
        right_shoulder: tuple[float, float],
        now: float | None = None,
        left_hip: tuple[float, float] | None = None,
        right_hip: tuple[float, float] | None = None,
        hip_confidence: float | None = None,
    ) -> dict:
        timestamp = time.monotonic() if now is None else float(now)
        hips_available = left_hip is not None and right_hip is not None
        if (
            self.state.baseline_left_y is None
            or self.state.baseline_right_y is None
            or timestamp - self.state.last_seen > self.stale_seconds
        ):
            self._reset_baseline(
                left_shoulder,
                right_shoulder,
                timestamp,
                left_hip,
                right_hip,
            )
        elif hips_available and (
            self.state.baseline_left_hip_y is None
            or self.state.baseline_right_hip_y is None
        ):
            self.state.baseline_left_hip_y = float(left_hip[1])
            self.state.baseline_right_hip_y = float(right_hip[1])
            self.state.hip_samples.clear()

        self.state.last_seen = timestamp
        current_shoulder_width = max(
            1.0,
            abs(float(right_shoulder[0]) - float(left_shoulder[0])),
        )
        self.state.samples.append((
            timestamp,
            float(left_shoulder[1]),
            float(right_shoulder[1]),
            current_shoulder_width,
        ))
        self.state.samples = self.state.samples[-self.speed_window_frames:]
        if hips_available:
            self.state.hip_samples.append((
                timestamp,
                float(left_hip[1]),
                float(right_hip[1]),
            ))
            self.state.hip_samples = (
                self.state.hip_samples[-self.speed_window_frames:]
            )
        else:
            self.state.hip_samples.clear()
            self.state.baseline_left_hip_y = None
            self.state.baseline_right_hip_y = None

        speed_ready = len(self.state.samples) >= self.speed_window_frames
        left_speed = 0.0
        right_speed = 0.0
        speed_window_s = 0.0
        if speed_ready:
            timestamps = [sample[0] for sample in self.state.samples]
            left_values = [sample[1] for sample in self.state.samples]
            right_values = [sample[2] for sample in self.state.samples]
            speed_window_s = timestamps[-1] - timestamps[0]
            if speed_window_s > 1e-6:
                left_speed = self._slope_per_second(timestamps, left_values)
                right_speed = self._slope_per_second(timestamps, right_values)
            else:
                speed_ready = False

        hip_speed_ready = (
            len(self.state.hip_samples) >= self.speed_window_frames
        )
        left_hip_speed = 0.0
        right_hip_speed = 0.0
        if hip_speed_ready:
            hip_timestamps = [
                sample[0] for sample in self.state.hip_samples
            ]
            left_hip_values = [
                sample[1] for sample in self.state.hip_samples
            ]
            right_hip_values = [
                sample[2] for sample in self.state.hip_samples
            ]
            hip_window_s = hip_timestamps[-1] - hip_timestamps[0]
            if hip_window_s > 1e-6:
                left_hip_speed = self._slope_per_second(
                    hip_timestamps,
                    left_hip_values,
                )
                right_hip_speed = self._slope_per_second(
                    hip_timestamps,
                    right_hip_values,
                )
            else:
                hip_speed_ready = False

        shoulder_width = max(
            1.0,
            sum(sample[3] for sample in self.state.samples)
            / len(self.state.samples),
        )
        left_shift = float(left_shoulder[1]) - float(self.state.baseline_left_y)
        right_shift = float(right_shoulder[1]) - float(self.state.baseline_right_y)
        mean_shift = (left_shift + right_shift) / 2.0
        symmetry_error = abs(left_shift - right_shift)
        left_speed_ratio = left_speed / shoulder_width
        right_speed_ratio = right_speed / shoulder_width
        mean_speed_ratio = (left_speed_ratio + right_speed_ratio) / 2.0
        speed_symmetry_error = abs(left_speed_ratio - right_speed_ratio)
        left_hip_speed_ratio = left_hip_speed / shoulder_width
        right_hip_speed_ratio = right_hip_speed / shoulder_width
        mean_hip_speed_ratio = (
            left_hip_speed_ratio + right_hip_speed_ratio
        ) / 2.0
        hip_speed_symmetry_error = abs(
            left_hip_speed_ratio - right_hip_speed_ratio
        )
        left_hip_shift = 0.0
        right_hip_shift = 0.0
        if (
            hips_available
            and self.state.baseline_left_hip_y is not None
            and self.state.baseline_right_hip_y is not None
        ):
            left_hip_shift = (
                float(left_hip[1]) - self.state.baseline_left_hip_y
            )
            right_hip_shift = (
                float(right_hip[1]) - self.state.baseline_right_hip_y
            )
        mean_hip_shift = (left_hip_shift + right_hip_shift) / 2.0
        hip_position_symmetry_error = abs(
            left_hip_shift - right_hip_shift
        )
        min_drop_px = shoulder_width * self.min_drop_ratio
        hip_min_drop_px = shoulder_width * self.hip_min_drop_ratio
        release_px = shoulder_width * self.release_ratio
        symmetry_px = shoulder_width * self.symmetry_ratio
        upward_reanchor_px = shoulder_width * self.upward_reanchor_ratio
        current_shoulder_y = (
            float(left_shoulder[1]) + float(right_shoulder[1])
        ) / 2.0
        recovery_px = shoulder_width * self.squat_recovery_ratio
        neutral_speed_limit = max(
            0.02,
            self.speed_threshold_ratio * 0.35,
        )

        candidate = "stand"
        shoulder_candidate = (
            speed_ready
            and left_speed_ratio >= self.speed_threshold_ratio
            and right_speed_ratio >= self.speed_threshold_ratio
            and speed_symmetry_error <= self.symmetry_ratio
            and mean_shift >= min_drop_px
            and symmetry_error <= symmetry_px
        )
        lower_body_confirmed = (
            hips_available
            and hip_speed_ready
            and left_hip_speed_ratio >= self.hip_speed_threshold_ratio
            and right_hip_speed_ratio >= self.hip_speed_threshold_ratio
            and hip_speed_symmetry_error <= self.symmetry_ratio
            and mean_hip_shift >= hip_min_drop_px
            and hip_position_symmetry_error <= symmetry_px
        )
        if shoulder_candidate and lower_body_confirmed:
            candidate = "squat"

        if self.state.action == "squat":
            if self.state.squat_floor_y is None:
                self.state.squat_floor_y = current_shoulder_y
            else:
                self.state.squat_floor_y = max(
                    self.state.squat_floor_y,
                    current_shoulder_y,
                )
            recovered_px = self.state.squat_floor_y - current_shoulder_y
            if candidate != "squat" and recovered_px >= recovery_px:
                self.state.recovery_candidate_frames += 1
            else:
                self.state.recovery_candidate_frames = 0
        else:
            self.state.recovery_candidate_frames = 0

        released = False
        release_reason = ""
        if self.state.action == "squat" and mean_shift < release_px:
            released = True
            release_reason = "near_baseline"
        elif (
            self.state.action == "squat"
            and self.state.recovery_candidate_frames
            >= self.squat_release_frames
        ):
            released = True
            release_reason = "recovered_from_squat_floor"

        if released:
            self.state.action = "stand"
            self.state.candidate = "stand"
            self.state.candidate_frames = 0
            self.state.squat_floor_y = None
            self.state.recovery_candidate_frames = 0
            candidate = "stand"
            baseline_mean_y = (
                float(self.state.baseline_left_y)
                + float(self.state.baseline_right_y)
            ) / 2.0
            # A jump can recover enough to release the squat while the body is
            # above the original neutral height. Do not adopt that transient
            # peak as the new baseline; wait for the body to settle first.
            self.state.neutral_reanchor_pending = (
                current_shoulder_y < baseline_mean_y - release_px
            )

        neutral_reanchor_needed = (
            self.state.action == "stand"
            and (
                self.state.neutral_reanchor_pending
                or abs(mean_shift) >= upward_reanchor_px
            )
        )
        neutral_is_stable = (
            speed_ready
            and abs(mean_speed_ratio) <= neutral_speed_limit
        )
        if neutral_reanchor_needed and neutral_is_stable:
            if self.state.neutral_candidate_started_at <= 0.0:
                self.state.neutral_candidate_started_at = timestamp
            self.state.neutral_candidate_frames += 1
            self.state.neutral_stable_frames += 1
        else:
            self.state.neutral_candidate_started_at = 0.0
            self.state.neutral_candidate_frames = 0
            self.state.neutral_stable_frames = 0

        if (
            self.state.neutral_candidate_started_at > 0.0
            and self.state.neutral_candidate_frames
            >= self.upward_reanchor_frames
            and self.state.neutral_stable_frames
            >= self.upward_reanchor_frames
            and timestamp - self.state.neutral_candidate_started_at
            >= self.upward_reanchor_hold_seconds
        ):
            self._reset_baseline(
                left_shoulder,
                right_shoulder,
                timestamp,
                left_hip,
                right_hip,
            )
            self.state.samples.append((
                timestamp,
                float(left_shoulder[1]),
                float(right_shoulder[1]),
                current_shoulder_width,
            ))
            return {
                "action": "stand",
                "candidate": "stand",
                "candidate_frames": 0,
                "confirmed": False,
                "released": released,
                "release_reason": release_reason,
                "reanchored": True,
                "speed_ready": False,
                "speed_window_frames": self.speed_window_frames,
                "speed_window_s": 0.0,
                "left_speed_px_s": 0.0,
                "right_speed_px_s": 0.0,
                "left_speed_ratio_s": 0.0,
                "right_speed_ratio_s": 0.0,
                "mean_speed_ratio_s": 0.0,
                "speed_symmetry_error": 0.0,
                "left_shift_px": 0.0,
                "right_shift_px": 0.0,
                "mean_shift_px": 0.0,
                "left_hip_shift_px": 0.0,
                "right_hip_shift_px": 0.0,
                "mean_hip_shift_px": 0.0,
                "hip_drop_ratio": 0.0,
                "hip_min_drop_px": round(hip_min_drop_px, 1),
                "hip_speed_ready": False,
                "mean_hip_speed_ratio_s": 0.0,
                "hip_speed_symmetry_error": 0.0,
                "hip_position_symmetry_error_px": 0.0,
                "hips_available": bool(hips_available),
                "hip_confidence": (
                    round(float(hip_confidence), 4)
                    if hip_confidence is not None else None
                ),
                "shoulder_candidate": False,
                "lower_body_confirmed": False,
                "shoulder_width_px": round(shoulder_width, 1),
                "min_drop_px": round(min_drop_px, 1),
                "drop_ratio": 0.0,
                "release_px": round(release_px, 1),
                "squat_recovery_px": round(recovery_px, 1),
                "symmetry_error_px": 0.0,
                "upward_candidate_frames": (
                    self.state.neutral_candidate_frames
                ),
                "recovery_candidate_frames": 0,
                "reason": "neutral_baseline_reanchored",
            }

        if self.state.action == "stand":
            if self.state.neutral_reanchor_pending:
                candidate = "stand"
            if candidate == "stand":
                self.state.candidate = "stand"
                self.state.candidate_frames = 0
                if abs(mean_shift) <= min_drop_px * 0.5:
                    self.state.baseline_left_y += (
                        float(left_shoulder[1]) - self.state.baseline_left_y
                    ) * self.baseline_alpha
                    self.state.baseline_right_y += (
                        float(right_shoulder[1]) - self.state.baseline_right_y
                    ) * self.baseline_alpha
                    if (
                        hips_available
                        and abs(mean_hip_shift) <= hip_min_drop_px * 0.5
                        and self.state.baseline_left_hip_y is not None
                        and self.state.baseline_right_hip_y is not None
                    ):
                        self.state.baseline_left_hip_y += (
                            float(left_hip[1])
                            - self.state.baseline_left_hip_y
                        ) * self.baseline_alpha
                        self.state.baseline_right_hip_y += (
                            float(right_hip[1])
                            - self.state.baseline_right_hip_y
                        ) * self.baseline_alpha
            else:
                if candidate == self.state.candidate:
                    self.state.candidate_frames += 1
                else:
                    self.state.candidate = candidate
                    self.state.candidate_frames = 1
                if self.state.candidate_frames >= self.confirm_frames:
                    self.state.action = candidate
                    self.state.candidate_frames = 0
                    self.state.squat_floor_y = current_shoulder_y
                    self.state.recovery_candidate_frames = 0
        elif candidate != "stand":
            self.state.candidate = candidate
            self.state.candidate_frames = 0

        return {
            "action": self.state.action,
            "candidate": candidate,
            "candidate_frames": self.state.candidate_frames,
            "upward_candidate_frames": self.state.neutral_candidate_frames,
            "recovery_candidate_frames": (
                self.state.recovery_candidate_frames
            ),
            "confirmed": self.state.action == "squat",
            "released": released,
            "release_reason": release_reason,
            "reanchored": False,
            "speed_ready": speed_ready,
            "speed_window_frames": self.speed_window_frames,
            "speed_window_s": round(speed_window_s, 3),
            "left_speed_px_s": round(left_speed, 1),
            "right_speed_px_s": round(right_speed, 1),
            "left_speed_ratio_s": round(left_speed_ratio, 3),
            "right_speed_ratio_s": round(right_speed_ratio, 3),
            "mean_speed_ratio_s": round(mean_speed_ratio, 3),
            "speed_symmetry_error": round(speed_symmetry_error, 3),
            "left_shift_px": round(left_shift, 1),
            "right_shift_px": round(right_shift, 1),
            "mean_shift_px": round(mean_shift, 1),
            "left_hip_shift_px": round(left_hip_shift, 1),
            "right_hip_shift_px": round(right_hip_shift, 1),
            "mean_hip_shift_px": round(mean_hip_shift, 1),
            "hip_drop_ratio": round(mean_hip_shift / shoulder_width, 3),
            "hip_min_drop_px": round(hip_min_drop_px, 1),
            "hip_speed_ready": hip_speed_ready,
            "left_hip_speed_ratio_s": round(left_hip_speed_ratio, 3),
            "right_hip_speed_ratio_s": round(right_hip_speed_ratio, 3),
            "mean_hip_speed_ratio_s": round(mean_hip_speed_ratio, 3),
            "hip_speed_symmetry_error": round(
                hip_speed_symmetry_error, 3
            ),
            "hip_position_symmetry_error_px": round(
                hip_position_symmetry_error, 1
            ),
            "hips_available": bool(hips_available),
            "hip_confidence": (
                round(float(hip_confidence), 4)
                if hip_confidence is not None else None
            ),
            "shoulder_candidate": bool(shoulder_candidate),
            "lower_body_confirmed": bool(lower_body_confirmed),
            "shoulder_width_px": round(shoulder_width, 1),
            "min_drop_px": round(min_drop_px, 1),
            "drop_ratio": round(mean_shift / shoulder_width, 3),
            "release_px": round(release_px, 1),
            "squat_recovery_px": round(recovery_px, 1),
            "symmetry_error_px": round(symmetry_error, 1),
            "reason": (
                "ok"
                if self.state.action == "squat"
                else (
                    "lower_body_unavailable"
                    if shoulder_candidate and not hips_available
                    else "hip_motion_below_threshold"
                    if shoulder_candidate
                    else "squat_speed_or_displacement_below_threshold"
                    if speed_ready
                    else "waiting_speed_window"
                )
            ),
        }
