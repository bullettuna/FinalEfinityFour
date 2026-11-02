"""Track body-relative joint movement without relying on shoulder keypoints."""
from __future__ import annotations

import time
from dataclasses import dataclass
from statistics import median


@dataclass
class _ElbowState:
    baseline_y: float | None = None
    peak_y: float | None = None
    raised: bool = False
    last_seen: float = 0.0
    samples: list[float] | None = None
    release_candidate_frames: int = 0

    def add_sample(self, value: float, window_frames: int) -> None:
        if self.samples is None:
            self.samples = []
        self.samples.append(float(value))
        self.samples = self.samples[-window_frames:]


class ElbowRiseTracker:
    """Detect one joint moving up from its resting body-relative position."""

    def __init__(
        self,
        rise_pixels: float = 20.0,
        release_pixels: float = 8.0,
        stale_seconds: float = 0.5,
        median_frames: int = 3,
        release_frames: int = 2,
        joint_name: str = "elbow",
    ) -> None:
        self.rise_pixels = max(1.0, float(rise_pixels))
        self.release_pixels = max(0.0, min(float(release_pixels), self.rise_pixels))
        self.stale_seconds = max(0.1, float(stale_seconds))
        self.median_frames = max(1, int(median_frames))
        self.release_frames = max(1, int(release_frames))
        self.joint_name = str(joint_name)
        self.states = {"left": _ElbowState(), "right": _ElbowState()}

    def reset(self) -> None:
        self.states = {"left": _ElbowState(), "right": _ElbowState()}

    def update(self, side: str, relative_y: float, threshold_px: float | None = None,
               now: float | None = None) -> dict:
        if side not in self.states:
            raise ValueError(f"unknown elbow side: {side}")
        timestamp = time.monotonic() if now is None else float(now)
        rise_threshold = (
            self.rise_pixels
            if threshold_px is None
            else max(1.0, float(threshold_px))
        )
        release_threshold = min(
            self.release_pixels * rise_threshold / self.rise_pixels,
            rise_threshold,
        )
        state = self.states[side]
        if state.baseline_y is None or timestamp - state.last_seen > self.stale_seconds:
            state.baseline_y = float(relative_y)
            state.peak_y = None
            state.raised = False
            state.samples = []
            state.release_candidate_frames = 0
        state.last_seen = timestamp
        state.add_sample(float(relative_y), self.median_frames)
        filter_ready = len(state.samples or []) >= self.median_frames
        filtered_y = median(state.samples or [float(relative_y)])

        if state.raised:
            rise_pixels = state.baseline_y - filtered_y
            state.peak_y = min(filtered_y, state.peak_y or filtered_y)
            if filtered_y - state.peak_y >= release_threshold:
                state.release_candidate_frames += 1
                if state.release_candidate_frames >= self.release_frames:
                    state.raised = False
                    state.baseline_y = filtered_y
                    state.peak_y = None
                    state.release_candidate_frames = 0
                    rise_pixels = 0.0
            else:
                state.release_candidate_frames = 0
        else:
            state.release_candidate_frames = 0
            if filtered_y >= state.baseline_y:
                state.baseline_y = filtered_y
            rise_pixels = state.baseline_y - filtered_y
            if filter_ready and rise_pixels >= rise_threshold:
                state.raised = True
                state.peak_y = filtered_y

        return {
            "valid": state.raised,
            "side": side,
            "relative_y_px": round(float(relative_y), 1),
            "filtered_y_px": round(float(filtered_y), 1),
            "median_window_frames": self.median_frames,
            "filter_ready": filter_ready,
            "release_candidate_frames": state.release_candidate_frames,
            "release_confirm_frames": self.release_frames,
            "baseline_y_px": round(float(state.baseline_y), 1),
            "peak_y_px": (
                round(float(state.peak_y), 1) if state.peak_y is not None else None
            ),
            "rise_px": round(float(rise_pixels), 1),
            "rise_threshold_px": round(float(rise_threshold), 1),
            "reason": (
                "ok" if state.raised
                else f"{self.joint_name}_not_raised"
            ),
        }
