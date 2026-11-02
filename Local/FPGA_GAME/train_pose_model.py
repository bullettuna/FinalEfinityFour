"""Train the human gate and arm-raise models from diagnostic kind5 captures."""
from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from ft232h_source import Frame, decode_eleven_point_result
from pose_model import (
    ARM_CLASS_NAMES,
    ARM_CLASS_TO_INDEX,
    MLPModel,
    arm_window_features,
    human_window_features,
)


ROOT = Path(__file__).resolve().parent
DEFAULT_DATA_ROOT = Path.home() / "Desktop" / "\u0031\u0031\u70b9\u9aa8\u67b6\u8bad\u7ec3\u6570\u636e"
DEFAULT_MODEL_OUT = ROOT / "models" / "eleven_point_model.npz"
SOURCE_FOLDERS = {
    "left": "\u5de6\u62ac\u624b",
    "right": "\u53f3\u62ac\u624b",
    "squat": "\u4e0b\u8e72",
    "garbage": "\u65e0\u610f\u4e49\u52a8\u4f5c",
    "empty": "\u65e0\u4eba\u7269",
}
FOLDER_TO_SOURCE = {folder: source for source, folder in SOURCE_FOLDERS.items()}
SOURCE_TO_ARM = {
    "left": "left_raise",
    "right": "right_raise",
    "squat": "no_raise",
    "garbage": "no_raise",
    "empty": "no_raise",
}


@dataclass(frozen=True)
class Capture:
    path: Path
    source: str
    coordinates: np.ndarray
    scores: np.ndarray


def load_capture(path: Path, source: str) -> Capture:
    data = json.loads(path.read_text(encoding="utf-8"))
    coordinates = []
    scores = []
    for event in data.get("events", []):
        if event.get("event") != "rx_frame" or int(event.get("kind", -1)) != 5:
            continue
        frame = Frame(
            kind=5,
            sequence=int(event["sequence"]),
            width=int(event["width"]),
            height=int(event["height"]),
            payload=bytes.fromhex(str(event["content_hex"])),
            version=int(event["version"]),
        )
        decoded = decode_eleven_point_result(frame)
        coordinates.append(
            np.asarray([[point["x"], point["y"]] for point in decoded["points"]], dtype=np.float64)
        )
        scores.append(
            np.asarray([float(point.get("score") or 0.0) for point in decoded["points"]], dtype=np.float64)
        )
    if not coordinates:
        raise ValueError(f"{path}: no kind5 frames")
    return Capture(path, source, np.stack(coordinates), np.stack(scores))


def collect_captures(root: Path) -> list[Capture]:
    captures = []
    for folder in sorted(path for path in root.iterdir() if path.is_dir()):
        source = FOLDER_TO_SOURCE.get(folder.name)
        if source is None:
            continue
        captures.extend(load_capture(path, source) for path in sorted(folder.glob("*.json")))
    missing = sorted(set(SOURCE_FOLDERS) - {capture.source for capture in captures})
    if missing:
        raise ValueError(f"missing sources: {missing}")
    return captures


def make_windows(capture: Capture, window_size: int, stride: int, human: bool) -> np.ndarray:
    rows = []
    for start in range(0, len(capture.coordinates) - window_size + 1, stride):
        coordinates = capture.coordinates[start:start + window_size]
        scores = capture.scores[start:start + window_size]
        rows.append(
            human_window_features(coordinates, scores)
            if human else arm_window_features(coordinates, scores)
        )
    return np.stack(rows)


def _initialize(
    input_size: int,
    hidden_sizes: tuple[int, ...],
    output_size: int,
    rng: np.random.Generator,
) -> MLPModel:
    sizes = (input_size, *hidden_sizes, output_size)
    weights = [
        rng.normal(0.0, math.sqrt(2.0 / fan_in), (fan_in, fan_out))
        for fan_in, fan_out in zip(sizes[:-1], sizes[1:], strict=True)
    ]
    biases = [np.zeros(size, dtype=np.float64) for size in sizes[1:]]
    return MLPModel(weights, biases)


