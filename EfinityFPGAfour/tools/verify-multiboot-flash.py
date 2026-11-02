"""Verify vendor-generated Flash addressing/options and unchanged CRAM payloads.
Run with Efinity's Python after setup.bat; never opens programming hardware.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,sys
sys.path.insert(0,str(Path(os.environ['EFINITY_HOME'])/'pgm/bin'))
from efx_pgm.util import bitstream_util
from efx_pgm.opt_reg_processor import OptionRegisterProcessor

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def decode(p):return bytes.fromhex(Path(p).read_text(encoding='ascii'))
def main():
 a=argparse.ArgumentParser();a.add_argument('--combined',type=Path,required=True);a.add_argument('--report',type=Path,required=True)
 a.add_argument('--image',type=Path,action='append',required=True);a.add_argument('--output',type=Path,required=True);v=a.parse_args()
 assert len(v.image)==3,'exactly image7/image1/image5, in slot order'
 txt=v.report.read_text();assert 'Image type: internal' in txt and 'Device: Ti60F225' in txt
 rows=re.findall(r"2'b([01]{2})\s+0x([0-9a-fA-F]+)\s+0x([0-9a-fA-F]+)\s+(.+)",txt)
 assert len(rows)==4,'four-slot vendor address table missing'
 slots=[dict(slot=int(s,2),address=int(ad,16),length=int(n,16),file=f.strip()) for s,ad,n,f in rows]
 expected=[0,0x280000,0x500000]
 assert [x['slot'] for x in slots]==[0,1,2,3]
 assert [x['address'] for x in slots[:3]]==expected and slots[3]['length']==0
 flash=decode(v.combined);assert len(flash)<=0x800000,'8 MB configuration Flash exceeded'
 db=bitstream_util.get_device_db();results=[]
 tmp=v.output.parent/'flash_verify';tmp.mkdir(parents=True,exist_ok=True)
 for i,(source,entry) in enumerate(zip(v.image,slots)):
  original=decode(source);assert len(original)==entry['length'],'vendor length mismatch'
  assert Path(entry['file']).resolve()==source.resolve(),'wrong/stale source path in vendor report'
  assert entry['address']%4096==0 and entry['address']+entry['length']<=([0x280000,0x500000,0x780000][i])
  extracted=flash[entry['address']:entry['address']+entry['length']];assert len(extracted)==len(original)
  part=tmp/f'slot{i}.hex';part.write_text(''.join(f'{b:02X}\n' for b in extracted),encoding='ascii')
  old=OptionRegisterProcessor(str(source),None,db);new=OptionRegisterProcessor(str(part),None,db)
  die=old.die;opt=die.find('option_register');features={f.get('id'):f for f in opt.findall('feature')}
  assert die.get('name')==new.die.get('name') and bitstream_util.get_spi_width_from_bitstream(str(part),die)==4
  allowed=set();values={}
  for key,want in [('EN_CB',0),('EN_RUPD',1),('CB_ADDR_1',0x280000),('CB_ADDR_2',0x500000),('CB_ADDR_3',slots[3]['address'])]:
   f=features[key];start=int(f.get('address'));length=int(f.get('length','1'))
   allowed.update(range(start,start+length));bits=new.get_feature_bits(start,length)
   value=sum(int(b)<<j for j,b in enumerate(bits));assert value==want,(key,value,want)
   values[key]=value
  changed={j for j,(before,after) in enumerate(zip(old.opt_bits,new.opt_bits)) if before!=after}
  assert changed<=allowed,'unexpected option-register mutation'
  sync=bytes.fromhex(opt.get('sync'));start=original.index(sync)+len(sync);end=start+int(opt.get('length'))//8
  assert original[:start]==extracted[:start] and original[end:]==extracted[end:],'CRAM/payload changed during merge'
  results.append(dict(image=[7,1,5][i],**entry,source_sha256=sha(source),options=values,changed_option_bits=len(changed),payload_preserved=True))
 result=dict(mode='selectable_flash_image',type='internal',default_image=7,flash_capacity_bytes=0x800000,
             programmed_bytes=len(flash),combined_sha256=sha(v.combined),all_three_cram_payloads_preserved=True,
             every_slot_has_internal_reconfiguration_and_same_address_table=True,slots=results,hardware_tested=False)
 v.output.write_text(json.dumps(result,indent=2)+'\n')
 print('PASS combined Flash: 8 MB capacity, image7 at power-up, all three option/address tables, unchanged configuration payloads; bytes='+str(len(flash)))
if __name__=='__main__':main()
