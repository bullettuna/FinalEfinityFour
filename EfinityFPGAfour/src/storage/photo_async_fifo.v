`timescale 1ns/1ps
// Gray-pointer dual-clock FIFO. Read data is registered, held until accepted.
module photo_async_fifo #(parameter WIDTH=128, parameter ABITS=10)(
 input wclk, input wrst_n, input wvalid, output wready, input [WIDTH-1:0] wdata,
 input rclk, input rrst_n, output reg rvalid, input rready,
 output reg [WIDTH-1:0] rdata, output [ABITS:0] rcount
);
 (* ram_style="block" *) reg [WIDTH-1:0] mem[0:(1<<ABITS)-1];
 reg [ABITS:0] wp,wg,rp,rg;
 (* async_reg="true" *) reg [ABITS:0] rg1,rg2,wg1,wg2;
 reg full;
 wire push=wvalid && wready;
 wire fetch=(!rvalid || rready) && (rg!=wg2);
 wire [ABITS:0] wn=wp+push, rn=rp+fetch;
 wire [ABITS:0] wgn=(wn>>1)^wn, rgn=(rn>>1)^rn;
 function [ABITS:0] ungray;
 input [ABITS:0] v; integer j;
 begin ungray[ABITS]=v[ABITS]; for(j=ABITS-1;j>=0;j=j-1) ungray[j]=ungray[j+1]^v[j]; end
 endfunction
 assign wready=!full;
 assign rcount=(ungray(wg2)-rp)+rvalid;
 always @(posedge wclk) if(push) mem[wp[ABITS-1:0]]<=wdata;
 always @(posedge rclk) if(fetch) rdata<=mem[rp[ABITS-1:0]];
 always @(posedge wclk or negedge wrst_n) begin
  if(!wrst_n) begin wp<=0;wg<=0;rg1<=0;rg2<=0;full<=0;end
  else begin rg1<=rg;rg2<=rg1;wp<=wn;wg<=wgn;
   full <= (wgn=={~rg2[ABITS:ABITS-1],rg2[ABITS-2:0]}); end
 end
 always @(posedge rclk or negedge rrst_n) begin
  if(!rrst_n) begin rp<=0;rg<=0;wg1<=0;wg2<=0;rvalid<=0;end
  else begin wg1<=wg;wg2<=wg1;rp<=rn;rg<=rgn;
   if(!rvalid || rready) rvalid<=fetch; end
 end
endmodule
