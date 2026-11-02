"""Publish a separately qualified performance candidate; never program hardware."""
from pathlib import Path
import hashlib,importlib.util,json,os,re,shutil,statistics,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[1]
PROFILE=ROOT/'images/image7_perf_a';NAME='Ti60_Image7_Perf_A'
STAGE=ROOT/'releases/image7/performance_v1';TMP=ROOT/'tmp/image7_perf_20261029'
OLD=ROOT/'releases/multiboot/image7_default_1_5'
spec=importlib.util.spec_from_file_location('multiboot_package',ROOT/'tools/package-multiboot.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
sha=helper.sha

def checked(name,marker):return helper.checked_log(ROOT/name,marker)
def live(path):
 text=path.read_text(errors='replace')
 rows=[dict(zip(['cycle','interval','capture_to_result'],map(int,r))) for r in re.findall(r'PERF live cycle=(\d+) interval=(\d+) capture_to_result=(\d+)',text)]
 assert len(rows)>=4,'need completed four-result live run'
 stable=rows[1:];period=statistics.mean(r['interval'] for r in stable)
 return dict(samples=rows,steady_interval_cycles=period,updates_per_second=96000000/period,
             capture_to_result_ms=statistics.mean(r['capture_to_result'] for r in stable)/96000,
             board_measured=False)
def vendor(command,env,log):
 result=subprocess.run('cmd.exe /d /s /c "call "E:\\Efinity\\bin\\setup.bat" >nul && '+command+'"',cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 log.write_text(result.stdout,encoding='utf-8')
 if result.returncode or re.search(r'ERROR:|Unexpected error:',result.stdout):raise RuntimeError('Vendor tool failed; incomplete release: '+result.stdout)
def preserved():
 data=json.loads((TMP/'baseline/preserved_artifacts.json').read_text())
 for f in data['files']:
  p=ROOT/f['path'];assert p.is_file() and p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],'original artifact changed: '+str(p)
 for old in (TMP/'baseline/rtl').glob('*.v'):assert sha(old)==sha(ROOT/'src/pose7'/old.name),'original runtime changed: '+old.name
 return data
def main():
 if STAGE.exists():raise FileExistsError('Preserve previous release: '+str(STAGE))
 assert not subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip(),'commit source first'
 old_files=preserved();out=PROFILE/'outflow'
 for name in ['pose7_layer_config.vh','pose7_boot_identity.vh','pose7_model_identity.vh']:
  assert sha(PROFILE/name)==sha(ROOT/'images/image7_mocap11_a'/name),'shared model contract changed'
 q=json.loads((out/'perf_qualification.json').read_text(encoding='utf-8-sig'))
 assert helper.fingerprint(7,PROFILE)==q['sourceFingerprintSHA256'],'stale candidate source'
 assert sha(out/(NAME+'.bit')).upper()==q['bitSHA256'] and sha(out/(NAME+'.hex')).upper()==q['hexSHA256']
 assert q['timingRelationships']>=28 and q['clockHz']==96000000
 resources=json.loads((out/'multiboot_resources.json').read_text())
 assert resources['xlr']<=60800 and resources['ram10']<=256 and resources['dsp']<=160
 before=json.loads((ROOT/'work_sim/pose7_perf_baseline/result.json').read_text())
 after=json.loads((ROOT/'work_sim/pose7_perf_candidate/result.json').read_text())
 assert before['total']==7570739 and after['total']<before['total']*.8
 checks=[
 ('work_sim/pose7_perf_baseline/result.log','PASS image7 full pipeline'),
 ('work_sim/pose7_perf_candidate/result.log','PASS image7 full pipeline'),
 ('work_sim/pose7_requant_batch/result.log','PASS pose7_requant_batch:'),
 ('work_sim/pose7_pool_fast/result.log','PASS pose7_input_pool_fast:'),
 ('tmp/image7_perf_20261029/build.log','PASS image7 performance candidate:'),
 ('tmp/image7_perf_20261029/interlocks.log','PASS image7 reconfiguration interlocks:'),
 ('tmp/image7_perf_20261029/baseline-live.log','PASS image7 live performance:'),
 ('tmp/image7_perf_20261029/standalone.log','PASS image7 standalone integration:')]
 for p,m in checks:checked(p,m)
 full=(TMP/'standalone.log').read_text(errors='replace')
 for m in ['PASS image7 reconfiguration startup drain:','PASS image7 reconfiguration live drain:','PASS contended DDR video:','PASS image7 eleven-point packet:','PASS integrated ASCII debug:','PASS integrated menu:']:assert m in full,m
 a=live(TMP/'baseline-live.log');b=live(TMP/'standalone.log')
 assert b['updates_per_second']>a['updates_per_second'] and b['capture_to_result_ms']<a['capture_to_result_ms'],'no integrated improvement'
 perf=dict(clock_hz=96000000,baseline_pipeline=before,candidate_pipeline=after,baseline_live=a,candidate_live=b,
           pipeline_cycle_reduction=1-after['total']/before['total'],live_update_increase=b['updates_per_second']/a['updates_per_second']-1,
           live_latency_reduction=1-b['capture_to_result_ms']/a['capture_to_result_ms'],board_measured=False)
 old_manifest=json.loads((OLD/'manifest.json').read_text())
 for name in ['fpga/image1.hex','fpga/image5.hex','fpga/image7.bit','fpga/image7.hex','FLASH_IMAGE7_1_5.hex']:
  assert sha(OLD/name)==old_manifest['files'][name]['sha256']
 model=ROOT/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN'
 assert model.stat().st_size==236448 and sha(model)=='74280f04c943f1684f7ff1336919db0806adb01f81b5feb76caf2168d33da12e'
 files={'README.md':ROOT/'docs/image7-performance-v1.md','fpga/image7_perf_a.bit':out/(NAME+'.bit'),'fpga/image7_perf_a.hex':out/(NAME+'.hex'),
        'fpga/image1.hex':OLD/'fpga/image1.hex','fpga/image5.hex':OLD/'fpga/image5.hex','sdcard/MODEL7.BIN':model,
        'baseline/image7_before.bit':OLD/'fpga/image7.bit','baseline/image7_before.hex':OLD/'fpga/image7.hex','baseline/FLASH_BEFORE.hex':OLD/'FLASH_IMAGE7_1_5.hex'}
 for ext in ['timing.rpt','cdc.rpt','map.v','warn.log','pt_timing.rpt']:files['reports/'+ext]=out/(NAME+'.'+ext)
 for name in ['perf_qualification.json','multiboot_resources.json','image7_mipi_guard.json','ft232h_external_budget.json']:files['reports/'+name]=out/name
 for i,(name,_) in enumerate(checks):files[f'reports/tests/{i:02d}_{Path(name).name}']=ROOT/name
 for name,p in files.items():
  dest=STAGE/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 (STAGE/'reports/performance.json').write_text(json.dumps(perf,indent=2)+'\n')
 (STAGE/'reports/preserved_originals.json').write_text(json.dumps(old_files,indent=2)+'\n')
 env=os.environ.copy();env['EFINITY_USER_DIR']=str(ROOT/'tmp/multiboot_vendor_user')
 inputs=[STAGE/'fpga/image7_perf_a.hex',STAGE/'fpga/image1.hex',STAGE/'fpga/image5.hex']
 combined=STAGE/'FLASH_IMAGE7_PERF_1_5.hex'
 args=' '.join('-ifile "'+str(p)+'"' for p in inputs)
 vendor('"E:\\Efinity\\python311\\bin\\python.exe" "E:\\Efinity\\pgm\\bin\\multi_image_merger.py" -m selectable_flash_image -t internal '+args+' -iaddr 0x000000 -iaddr 0x280000 -iaddr 0x500000 -o "'+str(combined)+'"',env,STAGE/'reports/combine.log')
 verify=STAGE/'reports/flash_verification.json'
 args=' '.join('--image "'+str(p)+'"' for p in inputs)
 vendor('"E:\\Efinity\\python311\\bin\\python.exe" "'+str(ROOT/'tools/verify-multiboot-flash.py')+'" --combined "'+str(combined)+'" --report "'+str(combined.with_suffix('.rpt'))+'" '+args+' --output "'+str(verify)+'"',env,STAGE/'reports/flash_verification.log')
 assert verify.is_file();preserved()
 subprocess.run(['git','archive','--format=zip','--output',str(STAGE/'source.zip'),'HEAD'],cwd=ROOT,check=True)
 manifest=dict(commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),default_image=7,hardware_tested=False,flash_written=False,
               model_unchanged=True,old_artifacts_preserved=len(old_files['files']),resources=resources,qualification=q,performance=perf,
               flash=json.loads(verify.read_text()),files={})
 for p in STAGE.rglob('*'):
  if p.is_file():manifest['files'][p.relative_to(STAGE).as_posix()]=dict(bytes=p.stat().st_size,sha256=sha(p))
 (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 bundle=STAGE.parent/'image7_performance_v1.zip'
 with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED) as z:
  for p in STAGE.rglob('*'):
   if p.is_file():z.write(p,p.relative_to(STAGE).as_posix())
 with zipfile.ZipFile(bundle) as z:
  assert z.testzip() is None
  for name,f in manifest['files'].items():assert hashlib.sha256(z.read(name)).hexdigest()==f['sha256']
 print(json.dumps(dict(bundle=str(bundle),sha256=sha(bundle),baseline_live=a,candidate_live=b,resources=resources,old_artifacts_preserved=len(old_files['files']),hardware_tested=False),indent=2))
if __name__=='__main__':main()
