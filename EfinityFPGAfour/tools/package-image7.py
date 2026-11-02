"""Package the qualified A11 temporary-JTAG release; never access hardware."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PC=ROOT.parent/'FPGA_GAME'
IMAGE=ROOT/'images/image7_mocap11_a'
OUT=IMAGE/'outflow'
MODEL=PC/'outputs/fourpoint/mocap11/image7_a11_int16_v2'
STAGE=ROOT/'releases/image7/standalone'
PROJECT='Ti60_Image7_Mocap11_A'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint():
    script=r'''
$root=(Get-Location).Path
$imageRoot=Join-Path $root 'images/image7_mocap11_a'
$files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File |
 Where-Object {$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
$files+=Get-ChildItem $imageRoot -File | Where-Object {$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
$files|Sort-Object FullName|ForEach-Object{$_.FullName}
'''
    paths=subprocess.check_output(['pwsh','-NoProfile','-Command',script],cwd=ROOT,text=True).splitlines()
    if not paths:raise RuntimeError('Empty source inventory')
    text='\n'.join(name+':'+sha(Path(name)).upper() for name in paths)
    return hashlib.sha256(text.encode()).hexdigest().upper()


def main():
    global STAGE
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--video-guard',action='store_true',help='Package experimental timing candidate separately from the original release')
    parser.add_argument('--menu',action='store_true',help='Package image7 HDMI menu with fresh control/integration regression')
    args=parser.parse_args()
    if args.menu and args.video_guard:parser.error('Choose one release profile')
    if args.menu:STAGE=ROOT/'releases/image7/menu_v3'
    if args.video_guard:STAGE=ROOT/'releases/image7/video_guard_v2'
    for repo in (ROOT,PC):
        if subprocess.check_output(['git','status','--porcelain'],cwd=repo,text=True).strip():raise RuntimeError(f'Commit final code before packaging: {repo}')
    build=json.loads((OUT/'image7_qualification.json').read_text(encoding='utf-8-sig'))
    if fingerprint()!=build['sourceFingerprintSHA256']:raise RuntimeError('Sources changed after qualified build')
    bit=OUT/(PROJECT+'_timing_checked.bit')
    if sha(bit).upper()!=build['bitSHA256'].upper():raise RuntimeError('Bitstream identity mismatch')
    timing=(OUT/(PROJECT+'.timing.rpt')).read_text()
    section=timing.split('Setup (Max) Clock Relationship',1)[1].split('Clock Relationship Summary (end)',1)[0]
    rows=re.findall(r'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)',section)
    if len(rows)!=28 or any(float(slack)<0 for _,slack in rows):raise RuntimeError('Setup/hold timing gate failed')
    cdc=(OUT/(PROJECT+'.cdc.rpt')).read_text()
    if 'No Synchronizer warnings to report.' not in cdc:raise RuntimeError('CDC review required')
    checks={
        'pipeline':('work_sim/pose7_pipeline/result.log','PASS image7 full pipeline'),
        'overlay':('work_sim/pose7_overlay/result.log','PASS HDMI eleven-point overlay'),
        'protocol':('tmp/image7-protocol.log','PASS image7 eleven-point packet'),
        'standalone':('tmp/image7-standalone.log','PASS contended DDR video'),
    }
    if args.menu:
        checks['pipeline']=('tmp/image7-menu-pipeline.log','PASS image7 full pipeline')
        checks['protocol']=('tmp/image7-menu-protocol.log','PASS image7 eleven-point packet')
        checks['standalone']=('tmp/image7-menu-standalone-final.log','PASS contended DDR video')
        checks['menu']=('tmp/image7-menu.log','PASS image7 menu controller and overlay')
    sources={'fpga/image7_mocap11_a.bit':bit,'sdcard/MODEL7.BIN':ROOT/'tmp/image7_mocap11_a/sdcard/MODEL7.BIN',
             'sdcard/manifest.json':ROOT/'tmp/image7_mocap11_a/sdcard/manifest.json','README.md':ROOT/'docs/image7-mocap11.md',
             'reports/build.json':OUT/'image7_qualification.json','reports/resources.json':OUT/'image7_resources.json',
             'reports/timing.rpt':OUT/(PROJECT+'.timing.rpt'),'reports/cdc.rpt':OUT/(PROJECT+'.cdc.rpt'),
             'reports/int16_qualification.json':MODEL/'qualification.json','reports/calibration.json':MODEL/'calibration.json',
             'reports/peak-domain-and-point-order.json':IMAGE/'migration.json','reports/unit-tests.log':PC/'outputs/fourpoint/mocap11/image7-unit-tests.log'}
    if args.menu:
        sources.update({'README.md':ROOT/'docs/image7-menu.md',
                        'original-image7-usage.md':ROOT/'docs/image7-mocap11.md',
                        'reports/mipi-guard.json':OUT/'image7_mipi_guard.json'})
        # Reuse model-only evidence only if the frozen mathematical and SD
        # paths really are byte-identical to the original qualified release.
        immutable=['images/image7_mocap11_a/pose7_model_identity.vh','images/image7_mocap11_a/pose7_boot_identity.vh',
                   'images/image7_mocap11_a/migration.json','src/pose7/pose7_network.v',
                   'src/pose7/pose7_mac16.v','src/pose7/pose7_requant.v','src/pose7/pose7_input_pool.v',
                   'src/pose7/pose7_decode.v','src/pose7/pose7_fat_reader.v','src/pose7/pose7_axi_master.v','src/pose7/pose7_packet.v','src/pose7/pose7_sd_boot.v',
                   'src/pose7/pose7_hdmi_overlay.v','src/ft232h','src/storage']
        tracked=set(subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines())
        for name in immutable:
            if not (ROOT/name).is_dir() and name not in tracked:raise RuntimeError('Missing immutable source '+name)
        if subprocess.check_output(['git','diff','4ba382d','HEAD','--',*immutable],cwd=ROOT):
            raise RuntimeError('Model-only evidence cannot be reused after mathematical/SD/packet changes')
        guard=json.loads((OUT/'image7_mipi_guard.json').read_text())
        if guard['report_sha256']!=sha(OUT/(PROJECT+'.timing.rpt')) or guard['constraints_sha256']!=sha(IMAGE/(PROJECT+'.pt.sdc')):
            raise RuntimeError('Stale menu MIPI margin evidence')
    if args.video_guard:
        guard=json.loads((OUT/'image7_mipi_guard.json').read_text())
        if not guard['experimental'] or guard['board_failure_resolved']:raise RuntimeError('Unexpected timing experiment status')
        if guard['report_sha256']!=sha(OUT/(PROJECT+'.timing.rpt')) or guard['constraints_sha256']!=sha(IMAGE/(PROJECT+'.pt.sdc')):
            raise RuntimeError('Stale MIPI timing-margin evidence')
        sources.update({'README.md':ROOT/'docs/image7-video-guard.md',
                        'original-image7-usage.md':ROOT/'docs/image7-mocap11.md',
                        'reports/video-diagnosis.md':ROOT/'docs/image7-video-diagnosis.md',
                        'reports/mipi-guard.json':OUT/'image7_mipi_guard.json',
                        'reports/board-image7-before.log':ROOT/'work_sim/image7_video_logs/20261028/COM32_first_image7.log',
                        'reports/board-image6-ab.log':ROOT/'work_sim/image7_video_logs/20261028/COM32_image6_ab.log'})
        # Only constraints changed. Reuse functional RTL regression evidence
        # only after proving every application RTL/header still matches the
        # fully tested A11 baseline; no source changes can slip through here.
        rtl_paths=['src/pose7','pri','images/image7_mocap11_a/*.v','images/image7_mocap11_a/*.vh']
        if subprocess.check_output(['git','diff','4ba382d','HEAD','--',*rtl_paths],cwd=ROOT):raise RuntimeError('Timing-only candidate has RTL changes; fresh functional regression required')
    for label,(name,marker) in checks.items():
        path=ROOT/name;text=path.read_text(errors='replace')
        if marker not in text or re.search(r'(?m)^\s*(Fatal:|ERROR:|FAIL(?:\s|:|$))',text):raise RuntimeError('Failed regression: '+label)
        sources['reports/'+label+'.log']=path
    integration=sources['reports/standalone.log'].read_text(errors='replace')
    for marker in ['PASS image7 standalone integration','PASS integrated ASCII debug','PASS image7 eleven-point packet']:
        if marker not in integration:raise RuntimeError('Missing standalone gate '+marker)
    if args.menu:
        if 'PASS integrated menu:' not in integration:raise RuntimeError('Missing live menu SD/model integration')
        menu_log=sources['reports/menu.log'].read_text(errors='replace')
        for marker in ['PASS image7_menu_ctrl:','PASS image7_menu_config:','PASS image7_menu_cdc:','PASS image7_menu_text_render:','PASS image7_menu_uart:','PASS image7_tile_guard: 2560']:
            if marker not in menu_log:raise RuntimeError('Missing menu gate '+marker)
    for card,volume,fault in [(1,2048,0),(0,0,0)]+[(1,2048,f) for f in range(1,8)]:
        path=ROOT/'work_sim/pose7_sd'/f'sd_{card}_{volume}_{fault}.log';text=path.read_text(errors='replace')
        if 'PASS SD4 boot' not in text or 'Fatal:' in text:raise RuntimeError('Missing SD regression '+path.name)
        sources['reports/'+path.name]=path
    unit=sources['reports/unit-tests.log'].read_text(errors='replace')
    if not re.search(r'Ran \d+ tests',unit) or not re.search(r'(?m)^OK\s*$',unit):raise RuntimeError('Missing unit-test pass')
    sd=json.loads(sources['sdcard/manifest.json'].read_text())
    if sha(sources['sdcard/MODEL7.BIN'])!=sd['sha256']:raise RuntimeError('SD package changed')
    quant=json.loads((MODEL/'qualification.json').read_text())
    if not quant['numerical_passed']:raise RuntimeError('Integer qualification failed')
    resources=json.loads((OUT/'image7_resources.json').read_text())
    if resources['xlr']>60800 or resources['ram10']>256 or resources['dsp']>160:raise RuntimeError('Device capacity exceeded')
    # Old image6 code and published bitstream remain independently verifiable.
    unchanged=subprocess.check_output(['git','diff','9fe8ca7','HEAD','--','images/image6_pose_int16','src/pose6','src/storage','src/vision','images/image5_canny'],cwd=ROOT)
    if unchanged:raise RuntimeError('Preserved image5/image6 runtime sources changed')
    old=ROOT/'releases/image6/standalone/fpga/image6_sd_hdmi.bit'
    old_sha=sha(old) if old.exists() else None
    if old_sha and old_sha!='a79499d8409fd2cc42b75adb49983ea4a0c2a86ff71884a42ca0df19673235e2':raise RuntimeError('Old image6 release changed')
    for folder,prefix in ((MODEL/'parameters','model/parameters'),(MODEL/'fixture','test')):
        for f in folder.rglob('*'):
            if f.is_file():sources[prefix+'/'+f.relative_to(folder).as_posix()]=f
    sources['model/source_best.pt']=MODEL/'source_best.pt'
    sources['model/mocap11_int16_qdq.onnx']=MODEL/'mocap11_int16_qdq.onnx'
    if STAGE.exists():raise FileExistsError('Preserve previous release; choose a new output name')
    for name,path in sources.items():
        target=STAGE/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    # Only version-controlled engineering source, no synthesis work databases.
    paths=subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines()
    paths=[p for p in paths if p.startswith(('src/','pri/','ip/','images/image5_canny/','images/image7_mocap11_a/')) or p.startswith('tools/') and 'image7' in p or p.startswith('docs/image7')]
    project_zip=STAGE/'source/image7_complete_project.zip';project_zip.parent.mkdir()
    with zipfile.ZipFile(project_zip,'w',zipfile.ZIP_DEFLATED) as z:
        for name in paths:z.write(ROOT/name,name)
    with zipfile.ZipFile(project_zip) as z:
        if z.testzip():raise RuntimeError('Source archive integrity failure')
    final_qualification={**build,'rtlRegressionRequired':False,'softwareChecksPassed':True,
                         'runtimeSourceVerified':True,'hardwareTested':False,'boardFPSMeasured':False,
                         'verifiedGates':['integer preservation on 43 development images','92 unit tests','full graph tensor bytes and eleven points/CRC','HDMI CDC and invalidation','UART and atomic USB','9 SD card/fault scenarios','SD self-test/reload/live inference with video/USB contention']}
    qualified_report=STAGE/'reports/qualification.json'
    qualified_report.write_text(json.dumps(final_qualification,indent=2)+'\n')
    if args.menu:final_qualification['verifiedGates'] += ['physical key menu/navigation/edit and closed-knob isolation','UART/menu configuration ownership and numeric clamps','coherent blank-only menu CDC and timing-preserving text overlay','key/command concurrent binary CRC and ASCII message protection','menu-driven inference drain, real missing-file recovery and exact SD self-test','exhaustive equivalence of constant-capacity tile guard and fresh whole-network tensor oracle']
    qualified_report.write_text(json.dumps(final_qualification,indent=2)+'\n')
    manifest=dict(profile='image7_mocap11_a_mipi_guard_candidate' if args.video_guard else 'image7_mocap11_a_temporary_jtag',hardware_tested=False,physical_card_written=False,flash_written=False,
                  previous_image6_unchanged=True,previous_image6_bit_sha256=old_sha,
                  user_reported_image6_sd_and_hdmi_verified=True,pc_runtime_scripts_included=False,
                  clock_hz=96000000,lanes=16,resources=resources,sd_package=sd,setup_hold_relationships=len(rows),
                  hdl_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  pc_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=PC,text=True).strip(),
                  rtl_verified=True,board_fps_measured=False,target_fps=15,
                  files={name:dict(bytes=(STAGE/name).stat().st_size,sha256=sha(STAGE/name)) for name in [*sources,'source/image7_complete_project.zip','reports/qualification.json']})
    if args.video_guard:
        manifest.update(experimental=True,board_failure_resolved=False,rtl_changed=False,
                        functional_rtl_evidence_reused_from_commit='4ba382d',mipi_extra_setup_ns=.5,mipi_extra_hold_ns=.3)
    if args.menu:
        manifest.update(profile='image7_mocap11_a_hdmi_menu_v3',rtl_changed=True,
                        previous_image7_video_guard_user_verified=True,menu_hardware_tested=False,
                        model_only_evidence_reused_from_commit='4ba382d',mipi_extra_setup_ns=.5,mipi_extra_hold_ns=.3)
    (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    archive=ROOT/'releases/image7'/('image7_hdmi_menu_v3.zip' if args.menu else 'image7_mipi_guard_candidate_v2.zip' if args.video_guard else 'image7_mocap11_a_temporary.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for path in STAGE.rglob('*'):
            if path.is_file():z.write(path,path.relative_to(STAGE).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip():raise RuntimeError('Release archive integrity failure')
        for name,info in manifest['files'].items():
            if hashlib.sha256(z.read(name)).hexdigest()!=info['sha256']:raise RuntimeError('Archive file mismatch '+name)
    print(json.dumps(dict(release=str(STAGE),archive=str(archive),sha256=sha(archive),resources=resources,hardware_tested=False),indent=2))


if __name__=='__main__':main()
