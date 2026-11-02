`timescale 1ns/1ps
// Synthesis-only resource probe. Independent state per bank prevents merging.
// This is not a board top and never substitutes for the full image6 report.
module pose6_probe_top(
 input clk,input rst_n,input [14:0] tile_address,input tile_write,input [15:0] write_data,
 input [8:0] weight_address,input [3:0] weight_lane,input weight_write,
 input [767:0] biases,input valid,input first,input last,input [15:0] input_zero,
 input rq_start,input [3:0] rq_lane,input [30:0] multiplier,input [5:0] shift,
 input [15:0] conv_zero,input relu,input [30:0] post_multiplier,
 input [5:0] post_shift,input [15:0] output_zero,
 output [767:0] sums,output mac_done,output rq_done,output [15:0] value
);
 (* ram_style="block" *) reg [15:0] tile[0:32767];
 reg [15:0] pixel;
 wire [255:0] weights;
 always @(posedge clk)begin
  if(tile_write)tile[tile_address]<=write_data;
  pixel<=tile[tile_address];
 end
 genvar g;
 generate for(g=0;g<16;g=g+1)begin:bank
  (* ram_style="block" *) reg [15:0] memory[0:511];
  reg [15:0] q;
  always @(posedge clk)begin
   if(weight_write&&weight_lane==g)memory[weight_address]<=write_data;
   q<=memory[weight_address];
  end
  assign weights[g*16+:16]=q;
 end endgenerate
 wire signed [16:0] centered=$signed({1'b0,pixel})-$signed({1'b0,input_zero});
 pose6_mac16 u_mac(.clk(clk),.rst_n(rst_n),.valid(valid),.first(first),.last(last),
  .activation(centered),.weights(weights),.biases(biases),.done(mac_done),.sums(sums));
 pose6_requant u_requant(.clk(clk),.rst_n(rst_n),.start(rq_start),.busy(),.done(rq_done),
  .accumulator(sums[rq_lane*48+:48]),.multiplier(multiplier),.shift(shift),.conv_zero(conv_zero),
  .relu(relu),.post_multiplier(post_multiplier),.post_shift(post_shift),.output_zero(output_zero),.value(value));
endmodule
