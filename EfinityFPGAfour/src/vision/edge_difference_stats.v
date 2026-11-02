`timescale 1ns/1ps
// Frame-latched diagnostics. A is the captured exact E CRC, C the current E
// CRC, B the read-back exact E CRC, N foreground pixels, M violations of the
// invariant exact-reference => expanded-reference. Query snapshots stay fixed
// for an entire UART message; no frame RAM or continuous serial stream.
module edge_difference_stats(
 input clk,input rst_n,input pclk,input prst_n,
 input vsync,input href,input current_edge,input reference_edge,input expanded_edge,input foreground,
 input [31:0] captured_crc,input tolerance_active,input reference_ready,
 input frozen,input source_active,input query,
 output wire busy,output wire tx_valid,output reg [7:0] tx_data,output wire tx_last,input tx_accept
);
function [31:0] crc_bit;
 input [31:0] crc;input pixel;
 begin crc_bit={crc[30:0],1'b0}^((crc[31]^pixel)?32'h04c11db7:32'd0);end
endfunction
reg vs_d,frame_toggle;
reg [31:0] current_crc,reference_crc;
reg [20:0] count,bad_pairs;
reg [127:0] frame_data;
always @(posedge pclk or negedge prst_n)begin
 if(!prst_n)begin
  vs_d<=0;frame_toggle<=0;current_crc<=32'hffffffff;reference_crc<=32'hffffffff;
  count<=0;bad_pairs<=0;frame_data<=0;
 end else begin
  vs_d<=vsync;
  if(!vsync)begin
   if(vs_d)begin frame_data<={~current_crc,~reference_crc,11'd0,count,11'd0,bad_pairs};frame_toggle<=!frame_toggle;end
   current_crc<=32'hffffffff;reference_crc<=32'hffffffff;count<=0;bad_pairs<=0;
  end else if(href)begin
   current_crc<=crc_bit(current_crc,current_edge);reference_crc<=crc_bit(reference_crc,reference_edge);
   if(foreground&&count!=21'h1fffff)count<=count+1'b1;
   if(reference_edge&&!expanded_edge&&bad_pairs!=21'h1fffff)bad_pairs<=bad_pairs+1'b1;
  end
 end
end
(* async_reg="true" *)reg tick_meta,tick_sync;
(* async_reg="true" *)reg [31:0] capture_meta,capture_sync;
(* async_reg="true" *)reg tolerance_meta,tolerance_sync,ready_meta,ready_sync;
reg tick_seen;
reg [127:0] latest_data,saved_data;
reg [31:0] saved_capture;
reg [3:0] saved_flags;
reg active;
reg [6:0] index;
assign busy=active;assign tx_valid=active;assign tx_last=index==71;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  tick_meta<=0;tick_sync<=0;tick_seen<=0;capture_meta<=0;capture_sync<=0;
  tolerance_meta<=0;tolerance_sync<=0;ready_meta<=0;ready_sync<=0;
  latest_data<=0;saved_data<=0;saved_capture<=0;saved_flags<=0;active<=0;index<=0;
 end else begin
  tick_meta<=frame_toggle;tick_sync<=tick_meta;
  capture_meta<=captured_crc;capture_sync<=capture_meta;
  tolerance_meta<=tolerance_active;tolerance_sync<=tolerance_meta;
  ready_meta<=reference_ready;ready_sync<=ready_meta;
  // The data bus settles before its two-stage toggle reaches this domain.
  if(tick_seen!=tick_sync)begin tick_seen<=tick_sync;latest_data<=frame_data;end
  if(query&&!active)begin
   saved_data<=latest_data;saved_capture<=capture_sync;
   saved_flags<={frozen,tolerance_sync,ready_sync,source_active};active<=1;index<=0;
  end else if(active&&tx_accept)begin
   if(tx_last)active<=0;else index<=index+1'b1;
  end
 end
end
reg [31:0] word;
reg [3:0] nibble;
reg [6:0] offset;
always @(*)begin
 tx_data=" ";word=0;offset=0;nibble=0;
 if(index<55)begin
  if(index<11)begin word=saved_capture;offset=index;end
  else if(index<22)begin word=saved_data[127:96];offset=index-11;end
  else if(index<33)begin word=saved_data[95:64];offset=index-22;end
  else if(index<44)begin word=saved_data[63:32];offset=index-33;end
  else begin word=saved_data[31:0];offset=index-44;end
  if(offset==0)begin
   if(index<11)tx_data="A";else if(index<22)tx_data="C";else if(index<33)tx_data="B";
   else if(index<44)tx_data="N";else tx_data="M";
  end else if(offset==1)tx_data="=";
  else if(offset<10)begin
   nibble=(word >> ((9-offset)*4))&4'hf;
   tx_data=nibble<10?"0"+nibble:"A"+nibble-10;
  end
 end else case(index)
  55:tx_data="F";56:tx_data="=";57:tx_data="0"+saved_flags[3];
  59:tx_data="T";60:tx_data="=";61:tx_data="0"+saved_flags[2];
  63:tx_data="R";64:tx_data="=";65:tx_data="0"+saved_flags[1];
  67:tx_data="E";68:tx_data="=";69:tx_data="0"+saved_flags[0];
  70:tx_data=13;71:tx_data=10;
 endcase
end
endmodule
