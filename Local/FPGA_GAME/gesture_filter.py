"""Turn noisy per-frame pose classifications into discrete game actions."""
from __future__ import annotations

import time
from collections import deque


ACTIONS = {
    "stand",
    "left",
    "right",
    "left_overhead",
    "right_overhead",
}


class GestureFilter:
    """Confirm a gesture, then trigger it again after a fixed cooldown."""

    def __init__(
        self,
        confirm_frames: int = 2,
        cooldown_s: float = 1.0,
        window_frames: int | None = None,
        min_votes: int | None = None,
    ) -> None:
        self.confirm_frames = max(1, int(confirm_frames))
        self.window_frames = max(
            self.confirm_frames,
            int(window_frames if window_frames is not None else self.confirm_frames),
        )
        requested_votes = (
            self.confirm_frames if min_votes is None else int(min_votes)
        )
        self.min_votes = min(self.window_frames, max(1, requested_votes))
        self.cooldown_s = max(0.0, float(cooldown_s))
        self.candidate = "stand"
        self.candidate_frames = 0
        self.history: deque[str | None] = deque(maxlen=self.window_frames)
        self.last_trigger_at: float | None = None

    def reset_candidate(self) -> None:
        self.candidate = "stand"
        self.candidate_frames = 0
        self.history.clear()

    def age(self) -> bool:
        """Advance the voting window without casting a vote.

        Used on frames where the person is not detected: existing votes still
        expire after ``window_frames`` frames, but the gap neither votes stand
        nor clears accumulated votes early.
        """
        self.history.append(None)
        self.candidate = "stand"
        self.candidate_frames = 0
        return False

    def update(self, action: str, now: float | None = None) -> bool:
        if action not in ACTIONS:
            action = "stand"
        self.history.append(action)
        self.candidate = action
        self.candidate_frames = self.history.count(action)

        if action == "stand" or self.candidate_frames < self.min_votes:
            return False

        timestamp = time.monotonic() if now is None else float(now)
        if (
            self.last_trigger_at is None
            or timestamp - self.last_trigger_at >= self.cooldown_s
        ):
            self.last_trigger_at = timestamp
            return True
        return False

    def snapshot(self, now: float | None = None) -> dict:
        timestamp = time.monotonic() if now is None else float(now)
        cooldown_remaining_s = 0.0
        if self.last_trigger_at is not None:
            cooldown_remaining_s = max(
                0.0,
                self.cooldown_s - (timestamp - self.last_trigger_at),
            )
        return {
            "candidate": self.candidate,
            "candidate_frames": self.candidate_frames,
            "min_votes": self.min_votes,
            "window_frames": self.window_frames,
            "history": list(self.history),
            "cooldown_s": self.cooldown_s,
            "cooldown_remaining_ms": round(cooldown_remaining_s * 1000.0),
        }


class PostSquatAttackGate:
    """Gate attacks right after a squat ends until the arms settle.

    Standing up tends to produce noisy raised-elbow classifications. This gate
    suppresses attacks for a short fixed window after the squat state ends, and
    additionally requires a run of neutral (stand) frames before attack voting
    is allowed again.
    """

    def __init__(
        self,
        suppress_s: float = 0.3,
        neutral_frames: int = 3,
        squat_confirm_frames: int = 2,
        max_gate_s: float = 1.0,
    ) -> None:
        self.suppress_s = max(0.0, float(suppress_s))
        self.neutral_frames = max(0, int(neutral_frames))
        self.squat_confirm_frames = max(1, int(squat_confirm_frames))
        self.max_gate_s = max(self.suppress_s, float(max_gate_s))
        self._squatting = False
        self._rearmed = True
        self._suppress_until = 0.0
        self._neutral_count = 0
        self._squat_streak = 0
        self._gate_started_at = 0.0
        self._recovery_required = False

    def reset(self) -> None:
        self._squatting = False
        self._rearmed = True
        self._suppress_until = 0.0
        self._neutral_count = 0
        self._squat_streak = 0
        self._gate_started_at = 0.0
        self._recovery_required = False

    def invalidate(self) -> None:
        """Cancel a gate that was derived from missing or invalid pose data."""
        self.reset()

    def update(self, body_action: str, attack_action: str,
               now: float | None = None) -> bool:
        """Return True while new attacks must stay gated."""
        timestamp = time.monotonic() if now is None else float(now)
        if body_action == "squat":
            self._squat_streak += 1
            if self._squat_streak >= self.squat_confirm_frames:
                if not self._squatting:
                    self._gate_started_at = timestamp
                self._squatting = True
                self._rearmed = False
                self._neutral_count = 0
            return False
        self._squat_streak = 0
        if self._squatting:
            self._squatting = False
            self._suppress_until = timestamp + self.suppress_s
            self._gate_started_at = timestamp
            self._neutral_count = 0
        if self._rearmed:
            return False
        if timestamp - self._gate_started_at >= self.max_gate_s:
            self._recovery_required = True
            self._neutral_count = 0
            return True
        if timestamp < self._suppress_until:
            return True
        if attack_action == "stand":
            self._neutral_count += 1
            if self._neutral_count >= self.neutral_frames:
                self._rearmed = True
                return False
            return True
        # Any elbow rise before the neutral run completes restarts it.
        self._neutral_count = 0
        return True

    def snapshot(self, now: float | None = None) -> dict:
        timestamp = time.monotonic() if now is None else float(now)
        return {
            "squatting": self._squatting,
            "rearmed": self._rearmed,
            "neutral_count": self._neutral_count,
            "neutral_frames_required": self.neutral_frames,
            "squat_streak": self._squat_streak,
            "squat_confirm_frames": self.squat_confirm_frames,
            "max_gate_s": self.max_gate_s,
            "max_gate_remaining_ms": round(
                max(
                    0.0,
                    self.max_gate_s - (timestamp - self._gate_started_at),
                )
                * 1000.0
            ) if self._gate_started_at else 0,
            "recovery_required": self._recovery_required,
            "suppress_remaining_ms": round(
                max(0.0, self._suppress_until - timestamp) * 1000.0
            ),
        }
