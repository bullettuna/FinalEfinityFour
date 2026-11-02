import argparse
from pathlib import Path
import sys

p=argparse.ArgumentParser();p.add_argument('--capture',type=Path,required=True);a=p.parse_args()
sys.path.insert(0,'E:/Efinity_Project/FPGA_GAME')
from ft232h_source import FrameParser
from fpga_points import decode_points
parser=FrameParser();frames=parser.feed(a.capture.read_bytes())
assert len(frames)==1 and not parser.bad_headers and not parser.bad_payloads
r=decode_points(frames[0]);assert r.valid and r.flags==11 and r.cycles==1234
assert r.input_crc==0x11223344 and r.heatmap_crc==0x55667788
assert r.points==tuple((100+i*10,200+i*5) for i in range(4))
print('PASS RTL packet decoded by production PC parser, both CRCs and latched four-point result preserved')
