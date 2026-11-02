"""The original C++ identify_pose supplies all five IoU scores independently."""
import json
import subprocess
import sys
from pathlib import Path
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location("exporter", Path(__file__).with_name("export-pose-templates.py"))
exporter = module_from_spec(spec)
spec.loader.exec_module(exporter)
cpp, out = map(Path, sys.argv[1:])
reference_dir = Path(__file__).resolve().parent.parent / 'samples/pose_upper'
templates = [exporter.normalize(reference_dir / f"pose{p}.pgm") for p in range(1, 6)]
boundaries = list(map(exporter.boundary, templates))
cases = [(mask, [1]*4096, True, True, 0) for mask in templates]
cases += [([1]*4096, [1]*4096, True, True, 0),
          ([0]*4096, [0]*4096, False, True, 0),
          (templates[2], [0]*4096, True, True, 0),
          (templates[2], [1]*4096, True, False, 0),
          (templates[4], [1]*4096, True, True, 137)]
# Mixed poses and deterministic holes exercise partial scores and ambiguity.
cases += [([templates[0][i] | templates[p][i] for i in range(4096)], [1]*4096, True, True, 0) for p in range(1, 5)]
cases += [([templates[1][i] and i % 13 != 0 for i in range(4096)], [1]*4096, True, True, 0),
          (templates[1], boundaries[1], True, True, 0)]
cases = [(*case, 64, 64) for case in cases]
cases += [(templates[1][:48], [1]*48, True, True, 17, 8, 6),
          ([1, 0, 1, 1, 1, 0], [1]*6, True, True, 23, 2, 3)]
# Supplementary photographs were not used as primary ROM templates. Photos
# 2/3/6 have clipped hands, so these check numerical agreement, not accuracy.
photo_checks = sorted((reference_dir.parent / 'pose_photo/validation').glob('*.pgm'))
assert len(photo_checks) == 5
for path in photo_checks:
    w, h, pixels = exporter.read_pgm(path)
    assert (w, h) == (64, 64)
    cases.append(([int(p <= 127) for p in pixels], [1]*4096, True, True, 0, 64, 64))
vectors, expected, counts = [], [], []
evidence = []
for n, (mask, edges, valid, edge_valid, offset, width, height) in enumerate(cases):
    source = out / f"case{n}.pgm"
    source.write_bytes(f"P5\n{width} {height}\n255\n".encode() + bytes(0 if x else 255 for x in mask))
    oracle = subprocess.run([str(out / "cpp_oracle.exe"), str(source), str(reference_dir)], check=True, capture_output=True, text=True).stdout
    rows = [list(map(int, row.split())) for row in oracle.splitlines()]
    best_pose, best, second = rows[0]
    # Empty C++ input returns before scoring. Its default best_pose is zero.
    template_index = max(0, best_pose-1)
    edge_count = sum(boundaries[template_index])
    normalized_edges = [edges[((2*y+1)*height//128)*width+(2*x+1)*width//128] for y in range(64) for x in range(64)]
    hits = sum(a and b for a,b in zip(normalized_edges, boundaries[template_index]))
    support = (1000*hits+edge_count//2)//edge_count
    pose = best_pose if valid and edge_valid and best>=550 and best-second>=80 and support>=200 else 0
    if not valid: best, second, support = 0, 0, 0
    vectors.extend(f"{int(mask[y*width+x]) | int(edges[y*width+x])<<1:x}" if x<width and y<height else "0"
                   for y in range(64) for x in range(64))
    expected.extend(f"{value:08x}" for value in (pose,best,best-second,support,int(valid),int(edge_valid),offset,width,height))
    counts.extend(f"{value:08x}" for row in rows[1:] for value in row)
    evidence.append({"case": n, "pose": pose, "score": best, "margin": best-second,
                     "edge": support, "cpp_scores": rows[1:]})
    if n >= 18:
        evidence[-1]['source_photo_mask'] = photo_checks[n-18].name
(out / "vectors.mem").write_text("\n".join(vectors)+"\n")
(out / "expected.mem").write_text("\n".join(expected)+"\n")
(out / "counts.mem").write_text("\n".join(counts)+"\n")
(out / "oracle-results.json").write_text(json.dumps(evidence, indent=2)+"\n")
# The snapshot selector remeasures the occupied bounds of its input. A source
# mask normalized to 64x64 need not occupy all 64 rows (pose 2 occupies 63).
# Independently score the resulting tight crop with C++, not a perfect-score
# assumption or the RTL itself.
snapshot_expected = []
for p, mask in enumerate(templates):
    xs = [i % 64 for i, pixel in enumerate(mask) if pixel]
    ys = [i // 64 for i, pixel in enumerate(mask) if pixel]
    xmin, xmax, ymin, ymax = min(xs), max(xs), min(ys), max(ys)
    w, h = xmax-xmin+1, ymax-ymin+1
    crop = [mask[y*64+x] for y in range(ymin, ymax+1) for x in range(xmin, xmax+1)]
    path = out / f"snapshot_pose{p+1}.pgm"
    path.write_bytes(f"P5\n{w} {h}\n255\n".encode()+bytes(0 if v else 255 for v in crop))
    result = subprocess.run([str(out / 'cpp_oracle.exe'), str(path), str(reference_dir)],
                            check=True, capture_output=True, text=True).stdout
    pose, best, second = map(int, result.splitlines()[0].split())
    assert pose == p+1 and best >= 550 and best-second >= 80
    snapshot_expected.extend(f"{v:08x}" for v in (pose, best, best-second, xmin, ymin, xmax, ymax))
(out / 'snapshot_expected.mem').write_text('\n'.join(snapshot_expected)+'\n')
print(f"PASS {len(cases)} test vectors and C++ reference executions generated")
