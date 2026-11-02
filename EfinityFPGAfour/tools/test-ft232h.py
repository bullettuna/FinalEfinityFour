"""Independent PC/RTL packet and image oracles. Run from repository root."""
import argparse
import importlib.util
from pathlib import Path
import random
import struct
import sys
import zlib
import ctypes
import types
import time
from unittest import mock

spec=importlib.util.spec_from_file_location('receiver',Path(__file__).with_name('ft232h_receive.py'))
rx=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=rx
spec.loader.exec_module(rx)

def packet(kind,seq,w,h,payload):
    h20=struct.pack('<4sBBBBIHHI',b'FT5!',1,kind,0,24,seq,w,h,len(payload))
    return h20+struct.pack('<I',zlib.crc32(h20))+payload+struct.pack('<I',zlib.crc32(payload))

def self_test():
    original=packet(0,0,0,0,bytes(range(256))*16)
    bad_header=bytearray(original);bad_header[12]^=1
    bad_data=bytearray(original);bad_data[-7]^=1
    following=packet(0,1,0,0,bytes(range(256))*16)
    data=b'noiseFT'+bad_header+bad_data+original+following
    parser=rx.Parser();frames=[];rng=random.Random(5);offset=0
    while offset<len(data):
        size=rng.randint(1,97);frames+=parser.feed(data[offset:offset+size]);offset+=size
    assert [f.sequence for f in frames]==[0,1]
    reset_parser=rx.Parser();recovered=reset_parser.feed(original[:100]+following)
    assert len(recovered)==1 and recovered[0].sequence==1,'partial reset frame did not resynchronize'
    assert parser.bad_headers>=1 and parser.bad_payloads==1
    for f in frames:rx.check_frame(f)
    full=packet(1,0,1920,1080,bytes([71])*(1920*1080))
    pp=rx.Parser();assert len(pp.feed(full))==1,'1080p length rejected'
    packed=packet(3,2,128,16,bytes(range(256)))
    pp=rx.Parser();f=pp.feed(packed)[0]
    expected=bytes(255 if b&(1<<bit) else 0 for b in range(256) for bit in range(7,-1,-1))
    assert rx.image_bytes(f)==expected,'MSB-first decoding'
    odd=rx.Frame(3,0,9,2,b"\x80\x80\x01\x00")
    rx.check_frame(odd)
    assert rx.image_bytes(odd)==bytes(255 if (y,x) in [(0,0),(0,8),(1,7)] else 0 for y in range(2) for x in range(9))
    try: rx.check_frame(rx.Frame(3,0,9,1,b"\x00\x01"))
    except RuntimeError: pass
    else: raise AssertionError('Nonzero row padding accepted')
    pp=rx.Parser();assert not pp.feed(packet(3,0,16,1,b'abc')) and pp.bad_headers
    full_packed=packet(3,0,1920,1080,bytes([0x59])*259200)
    pp=rx.Parser();assert len(rx.image_bytes(pp.feed(full_packed)[0]))==2073600
    print('PASS PC parser: fragmented USB reads, header/payload CRC, corruption rejection, junk resynchronization and counters')

def driver_test(mode="counter",edge_format="packed"):
    trace=[]
    class Port:
        def __init__(self,*a,**kw): self.reply=b""
        def reset_input_buffer(self): pass
        def flush(self): pass
        def write(self,b):
            trace.append(('uart',b))
            self.reply={b'!V':b'A',b'!?':b'A',b'!P':b'1'}.get(b,b[1:])
        def read(self,n): return self.reply
        def close(self): trace.append(('uart_close',))
    class API:
        def __init__(self): self.seq=0;self.pending=b''
        def open(self,serial):
            assert serial=='FT_TEST';trace.append(('open',));return 123
        def call(self,name,*a):
            if name=='FT_Read':
                assert a[2]==4096
                if not self.pending:
                    payload=bytes(range(256))*16 if mode=='counter' else bytes([0x59])*28800 if edge_format=='packed' else bytes([255])*230400
                    kind=0 if mode=='counter' else 3 if edge_format=='packed' else 2
                    self.pending=packet(kind,self.seq,0 if kind==0 else 640,0 if kind==0 else 360,payload);self.seq+=1
                b=self.pending[:4096];self.pending=self.pending[len(b):]
                ctypes.memmove(a[1],b,len(b));a[3]._obj.value=len(b);time.sleep(.0004)
            else: trace.append((name,)+a)
    argv=['receiver','--transport','async','--serial','FT_TEST','--uart','UART_TEST','--fifo-eeprom-confirmed','--mode',mode,'--edge-format',edge_format,'--width','640','--seconds','.20']
    with mock.patch.object(rx,'D2XX',API),mock.patch.dict(sys.modules,{'serial':types.SimpleNamespace(Serial=Port)}),mock.patch.object(sys,'argv',argv):
        rx.main()
    u=[t[1] for t in trace if t[0]=='uart']
    start=b'!1' if mode=='counter' else b'!3' if edge_format=='packed' else b'!7'
    assert u==[b'!V']+([b'!P'] if mode=='edge' else [])+[b'!0',b'!?',b'!5',start,b'!0'],u
    modes=[t for t in trace if t[0]=='FT_SetBitMode']
    assert len(modes)==1 and modes[0][2:]==(0,0),modes
    assert trace.index(('uart',b'!0'))<trace.index(('open',))<trace.index(modes[0])
    assert trace.index(('uart',start))<len(trace)-1
    assert trace[-1][0]=='FT_Close'
    print('PASS PC async driver mock: stop before mode reset, only 0x00, 4096-byte fragmented reads, size command, CRC/sequence, stop/close')


def captures(directory):
    for mode in [1,2,3,4]:
        for res in range(1 if mode==1 else 3):
            p=rx.Parser();frames=[];data=(directory/f'async_{mode}_{res}.bin').read_bytes()
            for offset in range(0,len(data),997): frames+=p.feed(data[offset:offset+997])
            assert frames,(mode,res,'missing complete frames')
            assert p.bad_headers==p.bad_payloads==0,(mode,res,p.bad_headers,p.bad_payloads)
            assert [f.sequence for f in frames]==list(range(len(frames)))
            scale=[6,3,1][res]
            for f in frames:
                assert f.kind==([0,1,3,2][mode-1])
                rx.check_frame(f)
                if mode==2:
                    base=f.payload[0]
                    expected=bytes((base+x*3*scale+y*5*scale)%256 for y in range(f.height) for x in range(f.width))
                    assert f.payload==expected,('gray single-frame centre sample/DDR ownership',res,f.sequence)
                if mode in (3,4):
                    expected=bytes(255 if x==13//scale or y==7//scale or (x==0 and y==0) else 0 for y in range(f.height) for x in range(f.width))
                    assert rx.image_bytes(f)==expected,('binary OR pool/DDR ownership/bit order',res,f.sequence)
                    if mode==3:
                        reference=bytes(sum((expected[i+j]!=0)<<(7-j) for j in range(8)) for i in range(0,len(expected),8))
                        assert f.payload==reference and len(f.payload)==f.width*f.height//8,'wire packing or length mismatch'
            print(f'PASS async RTL mode={mode} res={res}: {len(frames)} complete packets, CRC/sequence, {frames[0].width}x{frames[0].height} pixel oracle')

if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--captures',type=Path);args=a.parse_args()
    self_test()
    driver_test()
    driver_test("edge","packed")
    driver_test("edge","byte")
    if args.captures:captures(args.captures)
