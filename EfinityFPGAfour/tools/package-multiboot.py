"""Publish qualified image7/image1/image5 and one vendor-generated Flash HEX.
Only local files are read/written; no serial/JTAG/Flash hardware is accessed.
"""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
PROFILES=[(7,'image7_mocap11_a','Ti60_Image7_Mocap11_A'),(1,'image1_vision','Ti60_Image1_Vision'),(5,'image5_canny','Ti60_Image5_Canny')]
STAGE=ROOT/'releases/multiboot/image7_default_1_5'
EFINITY=Path(r'E:\Efinity')

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def fingerprint(image,profile):
 script=r"""
$root=(Get-Location).Path
$profile=Join-Path $root '%s'
$files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
$files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
%s
$files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName}
"""%(profile.relative_to(ROOT).as_posix(),"$files+=Get-Item (Join-Path $root 'example_top.v')" if image==1 else '')
 files=subprocess.check_output(['pwsh','-NoProfile','-Command',script],cwd=ROOT,text=True).splitlines()
 assert files,'empty source inventory'
 data='\n'.join(name+':'+sha(name).upper() for name in files)
 return hashlib.sha256(data.encode()).hexdigest().upper()
def checked_log(path,marker):
 text=path.read_text(errors='replace')
 if marker not in text or re.search(r'(?m)^\s*(Fatal:|ERROR:|FAIL(?:\s|:|$))',text):raise RuntimeError('Regression failed/missing: '+str(path))
 return path

