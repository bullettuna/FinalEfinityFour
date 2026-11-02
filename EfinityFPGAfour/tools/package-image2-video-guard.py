"""Publish only a qualified, simulated image2 build into a fresh local release."""
import hashlib,json,re,shutil,subprocess,zipfile,sys
from pathlib import Path

root=Path(__file__).resolve().parents[1];p=root/'images/image2_video_guard';name='Ti60_Image2_Video_Guard'
out=p/'outflow';audit=root/'tmp/image2_video_guard_20261029'
dest=root/'releases/image2/video_guard_20261029'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
read=lambda f:f.read_text(encoding='utf-8-sig')
subprocess.run([sys.executable,str(root/'tools/check-image2-video-guard.py'),'--reports'],check=True)
q=json.loads(read(out/'qualification.json'))
assert q['timingRelationships']>=28 and not q['hardwareTested'] and not q['flashWritten']
assert sha(out/(name+'_checked.bit')).upper()==q['bitSHA256']
assert sha(out/(name+'_checked.hex')).upper()==q['hexSHA256']
assert sha(out/(name+'.bit'))==sha(out/(name+'_checked.bit'))
assert sha(p/(name+'.xml')).upper()==q['projectSHA256'],'Build recipe changed after qualification'
# Use the same PowerShell culture-aware ordering as the build, including its
# handling of punctuation. Python's Unicode lexical order is not identical.
root_literal=str(root).replace("'","''")
ordering=r"""$root='%s';$profile=Join-Path $root 'images/image2_video_guard';
$files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'};
$files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'};
$files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName}
""" % root_literal
files=subprocess.check_output(['powershell','-NoProfile','-Command',ordering],text=True).splitlines()
fingerprint='\n'.join(f+':'+sha(Path(f)).upper() for f in files)
assert hashlib.sha256(fingerprint.encode()).hexdigest().upper()==q['sourceFingerprintSHA256'],'Runtime changed after qualification'
for top in ['image2_menu_control_tb','image2_menu_render_tb','image2_uart_regression_tb','image2_menu_video_tb']:
 log=read(root/('work_sim/image2_video_guard/'+top+'.log'))
 assert re.search(r'^PASS ',log,re.M) and not re.search(r'Fatal:|ERROR:|FAIL ',log),top
# Every old programming file remains intact. Two intentional existing source
# edits are the new build dispatch and ignore rule, both explicitly allowed.
old=json.loads(read(audit/'artifacts_before.json'))
for rel,h in old.items():assert sha(root/rel)==h,'Previous programming file changed: '+rel
tracked=json.loads(read(audit/'tracked_before.json'))
allowed={'tools/check-image2-p4-menu.py'}
for rel,h in tracked.items():
 if rel not in allowed:assert sha(root/rel)==h,'Previous runtime/source changed: '+rel
assert not dest.exists(),'Refuse to overwrite a published release'
(dest/'fpga').mkdir(parents=True);(dest/'reports').mkdir()
for ext in ['bit','hex']:
 shutil.copy2(out/(name+'_checked.'+ext),dest/('fpga/image2_video_guard.'+ext))
for suffix in ['.timing.rpt','.cdc.rpt','.pt.rpt','-hierarchical_stats.rpt','.warn.log']:
 shutil.copy2(out/(name+suffix),dest/('reports/'+name+suffix))
shutil.copy2(out/'qualification.json',dest/'reports/qualification.json')
shutil.copy2(out/'video_guard_checks.json',dest/'reports/video_guard_checks.json')
shutil.copy2(root/'work_sim/image2_video_diagnostic/result.log',dest/'reports/diagnostic_result.log')
shutil.copy2(root/'docs/image2-video-guard-20261029.md',dest/'README.md')
for f in audit.glob('*menu*.png'):shutil.copy2(f,dest/('reports/'+f.name))
for top in ['image2_menu_control_tb','image2_menu_render_tb','image2_uart_regression_tb','image2_menu_video_tb']:
 shutil.copy2(root/('work_sim/image2_video_guard/'+top+'.log'),dest/('reports/'+top+'.log'))
for f in ['build.log','preservation.json','diagnostic_test.log']:
 if (audit/f).exists():shutil.copy2(audit/f,dest/('reports/'+f))
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],cwd=root,text=True).strip(),'Commit source before publishing'
subprocess.run(['git','archive','-o',str(dest/'source.zip'),'HEAD'],cwd=root,check=True)
manifest={'sourceCommit':commit,'profile':p.relative_to(root).as_posix(),'hardware':'P4 13 GPIO, FPGA-side 1.8V; original UART image export','default':'color, H60/L30; no direct knob threshold takeover','menuItems':22,'modelRequired':False,'multibootBundle':False,'hardwareTested':False,'flashWritten':False,'boardFailureResolved':False,'candidate':True,'qualified':q,'preservedProgrammingFiles':len(old),'preservedOriginalTrackedFiles':len(tracked)-len(allowed),'files':{f.relative_to(dest).as_posix():sha(f) for f in dest.rglob('*') if f.is_file()}}
(dest/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
zip_path=dest.parent/'image2_video_guard_20261029.zip'
assert not zip_path.exists()
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
 for f in dest.rglob('*'):
  if f.is_file():z.write(f,f.relative_to(dest))
with zipfile.ZipFile(zip_path) as z:
 assert z.testzip() is None
 for rel,h in manifest['files'].items():assert hashlib.sha256(z.read(rel)).hexdigest()==h
print(json.dumps({'release':str(dest),'zip':str(zip_path),'preservedProgrammingFiles':len(old),'bitSHA256':sha(dest/'fpga/image2_video_guard.bit')},indent=2))
