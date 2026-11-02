from __future__ import annotations

import unittest

from shoulder_tracker import ShoulderMotionTracker, ShoulderWidthGate


class ShoulderMotionTrackerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tracker = ShoulderMotionTracker(
            speed_window_frames=5,
            speed_threshold_ratio=0.20,
            min_drop_ratio=0.08,
            release_ratio=0.05,
            symmetry_ratio=0.06,
            confirm_frames=1,
            stale_seconds=0.8,
            upward_reanchor_ratio=0.08,
            upward_reanchor_frames=2,
        )

    @staticmethod
    def _shoulders(left_y: float, right_y: float | None = None) -> tuple:
        if right_y is None:
            right_y = left_y
        return (100.0, left_y), (200.0, right_y)

    def _feed(
        self,
        values: list[float],
        hip_values: list[float] | None = None,
        start: float = 0.0,
        step: float = 0.055,
    ) -> list[dict]:
        results = []
        hips = hip_values or [value + 120.0 for value in values]
        for index, value in enumerate(values):
            left, right = self._shoulders(value)
            left_hip, right_hip = self._shoulders(hips[index])
            results.append(
                self.tracker.update(
                    left,
                    right,
                    now=start + index * step,
                    left_hip=left_hip,
                    right_hip=right_hip,
                    hip_confidence=0.9,
                )
            )
        return results

    def test_five_frame_speed_confirms_squat_and_holds(self) -> None:
        results = self._feed([100.0, 106.0, 112.0, 118.0, 124.0])

        self.assertFalse(results[3]["speed_ready"])
        self.assertEqual(results[3]["action"], "stand")
        self.assertTrue(results[4]["speed_ready"])
        self.assertEqual(results[4]["action"], "squat")
        self.assertGreater(results[4]["mean_speed_ratio_s"], 0.20)

        held = self._feed([124.0] * 6, start=0.30)
        self.assertEqual(held[-1]["action"], "squat")
        self.assertAlmostEqual(held[-1]["mean_speed_ratio_s"], 0.0)

    def test_two_frame_confirmation_accepts_sustained_descent(self) -> None:
        tracker = ShoulderMotionTracker(
            speed_window_frames=5,
            speed_threshold_ratio=0.20,
            min_drop_ratio=0.08,
            hip_speed_threshold_ratio=0.12,
            hip_min_drop_ratio=0.05,
            symmetry_ratio=0.06,
            confirm_frames=2,
        )
        results = []
        for index, value in enumerate(
            [100.0, 106.0, 112.0, 118.0, 124.0, 130.0]
        ):
            left, right = self._shoulders(value)
            left_hip, right_hip = self._shoulders(value + 120.0)
            results.append(tracker.update(
                left,
                right,
                now=index * 0.055,
                left_hip=left_hip,
                right_hip=right_hip,
                hip_confidence=0.9,
            ))

        self.assertEqual(results[4]["action"], "stand")
        self.assertEqual(results[4]["candidate"], "squat")
        self.assertEqual(results[5]["action"], "squat")

    def test_squat_releases_near_baseline(self) -> None:
        self._feed([100.0, 106.0, 112.0, 118.0, 124.0])
        left, right = self._shoulders(98.0)
        released = self.tracker.update(left, right, now=0.30)

        self.assertEqual(released["action"], "stand")
        self.assertTrue(released["released"])

    def test_brief_upward_motion_does_not_reanchor_baseline(self) -> None:
        results = self._feed([100.0, 94.0, 88.0, 82.0, 76.0])

        self.assertFalse(any(result["reanchored"] for result in results))
        self.assertAlmostEqual(self.tracker.state.baseline_left_y, 100.0)

        settled = self._feed([76.0] * 10, start=0.30, step=0.10)
        self.assertTrue(any(result["reanchored"] for result in settled))
        self.assertEqual(settled[-1]["action"], "stand")
        self.assertEqual(settled[-1]["candidate"], "stand")
        self.assertLess(abs(settled[-1]["mean_shift_px"]), 8.0)

    def test_jump_peak_does_not_pollute_baseline_after_squat(self) -> None:
        self._feed([100.0, 106.0, 112.0, 118.0, 124.0])
        jump = self._feed([50.0, 50.0], start=0.30)
        landed = self._feed([100.0] * 10, start=0.42, step=0.10)

        self.assertTrue(any(result["released"] for result in jump))
        self.assertTrue(any(result["reanchored"] for result in landed))
        self.assertEqual(landed[-1]["action"], "stand")
        self.assertGreater(self.tracker.state.baseline_left_y, 90.0)

    def test_squat_releases_after_recovery_even_with_stale_baseline(self) -> None:
        left, right = self._shoulders(57.0)
        self.tracker.update(left, right, now=0.0)
        self._feed([80.0, 110.0, 150.0, 200.0, 240.0], start=0.055)

        jump = self._feed([50.0, 50.0], start=0.34)
        self.assertTrue(any(result["released"] for result in jump))

        landing = self._feed([112.0] * 10, start=0.50, step=0.10)
        self.assertTrue(any(result["reanchored"] for result in landing))
        self.assertEqual(landing[-1]["action"], "stand")
        self.assertAlmostEqual(self.tracker.state.baseline_left_y, 112.0)

    def test_slow_drift_below_speed_threshold_is_ignored(self) -> None:
        tracker = ShoulderMotionTracker(
            speed_window_frames=5,
            speed_threshold_ratio=0.20,
            min_drop_ratio=0.01,
            release_ratio=0.005,
            symmetry_ratio=0.06,
            confirm_frames=1,
        )
        values = [100.0, 101.0, 102.0, 103.0, 104.0]
        for index, value in enumerate(values):
            left, right = self._shoulders(value)
            result = tracker.update(left, right, now=index * 0.055)

        self.assertTrue(result["speed_ready"])
        self.assertLess(result["mean_speed_ratio_s"], 0.20)
        self.assertEqual(result["action"], "stand")

    def test_asymmetric_shoulder_speed_is_not_a_squat(self) -> None:
        results = []
        for index, (left_y, right_y) in enumerate(
            [(100.0, 100.0), (106.0, 100.0), (112.0, 100.0),
             (118.0, 100.0), (124.0, 100.0)]
        ):
            left, right = self._shoulders(left_y, right_y)
            left_hip, right_hip = self._shoulders(
                220.0 + index * 6.0
            )
            results.append(
                self.tracker.update(
                    left,
                    right,
                    now=index * 0.055,
                    left_hip=left_hip,
                    right_hip=right_hip,
                    hip_confidence=0.9,
                )
            )

        self.assertEqual(results[-1]["action"], "stand")
        self.assertEqual(results[-1]["candidate"], "stand")

    def test_shoulder_drop_without_hip_motion_is_not_squat(self) -> None:
        results = self._feed(
            [100.0, 106.0, 112.0, 118.0, 124.0],
            hip_values=[220.0] * 5,
        )

        self.assertTrue(results[-1]["shoulder_candidate"])
        self.assertFalse(results[-1]["lower_body_confirmed"])
        self.assertEqual(results[-1]["action"], "stand")
        self.assertEqual(
            results[-1]["reason"],
            "hip_motion_below_threshold",
        )

    def test_stale_observation_rebuilds_baseline(self) -> None:
        left, right = self._shoulders(100.0)
        self.tracker.update(left, right, now=0.0)

        left, right = self._shoulders(80.0)
        result = self.tracker.update(left, right, now=1.0)
        self.assertEqual(result["action"], "stand")
        self.assertEqual(result["left_shift_px"], 0.0)
        self.assertEqual(result["right_shift_px"], 0.0)