def main():
 if STAGE.exists():raise FileExistsError('Preserve prior release: '+str(STAGE))
 if subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip():raise RuntimeError('Commit final source before packaging')
 files={'README.md':ROOT/'docs/multiboot-image157.md'};builds={}
 for image,folder,name in PROFILES:
  profile=ROOT/'images'/folder;out=profile/'outflow'
  q=json.loads((out/'multiboot_qualification.json').read_text(encoding='utf-8-sig'))
  assert q['image']==image and fingerprint(image,profile)==q['sourceFingerprintSHA256'],'source no longer matches image'+str(image)
  bit=out/(name+'_multiboot_checked.bit');hex_=out/(name+'_multiboot_checked.hex')
  assert sha(bit).upper()==q['bitSHA256'] and sha(hex_).upper()==q['hexSHA256'],'stale checked artifact'
  timing=(out/(name+'.timing.rpt')).read_text();section=timing.split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
  rows=re.findall(r'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',section)
  assert len(rows)>=28 and all(float(s)>=0 for _,s in rows),'setup/hold failure'
  assert 'No Synchronizer warnings to report.' in (out/(name+'.cdc.rpt')).read_text(),'CDC review required'
  resources=json.loads((out/'multiboot_resources.json').read_text())
  assert resources['xlr']<=60800 and resources['ram10']<=256 and resources['dsp']<=160
  builds[str(image)]=dict(**q,resources=resources)
  files.update({f'fpga/image{image}.bit':bit,f'fpga/image{image}.hex':hex_,f'reports/image{image}/build.json':out/'multiboot_qualification.json',
                f'reports/image{image}/resources.json':out/'multiboot_resources.json',f'reports/image{image}/timing.rpt':out/(name+'.timing.rpt'),f'reports/image{image}/cdc.rpt':out/(name+'.cdc.rpt')})
  checked_log(ROOT/f'tmp/multiboot-build{image}.log',f'PASS image{image} multiboot build')
  files[f'reports/image{image}/build.log']=ROOT/f'tmp/multiboot-build{image}.log'
 # Keep image6 and its actual shared runtime dependencies untouched.
 protected=['images/image6_pose_int16','src/pose6','src/storage','src/ft232h','src/vision','src/top','src/adc','src/uart','images/image5_canny/uart_vision_ctrl.v']
 assert not subprocess.check_output(['git','diff','afafc10','HEAD','--',*protected],cwd=ROOT),'image6 shared runtime changed'
 old=ROOT/'releases/image6/standalone/fpga/image6_sd_hdmi.bit'
 if old.exists():assert sha(old)=='a79499d8409fd2cc42b75adb49983ea4a0c2a86ff71884a42ca0df19673235e2'
 model=ROOT/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN'
 assert sha(model)=='74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e' and model.stat().st_size==236448
 files['sdcard/MODEL7.BIN']=model
 gates=[]
 for slot in range(3):gates.append((f'work_sim/multiboot/switch{slot}.log','PASS flash_image_switch'))
 for image in (1,5,7):
  gates.extend([(f'work_sim/multiboot/menu{image}.log','PASS flash_menu'),(f'work_sim/multiboot/chars{image}.log','PASS flash_menu_chars')])
 gates.extend([('tmp/multiboot-image1-menu.log','PASS image1 menu controller and overlay'),
 ('work_sim/image5_menu/image5_menu_ctrl.log','PASS image5 menu:'),('work_sim/image5_menu/image5_menu_key.log','PASS '),
 ('work_sim/image5_menu/image5_menu_video.log','PASS image5 menu video:'),('tmp/multiboot-image7-menu.log','PASS image7 menu controller and overlay'),
 ('work_sim/image7_menu/image7_menu_cdc.log','PASS image7_menu_cdc:'),
 ('tmp/multiboot-image7-integration-final.log','PASS image7 standalone integration'),('tmp/multiboot-image7-interlocks.log','PASS image7 reconfiguration interlocks:')])
 for n,(name,marker) in enumerate(gates):files[f'reports/tests/{n:02d}_{Path(name).name}']=checked_log(ROOT/name,marker)
 integration=(ROOT/'tmp/multiboot-image7-integration-final.log').read_text(errors='replace')
 for marker in ['PASS image7 reconfiguration startup drain:','PASS image7 reconfiguration live drain:','PASS contended DDR video:','PASS image7 eleven-point packet:']:
  assert marker in integration,'missing '+marker
 # All validation succeeds before creating the immutable release directory.
 for name,source in files.items():
  dest=STAGE/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(ROOT/'tmp/multiboot_vendor_user')
 inputs=[STAGE/f'fpga/image{i}.hex' for i in (7,1,5)]
 combined=STAGE/'FLASH_IMAGE7_1_5.hex'
 command='call "'+str(EFINITY/'bin/setup.bat')+'" >nul && "'+str(EFINITY/'python311/bin/python.exe')+'" "'+str(EFINITY/'pgm/bin/multi_image_merger.py')+'" -m selectable_flash_image -t internal '
 command+=' '.join('-ifile "'+str(f)+'"' for f in inputs)+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -o "'+str(combined)+'"'
 before=[sha(f) for f in inputs]
 # Pass raw cmd syntax: Windows list2cmdline would backslash-escape the
 # embedded path quotes, which cmd.exe treats as literal characters.
 result=subprocess.run('cmd.exe /d /s /c "'+command+'"',cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (STAGE/'reports/combine.log').write_text(result.stdout,encoding='utf-8')
 if result.returncode or re.search(r'ERROR:|Unexpected error:',result.stdout) or not combined.exists():raise RuntimeError('Vendor image combination failed; release incomplete')
 assert before==[sha(f) for f in inputs],'merger modified an input file'
 verify=STAGE/'reports/flash_verification.json'
 command='call "'+str(EFINITY/'bin/setup.bat')+'" >nul && "'+str(EFINITY/'python311/bin/python.exe')+'" "'+str(ROOT/'tools/verify-multiboot-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '
 command+=' '.join('--image "'+str(f)+'"' for f in inputs)+' --output "'+str(verify)+'"'
 result=subprocess.run('cmd.exe /d /s /c "'+command+'"',cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (STAGE/'reports/flash_verification.log').write_text(result.stdout,encoding='utf-8')
 if result.returncode or not verify.exists():raise RuntimeError('Combined Flash validation failed; release incomplete: '+result.stdout)
 # Source archive contains project-owned engineering files, not the Efinity installation.
 paths=subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines()
 selected=[p for p in paths if p=='example_top.v' or p.startswith(('src/','pri/','ip/','images/image1_vision/','images/image5_canny/','images/image7_mocap11_a/','tools/')) or p.startswith('docs/') and any(x in p for x in ['multiboot','image1','image5','image7'])]
 archive=STAGE/'source/image157_complete_project.zip';archive.parent.mkdir()
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
  for name in selected:z.write(ROOT/name,name)
 with zipfile.ZipFile(archive) as z:assert z.testzip() is None
 manifest=dict(profile='image157_internal_reconfiguration',default_image=7,slots={'0':7,'1':1,'2':5},
               hdl_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),builds=builds,
               flash=json.loads(verify.read_text()),sd_model_sha256=sha(model),hardware_tested=False,flash_written=False,
               image6_runtime_preserved=True,files={})
 for f in STAGE.rglob('*'):
  if f.is_file():manifest['files'][f.relative_to(STAGE).as_posix()]=dict(bytes=f.stat().st_size,sha256=sha(f))
 (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bundle=STAGE.parent/'image7_default_switch_image1_image5.zip'
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for f in STAGE.rglob('*'):
   if f.is_file():z.write(f,f.relative_to(STAGE).as_posix())
 with zipfile.ZipFile(bundle) as z:
  assert z.testzip() is None
  for name,info in manifest['files'].items():assert hashlib.sha256(z.read(name)).hexdigest()==info['sha256'],name
 print(json.dumps(dict(release=str(STAGE),flash=str(combined),zip=str(bundle),sha256=sha(bundle),programmed_bytes=manifest['flash']['programmed_bytes'],hardware_tested=False),indent=2))
if __name__=='__main__':main()
