"""Offline RTL byte-stream oracle; no USB access and no PC receiver app."""
from pathlib import Path
import argparse
import struct
import zlib

ROOT=Path(__file__).resolve().parents[1]


def check(capture, live=False):
    raw=Path(capture).read_bytes()
    assert len(raw)==114, f'Expected one complete atomic 114-byte packet, got {len(raw)}'
    assert raw[:8]==b'FT5!\x02\x05\x00\x18', 'Version/kind must distinguish eleven-point results'
    sequence,width,height,size=struct.unpack_from('<IHHI',raw,8)
    assert (sequence,width,height,size)==(0,640,360,86)
    assert struct.unpack_from('<I',raw,20)[0]==zlib.crc32(raw[:20]), 'Header CRC'
    payload=raw[24:110]
    assert struct.unpack_from('<I',raw,110)[0]==zlib.crc32(payload), 'Payload CRC'
    assert payload[:2]==bytes([2,11]) and payload[3]==0
    flags=payload[2]
    assert flags&3==3 and not flags&4
    if live:
        assert not flags&8
        expected,ic,hc=(ROOT/'work_sim/pose7_pipeline/expected.vec').read_text().split()
        assert payload[20:]==int(expected,16).to_bytes(66,'little')
        cycles,mc,icrc,hcrc=struct.unpack_from('<IIII',payload,4)
        assert cycles>0 and mc==0x1f704b5e and icrc==int(ic,16) and hcrc==int(hc,16)
    else:
        assert flags==0x0b
        assert struct.unpack_from('<IIII',payload,4)==(1234,0xbbffdf52,0x11223344,0x55667788)
        for i in range(11):
            assert struct.unpack_from('<HHH',payload,20+i*6)==(400+i*40,800+i*20,40000+i)
    print('PASS image7 eleven-point packet: exact coordinates/metadata, version, length, both CRCs, immutable data under backpressure')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture',type=Path,required=True);p.add_argument('--live',action='store_true')
    a=p.parse_args();check(a.capture,a.live)
