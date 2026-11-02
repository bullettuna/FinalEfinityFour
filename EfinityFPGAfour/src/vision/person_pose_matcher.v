`timescale 1ns/1ps
// Reads the selector's completed BACK bank before publication. No third RAM
// read port, no live-video backpressure, and no padded/smoothed display bbox.
module person_pose_matcher #(
 parameter X_BITS=9,Y_BITS=9,MIN_SIMILARITY=550,MIN_MARGIN=80,
 parameter MIN_EDGE_SUPPORT=200
)(
 input clk,input rst_n,input start,input cancel,input candidate_valid,input edge_frame_valid,
 input [X_BITS-1:0] xmin,xmax,input [Y_BITS-1:0] ymin,ymax,
 output reg busy,output reg done,
 output reg [X_BITS-1:0] read_x,output reg [Y_BITS-1:0] read_y,
 input mask_pixel,input canny_pixel,
 output reg [2:0] pose_id,output reg [9:0] similarity,margin,edge_support
);
localparam IDLE=0,ADDRESS=1,WAIT_RAM=2,ACCUMULATE=3,DIV_INIT=4,DIV_STEP=5,
 RANK=6,COMPLETE=7;
reg [3:0] state;
reg [11:0] index;
reg [X_BITS-1:0] left;
reg [Y_BITS-1:0] top;
reg [X_BITS:0] crop_w;
reg [Y_BITS:0] crop_h;
// Explicit product widths also handle crops smaller than 64 (repeated reads).
wire [X_BITS+7:0] product_x=({1'b0,index[5:0],1'b1})*crop_w;
wire [Y_BITS+7:0] product_y=({1'b0,index[11:6],1'b1})*crop_h;
(* ram_style="block" *) reg [9:0] template_rom[0:4095];
`include "src/vision/pose_templates.vh"
reg [9:0] reference;
always @(posedge clk)reference<=template_rom[index];
reg [12:0] intersections[0:4],unions[0:4],edge_hits[0:4],edge_totals[0:4];
reg [9:0] scores[0:4],supports[0:4];
reg [2:0] slot,best_id;
reg metric;
reg [21:0] dividend,quotient;
reg [13:0] remainder;
reg [12:0] divisor;
reg [4:0] div_bit;
wire [14:0] shifted_remainder={remainder,dividend[21]};
wire subtract=shifted_remainder>={2'b0,divisor};
wire [21:0] quotient_next={quotient[20:0],subtract};
reg [9:0] best,second,best_edge;
reg usable_edges;
integer p;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  state<=IDLE;busy<=0;done<=0;read_x<=0;read_y<=0;index<=0;left<=0;top<=0;crop_w<=0;crop_h<=0;
  pose_id<=0;similarity<=0;margin<=0;edge_support<=0;slot<=0;metric<=0;
  dividend<=0;quotient<=0;remainder<=0;divisor<=0;div_bit<=0;
  best<=0;second<=0;best_id<=0;best_edge<=0;usable_edges<=0;
  for(p=0;p<5;p=p+1)begin intersections[p]<=0;unions[p]<=0;edge_hits[p]<=0;edge_totals[p]<=0;scores[p]<=0;supports[p]<=0;end
 end else begin
  done<=0;
  if(cancel)begin state<=IDLE;busy<=0;pose_id<=0;similarity<=0;margin<=0;edge_support<=0;end
  else case(state)
   IDLE:if(start)begin
    busy<=1;index<=0;left<=xmin;top<=ymin;
    crop_w<={1'b0,xmax}-{1'b0,xmin}+1'b1;crop_h<={1'b0,ymax}-{1'b0,ymin}+1'b1;
    usable_edges<=edge_frame_valid;best<=0;second<=0;best_id<=0;best_edge<=0;
    for(p=0;p<5;p=p+1)begin intersections[p]<=0;unions[p]<=0;edge_hits[p]<=0;edge_totals[p]<=0;scores[p]<=0;supports[p]<=0;end
    if(candidate_valid&&xmax>=xmin&&ymax>=ymin)state<=ADDRESS;
    else state<=COMPLETE;
   end
   ADDRESS:begin read_x<=left+(product_x>>7);read_y<=top+(product_y>>7);state<=WAIT_RAM;end
   WAIT_RAM:state<=ACCUMULATE;
   ACCUMULATE:begin
    for(p=0;p<5;p=p+1)begin
     intersections[p]<=intersections[p]+(mask_pixel&&reference[p]);
     unions[p]<=unions[p]+(mask_pixel||reference[p]);
     edge_hits[p]<=edge_hits[p]+(canny_pixel&&reference[p+5]);
     edge_totals[p]<=edge_totals[p]+reference[p+5];
    end
    if(index==4095)begin slot<=0;metric<=0;state<=DIV_INIT;end
    else begin index<=index+1'b1;state<=ADDRESS;end
   end
   DIV_INIT:begin
    // Exact C++ rounding, one shared restoring divider (no combinational /).
    dividend<=metric?(edge_hits[slot]*22'd1000+(edge_totals[slot]>>1)):
                     (intersections[slot]*22'd1000+(unions[slot]>>1));
    divisor<=metric?edge_totals[slot]:unions[slot];
    quotient<=0;remainder<=0;div_bit<=21;state<=DIV_STEP;
   end
   DIV_STEP:begin
    dividend<={dividend[20:0],1'b0};quotient<=quotient_next;
    remainder<=subtract?shifted_remainder-divisor:shifted_remainder;
    if(div_bit==0)begin
     if(metric)supports[slot]<=divisor==0?0:quotient_next[9:0];
     else scores[slot]<=divisor==0?0:quotient_next[9:0];
     if(!metric)begin metric<=1;state<=DIV_INIT;end
     else if(slot==4)begin slot<=0;state<=RANK;end
     else begin slot<=slot+1'b1;metric<=0;state<=DIV_INIT;end
    end else div_bit<=div_bit-1'b1;
   end
   RANK:begin
    // Strict comparison preserves C++ stable ordering: lower pose ID wins ties.
    if(scores[slot]>best)begin second<=best;best<=scores[slot];best_id<=slot+1'b1;best_edge<=supports[slot];end
    else if(scores[slot]>second)second<=scores[slot];
    if(slot==4)state<=COMPLETE;else slot<=slot+1'b1;
   end
   COMPLETE:begin
    similarity<=best;margin<=best-second;edge_support<=best_edge;
    pose_id<=(best>=MIN_SIMILARITY&&best-second>=MIN_MARGIN&&usable_edges&&best_edge>=MIN_EDGE_SUPPORT)?best_id:0;
    busy<=0;done<=1;state<=IDLE;
   end
   default:begin state<=IDLE;busy<=0;end
  endcase
 end
end
endmodule
