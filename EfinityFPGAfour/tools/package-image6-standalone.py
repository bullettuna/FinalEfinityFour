"""Package a qualified temporary-JTAG standalone image; never touches hardware."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PC=ROOT.parent/'FPGA_GAME'
OUT=ROOT/'images/image6_pose_int16/outflow'
STAGE=ROOT/'releases/image6/standalone'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_fingerprint():
    # Match build-image6.ps1's inventory and Windows sort order. Hash in
    # Python so a child shell's module-autoload configuration is irrelevant.
    script=r'''
$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$imageRoot=Join-Path $root 'images/image6_pose_int16'
$files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File |
 Where-Object {$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
$files+=Get-ChildItem $imageRoot -File | Where-Object {$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
$files|Sort-Object FullName|ForEach-Object{$_.FullName}
'''
    paths=subprocess.check_output(['powershell','-NoProfile','-Command',script],cwd=ROOT,text=True).splitlines()
    if not paths:raise RuntimeError('Empty runtime source inventory')
    fingerprint='\n'.join(name+':'+sha(Path(name)).upper() for name in paths)
    return hashlib.sha256(fingerprint.encode('utf-8')).hexdigest().upper()


def main():
    # Independent training experiments do not belong to the FPGA runtime release.
    # Require every other PC source to match its recorded commit.
    for repo,paths in ((ROOT,[]),(PC,['--','.',':(exclude)fourpoint'])):
        if subprocess.check_output(['git','status','--porcelain',*paths],cwd=repo,text=True).strip():
            raise RuntimeError(f'Commit final source before packaging: {repo}')
    qualification=json.loads((OUT/'image6_qualification.json').read_text(encoding='utf-8-sig'))
    if source_fingerprint()!=qualification['sourceFingerprintSHA256']:
        raise RuntimeError('Runtime RTL/constraints changed after the qualified build')
    bit=OUT/'Ti60_Image6_Pose_timing_checked.bit'
    if sha(bit).upper()!=qualification['bitSHA256'].upper():raise RuntimeError('Bitstream/qualification mismatch')
    s=(OUT/'Ti60_Image6_Pose.timing.rpt').read_text()
    summary=s.split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
    rows=re.findall(r'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',summary)
    if len(rows)!=28 or any(float(slack)<0 for _,slack in rows):raise RuntimeError('Timing qualification incomplete')
    package=ROOT/'tmp/image6_standalone/sdcard/MODEL6.BIN'
    sd_manifest=json.loads((package.parent/'manifest.json').read_text())
    if sha(package)!=sd_manifest['sha256']:raise RuntimeError('SD boot file changed')
    sources={
        'fpga/image6_sd_hdmi.bit':bit,
        'sdcard/MODEL6.BIN':package,
        'sdcard/manifest.json':package.parent/'manifest.json',
        'README.md':ROOT/'docs/image6-standalone.md',
        'reports/build.json':OUT/'image6_qualification.json',
        'reports/resources.json':OUT/'image6_resources.json',
        'reports/timing.rpt':OUT/'Ti60_Image6_Pose.timing.rpt',
        'reports/cdc.rpt':OUT/'Ti60_Image6_Pose.cdc.rpt',
        'reports/pc-tests.log':PC/'outputs/fourpoint/image6/pc-tests-standalone.log',
        'reports/game-tests.log':PC/'outputs/fourpoint/image6/game-tests-standalone.log',
        'reports/overlay.log':ROOT/'work_sim/pose6_overlay/result.log',
        # Current full integration run includes the real outer video arbiter.
        'reports/standalone.log':ROOT/'work_sim/pose6_contended/result.log',
        'reports/contended.log':ROOT/'work_sim/pose6_contended/result.log',
        'reports/debug-uart.log':ROOT/'work_sim/pose6_debug/result.log',
        'reports/usb-oracle.log':ROOT/'work_sim/pose6_contended/usb-oracle.log',
        'reports/arithmetic.log':ROOT/'work_sim/pose6_arithmetic/result.log',
        'reports/convolution.log':ROOT/'work_sim/pose6_conv/result.log',
        'reports/video-coexistence.log':ROOT/'work_sim/pose6_video/result.log',
        'reports/uart.log':ROOT/'work_sim/pose6_protocol/result.log',
        'reports/uart-wire.log':ROOT/'work_sim/pose6_uart_wire/result.log',
        'pc/start-image6.ps1':PC/'start-image6.ps1',
        'pc/image6_control.py':PC/'image6_control.py',
        'pc/config.image6.json':PC/'config.image6.json',
    }
    checks=[('reports/game-tests.log','PASS independent dodge during attack'),
            ('reports/standalone.log','PASS image6 standalone integration'),
            ('reports/contended.log','PASS contended DDR video'),
            ('reports/debug-uart.log','PASS image6 ASCII diagnostics'),
            ('reports/uart-wire.log','PASS image6 ASCII commands over physical UART receiver'),
            ('reports/usb-oracle.log','PASS standalone RTL USB packet'),
            ('reports/arithmetic.log','500 two-stage RNE cases'),
            ('reports/convolution.log','PASS image6 tiled convolution exact uint16 outputs for 10 layers'),
            ('reports/overlay.log','PASS HDMI overlay'),('reports/video-coexistence.log','PASS image6 video coexistence'),
            ('reports/uart.log','PASS image6 UART')]
    for name,marker in checks:
        log=sources[name].read_text(errors='replace')
        if marker not in log or re.search(r'(?m)^\s*(Fatal:|ERROR:|FAIL)',log):raise RuntimeError(f'Missing regression: {name}')
    pc_log=sources['reports/pc-tests.log'].read_text(errors='replace')
    if 'PASS integrated ASCII debug' not in sources['reports/contended.log'].read_text(errors='replace'):
        raise RuntimeError('Missing real SD reload/on/off integration regression')
    if not re.search(r'Ran 40 tests',pc_log) or not re.search(r'(?m)^OK\s*$',pc_log):raise RuntimeError('PC regression missing')
    for card,volume,fault in [(1,2048,0),(0,0,0)]+[(1,2048,f) for f in range(1,8)]:
        name=f'sd_{card}_{volume}_{fault}.log'
        log=ROOT/'work_sim/pose6_sd'/name
        text=log.read_text(errors='replace')
        if 'PASS SD4 boot' not in text or 'Fatal:' in text:raise RuntimeError(f'SD regression missing: {name}')
        sources['reports/'+name]=log
    resources=json.loads(sources['reports/resources.json'].read_text())
    manifest=dict(profile='image6_sd_hdmi_temporary_jtag',hardware_tested=False,sd_physical_read_write_verified=False,
                  flash_written=False,card_written=False,card='user 2 GB FAT32; copy file manually later',
                  uart_debug_commands=['~6S','~6F','~6V','~6+','~6-','~6R','~6H'],
                  hdl_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  pc_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=PC,text=True).strip(),
                  timing_relationships=len(rows),resources=resources,sd_package=sd_manifest,
                  files={name:dict(bytes=path.stat().st_size,sha256=sha(path)) for name,path in sources.items()})
    for name,path in sources.items():
        target=STAGE/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    final_qualification={**qualification,'rtlRegressionRequired':False,'hardwareTested':False,
                         'runtimeSourceVerified':True,'softwareChecksPassed':True,
                         'hdlCommit':manifest['hdl_commit'],'pcCommit':manifest['pc_commit'],
                         'tests':{name:info for name,info in manifest['files'].items() if name.endswith('.log')}}
    qualified_report=STAGE/'reports/qualification.json'
    qualified_report.write_text(json.dumps(final_qualification,indent=2)+'\n')
    manifest['files']['reports/qualification.json']=dict(bytes=qualified_report.stat().st_size,sha256=sha(qualified_report))
    (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    archive=ROOT/'releases/image6/image6_sd_hdmi_temporary.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name in [*sources,'manifest.json','reports/qualification.json']:z.write(STAGE/name,name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise RuntimeError('Archive integrity failure')
        for name,path in sources.items():
            if hashlib.sha256(z.read(name)).hexdigest()!=sha(path):raise RuntimeError(f'Archive mismatch: {name}')
    print(json.dumps(dict(directory=str(STAGE),archive=str(archive),archive_sha256=sha(archive),
                          bit_sha256=sha(bit),resources=resources,hardware_tested=False),indent=2))


if __name__=='__main__':main()
