"""Publish the image7 point-stream switch; preserve other images and never program hardware."""
from pathlib import Path
import hashlib,importlib.util,json,os,re,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1];TMP=ROOT/'tmp/image7_usb_points_20261029'
STAGE=ROOT/'releases/multiboot/usb_points_20261029'
BUNDLE=STAGE.parent/'image157_usb_points_20261029.zip'
ORIGINAL_LOAD=ROOT/'releases/multiboot/image7_default_1_5'
spec=importlib.util.spec_from_file_location('perf_package',ROOT/'tools/package-image7-perf.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper);sha=helper.sha
def preserved():
 data=json.loads((TMP/'baseline/preserved_artifacts.json').read_text())
 for f in data['files']:
  p=ROOT/f['path'];assert p.is_file() and p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],'prior HEX/BIT changed: '+str(p)
 return data
def audit():
 paths=['src/pose7/'+n+'.v' for n in ['pose7_conv','pose7_network','pose7_input_pool','pose7_mac16','pose7_requant','pose7_decode','pose7_axi_master']]
 paths+=['src/ft232h/ft_ddr_snapshot.v','src/storage/photo_axi_mux.v','src/axi/axi4_ctrl.v','src/axi/AXI4_AWARMux.v','pri/mipi/MIPIRx4LaneFre.v','src/hdmi_ip/rgb2dvi.v','src/cmos_i2c/I2C_SC2210_19201080_4Lanes_Config.v']
 out={}
 for p in paths:
  old=subprocess.check_output(['git','show','afafc10:'+p],cwd=ROOT).replace(b'\r\n',b'\n')
  cur=(ROOT/p).read_bytes().replace(b'\r\n',b'\n');assert cur==old,'stable video/model baseline changed: '+p
  out[p]=hashlib.sha256(cur).hexdigest()
 p=ROOT/'src/stable_ui/image7_ft_link_stable.v';s=p.read_text(encoding='utf-8').replace('module image7_ft_link_stable #','module image7_ft_link #',1)
 s=s.replace('output [15:0] menu_status,output [7:0] check_feedback,','output [15:0] menu_status,',1)
 a=s.index(' reg [3:0] check_sequence;');b=s.index(' wire loader_tx_valid,',a);s=s[:a]+s[b:]
 assert s==(ROOT/'src/pose7/image7_ft_link.v').read_text(encoding='utf-8'),'feedback altered inference flow'
 s=(ROOT/'src/stable_ui/stable_pose7_overlay.v').read_text(encoding='utf-8')
 s=s.replace('module stable_pose7_overlay #','module pose7_hdmi_overlay #',1).replace('hud_x=px-40;','hud_x=px-16;',1).replace('hud=px>=40&&px<104','hud=px>=16&&px<80',1)
 assert s==(ROOT/'src/pose7/pose7_hdmi_overlay.v').read_text(encoding='utf-8'),'skeleton geometry/video mailbox changed'
 for i in [5,7]:
  s=(ROOT/f'images/image{i}_stable_ui/image{i}_platform.v').read_text(encoding='utf-8')
  for n,v in [('EDGE_THRESHOLD',23),('CANNY_LOW_THRESHOLD',11),('WB_RED_GAIN',496),('WB_GREEN_GAIN',416),('WB_BLUE_GAIN',313),('GAMMA_STRENGTH',255),('BLACK_THRESHOLD',96)]:
   assert re.search(r'DEFAULT_'+n+r"\s*=\s*\d+'d"+str(v)+r'\s*;',s),(i,n)
  assert '.DEFAULT_EDGE_THRESHOLD' in s and '.DEFAULT_WB_RED_GAIN' in s
  if i==7:
   assert 'pose7_perf' not in s and 'pose7_latest' not in s
   assert '.check_feedback(w_check_feedback)' in s and '.WIDTH(`M7_MENU_DISP_WIDTH)' in s
 for i,label in [(5,'32'),(7,'33')]:
  s=(ROOT/f'src/stable_ui/stable_menu_render{i}.v').read_text()
  assert "badge_region?8'h"+label in s and 'parameter MENU_X = 40' in s
 confirmed=ROOT/'releases/image7/menu_v3/fpga/image7_mocap11_a.bit'
 assert sha(confirmed)=='b7476606329cd0a11149d677061cb9ec2af10568147f659301c7bdd64ab0135d'
 return dict(confirmed_source='afafc10',confirmed_bit_sha256=sha(confirmed),unchanged_runtime=out,feedback_only_model_wrapper=True,overlay_only_hud_relocated=True,
             video_pipeline_cycles=3,labels={'image1':None,'image5':2,'image7':3},image1_number_deferred=True,defaults={'high':23,'low':11,'wb':[496,416,313],'gamma':255,'black':96},hardware_tested=False)

