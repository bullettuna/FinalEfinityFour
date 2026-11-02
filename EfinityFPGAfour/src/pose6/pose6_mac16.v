`timescale 1ns/1ps
// One signed 17x16 input/weight product per lane per cycle. Products are
// registered independently of the 48-bit feedback path for DSP inference.
module pose6_mac16(
 input clk,input rst_n,input valid,input first,input last,
 input signed [16:0] activation,input [255:0] weights,input [767:0] biases,
 output reg done,output [767:0] sums
);
 reg pv,pfirst,plast;
 reg signed [32:0] product[0:15];
 reg signed [47:0] acc[0:15];
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin pv<=0;pfirst<=0;plast<=0;done<=0;end
  else begin
   pv<=valid;pfirst<=first;plast<=last;done<=pv&&plast;
  end
 end
 genvar g;
 generate for(g=0;g<16;g=g+1)begin:lane
  wire signed [15:0] w=weights[g*16+:16];
  wire signed [47:0] bias=biases[g*48+:48];
  always @(posedge clk)begin
   if(valid)product[g]<=activation*w;
   if(pv)acc[g]<=(pfirst?bias:acc[g])+{{15{product[g][32]}},product[g]};
  end
  assign sums[g*48+:48]=acc[g];
 end endgenerate
endmodule
