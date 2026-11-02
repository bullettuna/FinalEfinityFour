from pathlib import Path
import struct,zlib,sys
raw=Path(sys.argv[1]).read_bytes();valid=[];pos=0
while True:
 pos=raw.find(b'FT5!',pos)
 if pos<0:break
 packet=raw[pos:pos+114]
 if len(packet)==114 and zlib.crc32(packet[:20])==struct.unpack_from('<I',packet,20)[0] and zlib.crc32(packet[24:110])==struct.unpack_from('<I',packet,110)[0]:
  assert packet[4:8]==bytes([2,5,0,24]);assert struct.unpack_from('<HHI',packet,12)==(640,360,86)
  body=packet[24:110];assert body[:4]==bytes([2,11,3,0]);tag,model,icrc,hcrc=struct.unpack_from('<IIII',body,4)
  assert (model,icrc,hcrc)==(0x1f704b5e,0x11110000+tag,0x22220000+tag)
  for j in range(11):assert struct.unpack_from('<HHH',body,20+j*6)==((tag<<8)+j,200+j,30000+j)
  valid.append((struct.unpack_from('<I',packet,8)[0],tag));pos+=114
 else:pos+=1
assert len(raw)==463 and valid==[(0,0x11),(1,0x33),(2,0x44),(3,0x66)],(len(raw),valid)
print('PASS USB sender wire oracle: 4 complete FT5! v2/kind5 packets, exact 11 points and immutable metadata, both CRCs, monotonic sequence, resync after canceled partial packet')
