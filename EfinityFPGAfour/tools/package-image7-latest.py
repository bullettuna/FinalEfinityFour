"""Publish the newest-complete-frame candidate without modifying prior files."""
from pathlib import Path
import hashlib,importlib.util,json,os,re,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1];TMP=ROOT/'tmp/image7_latest_20261029'
PROFILE=ROOT/'images/image7_latest_a';NAME='Ti60_Image7_Latest_A'
STAGE=ROOT/'releases/image7/performance_v2_latest';V1=ROOT/'releases/image7/performance_v1'
OLD=ROOT/'releases/multiboot/image7_default_1_5'
spec=importlib.util.spec_from_file_location('perf_package',ROOT/'tools/package-image7-perf.py')
perf=importlib.util.module_from_spec(spec);spec.loader.exec_module(perf)
sha=perf.sha
def preserved():
 data=json.loads((TMP/'baseline/preserved_artifacts.json').read_text())
 for f in data['files']:
  p=ROOT/f['path'];assert p.is_file() and p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],'prior HEX/BIT changed: '+str(p)
 protected=['images/image6_pose_int16','images/image7_mocap11_a','images/image7_perf_a','src/pose6','src/pose7_perf','src/ft232h','src/storage','src/vision','src/adc','src/uart','src/ui','src/pose7/*.v']
 assert not subprocess.check_output(['git','diff','fc5fcc3','HEAD','--',*protected],cwd=ROOT),'prior runtime changed'
 return data