class ShoulderWidthGateTests(unittest.TestCase):
    def test_requires_repeated_frames_before_first_accept(self) -> None:
        gate = ShoulderWidthGate(confirm_frames=3, tolerance_ratio=0.25)
        self.assertIsNone(gate.update(60.0))
        self.assertIsNone(gate.update(61.0))
        self.assertAlmostEqual(gate.update(59.0), 60.0)

    def test_single_frame_outlier_is_ignored(self) -> None:
        gate = ShoulderWidthGate(confirm_frames=3, tolerance_ratio=0.25)
        for width in (60.0, 60.0, 60.0):
            gate.update(width)

        self.assertIsNone(gate.update(300.0))
        self.assertAlmostEqual(gate.value, 60.0)
        self.assertAlmostEqual(gate.update(62.0), 62.0)

    def test_sustained_change_is_adopted(self) -> None:
        gate = ShoulderWidthGate(confirm_frames=3, tolerance_ratio=0.25)
        for width in (60.0, 60.0, 60.0):
            gate.update(width)

        self.assertIsNone(gate.update(120.0))
        self.assertIsNone(gate.update(118.0))
        self.assertAlmostEqual(gate.update(121.0), 119.666666, places=5)

    def test_reset_clears_state(self) -> None:
        gate = ShoulderWidthGate(confirm_frames=2, tolerance_ratio=0.25)
        gate.update(60.0)
        gate.update(60.0)
        gate.reset()
        self.assertIsNone(gate.value)
        self.assertIsNone(gate.update(60.0))


if __name__ == "__main__":
    unittest.main()
