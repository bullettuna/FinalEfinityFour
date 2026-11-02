"""Check internal configuration wiring and actual mapped resource budgets."""
from pathlib import Path
import argparse,json,re,xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--image',type=int,choices=[1,5,7],required=True);a.add_argument('--mapped',action='store_true');a.add_argument('--profile');a.add_argument('--project');args=a.parse_args()
folder,name,slot,select={1:('image1_vision','Ti60_Image1_Vision',1,17),5:('image5_canny','Ti60_Image5_Canny',2,19),7:('image7_mocap11_a','Ti60_Image7_Mocap11_A',0,18)}[args.image]
folder=args.profile or folder;name=args.project or name
profile=ROOT/'images'/folder
ns={'p':'http://www.efinixinc.com/peri_design_db'}
tree=E.parse(profile/(name+'.peri.xml'));ctrl=tree.find('.//p:ctrl',ns)
assert ctrl is not None and ctrl.get('is_remote_update_enable')=='true'
assert ctrl.get('clock_name')=='clk_sys'
for key,value in [('cbsel_bus_name','cfg_CBSEL'),('config_ctrl_name','cfg_CONFIG'),('ena_capture_name','cfg_ENA'),('error_status_name','cfg_ERROR')]:assert ctrl.get(key)==value,key
# Dedicated configuration Flash pins must not be driven as unrelated user GPIO.
for n in tree.findall('.//p:comp_gpio',ns):
 assert n.get('gpio_def') not in ['GPIOL_P_01_SSL_N','GPIOL_N_15_TEST_N'],n.attrib
platform=((profile/'example_top_stable.v' if (profile/'example_top_stable.v').exists() else ROOT/'example_top.v') if args.image==1 else profile/f'image{args.image}_platform.v').read_text(encoding='utf-8-sig')
wrapper=(profile/f'image{args.image}_top.v').read_text(encoding='utf-8-sig')
for port in ['cfg_ERROR','cfg_CBSEL','cfg_CONFIG','cfg_ENA']:
 assert '.'+port+'('+port+')' in wrapper,port
assert f'.CURRENT_SLOT({slot}),.SELECT_ADDR({select}),.LOAD_ADDR({select+1})' in platform
for item in ['.safe_to_switch(w_boot_safe)','.stop_request(w_boot_stop)','.boot_selected(w_boot_selected),.boot_status(w_boot_status)']:assert item in platform,item
if args.image==7:
 assert '.stop_for_reconfig(w_boot_stop),.reconfig_idle(w_boot_safe)' in platform
 assert 'image7_menu_cdc #(.WIDTH(`M7_MENU_DISP_WIDTH))' in platform
if args.image==5:assert '.run_n(w_ft_run&&!w_boot_stop)' in platform
if args.image==1:
 # A generate block may otherwise create shadow implicit wires before the
 # parent's later declarations, silently optimizing the switch away.
 switch_at=platform.index('generate if(MULTIBOOT_BUILD)')
 for declaration in ['rstn_sys = 0','wire w_menu_write_valid;','wire [4:0] w_menu_write_addr;','wire [11:0] w_menu_write_value;']:
  assert platform.index(declaration)<switch_at,'declare before generate: '+declaration
if args.mapped:
 out=profile/'outflow';h=(out/(name+'-hierarchical_stats.rpt')).read_text()
 assert re.search(r'\+(?:[\w]+\.)*u_flash_image_switch\s+\|',h),'missing mapped switch controller'
 required=['u_menu_ctrl']+(['u_ft_link','u_network','u_sd_boot','u_decode','u_pose7_hdmi_overlay'] if args.image==7 else ['u_ft_link','u_menu_render'] if args.image==5 else ['u_menu_text_render'])
 for block in required:assert re.search(r'\+(?:[\w]+\.)*'+block+r'\s+\|',h),'missing '+block
 row=next(line for line in h.splitlines() if f'+image{args.image}_top' in line);cells=row.split('|')
 resources=dict(xlr=float(re.search(r'[\d.]+',cells[2])[0]),ram10=int(re.search(r'\d+',cells[3])[0]),dsp=int(re.search(r'\d+',cells[4])[0]))
 assert resources['xlr']<=60800 and resources['ram10']<=256 and resources['dsp']<=160,resources
 net=(out/(name+'.map.v')).read_text()
 for port in ['cfg_ERROR','cfg_CBSEL','cfg_CONFIG','cfg_ENA']:assert port in net,port
 assert not re.search(r"assign\s+cfg_(?:CONFIG|ENA)\s*=\s*1'b[01]",net),'configuration control optimized to a constant'
 warn=(out/(name+'.warn.log')).read_text(errors='replace');warn=warn[warn.rfind('// Efinity Synthesis Started'):]
 warn=re.sub(r'\r?\n(?!(?:\[EFX-|//))','',warn) # tool wraps paths at the console width
 for line in warn.splitlines():
  if re.search(r"net 'i_dqs_n_(?:hi|lo)\[\d+\]'",line):continue # existing DDR IP unused complementary inputs
  if 'does not have a driver' in line or 'non-driven net' in line:
   if re.search(r'(flash_image_switch|menu_|example_top\.v|image[157]_(top|platform)|src[\\/](pose7|ft232h|adc|uart|vision|storage))',line):raise AssertionError(line)
 (out/'multiboot_resources.json').write_text(json.dumps(resources,indent=2)+'\n')
 print('PASS mapped multiboot image'+str(args.image),resources)
else:print('PASS internal configuration pin/slot contract image'+str(args.image))
