"""Publish checked 7/1/5/2 images and one verified internal-update Flash file."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,zipfile
R=Path(__file__).resolve().parents[1];S=R/'releases/multiboot/four_images_20261029';T=R/'tmp/four_images_20261029';E=Path('E:/Efinity')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def checked(p,mark):
 s=p.read_text(errors='replace');assert mark in s and not re.search(r'^Fatal:|^ERROR:|^FAIL ',s,re.M),str(p)
def vendor(command,env,log):
 cmd='call "'+str(E/'bin/setup.bat')+'" >nul && '+command
 v=subprocess.run('cmd.exe /d /s /c "'+cmd+'"',cwd=R,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 log.write_text(v.stdout,encoding='utf-8')
 assert v.returncode==0 and not re.search(r'ERROR:|Unexpected error:',v.stdout),v.stdout
def copy(source,target):
 p=S/target;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,p)
def main():
 assert not S.exists(),'Do not overwrite a prior release'
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=R,text=True).strip(),'Commit release source first'
 preserved=json.loads((T/'preserved.json').read_text())
 for f in preserved:assert sha(R/f['path'])==f['sha256'],'Old BIT/HEX changed: '+f['path']
 # Existing image6 runtime and qualified source profiles must stay byte-identical.
 base=(T/'base_commit.txt').read_text().strip()
 changed=subprocess.check_output(['git','diff','--name-only',base,'HEAD'],cwd=R,text=True).splitlines()
 assert not any(p.startswith(('src/','pri/','images/image6_','images/image1_vision/','images/image2_photo_status/','images/image5_stable_ui/','images/image7_usb_points/')) or p=='example_top.v' for p in changed),changed
 builds={};S.mkdir(parents=True)
 for i in [7,1,5,2]:
  p=R/f'images/image{i}_four_boot';name=f'Ti60_Image{i}_Four_Boot';out=p/'outflow'
  q=json.loads((out/'qualification.json').read_text(encoding='utf-8-sig'))
  assert sha(out/'runtime_fingerprint.txt').upper()==q['sourceFingerprintSHA256']
  for line in (out/'runtime_fingerprint.txt').read_text().splitlines():
   path,digest=line.rsplit(':',1);assert sha(path).upper()==digest,'Stale RTL/input: '+path
  assert sha(p/(name+'.xml')).upper()==q['projectSHA256']
  assert q['timingRelationships']>=28 and sha(out/(name+'_checked.bit')).upper()==q['bitSHA256'] and sha(out/(name+'_checked.hex')).upper()==q['hexSHA256']
  timing=(out/(name+'.timing.rpt')).read_text().split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
  rows=re.findall(r'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',timing)
  assert len(rows)>=28 and all(float(b)>=0 for a,b in rows)
  assert 'No Synchronizer warnings to report.' in (out/(name+'.cdc.rpt')).read_text()
  builds[str(i)]=dict(**q,resources=json.loads((out/'four_resources.json').read_text()),worstSlackNs=min(float(b) for a,b in rows))
  for ext in ['bit','hex']:copy(out/(name+'_checked.'+ext),f'fpga/image{i}.{ext}')
  for ext in ['timing.rpt','cdc.rpt','log','pt.rpt','pt_timing.rpt','warn.log']:copy(out/(name+'.'+ext),f'reports/image{i}/{ext}')
  for f in ['qualification.json','four_resources.json','runtime_fingerprint.txt']:copy(out/f,f'reports/image{i}/{f}')
  if (out/'placement_provenance.json').exists():
   copy(out/'placement_provenance.json',f'reports/image{i}/placement_provenance.json')
 for slot in range(4):
  p=R/f'work_sim/four_image/image1/slot{slot}.log';checked(p,'PASS flash_image_switch');copy(p,f'reports/tests/slot{slot}.log')
 for i in [1,2,5,7]:
  for test in ['keys','chars']:
   p=R/f'work_sim/four_image/image{i}/{test}{i}.log';checked(p,'PASS flash_menu');copy(p,f'reports/tests/{test}{i}.log')
 for test in ['photo_menu','photo_render','photo_uart','photo_reconfig','photo_video']:
  p=R/f'work_sim/four_image/photo/{test}.log';checked(p,'PASS ');copy(p,f'reports/tests/{test}.log')
 checked(R/'work_sim/four_image/photo/photo_reconfig.log','PASS image2 concurrent real SD4 SAVE/LOAD')
 checked(R/'work_sim/four_image/photo/photo_video.log','PASS actual photo WAIT -> committed OK;')
 copy(R/'docs/four-image-7152-20261029.md','README.md')
 copy(T/'preserved.json','reports/preserved_artifacts.json')
 model=R/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN'
 assert model.stat().st_size==236448 and sha(model)=='74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e'
 copy(model,'sdcard/MODEL7.BIN')
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(R/'tmp/multiboot_vendor_user')
 python='"'+str(E/'python311/bin/python.exe')+'"';inputs=[S/f'fpga/image{i}.hex' for i in [7,1,5,2]]
 combined=S/'FLASH_IMAGE7_1_5_2.hex';before=[sha(p) for p in inputs]
 command=python+' "'+str(E/'pgm/bin/multi_image_merger.py')+'" -m selectable_flash_image -t internal '
 command+=' '.join('-ifile "'+str(p)+'"' for p in inputs)+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -iaddr 0x680000 -o "'+str(combined)+'"'
 vendor(command,env,S/'reports/combine.log');assert before==[sha(p) for p in inputs]
 command=python+' "'+str(R/'tools/verify-four-image-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '
 command+=' '.join('--image "'+str(p)+'"' for p in inputs)+' --output "'+str(S/'reports/flash_verification.json')+'"'
 vendor(command,env,S/'reports/flash_verification.log')
 (S/'source').mkdir()
 with zipfile.ZipFile(S/'source/four_image_project.zip','w',zipfile.ZIP_DEFLATED) as z:
  for f in subprocess.check_output(['git','ls-files','-z'],cwd=R).decode('utf-8').split('\0'):
   if (R/f).is_file():z.write(R/f,f)
 verification=json.loads((S/'reports/flash_verification.json').read_text())
 manifest=dict(sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip(),slotOrder=[7,1,5,2],defaultImage=7,builds=builds,flash=verification,previousArtifactCount=len(preserved),previousArtifactsPreserved=True,hardwareTested=False,flashWritten=False)
 manifest['files']={p.relative_to(S).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in S.rglob('*') if p.is_file()}
 (S/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bundle=S.parent/'image7152_internal_20261029.zip';assert not bundle.exists()
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for p in S.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(S).as_posix())
 target=R.parent/'Hex/Hex7152_INTERNAL_20261029.hex';assert not target.exists()
 shutil.copy2(combined,target);assert sha(target)==sha(combined)
 for i in [7,1,5,2]:
  target_bit=target.parent/f'Image{i}_FOUR_BOOT_20261029.bit';assert not target_bit.exists();shutil.copy2(S/f'fpga/image{i}.bit',target_bit)
 shutil.copy2(S/'README.md',target.parent/'Hex7152_INTERNAL_20261029_README.md')
 (target.parent/'Hex7152_INTERNAL_20261029.sha256.txt').write_text(sha(target)+'  '+target.name+'\n')
 print('PASS published',target,'Flash bytes',verification['programmed_bytes'],'of',verification['flash_capacity_bytes'])
if __name__=='__main__':main()
