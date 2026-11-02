`timescale 1ns/1ps
// Convert eight immutable DDR edge bytes to one MSB-first wire byte.
// Supported image widths (320/640/1920) are all multiples of eight.
// The completed byte stays unchanged while the packet/USB consumer stalls.
module ft_edge_pack(
 input clk,input rst_n,input enable,input [20:0] byte_address,
 output [20:0] pixel_address,input [7:0] pixel_data,input pixel_valid,
 output [7:0] packed_data,output packed_valid
);
 reg [20:0] current;
 reg [2:0] bit_index;
 reg [1:0] settle;
 reg complete;
 reg [7:0] bits;
 assign pixel_address=enable?{current[17:0],3'b0}+bit_index:byte_address;
 assign packed_data=enable?bits:pixel_data;
 assign packed_valid=enable?(complete&&current==byte_address):pixel_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin current<=0;bit_index<=0;settle<=2;complete<=0;bits<=0;end
  else if(!enable)begin current<=0;bit_index<=0;settle<=2;complete<=0;bits<=0;end
  else if(current!=byte_address)begin
   current<=byte_address;bit_index<=0;settle<=2;complete<=0;bits<=0;
  end else if(!complete)begin
   if(settle!=0)settle<=settle-1'b1;
   else if(pixel_valid)begin
    bits[7-bit_index]<=pixel_data!=0;
    if(bit_index==7)complete<=1;
    else begin bit_index<=bit_index+1'b1;settle<=2;end
   end
  end
 end
endmodule
