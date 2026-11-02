from __future__ import annotations

import unittest

from gesture_filter import GestureFilter, PostSquatAttackGate


class GestureFilterTests(unittest.TestCase):
    def test_snapshot_reports_votes_and_cooldown(self) -> None:
        gesture = GestureFilter(
            confirm_frames=2,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=2,
        )
        self.assertFalse(gesture.update("left", now=10.0))
        self.assertTrue(gesture.update("left", now=10.1))
        snapshot = gesture.snapshot(now=10.3)

        self.assertEqual(snapshot["candidate"], "left")
        self.assertEqual(snapshot["candidate_frames"], 2)
        self.assertEqual(snapshot["min_votes"], 2)
        self.assertEqual(snapshot["cooldown_remaining_ms"], 800)

    def test_sustained_gesture_retriggers_after_cooldown(self) -> None:
        gesture = GestureFilter(confirm_frames=2, cooldown_s=1.0)

        self.assertFalse(gesture.update("right", now=0.0))
        self.assertTrue(gesture.update("right", now=0.1))
        self.assertFalse(gesture.update("right", now=0.9))
        self.assertTrue(gesture.update("right", now=1.1))
        self.assertFalse(gesture.update("right", now=1.5))
        self.assertTrue(gesture.update("right", now=2.1))

    def test_release_does_not_bypass_cooldown(self) -> None:
        gesture = GestureFilter(confirm_frames=1, cooldown_s=1.0)
        self.assertTrue(gesture.update("left", now=0.0))
        self.assertFalse(gesture.update("stand", now=0.2))
        self.assertFalse(gesture.update("left", now=0.8))
        self.assertTrue(gesture.update("left", now=1.05))

    def test_invalid_action_is_treated_as_stand(self) -> None:
        gesture = GestureFilter(confirm_frames=1, cooldown_s=1.0)
        self.assertFalse(gesture.update("not-an-action", now=0.0))
        self.assertIsNone(gesture.last_trigger_at)

    def test_requires_three_votes_in_four_frame_window(self) -> None:
        gesture = GestureFilter(
            confirm_frames=3,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=3,
        )

        self.assertFalse(gesture.update("right", now=0.0))
        self.assertFalse(gesture.update("stand", now=0.1))


