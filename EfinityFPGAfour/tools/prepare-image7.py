"""Create image7 A11 from the preserved image6 four-point source.

Offline development tool only; never opens a USB device, card or programmer.
Refuses to overwrite a generated profile. Model fixtures must already pass the
FPGA_GAME A11 integer qualification before RTL constants are generated.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import shutil
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
PC=ROOT.parent/'FPGA_GAME'
PROFILE='image7_mocap11_a'
PROJECT='Ti60_Image7_Mocap11_A'


def replace_file(path, pairs):
    s=path.read_text(encoding='utf-8-sig')
    for old,new in pairs:
        if old not in s:raise ValueError(f'{path}: missing expected source {old!r}')
        s=s.replace(old,new)
    path.write_text(s,encoding='utf-8')


def prepare(qualified):
    q=json.loads((qualified/'qualification.json').read_text())
    if not q['numerical_passed']:raise ValueError('A11 numerical qualification required')
    source=ROOT/'images/image6_pose_int16';image=ROOT/'images'/PROFILE;rtl=ROOT/'src/pose7'
    if image.exists() or rtl.exists():raise FileExistsError('Preserve existing A11 profile; do not silently regenerate')
    image.mkdir();rtl.mkdir()
    common=[('images/image6_pose_int16','images/'+PROFILE),('src/pose6','src/pose7'),('Ti60_Image6_Pose',PROJECT)]
    for f in source.iterdir():
        if f.is_file() and not f.name.startswith('RUNPNR_'):
            name=f.name.replace('Ti60_Image6_Pose',PROJECT)
            s=f.read_text(encoding='utf-8-sig')
            for a,b in common:s=s.replace(a,b)
            (image/name).write_text(s,encoding='utf-8')
    for f in (ROOT/'src/pose6').iterdir():
        if f.suffix not in ('.v','.sv'):continue
        if f.suffix=='.sv' and f.name not in {'pose6_pipeline_tb.sv','pose6_protocol_tb.sv','pose6_sd_boot_tb.sv','pose6_sd_card_tb.sv','pose6_standalone_tb.sv'}:continue
        s=f.read_text(encoding='utf-8-sig')
        for a,b in common:s=s.replace(a,b)
        (rtl/f.name).write_text(s,encoding='utf-8')
    sys.path.insert(0,str(PC))
    from fourpoint.probe_candidate import generate_constants
    contract,model,mc=generate_constants(image,qualified/'parameters')
    a=contract['addresses'];stages={s['id']:s for s in contract['stages']}
    if stages['head']['co']!=11 or stages['detail']['co']!=8:raise ValueError('Expected preferred A11 architecture')
    network=rtl/'pose6_network.v';s=network.read_text()
    start=s.index(' wire [31:0] source_address=');end=s.index(' assign busy=',start)
    s=s[:start]+f''' wire [31:0] source_address=!glue?
  32'h{a['ctx1']:08x}+((((y>>1)*16+(x>>1))*48+c)<<1):c<32?
  32'h{a['dec1']:08x}+((((y>>1)*32+(x>>1))*32+c)<<1):
  32'h{a['detail']:08x}+(((y*64+x)*8+c-32)<<1);
 wire [31:0] destination_address=!glue?
  32'h{a['up0']:08x}+(((y*32+x)*48+c)<<1):32'h{a['concat']:08x}+(((y*64+x)*40+c)<<1);
'''+s[end:]
    network.write_text(s.replace('(!glue?48:36)','(!glue?48:40)'))
    for f in ('image6_ft_link.v','pose6_pipeline_tb.sv','pose6_standalone_tb.sv','pose6_protocol_tb.sv'):
        replace_file(rtl/f,[('[191:0]','[527:0]')])
    replace_file(image/'image6_platform.v',[('[191:0] w_pose_result_points','[527:0] w_pose_result_points')])
    # Decoder scans NHWC channels across 128-bit DDR beat boundaries. Eleven
    # is not a power of two; unpack[1:0] and >>2 from four-point RTL are invalid.
    decoder=(ROOT/'src/pose6/pose6_decode.v').read_text()
    pairs=[('// Four NHWC','// Eleven NHWC'),('[191:0]','[527:0]'),('[13:0] word_index','[14:0] word_index'),
           ('peak[0:3]','peak[0:10]'),('index[0:3]','index[0:10]'),('reg [1:0] point;','reg [3:0] point;\n reg [3:0] channel;reg [11:0] pixel_index;'),
           (' wire [1:0] channel=unpack[1:0];\n',''),('neighbor_pixel*4+point','neighbor_pixel*11+point'),
           ("32'h02230000",f"32'h{a['head']:08x}"),('point<=0;neighbor<=0;crc<=0;','point<=0;channel<=0;pixel_index<=0;neighbor<=0;crc<=0;'),
           ('for(i=0;i<4;i=i+1)begin peak[i]<=0;index[i]<=0;neighbors[i]<=0;end','for(i=0;i<11;i=i+1)begin peak[i]<=0;index[i]<=0;end\n   for(i=0;i<4;i=i+1)neighbors[i]<=0;'),
           ("word_index<=0;crc<=32'hffffffff;state<=SCANREQ;","word_index<=0;channel<=0;pixel_index<=0;crc<=32'hffffffff;state<=SCANREQ;"),
           ('for(i=0;i<4;i=i+1)begin peak[i]<=0;index[i]<=0;end','for(i=0;i<11;i=i+1)begin peak[i]<=0;index[i]<=0;end'),
           ('crc<=next_crc;','crc<=next_crc;\n     if(channel==10)begin channel<=0;pixel_index<=pixel_index+1\'b1;end else channel<=channel+1\'b1;'),
           ('index[channel]<=(word_index+unpack)>>2','index[channel]<=pixel_index'),('word_index==9208','word_index==25336'),('point==3','point==10')]
    for old,new in pairs:
        if old not in decoder:raise ValueError('Decoder source changed: '+old)
        decoder=decoder.replace(old,new)
    (rtl/'pose6_decode.v').write_text(decoder)
    replace_file(rtl/'pose6_packet.v',[
        ('// FT5! v1 kind=4, 44-byte payload.','// FT5! v2 kind=5, 86-byte payload, eleven anatomical points.'),
        ('[191:0]','[527:0]'),('reg [5:0] index','reg [6:0] index'),('[351:0]','[687:0]'),
        ('4:header=1;5:header=4;','4:header=2;5:header=5;'),('16:header=44;','16:header=86;'),
        ("8'd4,8'd1","8'd11,8'd2"),('index==43','index==85')])
    head=stages['head'];threshold=min(65535,max(0,math.ceil(.2/head['output_scale']+head['output_zero'])))
    overlay=rtl/'pose6_hdmi_overlay.v';s=overlay.read_text()
    for old,new in [('// Four Q14.2','// Eleven Q14.2'),('MIN_PEAK=13759',f'MIN_PEAK={threshold}'),('[191:0]','[527:0]'),('[192:0]','[528:0]'),
                    ('[0:3]','[0:10]'),('[0:2]','[0:11]'),('[3:0] point_ok','[10:0] point_ok'),('[2:0] line_ok','[11:0] line_ok'),
                    ('wire [3:0] point_hit','wire [10:0] point_hit'),('wire [2:0] line_hit','wire [11:0] line_hit'),
                    ('g<4','g<11'),('g<3','g<12'),('i<4','i<11'),('i<3','i<12'),('data_sync[192]','data_sync[528]'),
                    ('data_sync[191:0]','data_sync[527:0]')]:s=s.replace(old,new)
    # Static skeleton topology; arithmetic retains the tested frame-boundary
    # CDC and incremental line rasterization from the four-point design.
    edges=[(0,1),(0,2),(1,2),(1,3),(3,5),(2,4),(4,6),(1,7),(2,8),(7,8),(7,9),(8,10)]
    functions=[]
    for axis in (0,1):
        functions+= [f' function integer endpoint_{axis};', ' input integer line_index;', ' begin case(line_index)']
        functions += [f' {i}:endpoint_{axis}={edge[axis]};' for i,edge in enumerate(edges)]
        functions+= [f' default:endpoint_{axis}=0;', ' endcase end endfunction']
    s=s.replace(' integer i,a,b;','\n'.join(functions)+'\n integer i,a,b;')
    s=s.replace('a=i==2?1:0;b=i==0?1:i==1?2:3;','a=endpoint_0(i);b=endpoint_1(i);')
    begin=s.index('  if(point_hit[0])');end=s.index('  if(hud)',begin)
    colors=['ffffff','49ddff','ffcc55','49ddff','ffcc55','59ff99','ff7799','49ddff','ffcc55','59ff99','ff7799']
    s=s[:begin]+''.join(f"  if(point_hit[{i}])rgb=24'h{color};\n" for i,color in enumerate(colors))+s[end:]
    overlay.write_text(s)
    fixture=qualified/'fixture';sd=json.loads((qualified/'sdcard/manifest.json').read_text());boot=(qualified/'sdcard'/sd['file']).read_bytes()
    phex,ic,hc=(fixture/'expected.vec').read_text().split()
    (image/'pose6_boot_identity.vh').write_text(f'''localparam POSE6_BOOT_BYTES={len(boot)};
localparam [31:0] POSE6_TEST_INPUT_CRC=32'h{ic};
localparam [31:0] POSE6_TEST_HEATMAP_CRC=32'h{hc};
localparam [527:0] POSE6_TEST_POINTS=528'h{phex};
''')
    replace_file(rtl/'pose6_sd_boot.v',[
        ('reg [511:0] header','reg [1023:0] header'),('offset-64','offset-128'),('offset<64','offset<128'),('offset<60','offset<124'),('offset==63','offset==127'),
        ("64'h313045534f503649|| // little-endian I6POSE01","64'h31303131434d3649|| // little-endian I6MC1101"),
        ('header[415:224]','header[751:224]'),('header[447:416]!=1||header[479:448]!=0||{data,header[503:480]}!=~header_crc',
         "header[783:752]!=1||header[815:784]!=11||header[991:816]!=0||{data,header[1015:992]}!=~header_crc")])
    # Source UART model defaults must agree even outside the main top wrapper.
    replace_file(rtl/'pose6_uart_loader.v',[('MODEL_BYTES=161440',f'MODEL_BYTES={len(model)}')])
    # Regression fixtures follow the exact new byte addresses and identities.
    end_address=max(a[s['id']]+s['oh']*s['ow']*s['co']*2 for s in contract['stages'])
    mem_limit=(end_address+65535)&~65535
    for f in ('pose6_pipeline_tb.sv','pose6_standalone_tb.sv'):
        replace_file(rtl/f,[("32'h23ffff",f"32'h{mem_limit-0x02000000-1:x}"),("32'h02240000",f"32'h{mem_limit:08x}"),("32'h240000",f"32'h{mem_limit-0x02000000:x}")])
    replace_file(rtl/'pose6_pipeline_tb.sv',[("32'h021b0000",f"32'h{a['up0']:08x}"),("32'h021e0000",f"32'h{a['concat']:08x}"),('four decoded','eleven decoded')])
    writes=(len(model)+73728)//16
    replace_file(rtl/'pose6_sd_card_tb.sv',[('235231',str(len(boot)-1)),('235232',str(len(boot))),('<58',f'<{math.ceil(len(boot)/4096)}'),('n==57',f'n=={math.ceil(len(boot)/4096)-1}'),('file_index==100','file_index==160')])
    replace_file(rtl/'pose6_sd_boot_tb.sv',[('161440',str(len(model))),('235231',str(len(boot)-1)),('235232',str(len(boot))),('14698',str(writes)),('offset=64+', 'offset=128+'),('offset+k==100','offset+k==160')])
    replace_file(rtl/'pose6_standalone_tb.sv',[('161440',str(len(model))),('boot_file[64+k]','boot_file[128+k]'),('000396E0',f'{len(boot):08X}'),('packet_bytes>=72','packet_bytes>=114')])
    replace_file(rtl/'pose6_protocol_tb.sv',[('j<4','j<11'),('packet_bytes!=72','packet_bytes!=114')])
    # Tests/builds use only the new profile, leaving all old scripts unchanged.
    for name in ['build-image6.ps1','prepare-image6-ft-constraints.py','check-image6-ft.py','check-image6-netlist.py',
                 'test-image6-pipeline.ps1','test-image6-protocol.ps1','test-image6-sd.ps1','test-image6-standalone.ps1']:
        s=(ROOT/'tools'/name).read_text(encoding='utf-8-sig')
        for old,new in common:s=s.replace(old,new)
        s=s.replace('work_sim/pose6_', 'work_sim/pose11_').replace('src/pose6','src/pose11')
        s=s.replace('tmp/image6_standalone','tmp/image6_mocap11_a')
        for original in ['prepare-image6-ft-constraints.py','check-image6-ft.py','check-image6-netlist.py','check-image6-packet.py','check-image6-standalone-packet.py']:
            s=s.replace(original,original.replace('image6','image6-11'))
        if name=='test-image6-pipeline.ps1':
            start=s.index("& 'E:\\Efinity_Project")
            end=s.index('function Run-Tool',start)
            s=s[:start]+s[end:]
        (ROOT/'tools'/name.replace('image6','image6-11')).write_text(s,encoding='utf-8')
    # New protocol tests use an offline packet checker, not a PC application.
    (image/'migration.json').write_text(json.dumps(dict(profile=PROFILE,project=PROJECT,source_hdl_commit='9fe8ca7',source_qualification=str(qualified.resolve()),checkpoint_sha256=q['checkpoint_sha256'],model_crc32=f'{mc:08x}',keypoint_order=contract['keypoint_order'],clock_hz=96000000,lanes=16,point_count=11,sd_format='I6MC1101',packet=dict(magic='FT5!',version=2,kind=5,payload_bytes=86,total_bytes=114),min_peak=threshold,head_scale=head['output_scale'],head_zero=head['output_zero'],hardware_tested=False),indent=2)+'\n')
    # Rename all newly generated modules/files/entry points to image7. Never
    # touch the preserved image6 directory, its sources or its release files.
    renames=[('MODEL6','MODEL7'),('I6MC1101','I7MC1101'),('31303131434d3649','31303131434d3749'),
             ('image6_mocap11_a','image7_mocap11_a'),('image6_top','image7_top'),('image6_platform','image7_platform'),
             ('image6_ft_link','image7_ft_link'),('pose6','pose7'),('pose11','pose7'),('image6-11','image7'),('image6','image7'),('Image6','Image7')]
    generated_tools=[ROOT/'tools'/n.replace('image6','image6-11') for n in ['build-image6.ps1','prepare-image6-ft-constraints.py','check-image6-ft.py','check-image6-netlist.py','test-image6-pipeline.ps1','test-image6-protocol.ps1','test-image6-sd.ps1','test-image6-standalone.ps1']]
    for f in list(image.iterdir())+list(rtl.iterdir())+generated_tools:
        if not f.is_file():continue
        text=f.read_text(encoding='utf-8');name=f.name
        for old,new in renames:text=text.replace(old,new);name=name.replace(old,new)
        if f.suffix=='.xml':text=text.replace('0x00060001','0x0007000b')
        f.write_text(text,encoding='utf-8')
        if name!=f.name:f.rename(f.with_name(name))
    shutil.copy2(ROOT/'tools/image7-overlay-template.sv',rtl/'pose7_overlay_tb.sv')
    sim=ROOT/'work_sim/pose7_pipeline';shutil.copytree(fixture,sim)
    dest=ROOT/'tmp/image7_mocap11_a/sdcard';dest.mkdir(parents=True)
    boot=bytearray(boot);boot[:8]=b'I7MC1101';boot[124:128]=struct.pack('<I',zlib.crc32(boot[:124]))
    (dest/'MODEL7.BIN').write_bytes(boot)
    sd.update(file='MODEL7.BIN',format='I7MC1101',sha256=hashlib.sha256(boot).hexdigest())
    (dest/'manifest.json').write_text(json.dumps(sd,indent=2)+'\n')
    print(f'PASS generated isolated A11 profile; model {len(model)} bytes, SD {len(boot)} bytes, CRC {mc:08x}, head 0x{a["head"]:08x}')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--qualified',type=Path,default=PC/'outputs/fourpoint/mocap11/image7_a11_int16_v2')
    prepare(p.parse_args().qualified)
