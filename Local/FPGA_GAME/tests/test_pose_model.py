from __future__ import annotations

import unittest
from pathlib import Path

import numpy as np

from pose_model import PoseModelBundle, fuse_arm_decision, rule_side_confidence


ROOT = Path(__file__).resolve().parents[1]


class PoseModelFusionTests(unittest.TestCase):
    def test_saved_bundle_outputs_human_and_three_arm_probabilities(self) -> None:
        model_path = ROOT / "models" / "eleven_point_model.npz"
        if not model_path.is_file():
            self.skipTest("pose model bundle is not present")
        bundle = PoseModelBundle(model_path)
        coordinates = np.zeros((bundle.window_size, 11, 2), dtype=np.float64)
        scores = np.zeros((bundle.window_size, 11), dtype=np.float64)

        result = bundle.predict(coordinates, scores)

        self.assertGreaterEqual(result["human_confidence"], 0.0)
        self.assertLessEqual(result["human_confidence"], 1.0)
        self.assertEqual(
            set(result["arm_probabilities"]),
            {"left_raise", "right_raise", "no_raise"},
        )
        self.assertAlmostEqual(sum(result["arm_probabilities"].values()), 1.0)

    def test_model_and_rule_agreement_uses_weighted_score(self) -> None:
        result = fuse_arm_decision(
            "right",
            {"left": 0.0, "right": 0.9},
            {"left_raise": 0.1, "right_raise": 0.8, "no_raise": 0.1},
            0.7,
            0.3,
        )

        self.assertTrue(result["accepted"])
        self.assertFalse(result["conflict"])
        self.assertEqual(result["action"], "right")
        self.assertAlmostEqual(result["combined_confidence"], 0.87, places=6)

    def test_direction_conflict_blocks_attack(self) -> None:
        result = fuse_arm_decision(
            "right",
            {"left": 0.0, "right": 0.9},
            {"left_raise": 0.8, "right_raise": 0.1, "no_raise": 0.1},
            0.7,
            0.3,
        )

        self.assertFalse(result["accepted"])
        self.assertTrue(result["conflict"])
        self.assertEqual(result["action"], "stand")

    def test_mirrored_model_side_matches_screen_based_rule(self) -> None:
        result = fuse_arm_decision(
            "right",
            {"left": 0.0, "right": 0.9},
            {"left_raise": 0.8, "right_raise": 0.1, "no_raise": 0.1},
            0.7,
            0.3,
            model_side_mirrored=True,
        )

        self.assertTrue(result["accepted"])
        self.assertFalse(result["conflict"])
        self.assertEqual(result["model_side"], "right")
        self.assertEqual(result["action"], "right")

    def test_rule_confidence_requires_elbow_and_wrist(self) -> None:
        arm = {
            "elbow_valid": True,
            "wrist_valid": True,
            "rise_px": 24.0,
            "rise_threshold_px": 20.0,
            "wrist_rise_px": 18.0,
            "wrist_rise_threshold_px": 13.0,
            "wrist_below_elbow_px": 3.0,
            "wrist_offset_limit_px": 12.0,
        }

        self.assertGreater(rule_side_confidence(arm), 0.5)
        arm["wrist_valid"] = False
        self.assertEqual(rule_side_confidence(arm), 0.0)


if __name__ == "__main__":
    unittest.main()
