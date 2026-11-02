"""Re-place identical image1 RTL with stronger camera/pixel margins; no hardware writes."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import argparse,hashlib,json,re,shutil,subprocess,time
R=Path(__file__).resolve().parents[1];P=R/'images/image1_four_video_guard';B=R/'images/image1_four_boot'
N='Ti60_Image1_Four_Boot';T=R/'tmp/image1_four_guard_20261029'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding='utf-8-sig')
def source_check():
 for p in B.iterdir():
  if p.is_file() and p.suffix in ['.v','.vh','.json']:
   assert sha(p)==sha(P/p.name),'Guard changed RTL/IO contract: '+p.name
 assert sha(B/(N+'.peri.xml'))==sha(P/(N+'.peri.xml')),'Pins/PLL/taps changed'
 expected=read(B/'board-domains.sdc')+'\n# Additional engineering margin after image1 hardware corruption report.\n'
 for kind,clock,value in [('setup','csi_rxc_i','0.800'),('hold','csi_rxc_i','0.600'),('setup','clk_pixel_2x','0.250')]:
  expected+=f'set_clock_uncertainty -{kind} -from [get_clocks {{{clock}}}] -to [get_clocks {{{clock}}}] {value}\n'
 assert read(P/'board-domains.sdc')==expected,'Unexpected additional constraints'
 for line in read(B/'outflow/runtime_fingerprint.txt').splitlines():
  path,digest=line.rsplit(':',1);assert sha(Path(path)).upper()==digest,'Mapped baseline source changed: '+path
 ident=json.loads((T/'reuse_identity.json').read_text())
 assert sha(P/'outflow'/(N+'.map.v'))==ident['mappedSHA256']==sha(B/'outflow'/(N+'.map.v'))
 return ident
def timing(out):
 s=read(out/(N+'.timing.rpt'));summary=s.split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
 rows=re.findall(r'^\s+(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',summary,re.M)
 bad=[row for row in rows if float(row[3])<0]
 assert len(rows)>=28 and 'No Synchronizer warnings to report.' in read(out/(N+'.cdc.rpt'))
 observed=[]
 for kind,title,clock,extra in [('setup','Max','csi_rxc_i',.8),('hold','Min','csi_rxc_i',.6),('setup','Max','clk_pixel_2x',.25)]:
  section=s.split('Path Details for '+title+' Critical Paths (begin)',1)[1]
  if title=='Max':section=section.split('Path Details for Min Critical Paths (begin)',1)[0]
  found=[]
  for block in re.split(r'\+\+\+\+ Path \d+',section):
   if not all(re.search(c+r' Clock\s*:\s*'+clock+r'\b',block) for c in ['Launch','Capture']):continue
   u=re.search(r'[+-] Clock Uncertainty\s*:\s*(\d+\.\d+)',block);sl=re.search(r'Slack\s*:\s*(-?\d+\.\d+)',block)
   assert u and sl and float(u[1])>=extra,'Required margin not applied'
   found.append(dict(slackNs=float(sl[1]),uncertaintyNs=float(u[1])))
  assert found,(clock,kind);observed.append(dict(clock=clock,kind=kind,paths=found))
 return dict(relationships=len(rows),violations=bad,worstSlackNs=min(float(x[3]) for x in rows),observed=observed)
def flow(p,which):
 cmd='call "E:\\Efinity\\bin\\setup.bat" >nul && call "E:\\Efinity\\bin\\efx_run.bat" '+N+'.xml --flow '+which
 v=subprocess.run('cmd.exe /d /s /c "'+cmd+'"',cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (p/(which+'_flow.log')).write_text(v.stdout,encoding='utf-8');return v.returncode==0
def trial(recipe):
 opt,seed=recipe.split(':');assert opt in ['TIMING_2','CONGESTION_1'];seed=int(seed)
 p=R/f'tmp/image1_guard_{opt}_s{seed}';assert not p.exists();p.mkdir()
 for f in P.iterdir():
  if f.is_file() and f.suffix in ['.v','.vh','.xml','.json','.sdc']:shutil.copy2(f,p/f.name)
 shutil.copytree(P/'outflow',p/'outflow')
 f=p/(N+'.xml');s=read(f);s=re.sub(r'name="seed" value="\d+"',f'name="seed" value="{seed}"',s)
 s=re.sub(r'name="optimization_level" value="\w+"',f'name="optimization_level" value="{opt}"',s)
 # Larger iteration ceiling, never use the unsupported early-exit flag.
 if 'name="max_router_iterations"' not in s:s=s.replace('<efx:param name="placer_effort_level"','<efx:param name="max_router_iterations" value="100" value_type="e_integer" />\n        <efx:param name="placer_effort_level"')
 f.write_text(s);started=time.time();print('START image1 guard',recipe,flush=True)
 routed=flow(p,'pnr');t=timing(p/'outflow') if routed else None
 if routed:assert (p/'outflow'/(N+'.timing.rpt')).stat().st_mtime>=started
 passed=bool(t and not t['violations']);print('RESULT',recipe,'PASS' if passed else 'REJECT',t['violations'] if t else 'routing failed',flush=True)
 return dict(recipe=recipe,directory=str(p),routed=routed,timing=t,passed=passed)
def main():
 a=argparse.ArgumentParser();a.add_argument('--recipes',nargs='+',required=True);v=a.parse_args();identity=source_check();results=[]
 with ThreadPoolExecutor(max_workers=2) as pool:
  for future in as_completed([pool.submit(trial,x) for x in v.recipes]):results.append(future.result())
 record=T/('trials_'+'_'.join(x.replace(':','_') for x in v.recipes)+'.json');record.write_text(json.dumps(results,indent=2))
 winners=[x for x in results if x['passed']]
 if not winners:raise SystemExit('No fully timed candidate: previous files preserved')
 # Prefer stronger achieved residual margin when both meet every constraint.
 winner=max(winners,key=lambda x:x['timing']['worstSlackNs']);p=Path(winner['directory']);assert flow(p,'pgm')
 identity2=source_check();assert identity2==identity
 for f in [N+'.xml',N+'.pt.sdc','board-domains.sdc']:shutil.copy2(p/f,P/f)
 for f in (p/'outflow').iterdir():
  if f.is_file():shutil.copy2(f,P/'outflow'/f.name)
 out=P/'outflow';assert sha(out/(N+'.map.v'))==identity['mappedSHA256']
 for ext in ['bit','hex']:shutil.copy2(out/(N+'.'+ext),out/(N+'_guard_checked.'+ext))
 # Confirm original mapped application and hardware budget, not just a raw PGM exit.
 stats=read(out/(N+'-hierarchical_stats.rpt'));row=next(x for x in stats.splitlines() if re.search(r'\+image1_top\s+\|',x))
 nums=[int(re.search(r'\d+',x)[0]) for x in row.split('|')[2:5]];assert all(x<=y for x,y in zip(nums,[60800,256,160]))
 source={f.relative_to(R).as_posix():sha(f) for f in P.iterdir() if f.is_file() and f.suffix in ['.v','.vh','.xml','.sdc','.json']}
 q=dict(identity=identity,winner=winner,bitSHA256=sha(out/(N+'_guard_checked.bit')),hexSHA256=sha(out/(N+'_guard_checked.hex')),sources=source,baselineRuntimeFingerprintSHA256=sha(B/'outflow/runtime_fingerprint.txt'),resources=dict(zip(['xlr','ram10','dsp'],nums)),hardwareTested=False,flashWritten=False)
 (out/'guard_qualification.json').write_text(json.dumps(q,indent=2));print('PASS qualified image1 guard:',winner['recipe'],'same mapped RTL',identity['mappedSHA256'],flush=True)
if __name__=='__main__':main()
