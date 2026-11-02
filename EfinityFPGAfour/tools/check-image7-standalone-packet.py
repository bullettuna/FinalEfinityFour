"""Offline standalone simulation result checker; does not access hardware."""
import importlib.util
from pathlib import Path
import argparse
p=argparse.ArgumentParser();p.add_argument('--capture',type=Path,required=True);a=p.parse_args()
spec=importlib.util.spec_from_file_location('image7_packet',Path(__file__).with_name('check-image7-packet.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.check(a.capture,live=True)
