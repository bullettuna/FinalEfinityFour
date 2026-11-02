"""Replace only image1 in a new, verified four-slot candidate; preserve all earlier files."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,zipfile
R=Path(__file__).resolve().parents[1];P=R/'images/image1_four_video_guard';N='Ti60_Image1_Four_Boot'
OLD=R/'releases/multiboot/four_images_20261029';S=R/'releases/multiboot/four_images_image1_guard_20261029';T=R/'tmp/image1_four_guard_20261029'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(src,target):
 p=S/target;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,p)
def vendor(cmd,log):
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(R/'tmp/multiboot_vendor_user')
 v=subprocess.run('cmd.exe /d /s /c "call "E:\\Efinity\\bin\\setup.bat" >nul && '+cmd+'"',cwd=R,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 log.write_text(v.stdout,encoding='utf-8');assert v.returncode==0 and not re.search(r'ERROR:|Unexpected error:',v.stdout),v.stdout
def main():
 assert not S.exists(),'Never overwrite a published candidate'
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=R,text=True).strip(),'Commit source first'
 old=json.loads((OLD/'manifest.json').read_text());out=P/'outflow';q=json.loads((out/'guard_qualification.json').read_text())
 for name,f in old['files'].items():assert sha(OLD/name)==f['sha256'],'Previous release changed: '+name
 for name,digest in q['sources'].items():assert sha(R/name)==digest,'Guard source changed: '+name
 assert sha(out/(N+'.map.v'))==q['identity']['mappedSHA256']==sha(R/'images/image1_four_boot/outflow'/(N+'.map.v'))
 for line in (R/'images/image1_four_boot/outflow/runtime_fingerprint.txt').read_text().splitlines():
  path,digest=line.rsplit(':',1);assert sha(Path(path)).upper()==digest,'Baseline RTL no longer matches map'
 assert q['winner']['passed'] and not q['winner']['timing']['violations'] and q['winner']['timing']['relationships']>=28
 assert sha(out/(N+'_guard_checked.bit'))==q['bitSHA256'] and sha(out/(N+'_guard_checked.hex'))==q['hexSHA256']
 preserved=json.loads((T/'preserved.json').read_text())
 for f in preserved:assert sha(R/f['path'])==f['sha256'],'Earlier BIT/HEX overwritten: '+f['path']
 S.mkdir(parents=True)
 for i in [7,5,2]:
  for ext in ['bit','hex']:copy(OLD/f'fpga/image{i}.{ext}',f'fpga/image{i}.{ext}')
  for f in (OLD/f'reports/image{i}').rglob('*'):
   if f.is_file():copy(f,f.relative_to(OLD).as_posix())
 for ext in ['bit','hex']:
  copy(out/(N+'_guard_checked.'+ext),'fpga/image1.'+ext)
  copy(OLD/('fpga/image1.'+ext),'baseline/image1_reported_corruption.'+ext)
 for ext in ['timing.rpt','cdc.rpt','log','pt.rpt','pt_timing.rpt','warn.log']:copy(out/(N+'.'+ext),'reports/image1/'+ext)
 copy(out/'guard_qualification.json','reports/image1/guard_qualification.json')
 for f in (OLD/'reports/tests').iterdir():
  if f.is_file():copy(f,'reports/tests/'+f.name)
 copy(OLD/'manifest.json','baseline/previous_manifest.json');copy(T/'preserved.json','reports/preserved_artifacts.json')
 copy(R/'docs/image1-four-video-guard-20261029.md','README.md');copy(OLD/'sdcard/MODEL7.BIN','sdcard/MODEL7.BIN')
 py='"E:\\Efinity\\python311\\bin\\python.exe"';inputs=[S/f'fpga/image{i}.hex' for i in [7,1,5,2]]
 combined=S/'FLASH_IMAGE7_1_5_2_IMAGE1_GUARD.hex';before=[sha(p) for p in inputs]
 cmd=py+' "E:\\Efinity\\pgm\\bin\\multi_image_merger.py" -m selectable_flash_image -t internal '+' '.join('-ifile "'+str(p)+'"' for p in inputs)+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -iaddr 0x680000 -o "'+str(combined)+'"'
 vendor(cmd,S/'reports/combine.log');assert before==[sha(p) for p in inputs]
 cmd=py+' "'+str(R/'tools/verify-four-image-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '+' '.join('--image "'+str(p)+'"' for p in inputs)+' --output "'+str(S/'reports/flash_verification.json')+'"'
 vendor(cmd,S/'reports/flash_verification.log');flash=json.loads((S/'reports/flash_verification.json').read_text())
 prior=bytes.fromhex((OLD/'FLASH_IMAGE7_1_5_2.hex').read_text());now=bytes.fromhex(combined.read_text())
 for entry in flash['slots']:
  if entry['image']==1:continue
  a,n=entry['address'],entry['length'];assert prior[a:a+n]==now[a:a+n],'Working image changed inside combined Flash'
 (S/'source').mkdir()
 with zipfile.ZipFile(S/'source/project.zip','w',zipfile.ZIP_DEFLATED) as z:
  for f in subprocess.check_output(['git','ls-files','-z'],cwd=R).decode('utf-8').split('\0'):
   if (R/f).is_file():z.write(R/f,f)
 manifest=dict(sourceCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip(),slotOrder=[7,1,5,2],defaultImage=7,guardQualification=q,flash=flash,unchangedOtherSlots=[7,5,2],previousArtifactsPreserved=len(preserved),hardwareTested=False,flashWritten=False)
 manifest['files']={p.relative_to(S).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in S.rglob('*') if p.is_file()}
 (S/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bundle=S.parent/'image7152_image1_guard_20261029.zip';assert not bundle.exists()
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for p in S.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(S).as_posix())
 dst=R.parent/'Hex';bit=dst/'Image1_VIDEO_GUARD_20261029.bit';hx=dst/'Hex7152_IMAGE1_GUARD_20261029.hex'
 assert not bit.exists() and not hx.exists();shutil.copy2(S/'fpga/image1.bit',bit);shutil.copy2(combined,hx)
 shutil.copy2(S/'README.md',dst/'Hex7152_IMAGE1_GUARD_20261029_README.md')
 (dst/'Hex7152_IMAGE1_GUARD_20261029.sha256.txt').write_text(sha(hx)+'  '+hx.name+'\n')
 print('PASS published candidate',bit,hx,'other three slots identical; board validation pending')
if __name__=='__main__':main()
