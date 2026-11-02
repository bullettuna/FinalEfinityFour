"""Export manually annotated photographic upper-body silhouettes.

Source masks already exclude head/legs. Keep the exact C++/RTL largest-component
and pixel-center normalization; never thicken a skeleton to make a silhouette.
"""
import argparse
import hashlib
import json
from collections import deque
from pathlib import Path


def read_pgm(path):
    data = path.read_bytes()
    pos, tokens = 0, []
    while len(tokens) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos] == 35:
            pos = data.index(b"\n", pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        tokens.append(data[pos:end])
        pos = end
    assert tokens[0] == b"P5" and tokens[3] == b"255"
    pos += 2 if data[pos:pos + 2] == b"\r\n" else 1
    w, h = map(int, tokens[1:3])
    pixels = data[pos:]
    assert len(pixels) == w * h
    return w, h, pixels


def largest_component(w, h, pixels):
    todo = {i for i, p in enumerate(pixels) if p <= 127}
    largest = set()
    # Scan order matches keep_largest_component's strict 'larger than' tie rule.
    for seed in range(w * h):
        if seed not in todo:
            continue
        todo.remove(seed)
        q, component = deque([seed]), {seed}
        while q:
            i = q.popleft()
            x, y = i % w, i // w
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    j = ny * w + nx
                    if 0 <= nx < w and 0 <= ny < h and j in todo:
                        todo.remove(j)
                        component.add(j)
                        q.append(j)
        if len(component) > len(largest):
            largest = component
    assert largest, "Empty reference"
    return largest


def normalize_component(w, largest):
    xmin, xmax = min(i % w for i in largest), max(i % w for i in largest)
    ymin, ymax = min(i // w for i in largest), max(i // w for i in largest)
    result = [int((ymin + (2*y+1)*(ymax-ymin+1)//128)*w +
                  xmin + (2*x+1)*(xmax-xmin+1)//128 in largest)
              for y in range(64) for x in range(64)]
    return result


def normalize(path):
    w, h, pixels = read_pgm(path)
    return normalize_component(w, largest_component(w, h, pixels))


def boundary(mask):
    return [int(mask[y*64+x] and any(
        not (0 <= x+dx < 64 and 0 <= y+dy < 64) or not mask[(y+dy)*64+x+dx]
        for dy in (-1, 0, 1) for dx in (-1, 0, 1)))
        for y in range(64) for x in range(64)]


def main():
    parser = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    parser.add_argument("samples", type=Path, nargs="?", default=root / "samples/pose_photo")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    annotation_path = args.samples / 'annotations.json'
    annotations = json.loads(annotation_path.read_text(encoding='utf-8'))
    assert sorted(s['pose'] for s in annotations['samples']) == list(range(1, 6))
    assert all(not s['hand_clipped_in_source'] for s in annotations['samples']), 'Clipped primary hand'
    sources = [args.samples / f"pose{i}.pgm" for i in range(1, 6)]
    masks = [normalize(path) for path in sources]
    edges = list(map(boundary, masks))
    lines = ["// Photographic upper-body silhouettes, photos 7/8/10/9/4; bit p = pose p+1.",
             "// Low five bits: filled mask. High five bits: 8-neighbor boundary.", "initial begin"]
    for i in range(4096):
        value = sum((masks[p][i] | edges[p][i] << 5) << p for p in range(5))
        lines.append(f"    template_rom[{i}] = 10'h{value:03x};")
    lines.append("end")
    manifest = {"profile": "photo-upper-v1: torso and both arms; no head/neck or legs",
                "input_framing": "neck/shoulders through waist, both arms and hands in frame",
                "method": annotations['method'],
                "annotation_sha256": hashlib.sha256(annotation_path.read_bytes()).hexdigest(),
                "mapping_image_sides": annotations['mapping_image_sides'],
                "normalization": "64x64 nearest center, tight largest 8-connected mask, dark<=127",
                "samples": [{"pose": p+1, "sha256": hashlib.sha256(
                    sources[p].read_bytes()).hexdigest(),
                    "foreground": sum(masks[p]), "boundary": sum(edges[p]),
                    "photo": int(annotations['primary_photo_for_pose'][str(p+1)]),
                    "photo_sha256": next(s['source_sha256'] for s in annotations['samples'] if s['pose']==p+1)
                    } for p in range(5)]}
    outputs = {root / "src/vision/pose_templates.vh": "\n".join(lines) + "\n",
               root / "docs/pose-template-manifest.json": json.dumps(manifest, indent=2) + "\n"}
    for path, content in outputs.items():
        if args.check:
            assert path.read_text() == content, f"Stale template: {path}"
        else:
            path.write_text(content, encoding="ascii")
    fixture_dir = root / 'samples/pose_upper'
    if not args.check:
        fixture_dir.mkdir(parents=True, exist_ok=True)
    for i, source in enumerate(sources,1):
        pgm = source.read_bytes()
        path = fixture_dir/f'pose{i}.pgm'
        if args.check:
            assert path.read_bytes() == pgm, f"Stale upper-body reference {path}"
        else:
            path.write_bytes(pgm)
    print("PASS five photographic upper-body references and ROM exported/verified")


if __name__ == "__main__":
    main()
