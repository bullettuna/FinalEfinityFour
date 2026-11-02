`timescale 1ns/1ps
// Read-only video observers and a private ~2D diagnostic command. No output
// drives camera reset, DDR arbitration, frame publication or video modes.
module image2_video_diagnostic #(
 parameter RX_TIMEOUT=960000
)(
 input clk,cam_clk,pixel_clk,rst_n,input cam_vs,cam_de,
 input [31:0] underflow_count,bad_frame_count,status,
 input [31:0] video_awaddr,video_araddr,
 input video_awvalid,video_awready,video_arvalid,video_arready,
 input aux_awvalid,aux_awready,aux_arvalid,aux_arready,
 input rx_valid,input [7:0] rx_data,output legacy_valid,
 output tx_valid,tx_last,output [7:0] tx_data,input tx_accept,
 output [383:0] data
);
 image2_video_counters counters(
 .clk(clk),.cam_clk(cam_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),
 .cam_vs(cam_vs),.cam_de(cam_de),.underflow_count(underflow_count),.bad_frame_count(bad_frame_count),.status(status),
 .video_awaddr(video_awaddr),.video_araddr(video_araddr),.video_awvalid(video_awvalid),.video_awready(video_awready),
 .video_arvalid(video_arvalid),.video_arready(video_arready),.aux_awvalid(aux_awvalid),.aux_awready(aux_awready),
 .aux_arvalid(aux_arvalid),.aux_arready(aux_arready),.data(data));
 reg [1:0] prefix;
 reg [$clog2(RX_TIMEOUT+1)-1:0] timeout_count;
 wire packet_busy;
 wire start=rx_valid && prefix==2 && rx_data=="D";
 assign legacy_valid=rx_valid && prefix==0 && rx_data!="~";
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin prefix<=0;timeout_count<=0;end
  else if(rx_valid)begin
   timeout_count<=0;
   case(prefix)
    0:if(rx_data=="~")prefix<=1;
    1:prefix<=rx_data=="2"?2:0;
    default:prefix<=0;
   endcase
  end else if(prefix!=0)begin
   if(timeout_count==RX_TIMEOUT-1)begin prefix<=0;timeout_count<=0;end
   else timeout_count<=timeout_count+1'b1;
  end
 end
 image2_video_packet packet(.clk(clk),.rst_n(rst_n),.start(start&&!packet_busy),.data(data),
 .busy(packet_busy),.last(tx_last),.valid(tx_valid),.byte_data(tx_data),.ready(tx_accept));
endmodule
`include "images/image2_video_guard/image2_video_counters.v"
