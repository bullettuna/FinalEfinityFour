"""Create the single FAT32 boot file; never accesses a card or programs Flash."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zlib

ROOT=Path(__file__).resolve().parents[1]


def prepare(output):
    model=(ROOT/'tmp/image6_parameters/model.bin').read_bytes()
    image=(ROOT/'work_sim/pose6_pipeline/trace/input.u16').read_bytes()
    points,icrc,hcrc=(ROOT/'work_sim/pose6_pipeline/expected.vec').read_text().split()
    mc=zlib.crc32(model);ic=zlib.crc32(image);hc=int(hcrc,16);pb=int(points,16).to_bytes(24,'little')
    if len(model)!=161440 or mc!=0xbbffdf52 or len(image)!=73728 or ic!=int(icrc,16):
        raise ValueError('Frozen model/test vector identity mismatch')
    header=struct.pack('<8sIIIII24sII',b'I6POSE01',len(model),len(image),mc,ic,hc,pb,1,0)
    assert len(header)==60
    header+=struct.pack('<I',zlib.crc32(header))
    payload=header+model+image
    output.mkdir(parents=True,exist_ok=True)
    (output/'MODEL6.BIN').write_bytes(payload)
    identity=(f'localparam POSE6_BOOT_BYTES={len(payload)};\n'
              f"localparam [31:0] POSE6_TEST_INPUT_CRC=32'h{ic:08x};\n"
              f"localparam [31:0] POSE6_TEST_HEATMAP_CRC=32'h{hc:08x};\n"
              f"localparam [191:0] POSE6_TEST_POINTS=192'h{points};\n")
    (ROOT/'images/image6_pose_int16/pose6_boot_identity.vh').write_text(identity,encoding='ascii')
    manifest=dict(file='MODEL6.BIN',bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),
                  model_bytes=len(model),model_crc32=f'{mc:08x}',input_bytes=len(image),input_crc32=f'{ic:08x}',
                  heatmap_crc32=f'{hc:08x}',points_hex=points,format='I6POSE01 / 64-byte header + frozen weights + fixed self-test input')
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,default=ROOT/'tmp/image6_standalone/sdcard')
    prepare(p.parse_args().output)
