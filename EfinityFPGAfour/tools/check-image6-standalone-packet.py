"""Check the real standalone RTL's resumed USB packet with production parsers."""
from pathlib import Path
import argparse
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'FPGA_GAME'))
from ft232h_source import FrameParser
from fpga_points import decode_points

p=argparse.ArgumentParser();p.add_argument('--capture',required=True,type=Path);a=p.parse_args()
frames=FrameParser().feed(a.capture.read_bytes())
assert len(frames)==1
r=decode_points(frames[0])
points,ic,hc=(Path(__file__).resolve().parents[1]/'work_sim/pose6_pipeline/expected.vec').read_text().split()
assert r.valid and not r.flags&8 and r.input_crc==int(ic,16) and r.heatmap_crc==int(hc,16)
assert frames[0].payload[20:]==int(points,16).to_bytes(24,'little')
print('PASS standalone RTL USB packet: production frame/CRC/point parser, exact oracle, live flag, immutable packet after backpressure')