class PostSquatAttackGateTests(unittest.TestCase):
    def test_snapshot_reports_gate_rearm_state(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        gate.update("squat", "left", now=10.0)
        gate.update("stand", "left", now=10.0)
        snapshot = gate.snapshot(now=10.1)

        self.assertFalse(snapshot["squatting"])
        self.assertFalse(snapshot["rearmed"])
        self.assertEqual(snapshot["neutral_count"], 0)
        self.assertEqual(snapshot["neutral_frames_required"], 3)
        self.assertEqual(snapshot["suppress_remaining_ms"], 200)

    def test_no_gate_without_squat(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        self.assertFalse(gate.update("stand", "left", now=0.0))
        self.assertFalse(gate.update("stand", "left", now=0.1))

    def test_squat_frames_are_not_gated(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        self.assertFalse(gate.update("squat", "stand", now=0.0))
        self.assertFalse(gate.update("squat", "stand", now=0.1))

    def test_first_frames_after_squat_are_gated(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        gate.update("squat", "stand", now=1.0)
        self.assertTrue(gate.update("stand", "stand", now=1.1))
        self.assertTrue(gate.update("stand", "left", now=1.2))
        self.assertTrue(gate.update("stand", "stand", now=1.5))
        self.assertTrue(gate.update("stand", "stand", now=1.6))

    def test_neutral_run_rearms_attacks(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.1,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        gate.update("squat", "stand", now=1.0)
        self.assertTrue(gate.update("stand", "stand", now=1.05))
        self.assertTrue(gate.update("stand", "stand", now=1.20))
        self.assertTrue(gate.update("stand", "stand", now=1.30))
        self.assertFalse(gate.update("stand", "stand", now=1.35))
        self.assertFalse(gate.update("stand", "left", now=1.40))

    def test_elbow_rise_restarts_neutral_run(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.1,
            neutral_frames=2,
            squat_confirm_frames=1,
        )
        gate.update("squat", "stand", now=1.0)
        self.assertTrue(gate.update("stand", "stand", now=1.20))
        self.assertTrue(gate.update("stand", "left", now=1.30))
        self.assertTrue(gate.update("stand", "stand", now=1.40))
        self.assertTrue(gate.update("stand", "left", now=1.50))
        self.assertTrue(gate.update("stand", "stand", now=1.60))
        self.assertFalse(gate.update("stand", "stand", now=1.70))
        self.assertFalse(gate.update("stand", "left", now=1.80))

    def test_reset_clears_gate(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        gate.update("squat", "stand", now=1.0)
        gate.reset()
        self.assertFalse(gate.update("stand", "left", now=1.1))

    def test_single_squat_frame_does_not_arm_gate(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=2,
        )
        self.assertFalse(gate.update("squat", "left", now=1.0))
        self.assertFalse(gate.update("stand", "left", now=1.1))
        self.assertFalse(gate.update("stand", "left", now=1.2))

    def test_invalidate_clears_false_gate(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
        )
        gate.update("squat", "stand", now=1.0)
        self.assertTrue(gate.update("stand", "left", now=1.1))
        gate.invalidate()
        self.assertFalse(gate.update("stand", "left", now=1.2))

    def test_max_gate_time_requires_recalibration(self) -> None:
        gate = PostSquatAttackGate(
            suppress_s=0.3,
            neutral_frames=3,
            squat_confirm_frames=1,
            max_gate_s=1.0,
        )
        gate.update("squat", "stand", now=1.0)
        self.assertTrue(gate.update("stand", "left", now=1.1))
        self.assertTrue(gate.update("stand", "left", now=2.1))
        self.assertTrue(gate.snapshot(now=2.1)["recovery_required"])


class GestureFilterVotingTests(unittest.TestCase):

    def test_age_advances_window_without_voting(self) -> None:
        gesture = GestureFilter(
            confirm_frames=2,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=2,
        )

        self.assertFalse(gesture.update("left", now=0.0))
        self.assertFalse(gesture.age())
        self.assertTrue(gesture.update("left", now=0.1))

    def test_votes_expire_by_frame_count_during_gaps(self) -> None:
        gesture = GestureFilter(
            confirm_frames=2,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=2,
        )

        self.assertFalse(gesture.update("left", now=0.0))
        for _ in range(3):
            self.assertFalse(gesture.age())
        self.assertFalse(gesture.update("left", now=0.1))
        self.assertIsNone(gesture.last_trigger_at)

    def test_two_votes_in_four_frames_tolerates_one_missing_frame(self) -> None:
        gesture = GestureFilter(
            confirm_frames=2,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=2,
        )

        self.assertFalse(gesture.update("stand", now=0.0))
        self.assertFalse(gesture.update("right", now=0.1))
        self.assertTrue(gesture.update("right", now=0.2))

    def test_mixed_directions_do_not_form_an_attack(self) -> None:
        gesture = GestureFilter(
            confirm_frames=3,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=3,
        )

        self.assertFalse(gesture.update("left", now=0.0))
        self.assertFalse(gesture.update("right", now=0.1))
        self.assertFalse(gesture.update("left", now=0.2))
        self.assertFalse(gesture.update("right", now=0.3))

    def test_reset_candidate_clears_votes_without_resetting_cooldown(self) -> None:
        gesture = GestureFilter(
            confirm_frames=3,
            cooldown_s=1.0,
            window_frames=4,
            min_votes=3,
        )

        gesture.update("left", now=0.0)
        gesture.update("left", now=0.1)
        self.assertTrue(gesture.update("left", now=0.2))

        gesture.reset_candidate()
        self.assertEqual(len(gesture.history), 0)
        self.assertFalse(gesture.update("left", now=0.3))
        self.assertFalse(gesture.update("left", now=0.4))
        self.assertTrue(gesture.update("left", now=1.3))


if __name__ == "__main__":
    unittest.main()
