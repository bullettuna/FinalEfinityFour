"""Check P4 pin mapping against user's handoff and isolated image2 integration."""
import argparse,hashlib,json,re,sys
from pathlib import Path
import xml.etree.ElementTree as ET
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--profile',default='image2_p4_menu')
parser.add_argument('--project',default='Ti60_Image2_P4_Menu')
parser.add_argument('--reports',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];p=root/'images'/args.profile;name=args.project
read=lambda f:f.read_text(encoding='utf-8-sig')
signals=json.loads(read(p/'p4-inputs.json'))['signals']
gpio={e.get('name'):e for e in ET.parse(p/(name+'.peri.xml')).iter() if e.tag.endswith('comp_gpio')}
assert len(signals)==13
used=[e.get('gpio_def') for e in gpio.values()];assert len(set(used))==len(used)
for sig in signals:
 e=gpio[sig['signal']]
 assert (e.get('gpio_def'),e.get('mode'),e.get('io_standard'))==(sig['resource'],sig['direction_from_fpga'],'1.8 V LVCMOS'),sig
# Copy must not silently change the algorithm/storage state machine.
base=read(root/'src/storage/photo_native_pipeline.v')
new=read(p/'image2_photo_pipeline.v').replace('module image2_photo_pipeline #','module photo_native_pipeline #')
new=re.sub(r' output \[3:0\] ui_stage.*?(?= input clk,input rst_n,input pclk)','',new,flags=re.S)
new=re.sub(r' assign ui_stage=current_stage;.*?(?= wire channels_idle=)','',new,flags=re.S)
if args.profile in ['image2_photo_status','image2_four_boot']:
 assert 'ENABLE_UART_EXPORT=0,AUTO_PREVIEW=0' in new
 new=new.replace(',AUTO_PREVIEW=0','')
 new=new.replace('if(AUTO_PREVIEW&&ENABLE_PROCESSING&&photo_mode!=0)','if(ENABLE_PROCESSING&&photo_mode!=0)')
 new=re.sub(r' // PHOTO_STATUS_OBSERVER_BEGIN.*? // PHOTO_STATUS_OBSERVER_END\n','',new,flags=re.S)
 if args.profile=='image2_four_boot':
  new=re.sub(r' // RECONFIG_IDLE_OBSERVER_BEGIN.*? // RECONFIG_IDLE_OBSERVER_END\n','',new,flags=re.S)
assert new==base,'Private SD pipeline contains changes beyond status outputs'
top=read(p/'image2_platform.v');wrapper=read(p/'image2_top.v')
for token in [".PHOTO_TF_BUILD(1'b1)",".ENABLE_PHOTO_TF(1'b1)",".ENABLE_ADC(1'b1)",".MENU_BUILD(1'b1)"]:
 assert token in wrapper,token
for token in ['image2_vision_ctrl #','image2_menu_ctrl u_menu_ctrl','image2_menu_render #','image2_photo_pipeline #','.ui_event_valid(ui_event_valid)']:
 assert token in top,token
assert 'if (!w_hdmi_vsync)' in top and 'r_menu_disp_active <= r_menu_disp_sync' in top
assert top.index('wire w_gallery_mode;')<top.index('image2_menu_ctrl u_menu_ctrl'),'Forward-declare gallery status before nested menu generate'
if '--reports' in sys.argv:
 rpt=read(p/('outflow/'+name+'.pt.rpt'))
 rows=[[c.strip() for c in l.split('|')[1:-1]] for l in rpt.splitlines() if l.startswith('|')]
 for sig in signals:
  assert any(len(c)>=9 and c[0]==sig['signal'] and c[1]==sig['resource'] and c[2]==sig['direction_from_fpga'] and c[-1]==sig['ball'] and '1.8 V LVCMOS' in c for c in rows),'Generated pin/ball mismatch: '+sig['signal']
 mapped=read(p/('outflow/'+name+'.map.v'))
 for token in ['u_key1_debounce','u_menu_ctrl','u_menu_text_render','u_mcp3202_spi','u_photo_native_pipeline','u_process','u_export']:
  assert token in mapped,'Missing runtime function: '+token
 warnings=read(p/('outflow/'+name+'.warn.log')).split('// Efinity Synthesis Started')[-1]
 for line in warnings.splitlines():
  if 'does not have a driver' in line and re.search(r'[/\\]image2_(?:platform|menu[^/\\]*|vision[^/\\]*|photo[^/\\]*)\.v:|src[/\\](storage|photo|vision|adc)[/\\]',line):
   assert re.search(r"net 'i_dqs_n_(hi|lo)\[\d+\]'",line),'Undriven application net: '+line
 stats=read(p/('outflow/'+name+'-hierarchical_stats.rpt'))
 row=next(l for l in stats.splitlines() if re.search(r'^\|\s+\+image2_top\s+\|',l))
 values=[int(re.search(r'\d+',c).group()) for c in row.split('|')[2:5]]
 assert values[0]<=60800 and values[1]<=256 and values[2]<=160,values
 print('PASS mapped image2 resources XLR/RAM10/DSP',values)
print('PASS image2: 13 unique P4 1.8V pads, menu, storage status and unchanged SD/FAT logic')
