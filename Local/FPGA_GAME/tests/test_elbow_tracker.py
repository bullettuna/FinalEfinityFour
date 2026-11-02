from __future__ import annotations

import unittest

from elbow_tracker import ElbowRiseTracker


class ElbowRiseTrackerTests(unittest.TestCase):
    def test_requires_upward_pixel_distance_and_rearms_after_release(self) -> None:
        tracker = ElbowRiseTracker(rise_pixels=20, release_pixels=8)

        baseline = tracker.update("left", relative_y=100, now=0.0)
        self.assertFalse(baseline["valid"])

        below = tracker.update("left", relative_y=85, now=0.1)
        self.assertFalse(below["valid"])

        filtered_out = tracker.update("left", relative_y=79, now=0.2)
        self.assertFalse(filtered_out["valid"])

        raised = tracker.update("left", relative_y=79, now=0.25)
        self.assertTrue(raised["valid"])
        self.assertEqual(raised["rise_px"], 21.0)

        held = tracker.update("left", relative_y=75, now=0.3)
        self.assertTrue(held["valid"])

        tracker.update("left", relative_y=94, now=0.4)
        tracker.update("left", relative_y=94, now=0.45)
        released = tracker.update("left", relative_y=94, now=0.5)
        self.assertFalse(released["valid"])

        tracker.update("left", relative_y=73, now=0.55)
        tracker.update("left", relative_y=73, now=0.6)
        raised_again = tracker.update("left", relative_y=73, now=0.65)
        self.assertTrue(raised_again["valid"])

    def test_stale_detection_resets_baseline(self) -> None:
        tracker = ElbowRiseTracker(
            rise_pixels=20,
            release_pixels=8,
            stale_seconds=0.5,
        )
        tracker.update("right", relative_y=100, now=0.0)

        raised = tracker.update("right", relative_y=70, now=0.6)
        self.assertFalse(raised["valid"])
        self.assertEqual(raised["baseline_y_px"], 70.0)

    def test_release_uses_peak_position_not_original_baseline(self) -> None:
        tracker = ElbowRiseTracker(rise_pixels=20, release_pixels=8)
        tracker.update("left", relative_y=100, now=0.0)
        tracker.update("left", relative_y=70, now=0.1)
        raised = tracker.update("left", relative_y=70, now=0.2)
        self.assertTrue(raised["valid"])

        # The person moved down inside the frame, so 90 is still above the
        # original baseline. The elbow nevertheless fell 20 px from its peak.
        tracker.update("left", relative_y=90, now=0.3)
        pending_release = tracker.update("left", relative_y=90, now=0.4)
        released = tracker.update("left", relative_y=90, now=0.5)
        self.assertTrue(pending_release["valid"])
        self.assertEqual(pending_release["release_candidate_frames"], 1)
        self.assertFalse(released["valid"])

    def test_single_frame_spike_is_rejected_by_median_filter(self) -> None:
        tracker = ElbowRiseTracker(rise_pixels=20, release_pixels=8)

        tracker.update("left", relative_y=100, now=0.0)
        spike = tracker.update("left", relative_y=50, now=0.1)
        recovered = tracker.update("left", relative_y=100, now=0.2)
        stable = tracker.update("left", relative_y=100, now=0.3)

        self.assertFalse(spike["valid"])
        self.assertFalse(recovered["valid"])
        self.assertFalse(stable["valid"])

    def test_dynamic_threshold_overrides_fixed_pixels(self) -> None:
        tracker = ElbowRiseTracker(rise_pixels=20, release_pixels=8)

        tracker.update("left", relative_y=100, now=0.0)
        tracker.update("left", relative_y=85, threshold_px=30, now=0.1)
        below = tracker.update("left", relative_y=79, threshold_px=30, now=0.2)
        still_below = tracker.update("left", relative_y=79, threshold_px=30, now=0.3)
        self.assertFalse(below["valid"])
        self.assertFalse(still_below["valid"])
        self.assertEqual(still_below["rise_threshold_px"], 30.0)

        lenient = tracker.update("left", relative_y=79, threshold_px=15, now=0.4)
        self.assertTrue(lenient["valid"])
        self.assertEqual(lenient["rise_threshold_px"], 15.0)


if __name__ == "__main__":
    unittest.main()
