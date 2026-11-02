"""Offline integer model of this project's FPGA Canny, with local batch conversion.

No downloads, no OpenCV, no model training. See tools/FPGA_CANNY.md.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

PROFILE_PATH = Path(__file__).with_name("fpga_canny_profile.json")
EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".ppm", ".pgm", ".tif", ".tiff", ".webp"}


@dataclass(frozen=True)
class Config:
    mode: str = "gray"
    low: int = 30
    high: int = 60
    wb: tuple[int, int, int] = (335, 248, 280)
    gamma: bool = True
    gamma_strength: int = 42
    layout: str = "raster"
    pipeline: str = "image5"
    median: bool = True
    cleanup: bool = True
    top_guard: int = 12

    def validate(self):
        if not 0 <= self.low <= self.high <= 2047:
            raise ValueError("Require 0 <= low <= high <= 2047")
        if len(self.wb) != 3 or any(not 0 <= x <= 2047 for x in self.wb):
            raise ValueError("WB gains must be three integers in 0..2047 (256 = 1.0)")
        if not 0 <= self.gamma_strength <= 256:
            raise ValueError("Gamma strength must be in 0..256")
        if self.mode not in {"gray", "color"} or self.layout not in {"raster", "centered"}:
            raise ValueError("Invalid mode or layout")
        if self.pipeline not in {"image5", "canny-core"}:
            raise ValueError("Invalid pipeline")
        if self.pipeline == "image5" and self.mode != "gray":
            raise ValueError("image5 is a grayscale pipeline; --mode color requires --pipeline canny-core")
        if self.top_guard < 0:
            raise ValueError("Top guard must be nonnegative")


def load_profile(path=PROFILE_PATH):
    profile = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    lut = profile["gamma_lut"]
    if len(lut) != 256 or any(not isinstance(x, int) or not 0 <= x <= 255 for x in lut):
        raise ValueError("Profile must contain 256 unsigned 8-bit gamma LUT entries")
    return profile


def windows(a, layout="raster"):
    """Nine RTL taps, with edge replication, returned as array views.

    RTL row r uses rows max(r-2,0), max(r-1,0), r. Column c uses
    max(c-1,0), c, min(c+1,W-1). This is intentionally not a symmetric
    OpenCV padding rule. 'centered' is an explicitly different offline mode.
    """
    h, w = a.shape[:2]
    pad = [(2, 0) if layout == "raster" else (1, 1), (1, 1)]
    pad += [(0, 0)] * (a.ndim - 2)
    p = np.pad(a, pad, mode="edge")
    return [p[y:y+h, x:x+w] for y in range(3) for x in range(3)]


def white_balance(rgb, gains):
    a = rgb.astype(np.int32)
    return np.minimum(255, (a * np.asarray(gains, dtype=np.int32) + 128) >> 8).astype(np.uint8)


def gamma_correct(rgb, strength, lut):
    a = rgb.astype(np.int32)
    delta = np.asarray(lut, dtype=np.int32)[a] - a
    return (a + ((delta * strength + 128) >> 8)).astype(np.uint8)


def grayscale(rgb):
    a = rgb.astype(np.int32)
    return ((54*a[..., 0] + 183*a[..., 1] + 19*a[..., 2] + 128) >> 8).astype(np.uint8)


def gaussian(a, layout):
    p = windows(a.astype(np.int32), layout)
    total = p[0] + p[2] + p[6] + p[8] + 2*(p[1]+p[3]+p[5]+p[7]) + 4*p[4]
    return ((total + 8) >> 4).astype(np.uint8)


def gradient(rgb, layout):
    p = windows(rgb.astype(np.int32), layout)
    gx = p[2] + 2*p[5] + p[8] - p[0] - 2*p[3] - p[6]
    gy = p[0] + 2*p[1] + p[2] - p[6] - 2*p[7] - p[8]
    mags = np.abs(gx) + np.abs(gy)
    # np.argmax picks R, then G, then B on ties, as the RTL ternaries do.
    channel = mags.argmax(axis=-1)[..., None]
    magnitude = np.take_along_axis(mags, channel, axis=-1)[..., 0]
    dx = np.take_along_axis(gx, channel, axis=-1)[..., 0]
    dy = np.take_along_axis(gy, channel, axis=-1)[..., 0]
    ax, ay = np.abs(dx), np.abs(dy)
    horizontal = ay*256 <= ax*106
    vertical = ax*256 <= ay*106
    direction = np.where(horizontal, 0, np.where(vertical, 2, np.where((dx < 0) == (dy < 0), 1, 3)))
    return magnitude.astype(np.uint16), direction.astype(np.uint8)


def nonmaximum(magnitude, direction, layout):
    p = windows(magnitude, layout)
    d = windows(direction, layout)[4]
    a = np.select([d == 0, d == 1, d == 2], [p[3], p[2], p[1]], default=p[0])
    b = np.select([d == 0, d == 1, d == 2], [p[5], p[6], p[7]], default=p[8])
    return np.where((p[4] != 0) & (p[4] >= a) & (p[4] >= b), p[4], 0).astype(np.uint16)


def classify(magnitude, low, high):
    return np.where((magnitude == 0) | (magnitude < low), 0,
                    np.where(magnitude >= high, 2, 1)).astype(np.uint8)


def hysteresis(classes, layout):
    p = windows(classes, layout)
    strong_neighbor = np.logical_or.reduce([p[i] == 2 for i in (0, 1, 2, 3, 5, 6, 7, 8)])
    return np.where((p[4] == 2) | ((p[4] == 1) & strong_neighbor), 255, 0).astype(np.uint8)


def median_filter(gray, layout, enabled):
    p = windows(gray, layout)
    # image5's disabled path still takes p22, retaining exactly one window.
    return np.partition(np.stack(p), 4, axis=0)[4] if enabled else p[4].copy()


def prune_edges(edges, layout, enabled):
    p = windows(edges != 0, layout)
    count = sum(p[i].astype(np.uint8) for i in (0, 1, 2, 3, 5, 6, 7, 8))
    return np.where(p[4] & ((count >= 2) if enabled else True), 255, 0).astype(np.uint8)


def convert(rgb, config, lut):
    config.validate()
    if rgb.ndim != 3 or rgb.shape[2] != 3 or rgb.dtype != np.uint8:
        raise ValueError("Expected HxWx3 RGB uint8 pixels")
    balanced = white_balance(rgb, config.wb)
    corrected = gamma_correct(balanced, config.gamma_strength, lut) if config.gamma else balanced
    gray = grayscale(corrected)
    median = median_filter(gray, config.layout, config.median) if config.pipeline == "image5" else gray
    canny_rgb = np.repeat(median[..., None], 3, axis=-1) if config.mode == "gray" else corrected
    smooth = gaussian(canny_rgb, config.layout)
    mag, direction = gradient(smooth, config.layout)
    nms = nonmaximum(mag, direction, config.layout)
    classes = classify(nms, config.low, config.high)
    raw = hysteresis(classes, config.layout)
    prune1 = prune_edges(raw, config.layout, config.cleanup) if config.pipeline == "image5" else raw
    prune2 = prune_edges(prune1, config.layout, config.cleanup) if config.pipeline == "image5" else raw
    edges = prune2.copy()
    if config.pipeline == "image5":
        edges[:config.top_guard] = 0
        edges[max(0, edges.shape[0]-2):] = 0
        edges[:, :2] = 0
        edges[:, max(0, edges.shape[1]-2):] = 0
    return {"white_balance": balanced, "gamma": corrected, "gray": gray,
            "median": median,
            "gaussian": smooth, "magnitude": mag, "direction": direction,
            "nms": nms, "classes": classes, "raw_edges": raw,
            "prune1": prune1, "prune2": prune2, "edges": edges}


def preview(rgb, gray, edges, destination, label):
    panel_width = min(480, rgb.shape[1])
    panel_height = max(1, round(rgb.shape[0]*panel_width/rgb.shape[1]))
    canvas = Image.new("RGB", (3*panel_width, panel_height+52), "#202830")
    draw = ImageDraw.Draw(canvas)
    for i, (name, pixels) in enumerate((("RGB input", rgb), ("FPGA gray", gray), ("Canny edges", edges))):
        im = Image.fromarray(pixels).convert("RGB")
        im = im.resize((panel_width, panel_height), Image.Resampling.NEAREST)
        canvas.paste(im, (i*panel_width, 52))
        draw.text((i*panel_width+8, 8), name, fill="white")
    draw.text((8, 30), label, fill="white")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)


def demo_image():
    """Synthetic diagnostic, not a real person or a training sample."""
    im = Image.new("RGB", (640, 360), (35, 42, 58))
    d = ImageDraw.Draw(im)
    d.rectangle((20, 25, 200, 180), fill=(195, 35, 35))
    d.rectangle((200, 25, 380, 180), fill=(35, 92, 35))
    d.ellipse((435, 25, 565, 155), fill=(205, 175, 135))
    d.rounded_rectangle((420, 150, 580, 300), radius=24, fill=(30, 160, 190))
    d.line((430, 185, 380, 245, 350, 200), fill=(205, 175, 135), width=22)
    d.line((565, 185, 600, 120, 590, 65), fill=(205, 175, 135), width=22)
    d.line((455, 290, 440, 350), fill=(65, 100, 190), width=24)
    d.line((540, 290, 560, 350), fill=(65, 100, 190), width=24)
    for x in range(25, 350, 13):
        d.line((x, 220, x+25, 340), fill=(95, 105, 115), width=2)
    return np.array(im)


def main():
    profile_parser = argparse.ArgumentParser(add_help=False)
    profile_parser.add_argument("--profile", type=Path, default=PROFILE_PATH)
    preliminary, _ = profile_parser.parse_known_args()
    profile = load_profile(preliminary.profile)
    defaults = profile["defaults"]
    p = argparse.ArgumentParser(description=__doc__, parents=[profile_parser])
    inputs = p.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--input", type=Path, help="One image or a directory scanned recursively")
    inputs.add_argument("--demo", action="store_true", help="Generate a local synthetic RGB diagnostic")
    p.add_argument("--output", type=Path, required=True, help="Separate output folder")
    p.add_argument("--mode", choices=("gray", "color"), default=defaults["mode"])
    p.add_argument("--low", type=int, default=defaults["low"])
    p.add_argument("--high", type=int, default=defaults["high"])
    p.add_argument("--wb", nargs=3, type=int, default=defaults["wb"], metavar=("R", "G", "B"))
    p.add_argument("--gamma", action=argparse.BooleanOptionalAction, default=defaults["gamma"])
    p.add_argument("--gamma-strength", type=int, default=defaults["gamma_strength"])
    p.add_argument("--layout", choices=("raster", "centered"), default=defaults["layout"])
    p.add_argument("--pipeline", choices=("image5", "canny-core"), default=defaults["pipeline"])
    p.add_argument("--median", action=argparse.BooleanOptionalAction, default=defaults["median"], help="image5 M switch")
    p.add_argument("--cleanup", action=argparse.BooleanOptionalAction, default=defaults["cleanup"], help="image5 D switch")
    p.add_argument("--top-guard", type=int, default=defaults["top_guard"])
    p.add_argument("--single-channel", action="store_true", help="Save L PNG instead of replicated RGB PNG")
    p.add_argument("--save-stages", action="store_true", help="Save intermediate PNG and raw arrays")
    p.add_argument("--preview-count", type=int, default=5)
    p.add_argument("--overwrite", action="store_true", help="Replace generated files; never removes a directory")
    p.add_argument("--fpga-root", type=Path, help="Verify that RTL hashes still match the profile snapshot")
    args = p.parse_args()
    config = Config(args.mode, args.low, args.high, tuple(args.wb), args.gamma, args.gamma_strength, args.layout,
                    args.pipeline, args.median, args.cleanup, args.top_guard)
    config.validate()
    if args.preview_count < 0:
        p.error("--preview-count must be nonnegative")
    if args.fpga_root:
        for relative, expected in profile["source_sha256"].items():
            actual = hashlib.sha256((args.fpga_root/relative).read_bytes()).hexdigest()
            if actual != expected:
                p.error(f"RTL snapshot changed: {relative}. Review profile before conversion.")
    out = args.output.resolve()
    source = args.input.resolve() if args.input else None
    if source and not source.exists():
        p.error(f"Input does not exist: {source}")
    if source and (source == out or source.is_relative_to(out) or (source.is_dir() and out.is_relative_to(source))):
        p.error("Input and output trees must be separate; output may not contain input")
    if out.exists() and any(out.iterdir()) and not args.overwrite:
        p.error("Output folder is not empty. Choose a new folder or explicitly use --overwrite")
    if args.demo:
        items = [(None, Path("demo.png"))]
    else:
        candidates = [source] if source.is_file() else sorted(source.rglob("*"))
        items = [(f, (Path(f.name) if source.is_file() else f.relative_to(source)).with_suffix(".png"))
                 for f in candidates if f.is_file() and f.suffix.lower() in EXTENSIONS]
    if not items:
        p.error("No supported images found")
    # A.jpg and A.bmp would otherwise silently overwrite A.png.
    keys = [str(rel).casefold() for _, rel in items]
    if len(keys) != len(set(keys)):
        p.error("Input images have colliding PNG output names (same stem, different extension)")
    out.mkdir(parents=True, exist_ok=True)
    report = {"config": asdict(config), "profile": profile, "results": [], "errors": [],
              "notes": "Offline pixel arithmetic, not clock-cycle/HDMI/ISP simulation. No labels copied. Raster layout has nominal +7 row feature delay for image5 (+4 for canny-core); centered is not the literal RTL raster."}
    print(f"pipeline={config.pipeline} mode={config.mode} low={config.low} high={config.high} M={int(config.median)} D={int(config.cleanup)} WB={config.wb} gamma={config.gamma}/{config.gamma_strength} layout={config.layout}")
    if config.layout == "raster":
        delay = 7 if config.pipeline == "image5" else 4
        print(f"NOTE: native RTL windows retain ~{delay} rows of feature delay; do not blindly copy original detection labels.")
    for index, (path, relative) in enumerate(items):
        try:
            if path is None:
                rgb = demo_image()
            else:
                with Image.open(path) as im:
                    # Preserve stored pixel geometry, including EXIF orientation.
                    # No rotation, resize, crop or per-file auto contrast.
                    rgb = np.array(im.convert("RGB"))
            stages = convert(rgb, config, profile["gamma_lut"])
            edge = stages["edges"]
            destination = out/"images"/relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            pixels = edge if args.single_channel else np.repeat(edge[..., None], 3, axis=2)
            Image.fromarray(pixels).save(destination)
            if index < args.preview_count:
                preview(rgb, stages["gray"], edge, out/"previews"/relative,
                        f"{config.pipeline}, L={config.low}, H={config.high}, M={int(config.median)}, D={int(config.cleanup)}, {config.layout}")
            if args.demo:
                Image.fromarray(rgb).save(out/"demo_rgb.png")
            if args.save_stages:
                stage_dir = out/"stages"/relative.with_suffix("")
                stage_dir.mkdir(parents=True, exist_ok=True)
                np.savez_compressed(stage_dir/"raw_stages.npz", **stages)
                for name in ("gray", "white_balance", "gamma", "median", "gaussian", "magnitude", "nms", "classes", "raw_edges", "prune1", "prune2", "edges"):
                    a = stages[name]
                    if name in {"magnitude", "nms"}:
                        a = np.minimum(255, a.astype(np.uint32)*255//2047).astype(np.uint8)
                    elif name == "classes":
                        a = np.asarray([0, 127, 255], dtype=np.uint8)[a]
                    Image.fromarray(a).save(stage_dir/(name+".png"))
            report["results"].append({"input": str(path) if path else "synthetic demo",
                                      "output": str(destination), "width": edge.shape[1], "height": edge.shape[0],
                                      "edge_pixels": int(np.count_nonzero(edge)),
                                      "edge_percent": round(float(np.count_nonzero(edge)/edge.size*100), 4)})
            if index < 5 or (index+1) % 100 == 0 or index+1 == len(items):
                print(f"[{index+1}/{len(items)}] {relative} -> {destination}")
        except (OSError, ValueError) as exc:
            report["errors"].append({"input": str(path), "error": str(exc)})
            print(f"ERROR {path}: {exc}", file=sys.stderr)
    (out/"manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"Done: {len(report['results'])} converted, {len(report['errors'])} failed. Report: {out/'manifest.json'}")
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
