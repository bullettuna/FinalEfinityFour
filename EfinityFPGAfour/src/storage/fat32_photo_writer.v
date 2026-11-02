`timescale 1ns/1ps
// Bounded FAT32 writer: IMG00001.BMP..IMG99999.BMP, RGB565 BI_BITFIELDS,
// 512-byte pixel offset, bottom-up pixels supplied from committed DDR.
// Uses an existing directory slot and a verified free contiguous cluster run.
// Directory publication is LAST. Unsupported/full volumes fail without
// formatting, overwriting another file, or issuing a success notification.
module fat32_photo_writer #(
 parameter WIDTH=960,HEIGHT=540,WAIT_TIMEOUT=192000000,ENABLE_DELETE=0
)(input clk,input rst_n,input start,
 input delete_start,input [31:0] delete_number,
 output reg delete_done,output reg delete_error,output reg delete_mutated,
 output reg busy,output reg done,output reg error,output reg [7:0] error_code,
 output reg [31:0] file_number,
 output [5:0] debug_state,output [2:0] debug_purpose,output reg [5:0] error_stage,
 output reg init_start,input init_done,input init_error,input [31:0] capacity_mb,
 output reg block_start,output reg block_write,output reg [31:0] block_lba,
 input block_done,input block_error,input block_rx_valid,input [7:0] block_rx_data,
 input [8:0] block_byte_index,output reg [7:0] block_tx_byte,
 output reg photo_start,output reg [19:0] photo_offset,
 input photo_done,input photo_error,input photo_valid,input [8:0] photo_index,input [7:0] photo_byte
);
 localparam PIXEL_BYTES=WIDTH*HEIGHT*2, FILE_BYTES=PIXEL_BYTES+512, FILE_SECTORS=FILE_BYTES/512;
 localparam IDLE=0,INIT=1,BOOT=2,GEOMETRY=3,DIR=4,DIR_CHECK=5,DIR_NEXT=6,
  ALLOC=7,ALLOC_CHECK=8,HEADER=9,DATA=10,DATA_WAIT=11,DATA_NEXT=12,
  FAT_READ=13,FAT_EDIT=14,FAT_WRITE=15,FAT_NEXT=16,FS_READ=17,FS_CHECK=18,
  FS_EDIT=19,FS_WRITE=20,FS_NEXT=21,DIR_READ=22,DIR_EDIT=23,DIR_END=24,
  DIR_WRITE=25,FINISH=26,FAILED=27,IO=28,BCD=29,
  DEL_HEADER=30,DEL_HEADER_CHECK=31,DEL_VERIFY=32,DEL_VERIFY_CHECK=33,
  DEL_DIR_READ=34,DEL_DIR_MARK=35,DEL_DIR_WRITE=36,DEL_FREE_START=37;
 localparam P_BOOT=0,P_DIR=1,P_ALLOC=2,P_FAT=3,P_FS=4,P_KEEP=5,P_HEADER=6;
 reg [5:0] state,return_state;reg [2:0] purpose;
 reg deleting,delete_found,preceding_lfn;
 reg [31:0] delete_target,delete_lba,delete_cluster,delete_size,entry_cluster,entry_size;
 reg [8:0] delete_offset;
 reg [31:0] chain_steps,chain_next;
 reg verify_copy;
 reg [15:0] bmp_magic,bmp_bpp;
 reg [31:0] bmp_size,bmp_offset,bmp_width,bmp_height,bmp_compression,bmp_rmask,bmp_gmask,bmp_bmask;
 wire bmp_delete_ok=bmp_magic==16'h4d42 && bmp_size==FILE_BYTES && bmp_offset==512 &&
   bmp_width==WIDTH && bmp_height==HEIGHT && bmp_bpp==16 && bmp_compression==3 &&
   bmp_rmask==32'hf800 && bmp_gmask==32'h07e0 && bmp_bmask==32'h001f;
 reg [31:0] wait_timer;
 assign debug_state=state;assign debug_purpose=purpose;
 (* ram_style="block" *) reg [7:0] sector[0:511];
 reg cpu_we;reg [8:0] cpu_addr;reg [7:0] cpu_data;
 wire sector_we=block_rx_valid||photo_valid||cpu_we;
 wire [8:0] sector_wa=block_rx_valid?block_byte_index:(photo_valid?photo_index:cpu_addr);
 wire [7:0] sector_wd=block_rx_valid?block_rx_data:(photo_valid?photo_byte:cpu_data);
 always @(posedge clk) begin
  block_tx_byte<=sector[block_byte_index];
  if(sector_we) sector[sector_wa]<=sector_wd;
 end
 reg [15:0] sig,bps,reserved,root_entries,fat16,extflags,fs_version,fsinfo,backup;
 reg [7:0] spc,nfats,part_type;
 reg [31:0] total,fatsz,root,partition,part_tmp,volume;
 reg part_found;
 reg [31:0] fat_base,data_base,max_cluster,needed;
 reg [3:0] cluster_shift;
 reg [31:0] dir_cluster,dir_steps;reg [7:0] dir_sector;
 reg free_found,free_was_end,dir_end;
 reg [31:0] free_lba,max_number;reg [8:0] free_offset;
 reg [7:0] first_char,entry_attr;reg name_ok;reg [31:0] entry_number;
 reg [31:0] alloc_sector,run_start,run_length,file_cluster,file_lba;
 reg alloc_found;reg [23:0] fat_low;reg [31:0] fat_value;
 reg [8:0] fat_offset;reg [3:0] fat_top;
 reg [31:0] data_sector,write_cluster;reg fat_copy;
 reg [8:0] edit_index;reg fs_copy;
 reg [31:0] fs_sig0,fs_sig1,fs_sig2;
 wire [31:0] scan_cluster=(alloc_sector<<7)+{25'd0,block_byte_index[8:2]};
 wire [31:0] received_fat={4'd0,block_rx_data[3:0],fat_low};
 wire [31:0] next_fat=deleting?32'd0:((write_cluster==file_cluster+needed-1)?32'h0fffffff:write_cluster+1'b1);
 wire chain_link_ok=(chain_steps+1==needed)?fat_value>=32'h0ffffff8:
   (fat_value>=2 && fat_value<=max_cluster && fat_value<32'h0ffffff0);
 wire [31:0] all_fat_sectors=nfats==2?(fatsz<<1):fatsz;
 wire [31:0] data_sectors=total-reserved-all_fat_sectors;
 reg [19:0] number_bcd,bcd_adjusted;
 reg [16:0] number_shift;
 reg [4:0] number_bits;
 integer digit;
 always @* begin
  bcd_adjusted=number_bcd;
  for(digit=0;digit<5;digit=digit+1)
   if(number_bcd[digit*4 +:4]>=5)bcd_adjusted[digit*4 +:4]=number_bcd[digit*4 +:4]+4'd3;
 end
 function [3:0] spc_log;
 input [7:0] s;
 begin case(s)1:spc_log=0;2:spc_log=1;4:spc_log=2;8:spc_log=3;
 16:spc_log=4;32:spc_log=5;64:spc_log=6;128:spc_log=7;default:spc_log=15;endcase end
 endfunction
 function [7:0] header_byte;
 input [8:0] i;
 begin
  header_byte=0;
  case(i)
   0:header_byte="B";1:header_byte="M";
   2:header_byte=FILE_BYTES;3:header_byte=FILE_BYTES>>8;4:header_byte=FILE_BYTES>>16;5:header_byte=FILE_BYTES>>24;
   11:header_byte=2;14:header_byte=40;
   18:header_byte=WIDTH;19:header_byte=WIDTH>>8;
   22:header_byte=HEIGHT;23:header_byte=HEIGHT>>8;
   26:header_byte=1;28:header_byte=16;30:header_byte=3;
   34:header_byte=PIXEL_BYTES;35:header_byte=PIXEL_BYTES>>8;36:header_byte=PIXEL_BYTES>>16;37:header_byte=PIXEL_BYTES>>24;
   55:header_byte=8'hf8;58:header_byte=8'he0;59:header_byte=8'h07;62:header_byte=8'h1f;
   default:header_byte=0;
  endcase
 end
 endfunction
 function [7:0] directory_byte;
 input [4:0] i;
 begin
  directory_byte=0;
  case(i)
   0:directory_byte="I";1:directory_byte="M";2:directory_byte="G";
   3:directory_byte=48+number_bcd[19:16];
   4:directory_byte=48+number_bcd[15:12];
   5:directory_byte=48+number_bcd[11:8];
   6:directory_byte=48+number_bcd[7:4];
   7:directory_byte=48+number_bcd[3:0];
   8:directory_byte="B";9:directory_byte="M";10:directory_byte="P";11:directory_byte=8'h20;
   16,18,24:directory_byte=8'h21; // 1980-01-01, time unavailable
   20:directory_byte=file_cluster>>16;21:directory_byte=file_cluster>>24;
   26:directory_byte=file_cluster;27:directory_byte=file_cluster>>8;
   28:directory_byte=FILE_BYTES;29:directory_byte=FILE_BYTES>>8;
   30:directory_byte=FILE_BYTES>>16;31:directory_byte=FILE_BYTES>>24;
   default:directory_byte=0;
  endcase
 end
 endfunction
 task issue;
 input wr;input [31:0] lba;input [2:0] why;input [5:0] next;
 begin block_write<=wr;block_lba<=lba;purpose<=why;return_state<=next;block_start<=1;state<=IO;end
 endtask
 task fail;
 input [7:0] code;
 begin error_code<=code;error_stage<=state;state<=FAILED;end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;return_state<=0;purpose<=0;busy<=0;done<=0;error<=0;error_code<=0;file_number<=0;
   init_start<=0;block_start<=0;block_write<=0;block_lba<=0;photo_start<=0;photo_offset<=0;
   deleting<=0;delete_found<=0;preceding_lfn<=0;delete_target<=0;delete_lba<=0;delete_cluster<=0;delete_size<=0;
   delete_offset<=0;entry_cluster<=0;entry_size<=0;chain_steps<=0;chain_next<=0;verify_copy<=0;
   delete_done<=0;delete_error<=0;delete_mutated<=0;
   bmp_magic<=0;bmp_size<=0;bmp_offset<=0;bmp_width<=0;bmp_height<=0;bmp_bpp<=0;bmp_compression<=0;
   bmp_rmask<=0;bmp_gmask<=0;bmp_bmask<=0;
   cpu_we<=0;cpu_addr<=0;cpu_data<=0;sig<=0;bps<=0;reserved<=0;root_entries<=0;fat16<=0;
   extflags<=0;fs_version<=0;fsinfo<=0;backup<=0;spc<=0;nfats<=0;part_type<=0;total<=0;fatsz<=0;root<=0;
   partition<=0;part_tmp<=0;volume<=0;part_found<=0;fat_base<=0;data_base<=0;max_cluster<=0;needed<=0;cluster_shift<=0;
   dir_cluster<=0;dir_steps<=0;dir_sector<=0;free_found<=0;free_was_end<=0;dir_end<=0;free_lba<=0;max_number<=0;free_offset<=0;
   first_char<=0;entry_attr<=0;name_ok<=0;entry_number<=0;alloc_sector<=0;run_start<=0;run_length<=0;file_cluster<=0;file_lba<=0;
   alloc_found<=0;fat_low<=0;fat_value<=0;fat_offset<=0;fat_top<=0;data_sector<=0;write_cluster<=0;fat_copy<=0;
   edit_index<=0;fs_copy<=0;fs_sig0<=0;fs_sig1<=0;fs_sig2<=0;
   number_bcd<=0;number_shift<=0;number_bits<=0;
   wait_timer<=0;error_stage<=0;
  end else begin
   done<=0;error<=0;delete_done<=0;delete_error<=0;init_start<=0;block_start<=0;photo_start<=0;cpu_we<=0;
   // Bound each wait for progress, not the total time to scan/save a card.
   if(state==INIT || state==IO || state==DATA_WAIT)begin
    if(init_done||init_error||block_done||block_error||block_rx_valid||photo_valid||photo_done||photo_error)
     wait_timer<=0;
    else if(wait_timer<WAIT_TIMEOUT)wait_timer<=wait_timer+1'b1;
   end else wait_timer<=0;
   if(block_rx_valid && state==IO) begin
    if(purpose==P_BOOT) begin
     case(block_byte_index)
      11:bps[7:0]<=block_rx_data;12:bps[15:8]<=block_rx_data;13:spc<=block_rx_data;
      14:reserved[7:0]<=block_rx_data;15:reserved[15:8]<=block_rx_data;16:nfats<=block_rx_data;
      17:root_entries[7:0]<=block_rx_data;18:root_entries[15:8]<=block_rx_data;
      22:fat16[7:0]<=block_rx_data;23:fat16[15:8]<=block_rx_data;
      32:total[7:0]<=block_rx_data;33:total[15:8]<=block_rx_data;34:total[23:16]<=block_rx_data;35:total[31:24]<=block_rx_data;
      36:fatsz[7:0]<=block_rx_data;37:fatsz[15:8]<=block_rx_data;38:fatsz[23:16]<=block_rx_data;39:fatsz[31:24]<=block_rx_data;
      40:extflags[7:0]<=block_rx_data;41:extflags[15:8]<=block_rx_data;42:fs_version[7:0]<=block_rx_data;43:fs_version[15:8]<=block_rx_data;
      44:root[7:0]<=block_rx_data;45:root[15:8]<=block_rx_data;46:root[23:16]<=block_rx_data;47:root[31:24]<=block_rx_data;
      48:fsinfo[7:0]<=block_rx_data;49:fsinfo[15:8]<=block_rx_data;50:backup[7:0]<=block_rx_data;51:backup[15:8]<=block_rx_data;
      510:sig[7:0]<=block_rx_data;511:sig[15:8]<=block_rx_data;
     endcase
     if(block_byte_index>=446 && block_byte_index<510) begin
      case((block_byte_index-446)&15)
       4:part_type<=block_rx_data;
       8:part_tmp[7:0]<=block_rx_data;9:part_tmp[15:8]<=block_rx_data;
       10:part_tmp[23:16]<=block_rx_data;11:part_tmp[31:24]<=block_rx_data;
       15:if(!part_found&&(part_type==8'h0b||part_type==8'h0c)) begin partition<=part_tmp;part_found<=1;end
      endcase
     end
    end
    if(purpose==P_DIR&&!dir_end) begin
     case(block_byte_index[4:0])
      0:begin first_char<=block_rx_data;name_ok<=(block_rx_data=="I");entry_number<=0;entry_cluster<=0;entry_size<=0;end
      1:if(block_rx_data!="M")name_ok<=0;
      2:if(block_rx_data!="G")name_ok<=0;
      3,4,5,6,7:begin
       if(block_rx_data<"0"||block_rx_data>"9")name_ok<=0;
       entry_number<=entry_number*10+block_rx_data-48;
      end
      8:if(block_rx_data!="B")name_ok<=0;
      9:if(block_rx_data!="M")name_ok<=0;
      10:if(block_rx_data!="P")name_ok<=0;
      11:entry_attr<=block_rx_data;
      20:entry_cluster[23:16]<=block_rx_data;21:entry_cluster[31:24]<=block_rx_data;
      26:entry_cluster[7:0]<=block_rx_data;27:entry_cluster[15:8]<=block_rx_data;
      28:entry_size[7:0]<=block_rx_data;29:entry_size[15:8]<=block_rx_data;30:entry_size[23:16]<=block_rx_data;
      31:begin
       if(ENABLE_DELETE && deleting && !delete_found && name_ok && entry_number==delete_target &&
          entry_attr==8'h20 && !preceding_lfn && first_char!=0 && first_char!=8'he5)begin
        delete_found<=1;delete_lba<=block_lba;delete_offset<={block_byte_index[8:5],5'd0};
        delete_cluster<=entry_cluster;delete_size<={block_rx_data,entry_size[23:0]};
       end
       preceding_lfn<=entry_attr==8'h0f && first_char!=0 && first_char!=8'he5;
       if(name_ok && first_char!=8'he5 && entry_attr!=8'h0f && !entry_attr[4] && !entry_attr[3] && entry_number>max_number)
        max_number<=entry_number;
       if(!free_found && (first_char==8'he5 || (first_char==0 && block_byte_index[8:5]!=15))) begin
        free_found<=1;free_was_end<=first_char==0;free_lba<=block_lba;free_offset<={block_byte_index[8:5],5'd0};
       end
       if(first_char==0)dir_end<=1;
      end
     endcase
    end
    if(purpose==P_ALLOC) begin
     case(block_byte_index[1:0])
      0:fat_low[7:0]<=block_rx_data;1:fat_low[15:8]<=block_rx_data;2:fat_low[23:16]<=block_rx_data;
      3:if(!alloc_found&&scan_cluster>=2&&scan_cluster<=max_cluster) begin
       if(received_fat==0) begin
        if(run_length==0)run_start<=scan_cluster;
        run_length<=run_length+1'b1;
        if(run_length+1>=needed)begin alloc_found<=1;file_cluster<=run_length==0?scan_cluster:run_start;end
       end else run_length<=0;
      end
     endcase
    end
    if(purpose==P_FAT) begin
     if(block_byte_index==fat_offset)fat_value[7:0]<=block_rx_data;
     if(block_byte_index==fat_offset+1)fat_value[15:8]<=block_rx_data;
     if(block_byte_index==fat_offset+2)fat_value[23:16]<=block_rx_data;
     if(block_byte_index==fat_offset+3)begin fat_value[31:24]<={4'd0,block_rx_data[3:0]};fat_top<=block_rx_data[7:4];end
    end
    if(purpose==P_HEADER && ENABLE_DELETE)begin
     case(block_byte_index)
      0:bmp_magic[7:0]<=block_rx_data;1:bmp_magic[15:8]<=block_rx_data;
      2,3,4,5:bmp_size[(block_byte_index-2)*8+:8]<=block_rx_data;
      10,11,12,13:bmp_offset[(block_byte_index-10)*8+:8]<=block_rx_data;
      18,19,20,21:bmp_width[(block_byte_index-18)*8+:8]<=block_rx_data;
      22,23,24,25:bmp_height[(block_byte_index-22)*8+:8]<=block_rx_data;
      28:bmp_bpp[7:0]<=block_rx_data;29:bmp_bpp[15:8]<=block_rx_data;
      30,31,32,33:bmp_compression[(block_byte_index-30)*8+:8]<=block_rx_data;
      54,55,56,57:bmp_rmask[(block_byte_index-54)*8+:8]<=block_rx_data;
      58,59,60,61:bmp_gmask[(block_byte_index-58)*8+:8]<=block_rx_data;
      62,63,64,65:bmp_bmask[(block_byte_index-62)*8+:8]<=block_rx_data;
     endcase
    end
    if(purpose==P_FS) begin
     case(block_byte_index)
      0:fs_sig0[7:0]<=block_rx_data;1:fs_sig0[15:8]<=block_rx_data;2:fs_sig0[23:16]<=block_rx_data;3:fs_sig0[31:24]<=block_rx_data;
      484:fs_sig1[7:0]<=block_rx_data;485:fs_sig1[15:8]<=block_rx_data;486:fs_sig1[23:16]<=block_rx_data;487:fs_sig1[31:24]<=block_rx_data;
      508:fs_sig2[7:0]<=block_rx_data;509:fs_sig2[15:8]<=block_rx_data;510:fs_sig2[23:16]<=block_rx_data;511:fs_sig2[31:24]<=block_rx_data;
     endcase
    end
   end
   case(state)
    IDLE:if(start || (ENABLE_DELETE && delete_start))begin
     busy<=1;error_code<=0;init_start<=1;state<=INIT;volume<=0;part_found<=0;
     deleting<=ENABLE_DELETE && delete_start && !start;delete_target<=delete_number;delete_found<=0;preceding_lfn<=0;delete_mutated<=0;
     max_number<=0;free_found<=0;dir_end<=0;run_length<=0;alloc_found<=0;end
    INIT:if(init_error)fail(8'h01);else if(init_done)issue(0,0,P_BOOT,BOOT);
    BOOT:if(sig!=16'haa55)fail(8'h02);
     else if(bps==512&&root_entries==0&&fat16==0&&fatsz!=0)state<=GEOMETRY;
     else if(part_found&&partition!=0)begin volume<=partition;issue(0,partition,P_BOOT,GEOMETRY);end
     else fail(8'h02);
    GEOMETRY:begin
     if(sig!=16'haa55||bps!=512||root_entries!=0||fat16!=0||fs_version!=0||extflags[7]||
        spc_log(spc)==15||reserved==0||nfats==0||nfats>2||fatsz==0||fatsz>32'h01ffffff||
        total<=reserved+all_fat_sectors||root<2||
        (data_sectors>>spc_log(spc))<65525 || (data_sectors>>spc_log(spc))>=32'h0ffffff5 ||
        (data_sectors>>spc_log(spc))+2>({32'd0,fatsz}<<7) ||
        root>=(data_sectors>>spc_log(spc))+2 ||
        ({1'b0,volume}+{1'b0,total})>({32'd0,capacity_mb}<<11))fail(8'h03);
     else begin
      fat_base<=volume+reserved;data_base<=volume+reserved+all_fat_sectors;
      cluster_shift<=spc_log(spc);max_cluster<=(data_sectors>>spc_log(spc))+1;
      needed<=(FILE_SECTORS+spc-1)>>spc_log(spc);dir_cluster<=root;dir_sector<=0;dir_steps<=0;state<=DIR;
     end
    end
    DIR:issue(0,data_base+((dir_cluster-2)<<cluster_shift)+dir_sector,P_DIR,DIR_CHECK);
    DIR_CHECK:if(dir_end || (deleting&&delete_found))begin
     if(deleting)begin if(delete_found)state<=DEL_HEADER;else fail(8'h04);end
     else if(!free_found)fail(8'h04);else state<=ALLOC;end
     else if(dir_sector+1<spc)begin dir_sector<=dir_sector+1'b1;state<=DIR;end
     else begin fat_offset<={dir_cluster[6:0],2'b00};issue(0,fat_base+(dir_cluster>>7),P_FAT,DIR_NEXT);end
    DIR_NEXT:if(fat_value>=32'h0ffffff8)begin
     if(deleting)begin if(delete_found)state<=DEL_HEADER;else fail(8'h04);end
     else if(free_found)state<=ALLOC;else fail(8'h04);end
     else if(fat_value<2||fat_value>max_cluster||dir_steps>=max_cluster)fail(8'h05);
     else begin dir_cluster<=fat_value;dir_sector<=0;dir_steps<=dir_steps+1'b1;state<=DIR;end
    ALLOC:if(max_number>=99999)fail(8'h06);else begin
     file_number<=max_number+1'b1;alloc_sector<=0;
     number_shift<=max_number+1'b1;number_bcd<=0;number_bits<=0;state<=BCD;
    end
    BCD:begin
     number_bcd<={bcd_adjusted[18:0],number_shift[16]};number_shift<=number_shift<<1;
     if(number_bits==16)issue(0,fat_base,P_ALLOC,ALLOC_CHECK);else number_bits<=number_bits+1'b1;
    end
    ALLOC_CHECK:if(alloc_found)begin file_lba<=data_base+((file_cluster-2)<<cluster_shift);edit_index<=0;state<=HEADER;end
     else if(((alloc_sector+1)<<7)>max_cluster)fail(8'h07);
     else begin alloc_sector<=alloc_sector+1'b1;issue(0,fat_base+alloc_sector+1,P_ALLOC,ALLOC_CHECK);end
    HEADER:begin cpu_we<=1;cpu_addr<=edit_index;cpu_data<=header_byte(edit_index);
     if(edit_index==511)begin data_sector<=0;state<=DATA_NEXT;end else edit_index<=edit_index+1'b1;end
    DATA:begin photo_offset<=(data_sector-1)<<9;photo_start<=1;state<=DATA_WAIT;end
    DATA_WAIT:if(photo_error)fail(8'h08);else if(photo_done)state<=DATA_NEXT;
    DATA_NEXT:issue(1,file_lba+data_sector,P_KEEP,FAT_READ);
    FAT_READ:begin
     if(data_sector<FILE_SECTORS-1)begin data_sector<=data_sector+1'b1;state<=DATA;end
     else begin write_cluster<=file_cluster;fat_copy<=0;fat_offset<={file_cluster[6:0],2'b00};
      issue(0,fat_base+(file_cluster>>7),P_FAT,FAT_EDIT);edit_index<=0;end
    end
    FAT_EDIT:if(deleting && edit_index==0 && ((!fat_copy&&!chain_link_ok)||(fat_copy&&fat_value!=chain_next)))fail(8'h0b);
    else begin
     if(deleting && edit_index==0 && !fat_copy)chain_next<=fat_value;
     cpu_we<=1;cpu_addr<=fat_offset+edit_index;
     case(edit_index)0:cpu_data<=next_fat[7:0];1:cpu_data<=next_fat[15:8];2:cpu_data<=next_fat[23:16];3:cpu_data<={fat_top,next_fat[27:24]};endcase
     if(edit_index==3)state<=FAT_WRITE;else edit_index<=edit_index+1'b1;
    end
    FAT_WRITE:issue(1,fat_base+(fat_copy?fatsz:0)+(write_cluster>>7),P_KEEP,FAT_NEXT);
    FAT_NEXT:begin
     edit_index<=0;
     if(!fat_copy&&nfats==2)begin fat_copy<=1;issue(0,fat_base+fatsz+(write_cluster>>7),P_FAT,FAT_EDIT);end
     else if(deleting)begin
      if(chain_steps+1==needed)state<=FINISH;
      else begin
       chain_steps<=chain_steps+1'b1;fat_copy<=0;write_cluster<=chain_next;
       fat_offset<={chain_next[6:0],2'b00};issue(0,fat_base+(chain_next>>7),P_FAT,FAT_EDIT);
      end
     end else if(write_cluster<file_cluster+needed-1)begin
      fat_copy<=0;write_cluster<=write_cluster+1'b1;fat_offset<={(write_cluster[6:0]+7'd1),2'b00};
      issue(0,fat_base+((write_cluster+1)>>7),P_FAT,FAT_EDIT);
     end else begin fs_copy<=0;state<=FS_READ;end
    end
    FS_READ:if(fsinfo==0||fsinfo>=reserved || (fs_copy&&(backup==0||backup==16'hffff||({1'b0,backup}+{1'b0,fsinfo})>=reserved)))state<=deleting?DEL_FREE_START:DIR_READ;
     else issue(0,volume+fsinfo+(fs_copy?backup:0),P_FS,FS_CHECK);
    FS_CHECK:if(fs_sig0==32'h41615252&&fs_sig1==32'h61417272&&fs_sig2==32'haa550000)begin edit_index<=0;state<=FS_EDIT;end
     else state<=FS_NEXT;
    FS_EDIT:begin cpu_we<=1;cpu_addr<=488+edit_index;cpu_data<=8'hff;
     if(edit_index==7)state<=FS_WRITE;else edit_index<=edit_index+1'b1;end
    FS_WRITE:issue(1,volume+fsinfo+(fs_copy?backup:0),P_KEEP,FS_NEXT);
    FS_NEXT:if(!fs_copy)begin fs_copy<=1;state<=FS_READ;end else state<=deleting?DEL_FREE_START:DIR_READ;
    DIR_READ:begin edit_index<=0;issue(0,free_lba,P_KEEP,DIR_EDIT);end
    DIR_EDIT:begin cpu_we<=1;cpu_addr<=free_offset+edit_index;cpu_data<=directory_byte(edit_index[4:0]);
     if(edit_index==31)state<=DIR_END;else edit_index<=edit_index+1'b1;end
    DIR_END:begin
     if(free_was_end)begin cpu_we<=1;cpu_addr<=free_offset+32;cpu_data<=0;end
     state<=DIR_WRITE;
    end
    DIR_WRITE:issue(1,free_lba,P_KEEP,FINISH);
    DEL_HEADER:begin
     if(delete_size!=FILE_BYTES || delete_cluster<2 || delete_cluster>max_cluster ||
        delete_cluster>=32'h0ffffff0 || delete_cluster==root || delete_target==0 || delete_target>99999)fail(8'h0c);
     else begin file_cluster<=delete_cluster;write_cluster<=delete_cluster;chain_steps<=0;verify_copy<=0;
      issue(0,data_base+((delete_cluster-2)<<cluster_shift),P_HEADER,DEL_HEADER_CHECK);end
    end
    DEL_HEADER_CHECK:if(!bmp_delete_ok)fail(8'h0c);else state<=DEL_VERIFY;
    DEL_VERIFY:begin fat_offset<={write_cluster[6:0],2'b00};
     issue(0,fat_base+(verify_copy?fatsz:0)+(write_cluster>>7),P_FAT,DEL_VERIFY_CHECK);end
    DEL_VERIFY_CHECK:begin
     if(!chain_link_ok || (verify_copy&&fat_value!=chain_next))fail(8'h0b);
     else if(!verify_copy&&nfats==2)begin chain_next<=fat_value;verify_copy<=1;state<=DEL_VERIFY;end
     else if(chain_steps+1==needed)state<=DEL_DIR_READ;
     else begin write_cluster<=fat_value;chain_steps<=chain_steps+1'b1;verify_copy<=0;state<=DEL_VERIFY;end
    end
    DEL_DIR_READ:issue(0,delete_lba,P_KEEP,DEL_DIR_MARK);
    DEL_DIR_MARK:begin cpu_we<=1;cpu_addr<=delete_offset;cpu_data<=8'he5;state<=DEL_DIR_WRITE;end
    // A failed write may have reached the card even without its acknowledgement.
    // Conservatively flag mutation before issuing the first destructive sector.
    DEL_DIR_WRITE:begin delete_mutated<=1;fs_copy<=0;issue(1,delete_lba,P_KEEP,FS_READ);end
    DEL_FREE_START:begin
     chain_steps<=0;write_cluster<=file_cluster;fat_copy<=0;fat_offset<={file_cluster[6:0],2'b00};edit_index<=0;
     issue(0,fat_base+(file_cluster>>7),P_FAT,FAT_EDIT);
    end
    FINISH:begin busy<=0;if(deleting)delete_done<=1;else done<=1;state<=IDLE;end
    FAILED:begin busy<=0;if(deleting)delete_error<=1;else error<=1;state<=IDLE;end
    IO:if(block_error)fail(8'h09);else if(block_done)state<=return_state;
   default:state<=IDLE;
   endcase
   if((state==INIT || state==IO || state==DATA_WAIT) && wait_timer>=WAIT_TIMEOUT &&
      !(init_done||init_error||block_done||block_error||block_rx_valid||photo_valid||photo_done||photo_error))
    fail(8'h0a);
  end
 end
endmodule