def main():
 if STAGE.exists():raise FileExistsError('Preserve prior output: '+str(STAGE))
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'commit source first'
 previous=preserved();out=PROFILE/'outflow'
 for n in ['pose7_layer_config.vh','pose7_model_identity.vh','pose7_boot_identity.vh']:assert sha(PROFILE/n)==sha(ROOT/'images/image7_mocap11_a'/n)
 q=json.loads((out/'latest_qualification.json').read_text(encoding='utf-8-sig'))
 assert perf.helper.fingerprint(7,PROFILE)==q['sourceFingerprintSHA256'],'stale build source'
 for ext,key in [('bit','bitSHA256'),('hex','hexSHA256')]:assert sha(out/(NAME+'.'+ext)).upper()==q[key]
 assert q['timingRelationships']>=28 and q['clockHz']==96000000
 resources=json.loads((out/'multiboot_resources.json').read_text())
 assert resources['xlr']<=60800 and resources['ram10']<=256 and resources['dsp']<=160
 checks=[('tmp/image7_latest_20261029/snapshot.log','PASS latest snapshot:'),
         ('tmp/image7_latest_20261029/control.log','PASS latest USB control:'),
         ('tmp/image7_latest_20261029/interlocks.log','PASS image7 reconfiguration interlocks:'),
         ('tmp/image7_latest_20261029/build.log','PASS image7 latest-frame candidate:'),
         ('tmp/image7_latest_20261029/v1-live.log','PASS image7 live performance:'),
         ('tmp/image7_latest_20261029/latest-live.log','PASS image7 live performance:'),
         ('tmp/image7_latest_20261029/standalone.log','PASS image7 standalone integration:')]
 for p,m in checks:perf.checked(p,m)
 full=(TMP/'standalone.log').read_text(errors='replace')
 for m in ['PASS image7 reconfiguration startup drain:','PASS image7 reconfiguration live drain:','PASS contended DDR video:','PASS image7 eleven-point packet:','PASS integrated ASCII debug:','PASS integrated menu:']:assert m in full,m
 before=perf.live(TMP/'v1-live.log');after=perf.live(TMP/'latest-live.log')
 assert len(before['samples'])==6 and len(after['samples'])==6
 assert after['updates_per_second']>=15 and after['updates_per_second']>=before['updates_per_second']*.95,'unacceptable throughput regression'
 assert after['capture_to_result_ms']<before['capture_to_result_ms']*.95,'no meaningful latency reduction'
 performance=dict(clock_hz=96000000,baseline_v1=before,latest_v2=after,latency_reduction=1-after['capture_to_result_ms']/before['capture_to_result_ms'],board_measured=False)
 model=ROOT/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN'
 assert model.stat().st_size==236448 and sha(model)=='74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e'
 files={'README.md':ROOT/'docs/image7-latest-frame-v2.md','fpga/image7_latest_a.bit':out/(NAME+'.bit'),'fpga/image7_latest_a.hex':out/(NAME+'.hex'),
        'fpga/image1.hex':OLD/'fpga/image1.hex','fpga/image5.hex':OLD/'fpga/image5.hex','sdcard/MODEL7.BIN':model,
        'baseline/image7_v1.bit':V1/'fpga/image7_perf_a.bit','baseline/image7_v1.hex':V1/'fpga/image7_perf_a.hex','baseline/FLASH_V1.hex':V1/'FLASH_IMAGE7_PERF_1_5.hex'}
 for ext in ['timing.rpt','cdc.rpt','map.v','warn.log','pt_timing.rpt']:files['reports/'+ext]=out/(NAME+'.'+ext)
 for n in ['latest_qualification.json','multiboot_resources.json','image7_mipi_guard.json','ft232h_external_budget.json']:files['reports/'+n]=out/n
 for i,(n,_) in enumerate(checks):files[f'reports/tests/{i:02d}_{Path(n).name}']=ROOT/n
 for n,p in files.items():
  d=STAGE/n;d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
 (STAGE/'reports/performance.json').write_text(json.dumps(performance,indent=2)+'\n')
 (STAGE/'reports/preserved_originals.json').write_text(json.dumps(previous,indent=2)+'\n')
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(ROOT/'tmp/multiboot_vendor_user')
 inputs=[STAGE/'fpga/image7_latest_a.hex',STAGE/'fpga/image1.hex',STAGE/'fpga/image5.hex'];hashes=[sha(p) for p in inputs]
 combined=STAGE/'FLASH_IMAGE7_LATEST_1_5.hex';args=' '.join('-ifile "'+str(p)+'"' for p in inputs)
 perf.vendor('"E:\\Efinity\\python311\\bin\\python.exe" "E:\\Efinity\\pgm\\bin\\multi_image_merger.py" -m selectable_flash_image -t internal '+args+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -o "'+str(combined)+'"',env,STAGE/'reports/combine.log')
 assert hashes==[sha(p) for p in inputs]
 verify=STAGE/'reports/flash_verification.json';args=' '.join('--image "'+str(p)+'"' for p in inputs)
 perf.vendor('"E:\\Efinity\\python311\\bin\\python.exe" "'+str(ROOT/'tools/verify-multiboot-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '+args+' --output "'+str(verify)+'"',env,STAGE/'reports/flash_verification.log')
 assert verify.is_file();preserved()
 subprocess.run(['git','archive','--format=zip','--output',str(STAGE/'source.zip'),'HEAD'],cwd=ROOT,check=True)
 manifest=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),default_image=7,hardware_tested=False,flash_written=False,
               model_unchanged=True,old_artifacts_preserved=len(previous['files']),resources=resources,qualification=q,performance=performance,flash=json.loads(verify.read_text()),files={})
 for p in STAGE.rglob('*'):
  if p.is_file():manifest['files'][p.relative_to(STAGE).as_posix()]=dict(bytes=p.stat().st_size,sha256=sha(p))
 (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bundle=STAGE.parent/'image7_performance_v2_latest.zip'
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for p in STAGE.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(STAGE).as_posix())
 with zipfile.ZipFile(bundle) as z:
  assert z.testzip() is None
  for n,f in manifest['files'].items():assert hashlib.sha256(z.read(n)).hexdigest()==f['sha256']
 print(json.dumps(dict(bundle=str(bundle),sha256=sha(bundle),performance=performance,resources=resources,old_artifacts_preserved=len(previous['files']),hardware_tested=False),indent=2))
if __name__=='__main__':main()
