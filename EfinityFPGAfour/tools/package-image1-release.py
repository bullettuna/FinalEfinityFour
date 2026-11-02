"""Package an image1 build only after constrained timing and pad checks pass."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "images/image1_vision"
OUT = PROFILE / "outflow"
RELEASE = ROOT / "releases/image1"
NAME = "Ti60_Image1_Vision"
subprocess.run([sys.executable, str(ROOT / "tools/check-image1-inputs.py"), "--reports"], check=True)
text = (OUT / f"{NAME}.timing.rpt").read_text(encoding="utf-8-sig")
summary = text.split("Setup (Max) Clock Relationship", 1)[1].split("Clock Relationship Summary (end)", 1)[0]
setup, hold = summary.split("Hold (Min) Clock Relationship", 1)

def relationships(section):
    return [dict(launch=a, capture=b, constraint=float(c), slack=float(d))
            for a, b, c, d in re.findall(
                r"(?m)^\s+(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)", section)]

timing = dict(setup=relationships(setup), hold=relationships(hold))
assert len(timing["setup"]) == len(timing["hold"]) == 14, "Incomplete timing report"
assert all(r["slack"] >= 0 for rows in timing.values() for r in rows), "Timing violation"
bit = OUT / f"{NAME}_checked.bit"
assert bit.read_bytes() == (OUT / f"{NAME}.bit").read_bytes(), "Unqualified/stale checked bit"
assert bit.stat().st_mtime >= (OUT / f"{NAME}.timing.rpt").stat().st_mtime, "Stale checked bit"
manifest_path = RELEASE / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
paths = set(manifest["source_files"]) | {
    "images/image1_vision/p4-inputs.json", "images/image1_vision/board-domains.sdc"}
manifest["project_xml_ignored_attributes"] = ["last_change"]
def normalized_source(path):
    data = (ROOT / path).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    if path == "images/image1_vision/Ti60_Image1_Vision.xml":
        element = ET.fromstring(data)
        element.attrib.pop("last_change", None)
        return ET.tostring(element, encoding="utf-8")
    return data.encode("utf-8")
manifest["source_files"] = {
    path: hashlib.sha256(normalized_source(path)).hexdigest() for path in sorted(paths)}
manifest["source_base_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
manifest["built_at"] = datetime.fromtimestamp(bit.stat().st_mtime).astimezone().isoformat()
manifest["timing"] = timing
manifest["hardware_inputs"] = json.loads((PROFILE / "p4-inputs.json").read_text(encoding="utf-8"))
manifest["board_validation"] = "P4 ADC/buttons: source, actual pad report, simulation and static timing checked; physical board test pending."
tree = ET.parse(PROFILE / f"{NAME}.xml")
recipe = {e.get("name"): e.get("value") for e in tree.iter() if e.tag.endswith("param")}
manifest["recipe"] = dict(optimization=recipe["optimization_level"], seed=int(recipe["seed"]), effort=int(recipe["placer_effort_level"]))
hierarchy = (OUT / f"{NAME}-hierarchical_stats.rpt").read_text(encoding="utf-8-sig")
top = next(line for line in hierarchy.splitlines() if re.match(r"^\|\s+\+image1_top\s+\|", line))
fields = top.split("|")
manifest["resources"] = {key: int(re.search(r"\d+", fields[index]).group())
                         for key, index in [("PNR_XLR", 2), ("RAM10", 3), ("DSP", 4)]}
manifest["artifacts"] = {}
for name in [f"{NAME}_checked.bit", f"{NAME}.hex"]:
    src = OUT / name
    shutil.copyfile(src, RELEASE / name)
    data = src.read_bytes()
    manifest["artifacts"][name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"PASS packaged image1 P4 release: {len(paths)} source/config files; 28 setup/hold relationships")
