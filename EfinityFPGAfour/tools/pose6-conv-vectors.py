"""Build all-layer golden vectors with the integer oracle (no float Conv)."""
import argparse
from pathlib import Path
import shutil
import sys
import json
import zlib


def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
    p.add_argument('--model-root',type=Path,default=Path('E:/Efinity_Project/FPGA_GAME'))
    a=p.parse_args();sys.path.insert(0,str(a.model_root))
    import numpy as np
    from fourpoint.fpga_integer import infer,export,decode,DEFAULT_GRAPH,DEFAULT_DATA
    from fourpoint.preprocess import or_resize
    from PIL import Image
    a.output.mkdir(parents=True,exist_ok=True)
    params=a.output/'parameters';contract=export(DEFAULT_GRAPH,params)
    images=np.load(DEFAULT_DATA/'or256/val/images.npy',mmap_mode='r')
    heatmaps=infer(images[0],params,contract,trace=a.output/'trace')
    record=json.loads((DEFAULT_DATA/'val/records.jsonl').read_text(encoding='utf-8').splitlines()[0])
    capture=np.asarray(Image.open(record['source']).convert('L'))
    if capture.shape!=(360,640):raise ValueError('expected image5 native capture geometry')
    np.testing.assert_array_equal(or_resize(capture,256,144),images[0])
    capture.astype('u1').tofile(a.output/'capture640.bin')
    xy=decode(heatmaps)
    packed=0
    for c,(x,y) in enumerate(xy):
        packed|=(int(round(x*4))|(int(round(y*4))<<16)|(int(heatmaps[:,:,c].max())<<32))<<(48*c)
    input_bytes=(np.asarray(images[0]>0,dtype='<u2')*65535).tobytes()
    (a.output/'expected.vec').write_text(f'{packed:048x} {zlib.crc32(input_bytes):08x} {zlib.crc32(heatmaps.astype("<u2").tobytes()):08x}\n')
    shutil.copyfile(params/'weights_lanes16.bin',a.output/'model.bin')
    rows=[]
    for i,s in enumerate(contract['stages']):
        rows.append(f'{i} {s["source_address"]:x} {s["output_address"]:x} trace/{s["source"]}.u16 trace/{s["id"]}.u16')
    (a.output/'stages.vec').write_text('\n'.join(rows)+'\n')
    print('Generated ten exact integer-convolution stages, including both dilation factors and asymmetric concat input')


if __name__=='__main__':main()
