"""Lightweight human and arm-raise models for FPGA eleven-point poses."""
from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np


ARM_CLASS_NAMES = ("left_raise", "right_raise", "no_raise")
ARM_CLASS_TO_INDEX = {name: index for index, name in enumerate(ARM_CLASS_NAMES)}
FEATURE_VERSION = 1


@dataclass
class MLPModel:
    weights: list[np.ndarray]
    biases: list[np.ndarray]


def _sigmoid(values: np.ndarray) -> np.ndarray:
    values = np.clip(values, -40.0, 40.0)
    return 1.0 / (1.0 + np.exp(-values))


def _softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - logits.max(axis=1, keepdims=True)
    exponent = np.exp(shifted)
    return exponent / exponent.sum(axis=1, keepdims=True)


def _frame_scale(points: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    shoulders = (points[1] + points[2]) * 0.5
    hips = (points[7] + points[8]) * 0.5
    shoulder_width = float(np.linalg.norm(points[1] - points[2]))
    torso_length = float(np.linalg.norm(shoulders - hips))
    return shoulders, hips, max(shoulder_width, torso_length, 1.0)


def human_frame_features(points: np.ndarray, scores: np.ndarray) -> np.ndarray:
    points = np.asarray(points, dtype=np.float64)
    scores = np.asarray(scores, dtype=np.float64)
    shoulders, hips, scale = _frame_scale(points)
    shoulder_width = float(np.linalg.norm(points[1] - points[2]))
    hip_width = float(np.linalg.norm(points[7] - points[8]))
    torso_length = float(np.linalg.norm(shoulders - hips))
    body_span = float(points[:, 1].max() - points[:, 1].min())
    body_width = float(points[:, 0].max() - points[:, 0].min())
    head_distance = float(np.linalg.norm(points[0] - shoulders))
    knee_mid = (points[9] + points[10]) * 0.5
    normalized = np.clip((points - shoulders) / scale, -5.0, 5.0).reshape(-1)
    score = np.clip(scores, 0.0, 1.0)
    geometry = np.asarray(
        [
            shoulder_width / scale,
            hip_width / scale,
            torso_length / scale,
            body_span / scale,
            body_width / scale,
            head_distance / scale,
            float(knee_mid[1] - hips[1]) / scale,
            float(shoulders[0]) / 640.0,
            float(shoulders[1]) / 360.0,
            float(hips[0]) / 640.0,
            float(hips[1]) / 360.0,
            float(score.mean()),
            float(score.min()),
            float(np.mean(score >= 0.12)),
            float(np.mean(score >= 0.20)),
            float(np.mean(score >= 0.40)),
            float(np.count_nonzero((points[:, 0] == 0.0) & (points[:, 1] == 0.0))) / 11.0,
        ],
        dtype=np.float64,
    )
    result = np.concatenate((normalized, score, geometry))
    return np.nan_to_num(result, nan=0.0, posinf=5.0, neginf=-5.0)


def arm_frame_features(points: np.ndarray) -> np.ndarray:
    points = np.asarray(points, dtype=np.float64)
    _shoulders, _hips, scale = _frame_scale(points)
    features = []
    for shoulder_index, elbow_index, wrist_index in ((1, 3, 5), (2, 4, 6)):
        shoulder = points[shoulder_index]
        elbow = points[elbow_index]
        wrist = points[wrist_index]
        upper = elbow - shoulder
        lower = wrist - elbow
        denominator = float(np.linalg.norm(upper) * np.linalg.norm(lower))
        elbow_cos = float(np.dot(upper, lower) / denominator) if denominator > 1e-6 else 0.0
        features.extend(
            (
                (shoulder[1] - wrist[1]) / scale,
                (shoulder[1] - elbow[1]) / scale,
                abs(float(wrist[0] - shoulder[0])) / scale,
                float(np.linalg.norm(upper)) / scale,
                float(np.linalg.norm(lower)) / scale,
                float(np.linalg.norm(wrist - shoulder)) / scale,
                elbow_cos,
            )
        )
    return np.nan_to_num(np.asarray(features, dtype=np.float64), nan=0.0, posinf=5.0, neginf=-5.0)


def _window_summary(per_frame: np.ndarray, include_motion: bool) -> np.ndarray:
    parts = [
        per_frame.mean(axis=0),
        per_frame.std(axis=0),
        per_frame.min(axis=0),
        per_frame.max(axis=0),
    ]
    if include_motion:
        velocity = np.diff(per_frame, axis=0)
        parts.extend((np.abs(velocity).mean(axis=0), per_frame[-1] - per_frame[0]))
    return np.nan_to_num(np.concatenate(parts), nan=0.0, posinf=10.0, neginf=-10.0)


def human_window_features(coordinates: np.ndarray, scores: np.ndarray) -> np.ndarray:
    per_frame = np.stack(
        [human_frame_features(points, score) for points, score in zip(coordinates, scores, strict=True)]
    )
    return _window_summary(per_frame, include_motion=False)


def arm_window_features(coordinates: np.ndarray, scores: np.ndarray) -> np.ndarray:
    del scores
    per_frame = np.stack([arm_frame_features(points) for points in coordinates])
    return _window_summary(per_frame, include_motion=True)


def _forward(model: MLPModel, features: np.ndarray) -> list[np.ndarray]:
    activations = [features]
    current = features
    for index, (weight, bias) in enumerate(zip(model.weights, model.biases, strict=True)):
        current = current @ weight + bias
        if index < len(model.weights) - 1:
            current = np.maximum(current, 0.0)
        activations.append(current)
    return activations


class PoseModelBundle:
    def __init__(self, model_path: Path) -> None:
        with np.load(model_path, allow_pickle=False) as data:
            self.window_size = int(data["window_size"])
            self.human_mean = np.asarray(data["human_mean"], dtype=np.float64)
            self.human_std = np.asarray(data["human_std"], dtype=np.float64)
            self.arm_mean = np.asarray(data["arm_mean"], dtype=np.float64)
            self.arm_std = np.asarray(data["arm_std"], dtype=np.float64)
            self.arm_classes = tuple(str(value) for value in data["arm_classes"].tolist())
            self.human_model = self._load_model(data, "human")
            self.arm_model = self._load_model(data, "arm")

    @staticmethod
    def _load_model(data: np.lib.npyio.NpzFile, prefix: str) -> MLPModel:
        weights = []
        biases = []
        index = 0
        while f"{prefix}_weight_{index}" in data:
            weights.append(np.asarray(data[f"{prefix}_weight_{index}"], dtype=np.float64))
            biases.append(np.asarray(data[f"{prefix}_bias_{index}"], dtype=np.float64))
            index += 1
        if not weights:
            raise ValueError(f"model bundle has no {prefix} layers")
        return MLPModel(weights, biases)

    def predict(self, coordinates: np.ndarray, scores: np.ndarray) -> dict:
        human_features = human_window_features(coordinates, scores)
        human_logit = _forward(
            self.human_model,
            ((human_features - self.human_mean) / self.human_std)[None, :],
        )[-1][0, 0]
        human_confidence = float(_sigmoid(np.asarray([human_logit]))[0])

        arm_features = arm_window_features(coordinates, scores)
        arm_probabilities = _softmax(
            _forward(
                self.arm_model,
                ((arm_features - self.arm_mean) / self.arm_std)[None, :],
            )[-1]
        )[0]
        probabilities = {
            name: float(value)
            for name, value in zip(self.arm_classes, arm_probabilities, strict=True)
        }
        raise_confidence = probabilities.get("left_raise", 0.0) + probabilities.get(
            "right_raise", 0.0
        )
        return {
            "human_confidence": human_confidence,
            "raise_confidence": float(raise_confidence),
            "arm_probabilities": probabilities,
        }


def rule_side_confidence(arm: dict) -> float:
    if not arm.get("elbow_valid") or not arm.get("wrist_valid"):
        return 0.0
    elbow_limit = max(1.0, float(arm.get("rise_threshold_px", 1.0)))
    wrist_limit = max(1.0, float(arm.get("wrist_rise_threshold_px", 1.0)))
    elbow_score = 0.5 + 0.5 * float(
        np.clip((float(arm.get("rise_px", 0.0)) - elbow_limit) / elbow_limit, 0.0, 1.0)
    )
    wrist_score = 0.5 + 0.5 * float(
        np.clip((float(arm.get("wrist_rise_px", 0.0)) - wrist_limit) / wrist_limit, 0.0, 1.0)
    )
    offset_limit = arm.get("wrist_offset_limit_px")
    if offset_limit is not None:
        below = float(arm.get("wrist_below_elbow_px", 0.0))
        if below > float(offset_limit):
            return 0.0
    return float(math.sqrt(elbow_score * wrist_score))


def fuse_arm_decision(
    rule_action: str,
    rule_confidences: dict[str, float],
    model_probabilities: dict[str, float],
    rule_weight: float,
    model_weight: float,
    model_side_mirrored: bool = False,
) -> dict:
    if rule_action not in {"left", "right"}:
        return {
            "accepted": False,
            "action": "stand",
            "reason": "no_rule_arm_candidate",
            "combined_confidence": 0.0,
            "conflict": False,
        }
    mapped_probabilities = {
        "left_raise": model_probabilities.get("left_raise", 0.0),
        "right_raise": model_probabilities.get("right_raise", 0.0),
        "no_raise": model_probabilities.get("no_raise", 0.0),
    }
    if model_side_mirrored:
        mapped_probabilities["left_raise"], mapped_probabilities["right_raise"] = (
            mapped_probabilities["right_raise"],
            mapped_probabilities["left_raise"],
        )
    model_side = max(
        ("left", "right"),
        key=lambda side: mapped_probabilities.get(f"{side}_raise", 0.0),
    )
    conflict = model_side != rule_action
    normalized_weight = max(1e-6, float(rule_weight) + float(model_weight))
    rule_weight = float(rule_weight) / normalized_weight
    model_weight = float(model_weight) / normalized_weight
    side_scores = {
        side: rule_weight * float(rule_confidences.get(side, 0.0))
        + model_weight * float(mapped_probabilities.get(f"{side}_raise", 0.0))
        for side in ("left", "right")
    }
    combined = float(side_scores[rule_action])
    return {
        "accepted": not conflict,
        "action": rule_action if not conflict else "stand",
        "reason": "model_rule_conflict" if conflict else "model_rule_agree",
        "combined_confidence": combined,
        "conflict": conflict,
        "model_side": model_side,
        "rule_side": rule_action,
        "left_score": float(side_scores["left"]),
        "right_score": float(side_scores["right"]),
    }
