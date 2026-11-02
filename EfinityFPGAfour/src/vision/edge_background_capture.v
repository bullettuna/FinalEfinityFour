`timescale 1ns/1ps
// Capture the actual full-resolution E output into the inactive image3 gallery
// DDR slot. Legacy mode packs eight exact bits per byte; tolerance mode packs
// four (exact, symmetric-3x3) bit pairs. The existing byte writer supplies
// AXI backpressure/BRESP handling. Publish only after every word is committed.
module edge_background_capture #(parameter WIDTH=1920,HEIGHT=1080,TIMEOUT=9600000,CHECK_INPUT_FAULT=0,TOLERANCE_AVAILABLE=0,H_TOTAL=2200)(
 input clk,input rst_n,input pclk,input prst_n,input capture_req,
 input in_vsync,input in_hsync,input in_href,input in_edge,input [64:0] config_signature,input input_frame_fault,
 input tolerance_enable,
 output reg ready,output busy,output reg error,
 output reg writer_start,output reg writer_end,output writer_byte_valid,
 output [7:0] writer_byte,output [19:0] writer_offset,
 input writer_busy,input writer_commit,input writer_error,input reader_error,
 output reader_request,input [7:0] reader_byte,input reader_valid,
 output reg out_vsync,output reg out_hsync,output reg out_href,
 output reg out_edge,output reg out_foreground,output wire reference_valid,
 output reg out_reference_edge,output reg out_reference_expanded,
 output reg [31:0] captured_crc,output wire tolerance_active_o,
 output wire frame_fault
);
localparam PIXELS_PER_BYTE=TOLERANCE_AVAILABLE?4:8;
localparam BYTES=WIDTH*HEIGHT/PIXELS_PER_BYTE,WORDS=BYTES/16;
wire capture_vsync,capture_href,capture_edge,capture_expanded,capture_fault;
generate if(TOLERANCE_AVAILABLE)begin : g_expand_reference
 edge_background_expand #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(H_TOTAL)) u_expand(
  .clk(pclk),.rst_n(prst_n),.in_vsync(in_vsync),.in_hsync(in_hsync),.in_href(in_href),.in_edge(in_edge),
  .in_fault(CHECK_INPUT_FAULT&&input_frame_fault),.out_vsync(capture_vsync),.out_hsync(),.out_href(capture_href),
  .out_edge(capture_edge),.out_expanded(capture_expanded),.out_fault(capture_fault));
end else begin : g_exact_reference
 assign capture_vsync=in_vsync;assign capture_href=in_href;assign capture_edge=in_edge;
 assign capture_expanded=in_edge;assign capture_fault=CHECK_INPUT_FAULT&&input_frame_fault;
end endgenerate
reg request_toggle,capture_busy,end_seen,failed;
reg [19:0] commits;
reg [31:0] timer;
reg [3:0] quiet_cycles;
wire fifo_ready,fifo_valid;wire [28:0] fifo_data;wire [9:0] fifo_count;
reg fifo_push;reg [28:0] fifo_push_data;
reg pixel_failed;
(* async_reg="true" *)reg failed_meta,failed_sync;
photo_async_fifo #(.WIDTH(29),.ABITS(9)) u_edge_capture_fifo(
 .wclk(pclk),.wrst_n(prst_n),.wvalid(fifo_push),.wready(fifo_ready),.wdata(fifo_push_data),
 .rclk(clk),.rrst_n(rst_n),.rvalid(fifo_valid),.rready(1'b1),.rdata(fifo_data),.rcount(fifo_count));
assign writer_byte_valid=capture_busy&&fifo_valid&&!failed;
assign writer_offset=fifo_data[27:8];assign writer_byte=fifo_data[7:0];
assign busy=capture_busy||writer_busy||fifo_valid||fifo_count!=0;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  request_toggle<=0;capture_busy<=0;end_seen<=0;failed<=0;commits<=0;timer<=0;
  ready<=0;error<=0;writer_start<=0;writer_end<=0;failed_meta<=0;failed_sync<=0;quiet_cycles<=0;
 end else begin
  writer_start<=0;writer_end<=0;failed_meta<=pixel_failed;failed_sync<=failed_meta;
  if(reader_error)begin ready<=0;error<=1;end
  if(capture_req&&!busy)begin
   request_toggle<=!request_toggle;capture_busy<=1;ready<=0;error<=0;
   end_seen<=0;failed<=0;commits<=0;timer<=0;writer_start<=1;quiet_cycles<=0;
  end
  if(capture_busy)begin
   timer<=timer+1'b1;
   if(writer_commit)commits<=commits+1'b1;
   if(writer_error||(failed_sync&&timer>32))begin failed<=1;ready<=0;error<=1;end
   if(fifo_valid&&fifo_data[28])begin end_seen<=1;writer_end<=1;end
   if(end_seen&&!writer_busy&&!fifo_valid&&fifo_count==0)begin
    if(quiet_cycles!=15)quiet_cycles<=quiet_cycles+1'b1;
   end else quiet_cycles<=0;
   // The async gallery word queue has a CDC visibility gap after its final
   // push. A transient !busy cannot prove that all words reached DDR.
   if(end_seen&&quiet_cycles>=8&&!writer_busy&&!fifo_valid&&fifo_count==0&&(commits==WORDS||failed))begin
    if(!failed&&!writer_error&&!failed_sync&&commits==WORDS)begin ready<=1;error<=0;end
    else begin ready<=0;error<=1;end
    capture_busy<=0;
   end else if(timer>=TIMEOUT)begin
    capture_busy<=0;ready<=0;error<=1;writer_end<=1;
   end
  end
 end
end
(* async_reg="true" *)reg req_meta,req_sync,ready_meta,ready_sync,armed_meta,armed_sync;
reg request_seen,pending,active,href_d;
(* async_reg="true" *)reg tolerance_meta,tolerance_sync;
reg tolerance_active;
assign tolerance_active_o=tolerance_active;
reg [31:0] capture_crc;
function [31:0] crc_bit;
 input [31:0] crc;input pixel;
 begin crc_bit={crc[30:0],1'b0}^((crc[31]^pixel)?32'h04c11db7:32'd0);end
endfunction
reg capture_href_d;
reg [11:0] capture_x;
reg [10:0] capture_y;
reg [11:0] x;reg [10:0] y;
wire [11:0] px=in_href&&!href_d?0:x;
wire [10:0] py=in_href&&!href_d?y+1'b1:y;
wire first=in_href&&px==0&&py==0;
wire [11:0] capture_px=capture_href&&!capture_href_d?0:capture_x;
wire [10:0] capture_py=capture_href&&!capture_href_d?capture_y+1'b1:capture_y;
wire capture_first=capture_href&&capture_px==0&&capture_py==0;
wire capture_last=capture_href&&capture_px==WIDTH-1&&capture_py==HEIGHT-1;
wire begin_capture=capture_first&&pending;
reg [7:0] pack,reference_byte;
reg [19:0] offset;
reg [64:0] saved_config;
reg valid_frame,read_fault;
wire configuration_matches=config_signature==saved_config;
wire allowed_reference=ready_sync&&configuration_matches;
assign reference_valid=allowed_reference;
assign frame_fault=read_fault||(CHECK_INPUT_FAULT&&input_frame_fault);
wire byte_first=TOLERANCE_AVAILABLE?px[1:0]==0:px[2:0]==0;
assign reader_request=in_href&&byte_first&&allowed_reference&&
 ((first&&allowed_reference)||valid_frame)&&!read_fault;
wire [7:0] live_reference_byte=byte_first?reader_byte:reference_byte;
wire [2:0] reference_index=TOLERANCE_AVAILABLE?3'd7-{px[1:0],1'b0}-{2'd0,tolerance_active}:3'd7-px[2:0];
wire reference_bit=live_reference_byte[reference_index];
wire [2:0] exact_index=TOLERANCE_AVAILABLE?3'd7-{px[1:0],1'b0}:3'd7-px[2:0];
wire raw_reference_bit=live_reference_byte[exact_index];
wire expanded_reference_bit=TOLERANCE_AVAILABLE?live_reference_byte[exact_index-1'b1]:raw_reference_bit;
wire reference_sample_ok=in_href&&allowed_reference&&((first&&allowed_reference)||valid_frame)&&!read_fault&&(!byte_first||reader_valid);
always @(posedge pclk or negedge prst_n)begin
 if(!prst_n)begin
  req_meta<=0;req_sync<=0;ready_meta<=0;ready_sync<=0;armed_meta<=0;armed_sync<=0;
  request_seen<=0;pending<=0;active<=0;href_d<=0;x<=0;y<=11'h7ff;pack<=0;reference_byte<=0;
  offset<=0;saved_config<=0;pixel_failed<=0;valid_frame<=0;read_fault<=0;
  tolerance_meta<=1;tolerance_sync<=1;tolerance_active<=TOLERANCE_AVAILABLE;
  capture_href_d<=0;capture_x<=0;capture_y<=11'h7ff;
  capture_crc<=32'hffffffff;captured_crc<=0;out_reference_edge<=0;out_reference_expanded<=0;
  fifo_push<=0;fifo_push_data<=0;out_vsync<=0;out_hsync<=0;out_href<=0;out_edge<=0;out_foreground<=0;
 end else begin
  req_meta<=request_toggle;req_sync<=req_meta;ready_meta<=ready;ready_sync<=ready_meta;
  armed_meta<=capture_busy;armed_sync<=armed_meta;href_d<=in_href;fifo_push<=0;
  tolerance_meta<=tolerance_enable;tolerance_sync<=tolerance_meta;
  if(!in_vsync)tolerance_active<=TOLERANCE_AVAILABLE&&tolerance_sync;
  capture_href_d<=capture_href;
  if(!capture_vsync)begin capture_x<=0;capture_y<=11'h7ff;end
  else if(capture_href)begin capture_x<=capture_px+1'b1;capture_y<=capture_py;end
  out_vsync<=in_vsync;out_hsync<=in_hsync;out_href<=in_href;out_edge<=in_href&&in_edge;
  out_reference_edge<=reference_sample_ok&&raw_reference_bit;
  out_reference_expanded<=reference_sample_ok&&expanded_reference_bit;
  out_foreground<=in_href&&in_edge&&!reference_bit&&allowed_reference&&
    ((first&&allowed_reference)||valid_frame)&&!read_fault&&(!byte_first||reader_valid);
  if(!in_vsync)begin x<=0;y<=11'h7ff;read_fault<=0;end
  else if(in_href)begin x<=px+1'b1;y<=py;end
  if(req_sync!=request_seen)begin request_seen<=req_sync;pending<=1;pixel_failed<=0;end
  if(first)begin valid_frame<=allowed_reference;read_fault<=0;end
  if(reader_request)begin
   reference_byte<=reader_byte;
   if(!reader_valid)read_fault<=1;
  end
  if(begin_capture)begin
   pending<=0;active<=1;offset<=0;saved_config<=config_signature;
   capture_crc<=crc_bit(32'hffffffff,capture_edge);
   pack<=TOLERANCE_AVAILABLE?{6'd0,capture_edge,capture_expanded}:{7'd0,capture_edge};
  end else if(active&&capture_href)begin
   capture_crc<=crc_bit(capture_crc,capture_edge);
   pack<=TOLERANCE_AVAILABLE?{pack[5:0],capture_edge,capture_expanded}:{pack[6:0],capture_edge};
  end
  if(active&&capture_href&&(TOLERANCE_AVAILABLE?capture_px[1:0]==3:capture_px[2:0]==7))begin
   fifo_push<=1;fifo_push_data<={capture_last,offset,TOLERANCE_AVAILABLE?{pack[5:0],capture_edge,capture_expanded}:{pack[6:0],capture_edge}};offset<=offset+1'b1;
  end
  if(fifo_push&&!fifo_ready)pixel_failed<=1;
  if(active&&capture_fault)pixel_failed<=1;
  if(active&&(config_signature!=saved_config || !armed_sync))begin active<=0;pixel_failed<=1;end
  if(active&&!capture_vsync)begin active<=0;pixel_failed<=1;end
  if(capture_last&&active)begin active<=0;captured_crc<=~crc_bit(capture_crc,capture_edge);end
 end
end
endmodule
