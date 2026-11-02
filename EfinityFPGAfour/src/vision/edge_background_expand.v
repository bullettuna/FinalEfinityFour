`timescale 1ns/1ps
// Precompute a symmetric, zero-padded 3x3 reference neighbourhood at capture
// time. Two synchronous line RAMs run through blanking as well as active data.
// The center sample and its timing/fault travel through the same line delay;
// the last image row is emitted during vertical blank, not silently discarded.
module edge_background_expand #(parameter WIDTH=1920,HEIGHT=1080,H_TOTAL=2200)(
 input clk,input rst_n,input in_vsync,input in_hsync,input in_href,input in_edge,input in_fault,
 output reg out_vsync,output reg out_hsync,output reg out_href,
 output reg out_edge,output reg out_expanded,output reg out_fault
);
localparam ADDR_BITS=$clog2(H_TOTAL),WARM_BITS=$clog2(H_TOTAL+3);
reg [4:0] line1[0:H_TOTAL-1];
reg line2[0:H_TOTAL-1];
reg [ADDR_BITS-1:0] address,address_d;
reg [WARM_BITS-1:0] warmup;
reg [4:0] middle_q,middle_d0;
reg middle_d1,top_q,top_d0,top_d1,bottom_q,bottom_d0,bottom_d1;
reg href_d;
reg [11:0] x;
reg [10:0] y;
wire [11:0] cx=middle_d0[1]&&!href_d?0:x;
wire [10:0] cy=middle_d0[1]&&!href_d?y+1'b1:y;
wire top_any=top_d0||(cx!=0&&top_d1)||(cx!=WIDTH-1&&top_q);
wire middle_any=middle_d0[0]||(cx!=0&&middle_d1)||(cx!=WIDTH-1&&middle_q[0]);
wire bottom_any=bottom_d0||(cx!=0&&bottom_d1)||(cx!=WIDTH-1&&bottom_q);
// RAM outputs deliberately have no reset so they infer synchronous block RAM.
always @(posedge clk)begin
 line1[address]<={in_fault,in_vsync,in_hsync,in_href,in_href&&in_edge};
 middle_q<=line1[address];
 line2[address_d]<=middle_q[0];
 top_q<=line2[address];
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  address<=0;address_d<=0;warmup<=0;middle_d0<=0;middle_d1<=0;
  top_d0<=0;top_d1<=0;bottom_q<=0;bottom_d0<=0;bottom_d1<=0;
  href_d<=0;x<=0;y<=11'h7ff;
  out_vsync<=0;out_hsync<=0;out_href<=0;out_edge<=0;out_expanded<=0;out_fault<=0;
 end else begin
  address<=address==H_TOTAL-1?0:address+1'b1;address_d<=address;
  if(warmup<H_TOTAL+2)warmup<=warmup+1'b1;
  bottom_q<=in_href&&in_edge;
  middle_d0<=middle_q;middle_d1<=middle_d0[0];
  top_d0<=top_q;top_d1<=top_d0;
  bottom_d0<=bottom_q;bottom_d1<=bottom_d0;
  if(warmup>=H_TOTAL+2)begin
   href_d<=middle_d0[1];
   if(!middle_d0[3])begin x<=0;y<=11'h7ff;end
   else if(middle_d0[1])begin x<=cx+1'b1;y<=cy;end
   out_vsync<=middle_d0[3];out_hsync<=middle_d0[2];out_href<=middle_d0[1];
   out_fault<=middle_d0[4];out_edge<=middle_d0[1]&&middle_d0[0];
   out_expanded<=middle_d0[1]&&(middle_any||(cy!=0&&top_any)||(cy!=HEIGHT-1&&bottom_any));
  end
 end
end
endmodule
