`timescale 1ns/1ps
// Tiled NHWC convolution. 8 output rows per tile, <=32768 uint16 input
// words; 16 banks of <=432 weights. Feature maps and whole-model weights
// remain in DDR. All ten layers reuse these same RAMs and MAC lanes.
module pose7_conv_fast(
 input clk,input rst_n,input start,input [3:0] layer_index,
 output busy,output reg done,output reg fault,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input [127:0] response_data
);
 reg [3:0] layer;
 `include "images/image7_mocap11_a/pose7_layer_config.vh"
 localparam IDLE=0,WREQ0=1,WWAIT0=2,WREQ1=3,WWAIT1=4,WCOMMIT=5,
  TILE=6,TREQ=7,TWAIT=8,TUNPACK=9,RUN=10,MACWAIT=11,
  QSTART=12,QWAIT=13,OREQ=14,OWAIT=15,ADVANCE=16,QSTORE=17;
 reg [4:0] state;
 reg [1:0] group;
 reg [8:0] weight_index;
 reg [255:0] weight_vector;
 reg [7:0] tile_out,tile_y0,tile_y1,tile_end,oy,ox;
 reg [15:0] load_index,tile_words;
 reg [2:0] unpack_lane;
 reg [127:0] load_data;
 reg [5:0] ic;
 reg [1:0] kx,ky;
 reg [3:0] lane;
 reg [127:0] output_buffer;
 reg [2:0] output_lane;
 reg [31:0] output_address;
 wire [8:0] kernel_words=ci*kernel*kernel;
 wire [5:0] channel=group*16+lane;
 wire [3:0] requant_lane;
 wire [68:0] constants=channel_constants(layer,group*16+requant_lane);
 wire [8:0] sample_weight=(ky*kernel+kx)*ci+ic;
 wire signed [10:0] sample_x=$signed({1'b0,ox})*$signed({1'b0,stride})+
  $signed({1'b0,kx})*$signed({1'b0,dilation})-$signed({1'b0,pad});
 wire signed [10:0] sample_y=$signed({1'b0,oy})*$signed({1'b0,stride})+
  $signed({1'b0,ky})*$signed({1'b0,dilation})-$signed({1'b0,pad});
 wire sample_outside=sample_x<0||sample_y<0||sample_x>=$signed({1'b0,iw})||sample_y>=$signed({1'b0,ih});
 wire [23:0] sample_linear=((sample_y-tile_y0)*iw+sample_x)*ci+ic;
 wire [14:0] tile_read_address=sample_outside?15'd0:sample_linear[14:0];
 (* ram_style="block" *)reg [127:0] tile_memory[0:4095];
 reg [127:0] tile_word_q;reg [2:0] tile_lane_q;
 wire [15:0] tile_q=tile_word_q[tile_lane_q*16+:16];
 wire [255:0] weights;
 wire [767:0] biases;
 wire [767:0] sums;
 reg issue_valid,issue_first,issue_last,issue_zero;
 wire signed [16:0] activation=issue_zero?17'sd0:
  $signed({1'b0,tile_q})-$signed({1'b0,input_zero});
 always @(posedge clk)begin
  tile_word_q<=tile_memory[tile_read_address[14:3]];tile_lane_q<=tile_read_address[2:0];
  if(state==TUNPACK)tile_memory[load_index[14:3]]<=load_data;
 end
 genvar g;
 generate for(g=0;g<16;g=g+1)begin:weight_bank
  (* ram_style="block" *)reg [15:0] memory[0:511];
  reg [15:0] q;
  wire [68:0] meta=channel_constants(layer,group*16+g);
  always @(posedge clk)begin
   q<=memory[sample_weight];
   if(state==WCOMMIT)memory[weight_index]<=weight_vector[g*16+:16];
  end
  assign weights[g*16+:16]=q;
  assign biases[g*48+:48]={{16{meta[31]}},meta[31:0]};
 end endgenerate
 wire mac_done;
 pose7_mac16 u_mac(.clk(clk),.rst_n(rst_n),.valid(issue_valid),.first(issue_first),.last(issue_last),
  .activation(activation),.weights(weights),.biases(biases),.done(mac_done),.sums(sums));
 wire rq_done;wire [255:0] rq_values;
 wire [5:0] channels_left=co-group*16;
 wire [4:0] rq_count=channels_left>=16?5'd16:channels_left[4:0];
 pose7_requant_batch u_requant(.clk(clk),.rst_n(rst_n),.start(state==QSTART),.busy(),.done(rq_done),
  .accumulators(sums),.count(rq_count),.meta_lane(requant_lane),.multiplier(constants[62:32]),.shift(constants[68:63]),
  .conv_zero(conv_zero),.relu(use_relu),.post_multiplier(post_multiplier),
  .post_shift(post_shift),.output_zero(output_zero),.values(rq_values));
 assign busy=state!=IDLE;
 assign command_valid=state==WREQ0||state==WREQ1||state==TREQ||state==OREQ;
 assign command_write=state==OREQ;
 assign command_address=state==OREQ?output_address:state==TREQ?
  source_base+((tile_y0*iw*ci+load_index)<<1):
  weight_base+((group*kernel_words+weight_index)<<5)+(state==WREQ1?16:0);
 assign command_data=output_buffer;
 wire [31:0] result_address=destination_base+(((oy*ow+ox)*co+group*16+lane)<<1);
 integer first_row,last_row,last_output;
 always @*begin
  last_output=tile_out+8;if(last_output>oh)last_output=oh;
  first_row=tile_out*stride-pad;if(first_row<0)first_row=0;
  last_row=(last_output-1)*stride+pad+1;if(last_row>ih)last_row=ih;
 end
 // Equivalent tile-size guard: the ten fixed layers have constant iw*ci.
 // Compare the row span with floor(32768/(iw*ci)), avoiding a wide pair of
 // multipliers feeding the sticky fault FF. Data addressing/MACs are untouched.
 function [8:0] tile_row_capacity;
 input [3:0] index;
 begin case(index)
  4'd0:tile_row_capacity=9'd128; // 256 * 1 words per input row
  4'd1:tile_row_capacity=9'd32; // 128 * 8 words per input row
  4'd2:tile_row_capacity=9'd32; // 64 * 16 words per input row
  4'd3:tile_row_capacity=9'd32; // 32 * 32 words per input row
  4'd4:tile_row_capacity=9'd42; // 16 * 48 words per input row
  4'd5:tile_row_capacity=9'd42; // 16 * 48 words per input row
  4'd6:tile_row_capacity=9'd21; // 32 * 48 words per input row
  4'd7:tile_row_capacity=9'd32; // 64 * 16 words per input row
  4'd8:tile_row_capacity=9'd12; // 64 * 40 words per input row
  4'd9:tile_row_capacity=9'd32; // 64 * 16 words per input row
  default:tile_row_capacity=0;
 endcase end
 endfunction
 wire [31:0] tile_row_span=last_row-first_row;
 wire tile_size_fault=tile_row_span>tile_row_capacity(layer);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;layer<=0;group<=0;weight_index<=0;weight_vector<=0;
   tile_out<=0;tile_y0<=0;tile_y1<=0;tile_end<=0;oy<=0;ox<=0;
   load_index<=0;tile_words<=0;unpack_lane<=0;load_data<=0;
   ic<=0;kx<=0;ky<=0;lane<=0;output_buffer<=0;output_lane<=0;output_address<=0;
   issue_valid<=0;issue_first<=0;issue_last<=0;issue_zero<=0;done<=0;fault<=0;
  end else begin
   done<=0;issue_valid<=state==RUN;
   if(state==RUN)begin
    issue_first<=ic==0&&kx==0&&ky==0;
    issue_last<=ic==ci-1&&kx==kernel-1&&ky==kernel-1;
    issue_zero<=sample_outside;
    if(!sample_outside&&sample_linear>=32768)fault<=1;
   end
   case(state)
    IDLE:if(start)begin
     if(layer_index>9)fault<=1;
     else begin layer<=layer_index;group<=0;weight_index<=0;tile_out<=0;
      output_lane<=0;lane<=0;state<=WREQ0;end
    end
    WREQ0:if(command_ready)state<=WWAIT0;
    WWAIT0:if(response_valid)begin weight_vector[127:0]<=response_data;state<=WREQ1;end
    WREQ1:if(command_ready)state<=WWAIT1;
    WWAIT1:if(response_valid)begin weight_vector[255:128]<=response_data;state<=WCOMMIT;end
    WCOMMIT:begin
     if(weight_index==kernel_words-1)begin weight_index<=0;state<=TILE;end
     else begin weight_index<=weight_index+1'b1;state<=WREQ0;end
    end
    TILE:begin
     tile_y0<=first_row;tile_y1<=last_row;tile_end<=last_output;
     tile_words<=(last_row-first_row)*iw*ci;load_index<=0;state<=TREQ;
     if(tile_size_fault)fault<=1;
    end
    TREQ:if(command_ready)state<=TWAIT;
    TWAIT:if(response_valid)begin load_data<=response_data;unpack_lane<=0;state<=TUNPACK;end
    TUNPACK:begin
     begin
      if(load_index+8>=tile_words)begin oy<=tile_out;ox<=0;ic<=0;kx<=0;ky<=0;state<=RUN;end
      else begin load_index<=load_index+8;state<=TREQ;end
     end
    end
    RUN:begin
     if(ic==ci-1)begin ic<=0;
      if(kx==kernel-1)begin kx<=0;
       if(ky==kernel-1)begin ky<=0;state<=MACWAIT;end else ky<=ky+1'b1;
      end else kx<=kx+1'b1;
     end else ic<=ic+1'b1;
    end
    MACWAIT:if(mac_done)begin lane<=0;state<=QSTART;end
    QSTART:state<=QWAIT;
    QWAIT:if(rq_done)state<=QSTORE;
    QSTORE:begin
     output_buffer[output_lane*16+:16]<=rq_values[lane*16+:16];
     if(output_lane==0)output_address<={result_address[31:4],4'b0};
     output_lane<=output_lane+1'b1;
     state<=output_lane==7?OREQ:ADVANCE;
    end
    OREQ:if(command_ready)state<=OWAIT;
    OWAIT:if(response_valid)state<=ADVANCE;
    ADVANCE:begin
     if(lane!=15&&group*16+lane+1<co)begin lane<=lane+1'b1;state<=QSTORE;end
     else begin lane<=0;
      if(ox+1<ow)begin ox<=ox+1'b1;state<=RUN;end
      else begin ox<=0;
       if(oy+1<tile_end)begin oy<=oy+1'b1;state<=RUN;end
       else if(tile_end<oh)begin tile_out<=tile_end;state<=TILE;end
       else if(group*16+16<co)begin group<=group+1'b1;tile_out<=0;weight_index<=0;state<=WREQ0;end
       else begin if(output_lane!=0)fault<=1;done<=1;state<=IDLE;end
      end
     end
    end
   endcase
  end
 end
endmodule