def _hidden(parameters: MLPModel, features: np.ndarray) -> list[np.ndarray]:
    activations = [features]
    current = features
    for index, (weight, bias) in enumerate(zip(parameters.weights, parameters.biases, strict=True)):
        current = current @ weight + bias
        if index < len(parameters.weights) - 1:
            current = np.maximum(current, 0.0)
        activations.append(current)
    return activations


def _softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits - logits.max(axis=1, keepdims=True)
    exponent = np.exp(shifted)
    return exponent / exponent.sum(axis=1, keepdims=True)


def _sigmoid(values: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(values, -40.0, 40.0)))


def train_model(
    features: np.ndarray,
    labels: np.ndarray,
    output_size: int,
    hidden_sizes: tuple[int, ...],
    epochs: int,
    weight_decay: float,
    seed: int,
) -> MLPModel:
    rng = np.random.default_rng(seed)
    parameters = _initialize(features.shape[1], hidden_sizes, output_size, rng)
    if output_size == 1:
        targets = labels.astype(np.float64)[:, None]
        counts = np.bincount(labels.astype(np.int64), minlength=2).astype(np.float64)
        sample_weights = np.where(labels == 1, labels.size / (2 * max(1, counts[1])), labels.size / (2 * max(1, counts[0])))
    else:
        targets = np.eye(output_size, dtype=np.float64)[labels]
        counts = np.bincount(labels, minlength=output_size).astype(np.float64)
        sample_weights = labels.size / (output_size * np.maximum(1.0, counts[labels]))
    sample_weights /= sample_weights.mean()

    moments = [(np.zeros_like(w), np.zeros_like(w)) for w in parameters.weights]
    moments += [(np.zeros_like(b), np.zeros_like(b)) for b in parameters.biases]
    for step in range(1, epochs + 1):
        activations = _hidden(parameters, features)
        logits = activations[-1]
        probabilities = _sigmoid(logits) if output_size == 1 else _softmax(logits)
        weighted = sample_weights / sample_weights.sum()
        delta = (probabilities - targets) * weighted[:, None]
        if output_size == 1:
            delta = delta
        gradient_weights = []
        gradient_biases = []
        for layer in range(len(parameters.weights) - 1, -1, -1):
            gradient_weights.append(
                activations[layer].T @ delta + weight_decay * parameters.weights[layer]
            )
            gradient_biases.append(delta.sum(axis=0))
            if layer:
                delta = (delta @ parameters.weights[layer].T) * (activations[layer] > 0.0)
        gradient_weights.reverse()
        gradient_biases.reverse()
        gradients = gradient_weights + gradient_biases
        for parameter, gradient, moment in zip(
            parameters.weights + parameters.biases, gradients, moments, strict=True
        ):
            first, second = moment
            first *= 0.9
            first += 0.1 * gradient
            second *= 0.999
            second += 0.001 * np.square(gradient)
            parameter -= 0.004 * (first / (1.0 - 0.9 ** step)) / (
                np.sqrt(second / (1.0 - 0.999 ** step)) + 1e-8
            )
    return parameters


def predict(parameters: MLPModel, features: np.ndarray, output_size: int) -> np.ndarray:
    logits = _hidden(parameters, features)[-1]
    return _sigmoid(logits).reshape(-1) if output_size == 1 else _softmax(logits)