def reuse_image1(files,builds):
 # Reuse the already qualified LOAD-only image1, never a failed new layout.
 manifest=json.loads((ORIGINAL_LOAD/'manifest.json').read_text())
 q=manifest['builds']['1']
 assert q['bitSHA256']=='8E39552C393CC4A165FA4B717D31E9226A35D0A8A4BAAC88D0806CAD6CF55775'
 assert q['hexSHA256']=='58635070FC1E20876A883055DB17AE902C756E4A580BA891C05F3282C8018F29'
 assert q['timingRelationships']>=28
 records={f'fpga/image1_load.{e}':f'fpga/image1.{e}' for e in ['bit','hex']}
 records.update({'reports/image1/'+n:'reports/image1/'+n for n in ['build.json','resources.json','build.log','timing.rpt','cdc.rpt']})
 records.update({'source/image1_original_load_project.zip':'source/image157_complete_project.zip','reports/image1/menu.log':'reports/tests/09_multiboot-image1-menu.log'})
 for target,origin in records.items():
  p=ORIGINAL_LOAD/origin;f=manifest['files'][origin]
  assert p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],'original image1 provenance changed: '+origin
  files[target]=p
 timing=(ORIGINAL_LOAD/'reports/image1/timing.rpt').read_text();timing=timing.split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
 rows=re.findall(r'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',timing)
 assert len(rows)>=28 and all(float(b)>=0 for a,b in rows)
 assert 'No Synchronizer warnings to report.' in (ORIGINAL_LOAD/'reports/image1/cdc.rpt').read_text()
 source=ORIGINAL_LOAD/'source/image157_complete_project.zip'
 with zipfile.ZipFile(source) as z:
  assert z.testzip() is None
  top=z.read('example_top.v').decode('utf-8-sig')
  assert 'flash_image_switch #(.CURRENT_SLOT(1),.SELECT_ADDR(17),.LOAD_ADDR(18))' in top
  assert top.replace('\r\n','\n')==(ROOT/'example_top.v').read_text(encoding='utf-8-sig'),'original image1 platform changed'
 builds['1']=dict(**q,reused_qualified_binary=True,sourceCommit=manifest['hdl_commit'],new_number_not_included=True)
