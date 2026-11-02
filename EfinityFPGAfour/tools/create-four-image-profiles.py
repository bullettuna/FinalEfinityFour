"""Create isolated 7/1/5/2 profiles; never replace qualified projects or bitstreams."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,zipfile,sys
R=Path(__file__).resolve().parents[1]
def read(p):return p.read_text(encoding='utf-8-sig')
def write(p,s):p.write_text(s,encoding='utf-8',newline='\n')
def replace(s,a,b):
 assert a in s,a
 return s.replace(a,b)
def main():
 tmp=R/'tmp/four_images_20261029'
 if '--resume' not in sys.argv:
  tmp.mkdir(parents=True,exist_ok=False)
 else:assert (tmp/'source_before.zip').is_file()
 files=[p for base in ['images','releases'] for p in (R/base).rglob('*') if p.is_file() and p.suffix.lower() in ['.bit','.hex']]
 if '--resume' not in sys.argv:
  (tmp/'preserved.json').write_text(json.dumps([{'path':p.relative_to(R).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files],indent=2))
  (tmp/'base_commit.txt').write_bytes(subprocess.check_output(['git','rev-parse','HEAD'],cwd=R))
  with zipfile.ZipFile(tmp/'source_before.zip','w',zipfile.ZIP_DEFLATED) as z:
   for n in subprocess.check_output(['git','ls-files'],cwd=R,text=True).splitlines():
    if (R/n).is_file():z.write(R/n,n)
 profiles={1:('image1_vision','Ti60_Image1_Vision'),2:('image2_photo_status','Ti60_Image2_Photo_Status'),5:('image5_stable_ui','Ti60_Image5_Stable_UI'),7:('image7_usb_points','Ti60_Image7_USB_Points')}
 for i,(folder,name) in profiles.items():
  dest=R/f'images/image{i}_four_boot';dest.mkdir(exist_ok='--resume' in sys.argv)
  project=f'Ti60_Image{i}_Four_Boot'
  for p in (R/'images'/folder).iterdir():
   if p.is_file() and (p.suffix in ['.v','.sv','.vh','.xml','.sdc','.json']):
    s=read(p).replace(f'images/{folder}/',f'images/image{i}_four_boot/').replace(name,project)
    write(dest/p.name.replace(name,project),s)
  platform=dest/f'image{i}_platform.v'
  if i==1:
   write(platform,read(R/'example_top.v').replace('module example_top #','module image1_four_platform #'))
   p=dest/'image1_top.v';write(p,read(p).replace('example_top #','image1_four_platform #'))
   p=dest/(project+'.xml');write(p,read(p).replace('../../example_top.v','image1_platform.v'))
  s=read(platform).replace('src/ui/flash_image_switch.v','images/four_boot_common/flash_image_switch.v')
  extra={1:[('src/ui/menu_ctrl.v','image1_menu_ctrl.v'),('src/ui/menu_text_render.v','image1_menu_render.v')],
   5:[('images/image5_canny/image5_menu_ctrl.v','image5_menu_ctrl.v'),('src/stable_ui/stable_menu_render5.v','image5_menu_render.v')]}.get(i,[])
  for old,new in extra:
   write(dest/new,read(R/old));s=replace(s,old,f'images/image{i}_four_boot/{new}')
  write(platform,s)
  ctrl=dest/({1:'image1_menu_ctrl.v',2:'image2_menu_ctrl.v',5:'image5_menu_ctrl.v',7:'image7_usb_menu_ctrl.v'}[i])
  render=dest/({1:'image1_menu_render.v',2:'image2_menu_render.v',5:'image5_menu_render.v',7:'image7_usb_menu_render.v'}[i])
  if i!=2:
   s=read(ctrl);s=re.sub(r"boot_selected\s*==\s*(?:2'd)?2\s*\?\s*2'd0\s*:\s*boot_selected\s*\+\s*2'd1","boot_selected+2'd1",s)
   assert 'boot_selected+2\'d1' in s
   write(ctrl,s)
   s=read(render)
   if 'case(slot)' in s:s=replace(s,'2:word_="IMAGE5";default:word_="------";','2:word_="IMAGE5";default:word_="IMAGE2";')
   else:
    s=replace(s,'default:word="IMAGE5      ";','2:word="IMAGE5      ";default:word="IMAGE2      ";')
   write(render,s)
  else:
   s=read(platform)
   s=replace(s,"assign w_boot_safe=1'b1;",'// w_boot_safe comes from the real SD/DDR pipeline drain observer.')
   s=replace(s,'.CURRENT_SLOT(1),.SELECT_ADDR(17),.LOAD_ADDR(18)','.CURRENT_SLOT(3),.SELECT_ADDR(22),.LOAD_ADDR(23)')
   for a,b in [('PHOTO_TF_BUILD?11\'d60:11\'d25',"11'd25"),('PHOTO_TF_BUILD?11\'d30:11\'d8',"11'd8"),('PHOTO_TF_BUILD?11\'d335:11\'d496',"11'd496"),('PHOTO_TF_BUILD?11\'d248:11\'d416',"11'd416"),('PHOTO_TF_BUILD?11\'d280:11\'d313',"11'd313"),('PHOTO_TF_BUILD?9\'d42:9\'d255',"9'd255")]:s=replace(s,a,b)
   s=replace(s,'image2_menu_ctrl u_menu_ctrl (','image2_menu_ctrl u_menu_ctrl (\n                .boot_selected(w_boot_selected),.boot_status(w_boot_status),')
   start=s.index('image2_photo_pipeline #');end=s.index('\n\t);',start)
   block=s[start:end]
   for signal in ['w_photo_capture_request','w_photo_uart_request','w_photo_delete_request','w_sd_info_query_request','w_photo_gallery_toggle_request','w_photo_gallery_prev_request','w_photo_gallery_next_request']:
    block=replace(block,'('+signal+')','('+signal+'&&!w_boot_stop)')
   block=replace(block,'.ui_photo_status(ui_photo_status),','.ui_photo_status(ui_photo_status),.ui_reconfig_idle(w_boot_safe),')
   s=s[:start]+block+s[end:];write(platform,s)
   p=dest/'image2_top.v';s=read(p).replace('image2_platform #(',"image2_platform #(.MULTIBOOT_BUILD(1'b1),")
   s=replace(s,'`include "src/top/camera_board_ports.vh"','`include "src/top/camera_board_ports.vh"\n, input cfg_ERROR,output [1:0] cfg_CBSEL,output cfg_CONFIG,cfg_ENA')
   s=replace(s,'`include "src/top/camera_board_connections.vh"','`include "src/top/camera_board_connections.vh"\n, .cfg_ERROR(cfg_ERROR),.cfg_CBSEL(cfg_CBSEL),.cfg_CONFIG(cfg_CONFIG),.cfg_ENA(cfg_ENA)');write(p,s)
   p=dest/(project+'.peri.xml');s=read(p)
   s=re.sub(r'(<efxpt:ctrl name="cfg"[^>]*clock_name=")"',r'\1clk_sys"',s)
   s=replace(s,'is_remote_update_enable="false"','is_remote_update_enable="true"');write(p,s)
   p=dest/'image2_menu_defs.vh';s=read(p).replace('`define MENU_ITEM_COUNT      22','`define MENU_ITEM_COUNT      24').replace('`define MENU_DISP_WIDTH      267','`define MENU_DISP_WIDTH      273')
   s=replace(s,'// Image2 action slots: no Flash slot changes are exposed in this profile.','// Image2 photo actions and four-slot internal Flash selection.')
   s=replace(s,'`endif',"`define MENU_ITEM_BOOT 5'd22\n`define MENU_ITEM_LOAD 5'd23\n`define MD_BOOT_OFF 267\n`define MD_BOOT_STATUS_OFF 269\n`endif");write(p,s)
   s=read(ctrl).replace('    input clk,','    input [1:0] boot_selected,input [3:0] boot_status,\n    input clk,',1)
   s=replace(s,'`MENU_ITEM_CLEANUP, `MENU_ITEM_VIEW:', '`MENU_ITEM_BOOT, `MENU_ITEM_CLEANUP, `MENU_ITEM_VIEW:')
   s=replace(s,'`MENU_ITEM_CAPTURE, `MENU_ITEM_GALLERY, `MENU_ITEM_SD,','`MENU_ITEM_LOAD, `MENU_ITEM_CAPTURE, `MENU_ITEM_GALLERY, `MENU_ITEM_SD,')
   s=replace(s,"2'd2: if(cursor==`MENU_ITEM_CLEANUP)","2'd2: if(cursor==`MENU_ITEM_BOOT) issue_write(cursor,{10'd0,boot_selected+2'd1});\n                    else if(cursor==`MENU_ITEM_CLEANUP)")
   s=replace(s,'    disp_r[`MD_CLEANUP_OFF', '    disp_r[`MD_BOOT_OFF+:2]=boot_selected;\n    disp_r[`MD_BOOT_STATUS_OFF+:4]=boot_status;\n    disp_r[`MD_CLEANUP_OFF');write(ctrl,s)
   p=dest/'image2_menu_rom.v';s=read(p)
   labels=''
   for row,label in [(22,'BOOT IMAGE'),(23,'LOAD IMAGE')]:
    for col,ch in enumerate(label,1):labels+=f"10'h{row*32+col:03x}:ch=8'h{ord(ch):02x};\n"
   s=replace(s,'case({item,col})','case({item,col})\n'+labels);write(p,s)
   s=read(render);reference=read(R/'src/ui/menu_text_render.v');functions=reference[reference.index('function [7:0] boot_char;'):reference.index('function is_toggle_item;')]
   functions=functions.replace('default:word_="------"','default:word_="IMAGE2"')
   s=replace(s,'function [7:0] hex_char;',functions+'function [7:0] hex_char;')
   s=replace(s,'5\'d29: ch0 = "2";', '5\'d29: ch0 = "4";')
   s=replace(s,'            if (row_item == `MENU_ITEM_VIEW)', '''            if(row_item==`MENU_ITEM_BOOT)begin
                if(cell_col>=12&&cell_col<=17)ch0=boot_char(disp[`MD_BOOT_OFF+:2],cell_col-12);
            end else if(row_item==`MENU_ITEM_LOAD)begin
                if(cell_col>=12&&cell_col<=19)ch0=boot_status_char(disp[`MD_BOOT_STATUS_OFF+:4],cell_col-12);
            end else if (row_item == `MENU_ITEM_VIEW)''');write(render,s)
   p=dest/'image2_photo_pipeline.v';s=read(p)
   s=replace(s,' output [9:0] ui_sd_detail,',' output [9:0] ui_sd_detail,output ui_reconfig_idle,')
   line=' wire channels_idle=!process_busy&&!dma_busy&&!photo_read_busy&&!hi_busy&&!hb_busy&&!save_busy&&!axi_read_stalled;'
   s=replace(s,line,line+'''
 // RECONFIG_IDLE_OBSERVER_BEGIN
 // Caller blocks new commands while draining. Never interrupt FAT/metadata or AXI.
 assign ui_reconfig_idle=channels_idle&&(state==IDLE||state==FAULT||state==DELETE_FAULT)&&
  !query_busy&&!gallery_busy&&!gallery_storage_busy&&!open_saved_photo&&!refresh_pending&&
  !dma_start&&!save_start&&!process_start&&!query_start&&!delete_start&&!reader_reload&&!export_busy;
 // RECONFIG_IDLE_OBSERVER_END''');write(p,s)
 common=R/'images/four_boot_common';common.mkdir()
 s=read(R/'src/ui/flash_image_switch.v').replace('2=image5.','2=image5, 3=image2.').replace('write_value<3','write_value<4');write(common/'flash_image_switch.v',s)
 print('Created four isolated profiles and preserved',len(files),'prior BIT/HEX files')
if __name__=='__main__':main()
