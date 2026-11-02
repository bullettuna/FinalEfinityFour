`timescale 1ns/1ps
// Read-only FAT32 8.3 root-file reader. Based on image2's streaming BPB,
// directory and FAT-chain approach; file bytes are not BMP-decoded.
// One sector is held until the native SD4 host has checked all four CRC16s.
module pose6_fat_reader #(
 parameter [87:0] FILE_NAME="MODEL6  BIN",parameter FILE_BYTES=235232,
 parameter CLOCK_HZ=96000000
)(
 input clk,rst_n,start,abort,
 output reg busy,done,error,output reg [7:0] error_code,
 output reg init_start,input init_done,init_error,
 output reg block_start,output [31:0] block_lba,input block_busy,block_done,block_error,
 input block_rx_valid,input [8:0] block_byte_index,input [7:0] block_rx_data,
 output byte_valid,input byte_ready,output reg [7:0] byte_data,output reg [31:0] byte_offset,
 output reg fat_valid,file_found,output reg [31:0] file_size
);
 localparam IDLE=0,INIT=1,ISSUE=2,WAIT=3,MBR_PARSE=4,BPB_PARSE=5,
  DIR_NEXT=6,FAT_NEXT=7,FILE_READ=8,SEND_FETCH=9,SEND_BYTE=10,FAIL=11,FINISH=12;
 localparam MBR=0,BPB=1,DIR=2,FILE_DATA=3,DIR_FAT=4,FILE_FAT=5;
 reg [3:0] state;reg [2:0] purpose;
 reg [31:0] lba,timer,volume,first_fat,first_data,total_sectors,fat_sectors;
 reg [15:0] bps,reserved,root_entries,fat16,ext_flags;
 reg [7:0] spc,fats;reg [2:0] cluster_shift;
 reg [27:0] root_cluster,cluster,next_cluster;
 reg [31:0] max_cluster;
 reg [7:0] sector_in_cluster;
 reg [15:0] signature;
 reg [7:0] partition_type[0:3];reg [31:0] partition_lba[0:3];
 reg [15:0] dir_clusters;
 reg entry_match,dir_end,found;
 reg [7:0] entry_attr;
 reg [15:0] entry_hi,entry_lo;
 reg [31:0] entry_size,found_size;
 reg [27:0] found_cluster;
 reg [8:0] fat_offset,send_index,last_index;
 (* ram_style="block" *) reg [7:0] sector[0:511];
 wire [4:0] ei=block_byte_index[4:0];
 wire [27:0] entry_cluster={entry_hi[11:0],entry_lo};
 wire [31:0] complete_size={block_rx_data,entry_size[23:0]};
 wire [32:0] data_base={1'b0,volume}+reserved+({1'b0,fat_sectors}<<(fats==2));
 wire superfloppy=bps==512&&root_entries==0&&fat16==0&&fat_sectors!=0;
 wire [31:0] active_fat=volume+reserved+((ext_flags[7]&&ext_flags[3:0]==1)?fat_sectors:0);
 assign block_lba=lba;
 assign byte_valid=state==SEND_BYTE;
 integer j;
 function [2:0] spc_shift;
  input [7:0] value;
  begin case(value)1:spc_shift=0;2:spc_shift=1;4:spc_shift=2;8:spc_shift=3;
   16:spc_shift=4;32:spc_shift=5;64:spc_shift=6;default:spc_shift=7;endcase end
 endfunction
 task fail;
  input [7:0] code;
  begin error_code<=code;state<=FAIL;end
 endtask
 task issue;
  input [2:0] kind;input [31:0] address;
  begin purpose<=kind;lba<=address;state<=ISSUE;end
 endtask
 always @(posedge clk)begin
  if(block_rx_valid)sector[block_byte_index]<=block_rx_data;
  if(state==SEND_FETCH)byte_data<=sector[send_index];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;purpose<=0;busy<=0;done<=0;error<=0;error_code<=0;init_start<=0;block_start<=0;
   fat_valid<=0;file_found<=0;file_size<=0;
   lba<=0;timer<=0;volume<=0;first_fat<=0;first_data<=0;total_sectors<=0;fat_sectors<=0;
   bps<=0;reserved<=0;root_entries<=0;fat16<=0;ext_flags<=0;spc<=0;fats<=0;cluster_shift<=0;
   root_cluster<=0;cluster<=0;next_cluster<=0;max_cluster<=0;sector_in_cluster<=0;signature<=0;
   dir_clusters<=0;entry_match<=0;dir_end<=0;found<=0;entry_attr<=0;entry_hi<=0;entry_lo<=0;
   entry_size<=0;found_size<=0;found_cluster<=0;fat_offset<=0;send_index<=0;last_index<=0;byte_offset<=0;
   for(j=0;j<4;j=j+1)begin partition_type[j]<=0;partition_lba[j]<=0;end
  end else begin
   done<=0;init_start<=0;block_start<=0;
   if(state==WAIT||state==INIT)begin
    if(timer<CLOCK_HZ*3)timer<=timer+1'b1;
   end else timer<=0;
   // Decode metadata while receiving, but never use it until block_done.
   if(block_rx_valid&&state==WAIT)begin
    if(purpose==MBR||purpose==BPB)begin
     case(block_byte_index)
      11:bps[7:0]<=block_rx_data;12:bps[15:8]<=block_rx_data;13:spc<=block_rx_data;
      14:reserved[7:0]<=block_rx_data;15:reserved[15:8]<=block_rx_data;16:fats<=block_rx_data;
      17:root_entries[7:0]<=block_rx_data;18:root_entries[15:8]<=block_rx_data;
      22:fat16[7:0]<=block_rx_data;23:fat16[15:8]<=block_rx_data;
      32,33,34,35:total_sectors[(block_byte_index-32)*8+:8]<=block_rx_data;
      36,37,38,39:fat_sectors[(block_byte_index-36)*8+:8]<=block_rx_data;
      40:ext_flags[7:0]<=block_rx_data;41:ext_flags[15:8]<=block_rx_data;
      44:root_cluster[7:0]<=block_rx_data;45:root_cluster[15:8]<=block_rx_data;
      46:root_cluster[23:16]<=block_rx_data;47:root_cluster[27:24]<=block_rx_data[3:0];
      510:signature[7:0]<=block_rx_data;511:signature[15:8]<=block_rx_data;
     endcase
     if(purpose==MBR&&block_byte_index>=446&&block_byte_index<510)begin
      if((block_byte_index-446)%16==4)partition_type[(block_byte_index-446)/16]<=block_rx_data;
      if((block_byte_index-446)%16>=8&&(block_byte_index-446)%16<=11)
       partition_lba[(block_byte_index-446)/16][(((block_byte_index-446)%16)-8)*8+:8]<=block_rx_data;
     end
    end
    if(purpose==DIR)begin
     if(ei==0)begin entry_match<=block_rx_data==FILE_NAME[87:80];if(block_rx_data==0)dir_end<=1;end
     else if(ei<=10)entry_match<=entry_match&&block_rx_data==FILE_NAME[(10-ei)*8+:8];
     case(ei)
      11:entry_attr<=block_rx_data;
      20:entry_hi[7:0]<=block_rx_data;21:entry_hi[15:8]<=block_rx_data;
      26:entry_lo[7:0]<=block_rx_data;27:entry_lo[15:8]<=block_rx_data;
      28:entry_size[7:0]<=block_rx_data;29:entry_size[15:8]<=block_rx_data;30:entry_size[23:16]<=block_rx_data;
      31:if(!dir_end&&entry_match&&!entry_attr[4]&&!entry_attr[3]&&entry_attr!=8'h0f)begin
       found<=1;found_cluster<=entry_cluster;found_size<=complete_size;
      end
     endcase
    end
    if(purpose==DIR_FAT||purpose==FILE_FAT)begin
     if(block_byte_index==fat_offset)next_cluster[7:0]<=block_rx_data;
     if(block_byte_index==fat_offset+1)next_cluster[15:8]<=block_rx_data;
     if(block_byte_index==fat_offset+2)next_cluster[23:16]<=block_rx_data;
     if(block_byte_index==fat_offset+3)next_cluster[27:24]<=block_rx_data[3:0];
    end
   end
   case(state)
    IDLE:if(start)begin
     fat_valid<=0;file_found<=0;file_size<=0;
     busy<=1;error<=0;error_code<=0;byte_offset<=0;volume<=0;found<=0;dir_end<=0;dir_clusters<=0;
     init_start<=1;state<=INIT;
    end
    INIT:if(init_error)fail(1);else if(init_done)issue(MBR,0);
    ISSUE:if(!block_busy&&!block_start&&!block_done)begin
     if(purpose==MBR||purpose==BPB)begin bps<=0;fat_sectors<=0;signature<=0;end
     if(purpose==DIR)begin found<=0;dir_end<=0;entry_match<=0;end
     block_start<=1;state<=WAIT;
    end
    WAIT:if(block_error)fail(2);else if(block_done)case(purpose)
     MBR:state<=MBR_PARSE;
     BPB:state<=BPB_PARSE;
     DIR:state<=DIR_NEXT;
     DIR_FAT,FILE_FAT:state<=FAT_NEXT;
     FILE_DATA:begin send_index<=0;last_index<=FILE_BYTES-byte_offset>=512?511:FILE_BYTES-byte_offset-1;state<=SEND_FETCH;end
    endcase
    MBR_PARSE:begin
     if(signature!=16'haa55)fail(3);
     else if(superfloppy)begin volume<=0;state<=BPB_PARSE;end
     else if((partition_type[0]==8'h0b||partition_type[0]==8'h0c)&&partition_lba[0]!=0)begin volume<=partition_lba[0];issue(BPB,partition_lba[0]);end
     else if((partition_type[1]==8'h0b||partition_type[1]==8'h0c)&&partition_lba[1]!=0)begin volume<=partition_lba[1];issue(BPB,partition_lba[1]);end
     else if((partition_type[2]==8'h0b||partition_type[2]==8'h0c)&&partition_lba[2]!=0)begin volume<=partition_lba[2];issue(BPB,partition_lba[2]);end
     else if((partition_type[3]==8'h0b||partition_type[3]==8'h0c)&&partition_lba[3]!=0)begin volume<=partition_lba[3];issue(BPB,partition_lba[3]);end
     else fail(3);
    end
    BPB_PARSE:begin
     if(signature!=16'haa55||!superfloppy||reserved==0||(fats!=1&&fats!=2)||spc==0||(spc&(spc-1))!=0||spc>128||
        root_cluster<2||data_base[32]||total_sectors<=reserved+({fat_sectors}<<(fats==2))||
        (ext_flags[7]&&ext_flags[3:0]>=fats))fail(3);
     else begin
      fat_valid<=1;
      cluster_shift<=spc_shift(spc);first_fat<=active_fat;first_data<=data_base[31:0];
      max_cluster<=((total_sectors-reserved-(fat_sectors<<(fats==2)))>>spc_shift(spc))+2;
      cluster<=root_cluster;sector_in_cluster<=0;dir_clusters<=1;
      issue(DIR,data_base[31:0]+((root_cluster-2)<<spc_shift(spc)));
     end
    end
    DIR_NEXT:if(found)begin
     file_found<=1;file_size<=found_size;
     if(found_size!=FILE_BYTES)fail(5);
     else if(found_cluster<2||found_cluster>=max_cluster)fail(6);
     else begin cluster<=found_cluster;sector_in_cluster<=0;state<=FILE_READ;end
    end else if(dir_end)fail(4);
    else if(sector_in_cluster+1<spc)begin
     sector_in_cluster<=sector_in_cluster+1'b1;issue(DIR,first_data+((cluster-2)<<cluster_shift)+sector_in_cluster+1);
    end else begin fat_offset<={cluster[6:0],2'b0};issue(DIR_FAT,first_fat+(cluster>>7));end
    FAT_NEXT:if(next_cluster>=28'h0ffffff8)fail(purpose==DIR_FAT?4:6);
    else if(next_cluster<2||next_cluster>=max_cluster||next_cluster==28'h0ffffff7||next_cluster==cluster)fail(6);
    else if(purpose==DIR_FAT&&dir_clusters>=128)fail(6);
    else begin
     cluster<=next_cluster;sector_in_cluster<=0;
     if(purpose==DIR_FAT)begin dir_clusters<=dir_clusters+1'b1;issue(DIR,first_data+((next_cluster-2)<<cluster_shift));end
     else state<=FILE_READ;
    end
    FILE_READ:issue(FILE_DATA,first_data+((cluster-2)<<cluster_shift)+sector_in_cluster);
    SEND_FETCH:state<=SEND_BYTE;
    SEND_BYTE:if(byte_ready)begin
     byte_offset<=byte_offset+1'b1;
     if(byte_offset==FILE_BYTES-1)state<=FINISH;
     else if(send_index==last_index)begin
      if(sector_in_cluster+1<spc)begin sector_in_cluster<=sector_in_cluster+1'b1;state<=FILE_READ;end
      else begin fat_offset<={cluster[6:0],2'b0};issue(FILE_FAT,first_fat+(cluster>>7));end
     end else begin send_index<=send_index+1'b1;state<=SEND_FETCH;end
    end
    FAIL:begin busy<=0;error<=1;state<=IDLE;end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
   endcase
   if((state==WAIT||state==INIT)&&timer==CLOCK_HZ*3-1)fail(7);
   if(abort&&state!=WAIT&&state!=INIT&&state!=IDLE)fail(8);
  end
 end
endmodule