def usb_audit():
 profile=ROOT/'images/image7_usb_points';base='images/image7_usb_points/'
 s=(profile/'image7_platform.v').read_text(encoding='utf-8')
 for before,after in [('src/stable_ui/image7_menu_defs.vh',base+'image7_usb_menu_defs.vh'),('src/stable_ui/image7_ft_link_stable.v',base+'image7_ft_link_usb.v'),('src/stable_ui/stable_menu_ctrl7.v',base+'image7_usb_menu_ctrl.v'),('src/stable_ui/stable_menu_render7.v',base+'image7_usb_menu_render.v'),('src/pose7/ui/image7_menu_text_rom.v',base+'image7_usb_menu_text_rom.v'),('src/pose7/pose7_packet.v',base+'pose7_usb_packet.v'),('image7_ft_link_stable #','image7_ft_link_usb #'),('stable_menu_ctrl7 u_menu_ctrl','image7_usb_menu_ctrl u_menu_ctrl'),('stable_menu_render7 u_menu_text_render','image7_usb_menu_render u_menu_text_render')]:s=s.replace(after,before)
 s=s.replace(';wire w_usb_points_enabled;',';').replace('.cur_usb_points(w_usb_points_enabled),','').replace('.usb_points_enabled(w_usb_points_enabled),','').replace('\n`include "'+base+'pose7_usb_sender.v"\n','')
 assert s==(ROOT/'images/image7_stable_ui/image7_platform.v').read_text(encoding='utf-8'),'video/inference platform changed beyond USB/UI binding'
 a=(profile/'Ti60_Image7_USB_Points.peri.xml').read_text(encoding='utf-8-sig').replace('Ti60_Image7_USB_Points','Ti60_Image7_Stable_UI')
 assert a==(ROOT/'images/image7_stable_ui/Ti60_Image7_Stable_UI.peri.xml').read_text(encoding='utf-8-sig'),'clock/pin configuration changed'
 p=(profile/'pose7_usb_packet.v').read_text().replace('module pose7_usb_packet(','module pose7_packet(').replace('input cancel,','').replace('sequence_id','sequence').replace('!cancel&&state>=1','state>=1')
 p=p.replace('  else if(cancel)begin\n   state<=0;index<=0;release_result<=0;\n  end else begin','  else begin')
 assert p==(ROOT/'src/pose7/pose7_packet.v').read_text(),'point packet format changed'
 six=json.loads((TMP/'baseline/image6_sources.json').read_text())
 for name,value in six.items():assert sha(ROOT/name)==value,'image6/shared runtime changed: '+name
 for name in ['pose7_model_identity.vh','pose7_boot_identity.vh','pose7_layer_config.vh']:assert sha(profile/name)==sha(ROOT/'images/image7_stable_ui'/name)
 mapped=(profile/'outflow/Ti60_Image7_USB_Points.map.v').read_text();assert 'EFX_FF \\u_platform/w_usb_points_enabled~FF' in mapped and '.Q(\\u_platform/w_usb_points_enabled ' in mapped and 'u_point_sender' in mapped
 core=(profile/'image7_ft_link_usb.v').read_text();assert 'usb_points_enabled<=0' in core and 'menu_write_addr==20' in core
 return dict(image6_source_hashes=six,usb_default_off=True,menu_item=20,menu_record_width=155,video_platform_normalized_identical=True,clocks_and_pins_identical=True,point_packet_format_identical=True)

