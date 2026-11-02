`timescale 1ns/1ps
module image5_ft_link #(parameter WIDTH=1920,HEIGHT=1080)(
 input sclk,input rst_n,input pclk,input run_n,input [1:0] mode,resolution,input edge_packed,input txe_n_async,
 input gray_vs,gray_de,input [7:0] gray_pixel,
 input edge_vs,edge_de,input [7:0] edge_pixel,
 output link_ready,output stopped,output [7:0] data_o,output [7:0] data_oe,output wr_n,output wr_oe,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 // Internal reset readiness only, NOT USB/module presence detection.
 reg [2:0] init;
 always @(posedge sclk or negedge rst_n)if(!rst_n)init<=0;else init<={init[1:0],1'b1};
 assign link_ready=init[2];
 wire available,release_frame,ddr_stopped,tx_stopped,snapshot_valid;
 wire [20:0] address;wire [7:0] snap_data;wire [15:0] width,height;wire fault;
 wire is_edge=mode==3;
 ft_ddr_snapshot #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_snapshot(
  .clk(sclk),.rst_n(rst_n),.pclk(pclk),.enable(run_n&&mode>1),.edge_mode(is_edge),.resolution(resolution),
  .vs(is_edge?edge_vs:gray_vs),.de(is_edge?edge_de:gray_de),.pixel(is_edge?edge_pixel:gray_pixel),
  .available(available),.release_frame(release_frame),.stopped(ddr_stopped),.fault(fault),
  .address(address),.byte_data(snap_data),.byte_valid(snapshot_valid),.frame_width(width),.frame_height(height),
  .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 wire valid,ready;wire [7:0] byte_data,packed_data;wire packed_valid;
 wire [20:0] payload_address;
 ft_edge_pack u_pack(
  .clk(sclk),.rst_n(rst_n&&run_n),.enable(is_edge&&edge_packed),.byte_address(payload_address),
  .pixel_address(address),.pixel_data(snap_data),.pixel_valid(snapshot_valid),
  .packed_data(packed_data),.packed_valid(packed_valid));
 ft_packet_source u_packet(
  .clk(sclk),.rst_n(rst_n&&run_n),.mode(mode),.edge_packed(edge_packed),.frame_width(width),.frame_height(height),
  .snapshot_available(available),.snapshot_valid(packed_valid),.snapshot_release(release_frame),
  .snapshot_address(payload_address),.snapshot_data(packed_data),.valid(valid),.data(byte_data),.ready(ready));
 ft245_async_tx u_tx(.clk(sclk),.rst_n(rst_n),.run_enable(run_n),.txe_n_async(txe_n_async),
  .valid(valid),.data(byte_data),.ready(ready),.data_o(data_o),.data_oe(data_oe),
  .wr_n(wr_n),.wr_oe(wr_oe),.stopped(tx_stopped));
 assign stopped=tx_stopped&&ddr_stopped;
endmodule
