"""Qualify the isolated image2 guard candidate; board success remains unverified."""
import json,re,subprocess,sys,hashlib
from pathlib import Path
import xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[1];p=r/'images/image2_photo_status';old=r/'images/image2_p4_menu'
name='Ti60_Image2_Photo_Status';read=lambda f:f.read_text(encoding='utf-8-sig')
subprocess.run([sys.executable,str(r/'tools/check-image2-p4-menu.py'),'--profile',p.name,'--project',name]+(['--reports'] if '--reports' in sys.argv else []),check=True)
for f in ['image2_top.v','image2_vision_ctrl.v','image2_menu_rom.v','p4-inputs.json']:
 assert read(p/f).replace('images/image2_photo_status/','images/image2_p4_menu/')==read(old/f),'Unexpected algorithm change: '+f
def norm(e):return (e.tag,tuple(sorted(e.attrib.items())),tuple(norm(c) for c in e))
a=ET.parse(p/(name+'.peri.xml')).getroot();b=ET.parse(old/'Ti60_Image2_P4_Menu.peri.xml').getroot()
a.attrib.pop('name');b.attrib.pop('name');assert norm(a)==norm(b),'Physical pins, PLL or DPHY taps changed'
board=read(p/'board-domains.sdc')
assert board==read(old/'board-domains.sdc').replace('0.500','0.800').replace('0.300','0.600')
platform=read(p/'image2_platform.v')
assert '.AUTO_PREVIEW(1' not in platform
assert 'ui_photo_status' in platform
assert '.rx_valid\t\t(w_uart_legacy_valid)' in platform
assert '.video_health({w_video_diagnostic_data[271:256],w_video_diagnostic_data[239:224],w_video_diagnostic_data[79:64],w_video_diagnostic_data[47:32]})' in platform
counter=read(p/'image2_video_counters.v').replace('image2_video_count_sync','pose7_diag_count_sync').replace('image2_video_counters','pose7_video_diag').replace('image2_video_packet','pose7_diag_packet').replace("32'h31443250","32'h31443650").replace('~2D reply: P2D1','~6D reply: P6D1')
assert counter==read(r/'src/pose7/pose7_video_diag.v'),'Passive counter implementation changed'
if '--reports' in sys.argv:
 sdc=read(p/(name+'.pt.sdc'));text=read(p/('outflow/'+name+'.timing.rpt'))
 assert sdc.count('create_clock -period 6 -name csi_rxc_i')==1
 observed=[]
 for kind,value,marker in [('setup',.8,'Path Details for Max Critical Paths (begin)'),('hold',.6,'Path Details for Min Critical Paths (begin)')]:
  expected=f'set_clock_uncertainty -{kind} -from [get_clocks {{csi_rxc_i}}] -to [get_clocks {{csi_rxc_i}}] {value:.3f}'
  assert sdc.count(expected)==1,expected
  part=text.split(marker,1)[1]
  if kind=='setup':part=part.split('Path Details for Min Critical Paths (begin)',1)[0]
  found=[]
  for block in re.split(r'\+\+\+\+ Path \d+',part):
   if not(re.search(r'Launch Clock\s*:\s*csi_rxc_i\b',block) and re.search(r'Capture Clock\s*:\s*csi_rxc_i\b',block)):continue
   slack=re.search(r'Slack\s*:\s*(-?\d+\.\d+)',block);u=re.search(r'[+-] Clock Uncertainty\s*:\s*(\d+\.\d+)',block)
   assert slack and u and float(slack[1])>=0 and float(u[1])>=value
   found.append({'slackNs':float(slack[1]),'uncertaintyNs':float(u[1])})
  assert found,'Missing observed camera timing '+kind
  observed.append({'analysis':kind,'paths':found})
 mapped=read(p/('outflow/'+name+'.map.v'))
 for token in ['u_image2_video_diagnostic','camera_frames','camera_good','packet']:
  assert token in mapped,token
 report={'hardwareTested':False,'failureResolved':False,'physicalInterfacesUnchanged':True,'setupExtraNs':.8,'holdExtraNs':.6,'observed':observed}
 (p/'outflow/video_guard_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print('PASS observed camera uncertainty: setup >=0.8ns, hold >=0.6ns')
print('PASS image2 guard isolation: algorithms, pins, clocks/taps unchanged; passive observers and stronger camera constraints')