def save_bundle(
    path: Path,
    human_model: MLPModel,
    human_mean: np.ndarray,
    human_std: np.ndarray,
    arm_model: MLPModel,
    arm_mean: np.ndarray,
    arm_std: np.ndarray,
    window_size: int,
    report: dict,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    arrays = {
        "window_size": np.asarray(window_size, dtype=np.int64),
        "human_mean": human_mean,
        "human_std": human_std,
        "arm_mean": arm_mean,
        "arm_std": arm_std,
        "arm_classes": np.asarray(ARM_CLASS_NAMES),
    }
    for prefix, model in (("human", human_model), ("arm", arm_model)):
        for index, (weight, bias) in enumerate(zip(model.weights, model.biases, strict=True)):
            arrays[f"{prefix}_weight_{index}"] = weight
            arrays[f"{prefix}_bias_{index}"] = bias
    np.savez_compressed(path, **arrays)
    path.with_suffix(".json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train eleven-point human and arm models")
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    parser.add_argument("--model-out", type=Path, default=DEFAULT_MODEL_OUT)
    parser.add_argument("--window-size", type=int, default=18)
    parser.add_argument("--stride", type=int, default=2)
    parser.add_argument("--epochs", type=int, default=1000)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    captures = collect_captures(args.data_root)
    train_captures = []
    test_captures = []
    for source in SOURCE_FOLDERS:
        group = sorted(
            [capture for capture in captures if capture.source == source],
            key=lambda capture: capture.path.name,
        )
        train_captures.extend(group[:-1])
        test_captures.append(group[-1])

    human_train = np.concatenate(
        [make_windows(capture, args.window_size, args.stride, True) for capture in train_captures]
    )
    human_labels = np.concatenate(
        [
            np.full(
                len(make_windows(capture, args.window_size, args.stride, True)),
                0 if capture.source == "empty" else 1,
            )
            for capture in train_captures
        ]
    )
    arm_train = np.concatenate(
        [make_windows(capture, args.window_size, args.stride, False) for capture in train_captures]
    )
    arm_labels = np.concatenate(
        [
            np.full(
                len(make_windows(capture, args.window_size, args.stride, False)),
                ARM_CLASS_TO_INDEX[SOURCE_TO_ARM[capture.source]],
            )
            for capture in train_captures
        ]
    )

    human_mean = human_train.mean(axis=0)
    human_std = human_train.std(axis=0)
    human_std[human_std < 1e-8] = 1.0
    arm_mean = arm_train.mean(axis=0)
    arm_std = arm_train.std(axis=0)
    arm_std[arm_std < 1e-8] = 1.0
    human_model = train_model(
        (human_train - human_mean) / human_std,
        human_labels,
        1,
        (32, 16),
        args.epochs,
        1e-3,
        7,
    )
    arm_model = train_model(
        (arm_train - arm_mean) / arm_std,
        arm_labels,
        3,
        (16, 8),
        args.epochs,
        5e-3,
        7,
    )

    human_scores = []
    human_targets = []
    arm_predictions = []
    arm_targets = []
    capture_results = []
    for capture in test_captures:
        human_features = make_windows(capture, args.window_size, 1, True)
        human_probability = predict(
            human_model,
            (human_features - human_mean) / human_std,
            1,
        )
        target = 0 if capture.source == "empty" else 1
        human_scores.extend(human_probability.tolist())
        human_targets.extend([target] * len(human_probability))
        arm_features = make_windows(capture, args.window_size, 1, False)
        arm_probability = predict(
            arm_model,
            (arm_features - arm_mean) / arm_std,
            3,
        )
        prediction = [ARM_CLASS_NAMES[index] for index in arm_probability.argmax(axis=1)]
        target_arm = SOURCE_TO_ARM[capture.source]
        arm_predictions.extend(prediction)
        arm_targets.extend([target_arm] * len(prediction))
        capture_results.append(
            {
                "capture": str(capture.path),
                "source": capture.source,
                "human_mean": float(np.mean(human_probability)),
                "arm_counts": {name: prediction.count(name) for name in ARM_CLASS_NAMES},
            }
        )

    human_scores_array = np.asarray(human_scores)
    human_targets_array = np.asarray(human_targets)
    human_predictions = human_scores_array >= 0.65
    human_accuracy = float(np.mean(human_predictions == human_targets_array.astype(bool)))
    human_recall = float(np.mean(human_predictions[human_targets_array == 1]))
    empty_recall = float(np.mean(~human_predictions[human_targets_array == 0]))
    arm_accuracy = float(np.mean(np.asarray(arm_predictions) == np.asarray(arm_targets)))
    report = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "protocol": "strict_holdout_human_and_arm",
        "window_size": args.window_size,
        "training_captures": [str(capture.path) for capture in train_captures],
        "test_captures": [str(capture.path) for capture in test_captures],
        "human": {
            "threshold": 0.65,
            "accuracy": human_accuracy,
            "human_recall": human_recall,
            "empty_recall": empty_recall,
        },
        "arm": {"accuracy": arm_accuracy},
        "capture_results": capture_results,
    }
    save_bundle(
        args.model_out,
        human_model,
        human_mean,
        human_std,
        arm_model,
        arm_mean,
        arm_std,
        args.window_size,
        report,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"saved model: {args.model_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
