"""Check four-slot configuration, preserved board interfaces and runtime resource bounds."""
from pathlib import Path
import argparse,json,re,xml.etree.ElementTree as E,subprocess,sys
R=Path(__file__).resolve().parents[1];a=argparse.ArgumentParser()
a.add_argument('--image',type=int,choices=[1,2,5,7],required=True);a.add_argument('--reports',action='store_true');v=a.parse_args()
i=v.image;p=R/f'images/image{i}_four_boot';name=f'Ti60_Image{i}_Four_Boot'
read=lambda p:p.read_text(encoding='utf-8-sig')
oldfolder={1:'image1_vision',2:'image2_photo_status',5:'image5_stable_ui',7:'image7_usb_points'}[i]
oldname={1:'Ti60_Image1_Vision',2:'Ti60_Image2_Photo_Status',5:'Ti60_Image5_Stable_UI',7:'Ti60_Image7_USB_Points'}[i]
old=R/'images'/oldfolder
def norm(e):return(e.tag,tuple(sorted(e.attrib.items())),tuple(norm(c) for c in e))
tree=E.parse(p/(name+'.peri.xml')).getroot();base=E.parse(old/(oldname+'.peri.xml')).getroot()
tree.attrib.pop('name');base.attrib.pop('name')
ctrl=next(e for e in tree.iter() if e.tag.endswith('}ctrl') and e.get('name')=='cfg')
assert ctrl.get('is_remote_update_enable')=='true' and ctrl.get('clock_name')=='clk_sys'
if i==2:
 oldctrl=next(e for e in base.iter() if e.tag.endswith('}ctrl') and e.get('name')=='cfg')
 oldctrl.set('is_remote_update_enable','true');oldctrl.set('clock_name','clk_sys')
assert norm(tree)==norm(base),'Board IO/clocks/taps modified beyond internal configuration enable'
board=read(p/'board-domains.sdc')
if i==2:board=board.replace('-hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.700','-hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.600')
assert board==read(old/'board-domains.sdc'),'Camera constraints changed beyond extra hold margin'
top=read(p/f'image{i}_platform.v');wrapper=read(p/f'image{i}_top.v')
slot,addr={7:(0,18),1:(1,17),5:(2,19),2:(3,22)}[i]
for token in [f'.CURRENT_SLOT({slot}),.SELECT_ADDR({addr}),.LOAD_ADDR({addr+1})',
 '.safe_to_switch(w_boot_safe)','.boot_selected(w_boot_selected),.boot_status(w_boot_status)',
 '`include "images/four_boot_common/flash_image_switch.v"']:assert token in top,token
for port in ['cfg_ERROR','cfg_CBSEL','cfg_CONFIG','cfg_ENA']:assert f'.{port}({port})' in wrapper
if i==1:
 assert 'badge' not in top and "module image1_four_platform #" in top
 # Only private include bindings and module name differ from qualified image1.
 s=top.replace('module image1_four_platform #','module example_top #')
 for x,y in [('images/image1_four_boot/image1_menu_ctrl.v','src/ui/menu_ctrl.v'),('images/image1_four_boot/image1_menu_render.v','src/ui/menu_text_render.v'),('images/four_boot_common/flash_image_switch.v','src/ui/flash_image_switch.v')]:s=s.replace(x,y)
 assert s==read(R/'example_top.v'),'image1 algorithm/video changed'
if i in [5,7]:
 s=top.replace(f'images/image{i}_four_boot/',f'images/{oldfolder}/').replace('images/four_boot_common/flash_image_switch.v','src/ui/flash_image_switch.v')
 if i==5:
  s=s.replace('images/image5_stable_ui/image5_menu_ctrl.v','images/image5_canny/image5_menu_ctrl.v').replace('images/image5_stable_ui/image5_menu_render.v','src/stable_ui/stable_menu_render5.v')
 assert s==read(old/f'image{i}_platform.v'),'Stable video/inference changed'
if i in [1,5,7]:
 ctrl_file={1:'image1_menu_ctrl.v',5:'image5_menu_ctrl.v',7:'image7_usb_menu_ctrl.v'}[i]
 source_ctrl={1:R/'src/ui/menu_ctrl.v',5:R/'images/image5_canny/image5_menu_ctrl.v',7:old/'image7_usb_menu_ctrl.v'}[i]
 expected=read(source_ctrl).replace(f'images/{oldfolder}/',f'images/image{i}_four_boot/')
 expected=re.sub(r"boot_selected\s*==\s*(?:2'd)?2\s*\?\s*2'd0\s*:\s*boot_selected\s*\+\s*2'd1","boot_selected+2'd1",expected)
 assert read(p/ctrl_file)==expected,'Menu control changed beyond four-slot wrap'
 render_file={1:'image1_menu_render.v',5:'image5_menu_render.v',7:'image7_usb_menu_render.v'}[i]
 source_render={1:R/'src/ui/menu_text_render.v',5:R/'src/stable_ui/stable_menu_render5.v',7:old/'image7_usb_menu_render.v'}[i]
 expected=read(source_render).replace(f'images/{oldfolder}/',f'images/image{i}_four_boot/')
 expected=expected.replace('default:word_="------"','default:word_="IMAGE2"').replace('default:word="IMAGE5      ";','2:word="IMAGE5      ";default:word="IMAGE2      ";')
 assert read(p/render_file)==expected,'Menu pixels changed beyond IMAGE2 name'
