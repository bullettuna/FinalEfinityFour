"""Retain verified clock-domain constraints after pad/voltage regeneration."""
from pathlib import Path
import argparse

root = Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument("--profile",default="image1_vision");a.add_argument("--project",default="Ti60_Image1_Vision");args=a.parse_args()
profile = root / "images" / args.profile
sdc = profile / (args.project+".pt.sdc")
text = sdc.read_text(encoding="utf-8-sig")
domains = (profile / "board-domains.sdc").read_text(encoding="utf-8-sig")
missing = [line for line in domains.splitlines() if line.startswith("set_") and line not in text]
if missing:
    text += "\n# Retained image1 clock-domain constraints\n" + "\n".join(missing) + "\n"
    sdc.write_text(text, encoding="utf-8")
assert "create_clock -period 6.720 -name clk_pixel_2x" in text
print(f"PASS image1 generated pad timing and verified clock-domain constraints ({len(missing)} restored)")
