"""Archive the checked bitstream, model, deterministic input and evidence."""
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
import zlib


def sha(data):return hashlib.sha256(data).hexdigest()


def main():
    p=argparse.ArgumentParser();p.add_argument('--game-root',type=Path,default=Path('E:/Efinity_Project/FPGA_GAME'));a=p.parse_args()
    root=Path(__file__).resolve().parents[1];out=root/'releases/image6';out.mkdir(parents=True,exist_ok=True)
    flow=root/'images/image6_pose_int16/outflow';parameters=root/'tmp/image6_parameters';test=root/'work_sim/pose6_pipeline'
    q=json.loads((flow/'image6_qualification.json').read_text(encoding='utf-8-sig'))
    bit=flow/'Ti60_Image6_Pose_timing_checked.bit'
    if sha(bit.read_bytes()).upper()!=q['bitSHA256']:raise ValueError('bitstream identity mismatch')
    model=(parameters/'model.bin').read_bytes()
    if len(model)!=161440 or zlib.crc32(model)!=0xbbffdf52:
        raise ValueError('model payload does not match the compiled image6 identity')
    files={
        'README.md':out/'README.md',
        'bitstream/Ti60_Image6_Pose_timing_checked.bit':bit,
        'bitstream/image6_qualification.json':flow/'image6_qualification.json',
        'model/model.bin':parameters/'model.bin',
        'model/manifest.json':parameters/'manifest.json',
        'model/contract.json':root/'images/image6_pose_int16/model-contract.json',
        'test/input.u16':test/'trace/input.u16',
        'test/expected.vec':test/'expected.vec',
        'docs/IMAGE6.md':a.game_root/'IMAGE6.md',
        'docs/hdl-image6.md':root/'docs/image6-pose-int16.md',
    }
    for name in ['place.rpt','timing.rpt','pt_timing.rpt']:
        files['reports/'+name]=flow/('Ti60_Image6_Pose.'+name)
    for name in ['ft232h_external_budget.json','image6_resources.json']:
        files['reports/'+name]=flow/name
    for folder in ['pose6_arithmetic','pose6_conv','pose6_pipeline','pose6_protocol','pose6_axi']:
        files['reports/'+folder+'.log']=root/'work_sim'/folder/'result.log'
    for name in ['integer_validation/validation.json','pc-tests.log','controller-tests.log']:
        f=a.game_root/'outputs/fourpoint/image6'/name
        if f.exists():files['reports/'+Path(name).name]=f
    sources={}
    for key,directory in [('hdl',root),('pc',a.game_root)]:
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=directory,text=True).strip()
        dirty=subprocess.check_output(['git','status','--porcelain'],cwd=directory,text=True).strip()
        sources[key]=dict(directory=str(directory),commit=commit,dirty=bool(dirty))
    board_file=a.game_root/'outputs/fourpoint/image6/board_test.json'
    jtag_file=flow/'image6_jtag_download.json'
    jtag=json.loads(jtag_file.read_text()) if jtag_file.exists() else {}
    board=json.loads(board_file.read_text()) if board_file.exists() else {}
    jtag_ok=bool(jtag.get('jtag_downloaded') and jtag.get('bit_sha256')==sha(bit.read_bytes()))
    board_ok=bool(board.get('passed') and board.get('model_crc32')=='bbffdf52')
    if jtag_ok:files['reports/image6_jtag_download.json']=jtag_file
    if board_ok:files['reports/board_test.json']=board_file
    record=dict(created=datetime.now(timezone(timedelta(hours=8))).isoformat(),sources=sources,
                scope='Software/build/simulation delivery complete; physical board validation is owned by the user and remains unverified',
                software_delivery_complete=True,
                jtag_downloaded=jtag_ok,deterministic_board_test_passed=board_ok,live_game_verified=False,
                bitstream_sha256=sha(bit.read_bytes()),model_crc32='bbffdf52',
                resources=dict(xlr=31010,xlr_total=60800,ram10=184,ram10_total=256,dsp=50,dsp_total=160),
                source_file_hashes={name:sha(f.read_bytes()) for name,f in files.items()})
    archive=out/'image6_int16_prototype.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for name,f in files.items():z.write(f,name)
        z.writestr('manifest.json',json.dumps(record,indent=2)+'\n')
    record['archive_sha256']=sha(archive.read_bytes());record['archive_bytes']=archive.stat().st_size
    (out/'manifest.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:raise AssertionError('archive CRC check failed')
    print(json.dumps({k:v for k,v in record.items() if k!='source_file_hashes'},indent=2))


if __name__=='__main__':main()