if i==7:
 assert '.stop_for_reconfig(w_boot_stop),.reconfig_idle(w_boot_safe)' in top
 for n in ['image7_ft_link_usb.v','pose7_usb_packet.v','pose7_usb_sender.v','pose7_layer_config.vh','pose7_model_identity.vh','pose7_boot_identity.vh']:
  assert read(p/n).replace('images/image7_four_boot/','images/image7_usb_points/')==read(old/n),n
if i==5:assert '.run_n(w_ft_run&&!w_boot_stop)' in top
if i==2:
 subprocess.run([sys.executable,str(R/'tools/check-image2-p4-menu.py'),'--profile',p.name,'--project',name]+(['--reports'] if v.reports else []),check=True)
 for key,value in [('EDGE_THRESHOLD',25),('CANNY_LOW_THRESHOLD',8),('WB_RED_GAIN',496),('WB_GREEN_GAIN',416),('WB_BLUE_GAIN',313),('GAMMA_STRENGTH',255)]:assert re.search(r'DEFAULT_'+key+r'\s*=\s*\d+\x27d'+str(value)+r';',top),key
 assert "assign w_boot_safe=1'b1;" not in top
 for n in ['w_photo_capture_request','w_photo_uart_request','w_photo_delete_request','w_sd_info_query_request','w_photo_gallery_toggle_request','w_photo_gallery_prev_request','w_photo_gallery_next_request']:assert '('+n+'&&!w_boot_stop)' in top,n
 assert '.ui_reconfig_idle(w_boot_safe)' in top
 for n in ['image2_vision_ctrl.v','image2_video_counters.v','image2_video_diagnostic.v']:
  assert read(p/n).replace('images/image2_four_boot/','images/image2_photo_status/')==read(old/n),n
if v.reports:
 out=p/'outflow';stats=read(out/(name+'-hierarchical_stats.rpt'))
 row=next(l for l in stats.splitlines() if re.search(r'\+image'+str(i)+r'_top\s+\|',l))
 nums=[int(re.search(r'\d+',c)[0]) for c in row.split('|')[2:5]]
 assert all(n<=limit for n,limit in zip(nums,[60800,256,160])),nums
 for token in ['u_flash_image_switch','u_menu_ctrl']+(['u_network','u_sd_boot','u_point_sender'] if i==7 else []):assert token in stats,token
 net=read(out/(name+'.map.v'))
 for port in ['cfg_ERROR','cfg_CBSEL','cfg_CONFIG','cfg_ENA']:assert port in net,port
 assert not re.search(r"assign\s+cfg_(?:CONFIG|ENA)\s*=\s*1'b[01]",net)
 warn=read(out/(name+'.warn.log')).split('// Efinity Synthesis Started')[-1]
 warn=re.sub(r'\r?\n(?!(?:\[EFX-|//))','',warn)
 for line in warn.splitlines():
  if 'does not have a driver' not in line and 'non-driven net' not in line:continue
  if re.search(r"net 'i_dqs_n_(hi|lo)\[\d+\]'",line):continue
  if re.search(r'[/\\](?:flash_image_switch|image[1257]_(?:platform|menu[^/\\]*|top)|image7_usb_[^/\\]*)\.v:|src[/\\](?:pose7|storage|photo|vision|adc|uart|ft232h)[/\\]',line):raise AssertionError(line)
 timing=read(out/(name+'.timing.rpt'))
 if i in [2,7]:
  for kind,unc in [('setup',.8 if i==2 else .5),('hold',.6 if i==2 else .3)]:
   section=timing.split('Path Details for '+('Max' if kind=='setup' else 'Min')+' Critical Paths (begin)',1)[1]
   if kind=='setup':section=section.split('Path Details for Min Critical Paths (begin)',1)[0]
   found=[]
   for block in re.split(r'\+\+\+\+ Path \d+',section):
    if not all(re.search(c+r' Clock\s*:\s*csi_rxc_i\b',block) for c in ['Launch','Capture']):continue
    u=re.search(r'[+-] Clock Uncertainty\s*:\s*(\d+\.\d+)',block);s=re.search(r'Slack\s*:\s*(-?\d+\.\d+)',block)
    assert u and s and float(u[1])>=unc and float(s[1])>=0;found.append(True)
   assert found,'Missing actual CSI '+kind+' paths'
 (out/'four_resources.json').write_text(json.dumps(dict(zip(['xlr','ram10','dsp'],nums)),indent=2))
 print('PASS mapped four-slot image',i,'XLR/RAM10/DSP',nums)
print('PASS four-slot source/pin/stable-video contract image',i)
