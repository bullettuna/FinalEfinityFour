"""Use the existing Efinity SDK with the identified ELITES JTAG cable only.

The SDK's blanket scan aborts on a second FT232H using the D2XX receive driver.
This process-local enumeration filter leaves that receiver and all installed
drivers/SDK files unchanged. Identity and IDCODE are required before download.
Only temporary JTAG configuration is supported; no Flash operations.
Run with Efinity's setup.bat + python3.bat.
"""
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import json
import os
from pathlib import Path
import runpy
import sys


def main():
    root=Path(__file__).resolve().parents[1]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation',choices=['detect','download'])
    p.add_argument('--serial',default='FTC4XDT0')
    p.add_argument('--bit',type=Path,default=root/'images/image6_pose_int16/outflow/Ti60_Image6_Pose_timing_checked.bit')
    a=p.parse_args()
    sdk=Path(os.environ['EFINITY_HOME'])
    sys.path[:0]=[str(sdk/'debugger/bin'),str(sdk/'pgm/bin')]
    from pyftdi.usbtools import UsbTools
    from efx_pgm.usb_resolver import UsbResolver
    from efx_pgm.util.gen_util import set_efinity_user_dir_env
    set_efinity_user_dir_env()
    original=UsbTools._find_devices

    def identified(cls,vendor,product,nocache=False):
        result=set()
        if (vendor,product)!=(0x0403,0x6014):return result
        for device in original(vendor,product,nocache):
            try:
                device._langids=(1033,)
                serial=UsbTools.get_string(device,device.iSerialNumber)
                description=UsbTools.get_string(device,device.iProduct)
            except (NotImplementedError, OSError) as e:
                print(f'Ignoring USB target with incompatible libusb receive driver: {type(e).__name__}',flush=True)
                continue
            print(f'USB descriptor: serial={serial!r}, product={description!r}',flush=True)
            if serial==a.serial:result.add(device)
        cls.UsbDevices[(vendor,product)]=result
        return result

    UsbTools._find_devices=classmethod(identified)
    targets=[d for d in UsbResolver().get_usb_connections() if d.serial_number==a.serial]
    if len(targets)!=1:raise RuntimeError(f'expected one identified ELITES-232DL {a.serial}; got {len(targets)}')
    urls=[u for u in targets[0].URLS if u]
    if len(urls)!=1:raise RuntimeError(f'ambiguous JTAG interface: {urls}')
    url=urls[0]
    print(f'Identified JTAG cable {a.serial}, {url}',flush=True)
    from efx_pgm.efx_hw_common.manager import EfxFTDIHwConnectionManager
    from efx_dbg.jcf import JtagChainEngine,BaseJtagEngine
    saved_argv=sys.argv
    verified=False
    # Match Efinity's jtag_program path: trst=False. The generic chain tool
    # uses a default TRST GPIO and can hold this board in reset.
    for frequency in (1e6,3e6,6e6):
        provider=EfxFTDIHwConnectionManager.get_controller(url,EfxFTDIHwConnectionManager.ConnectionType.JTAG,trst=False,frequency=frequency)
        engine=JtagChainEngine(devices=None,target_num=1,engine_provider=provider)
        try:
            engine.configure(url=url)
            ids=[int(engine.detect_idcode()) for _ in range(2)]
            print(f'JTAG {frequency/1e6:.0f} MHz IDCODE reads: '+', '.join(f'0x{x:08X}' for x in ids),flush=True)
            verified=ids==[0x10660A79,0x10660A79]
            if not verified:
                explicit=[]
                for _ in range(2):
                    engine.reset();engine.write_ir(BaseJtagEngine.INSTR['efx_ti']['IDCODE'])
                    explicit.append(int(engine.read_dr(32)))
                print('Explicit Titanium IDCODE instruction reads: '+', '.join(f'0x{x:08X}' for x in explicit),flush=True)
                verified=explicit==[0x10660A79,0x10660A79]
        finally:engine.close()
        if verified:break
    if not verified:
        raise RuntimeError('Ti60 IDCODE 0x10660A79 not confirmed; no download attempted')
    if a.operation=='detect':return
    qualification=a.bit.parent/'image6_qualification.json'
    q=json.loads(qualification.read_text(encoding='utf-8-sig'))
    digest=hashlib.sha256(a.bit.read_bytes()).hexdigest()
    if digest.upper()!=q['bitSHA256']:raise RuntimeError('qualified bitstream SHA256 mismatch')
    print('IDCODE and bitstream identity verified; temporary JTAG download, no Flash write',flush=True)
    sys.argv=[str(sdk/'pgm/bin/efx_pgm/ftdi_program.py'),'--mode','jtag','--board_profile',
              'Generic Board Profile Using FT232','--url',url,str(a.bit)]
    try:
        try:runpy.run_path(sys.argv[0],run_name='__main__')
        except SystemExit as e:
            if e.code not in (0,None):raise
    finally:sys.argv=saved_argv
    report=dict(jtag_downloaded=True,model_tested=False,device_id='0x10660A79',cable_serial=a.serial,
                url=url,bit_sha256=digest,flash_written=False,
                timestamp=datetime.now(timezone(timedelta(hours=8))).isoformat())
    (a.bit.parent/'image6_jtag_download.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)


if __name__=='__main__':main()