def main():
 if STAGE.exists() or BUNDLE.exists():raise FileExistsError('Preserve prior release: '+str(STAGE))
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'commit source first'
 old=preserved();proof=audit();proof.update(usb_audit());files={'README.md':ROOT/'docs/image7-usb-points-20261029.md','baseline/image7_previous_stable.bit':ROOT/'releases/multiboot/stable_ui_20261029/fpga/image7_stable_ui.bit'};builds={}
 reuse_image1(files,builds)
 for i in [5,7]:
  folder='image7_usb_points' if i==7 else 'image5_stable_ui';name='Ti60_Image7_USB_Points' if i==7 else 'Ti60_Image5_Stable_UI';profile=ROOT/'images'/folder;out=profile/'outflow';stem='image7_usb_points' if i==7 else 'image5_stable_ui'
  q=json.loads((out/('usb_points_qualification.json' if i==7 else 'stable_qualification.json')).read_text(encoding='utf-8-sig'))
  assert helper.helper.fingerprint(i,profile)==q['sourceFingerprintSHA256'],'stale source image'+str(i)
  bit=out/(name+'_multiboot_checked.bit');hx=out/(name+'_multiboot_checked.hex')
  assert sha(bit).upper()==q['bitSHA256'] and sha(hx).upper()==q['hexSHA256'] and q['timingRelationships']>=28
  resource=json.loads((out/'multiboot_resources.json').read_text());assert resource['xlr']<=60800 and resource['ram10']<=256 and resource['dsp']<=160
  builds[str(i)]=dict(**q,resources=resource)
  log='tmp/image7_usb_points_20261029/build.log' if i==7 else 'tmp/stable_ui_20261029/build5.log';helper.checked(log,'PASS image7 USB points build' if i==7 else 'PASS image5 stable UI build')
  files.update({f'fpga/{stem}.bit':bit,f'fpga/{stem}.hex':hx,f'reports/image{i}/build.json':out/('usb_points_qualification.json' if i==7 else 'stable_qualification.json'),f'reports/image{i}/resources.json':out/'multiboot_resources.json',f'reports/image{i}/build.log':ROOT/log})
  for ext in ['timing.rpt','cdc.rpt']:files[f'reports/image{i}/'+ext]=out/(name+'.'+ext)
 for n,mark in [('sender.log','PASS USB sender wire oracle:'),('menu.log','PASS USB menu control:'),('render.log','PASS USB UI'),('multiboot.log','PASS current stable menus:'),('standalone.log','PASS USB menu runtime:')]:
  helper.checked('tmp/image7_usb_points_20261029/'+n,mark);files['reports/tests/'+n]=TMP/n
 full=(TMP/'standalone.log').read_text(errors='replace')
 for mark in ['PASS image7 standalone integration:','PASS contended DDR video:','PASS image7 eleven-point packet:','PASS image7 reconfiguration live drain:','PASS integrated ASCII debug:','PASS integrated menu:','PASS stable check feedback:']:assert mark in full,mark
 model=ROOT/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN';assert model.stat().st_size==236448 and sha(model)=='74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e';files['sdcard/MODEL7.BIN']=model
 for n,p in files.items():
  d=STAGE/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
 (STAGE/'reports/baseline_audit.json').write_text(json.dumps(proof,indent=2)+'\n');(STAGE/'reports/preserved_originals.json').write_text(json.dumps(old,indent=2)+'\n')
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(ROOT/'tmp/multiboot_vendor_user')
 inputs=[STAGE/'fpga/image7_usb_points.hex',STAGE/'fpga/image1_load.hex',STAGE/'fpga/image5_stable_ui.hex'];hashes=[sha(p) for p in inputs]
 combined=STAGE/'FLASH_IMAGE7_USB_POINTS_1_5.hex';args=' '.join('-ifile "'+str(p)+'"' for p in inputs)
 helper.vendor('"E:\\Efinity\\python311\\bin\\python.exe" "E:\\Efinity\\pgm\\bin\\multi_image_merger.py" -m selectable_flash_image -t internal '+args+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -o "'+str(combined)+'"',env,STAGE/'reports/combine.log')
 assert hashes==[sha(p) for p in inputs]
 verify=STAGE/'reports/flash_verification.json';args=' '.join('--image "'+str(p)+'"' for p in inputs)
 helper.vendor('"E:\\Efinity\\python311\\bin\\python.exe" "'+str(ROOT/'tools/verify-multiboot-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '+args+' --output "'+str(verify)+'"',env,STAGE/'reports/flash_verification.log')
 assert verify.is_file();preserved();subprocess.run(['git','archive','--format=zip','--output',str(STAGE/'source.zip'),'HEAD'],cwd=ROOT,check=True)
 manifest=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),default_image=7,hardware_tested=False,flash_written=False,video_acceptance_priority=True,
               source_baseline='afafc10',usb_point_stream_default=False,point_packet_bytes=114,point_packet_kind=5,image6_runtime_unchanged=True,image1_number_deferred=True,performance_v1_v2_user_reported_video_stutter=True,preserved_hex_bit_count=len(old['files']),builds=builds,flash=json.loads(verify.read_text()),files={})
 for p in STAGE.rglob('*'):
  if p.is_file():manifest['files'][p.relative_to(STAGE).as_posix()]=dict(bytes=p.stat().st_size,sha256=sha(p))
 (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');bundle=BUNDLE
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for p in STAGE.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(STAGE).as_posix())
 with zipfile.ZipFile(bundle) as z:
  assert z.testzip() is None
  for n,f in manifest['files'].items():assert hashlib.sha256(z.read(n)).hexdigest()==f['sha256']
 print(json.dumps(dict(bundle=str(bundle),sha256=sha(bundle),preserved_hex_bit_count=len(old['files']),builds=builds,hardware_tested=False),indent=2))
if __name__=='__main__':main()
