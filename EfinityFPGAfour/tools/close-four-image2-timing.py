"""Try isolated placements of the SAME mapped image2; adopt only a fully timed winner."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import argparse,hashlib,json,re,shutil,subprocess
R=Path(__file__).resolve().parents[1];P=R/'images/image2_four_boot';N='Ti60_Image2_Four_Boot';T=R/'tmp/four_images_20261029'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def timed(out):
 p=out/(N+'.timing.rpt')
 if not p.exists():return False,[]
 s=p.read_text().split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
 rows=re.findall(r'^\s+(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',s,re.M)
 bad=[row for row in rows if float(row[3])<0]
 return len(rows)>=28 and not bad and 'No Synchronizer warnings to report.' in (out/(N+'.cdc.rpt')).read_text(),bad
def flow(p,which):
 cmd='call "E:\\Efinity\\bin\\setup.bat" >nul && call "E:\\Efinity\\bin\\efx_run.bat" '+N+'.xml --flow '+which
 v=subprocess.run('cmd.exe /d /s /c "'+cmd+'"',cwd=p,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (p/(which+'_flow.log')).write_text(v.stdout,encoding='utf-8');return v.returncode==0
def run(seed,skew):
 trial=R/f'tmp/four_image2_s{seed}_{skew}';assert not trial.exists();trial.mkdir()
 for f in P.iterdir():
  if f.is_file() and f.suffix in ['.v','.vh','.xml','.json','.sdc']:shutil.copy2(f,trial/f.name)
 shutil.copytree(P/'outflow',trial/'outflow')
 # This is a PNR-only experiment: every candidate consumes an identical map.
 assert sha(trial/'outflow'/(N+'.map.v'))==sha(P/'outflow'/(N+'.map.v'))
 xml=trial/(N+'.xml');s=xml.read_text();s=re.sub(r'name="seed" value="\d+"',f'name="seed" value="{seed}"',s)
 s=re.sub(r'name="beneficial_skew" value="\w+"',f'name="beneficial_skew" value="{skew}"',s);xml.write_text(s)
 for f in [trial/'board-domains.sdc',trial/(N+'.pt.sdc')]:
  s=f.read_text().replace('-hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.700','-hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.600');f.write_text(s)
 # Do not count a stale report copied from an earlier failed route.
 started=__import__('time').time();print('START isolated image2 seed',seed,'skew',skew,flush=True)
 ok=flow(trial,'pnr');passed,bad=timed(trial/'outflow') if ok else (False,[])
 if passed:assert (trial/'outflow'/(N+'.timing.rpt')).stat().st_mtime>=started
 print('RESULT seed',seed,skew,'PASS' if passed else 'REJECT',bad,flush=True)
 return dict(seed=seed,beneficial_skew=skew,directory=str(trial),routed=ok,timingPassed=passed,violations=bad)
def main():
 a=argparse.ArgumentParser();a.add_argument('--seeds',type=int,nargs='+',required=True);a.add_argument('--skew',choices=['on','off'],default='on');v=a.parse_args()
 results=[]
 with ThreadPoolExecutor(max_workers=2) as pool:
  for future in as_completed([pool.submit(run,s,v.skew) for s in v.seeds]):results.append(future.result())
 winners=[r for r in results if r['timingPassed']]
 record=T/('placements_'+'_'.join(map(str,v.seeds))+'_'+v.skew+'.json');record.write_text(json.dumps(results,indent=2))
 if not winners:raise SystemExit('No candidate qualified; original project untouched')
 winner=winners[0];trial=Path(winner['directory']);assert flow(trial,'pgm')
 assert sha(trial/'outflow'/(N+'.map.v'))==sha(P/'outflow'/(N+'.map.v'))
 backup=T/('before_adopt_seed'+str(winner['seed'])+'_'+v.skew);backup.mkdir()
 for f in [P/(N+'.xml'),P/(N+'.pt.sdc'),P/'board-domains.sdc']+list((P/'outflow').glob(N+'.*')):
  if f.is_file():shutil.copy2(f,backup/f.name)
 for f in [N+'.xml',N+'.pt.sdc','board-domains.sdc']:shutil.copy2(trial/f,P/f)
 for f in (trial/'outflow').iterdir():
  if f.is_file():shutil.copy2(f,P/'outflow'/f.name)
 (P/'outflow/placement_provenance.json').write_text(json.dumps(dict(winner=winner,sourceMapSHA256=sha(P/'outflow'/(N+'.map.v')),allTrials=str(record)),indent=2))
 print('ADOPTED fully timed placement seed',winner['seed'],v.skew,'same mapped RTL; run build-four-image.ps1 -Image 2 -QualifyOnly',flush=True)
if __name__=='__main__':main()
