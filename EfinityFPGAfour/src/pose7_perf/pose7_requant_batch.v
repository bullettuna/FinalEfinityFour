`timescale 1ns/1ps
// Reuse one signed48 x unsigned31 multiplier and one RNE/saturation circuit
// for two batched passes. No weight, zero-point or rounding change.
module pose7_requant_batch(
 input clk,rst_n,start,output busy,output reg done,
 input [767:0] accumulators,input [4:0] count,
 output [3:0] meta_lane,input [30:0] multiplier,input [5:0] shift,
 input [15:0] conv_zero,input relu,input [30:0] post_multiplier,
 input [5:0] post_shift,input [15:0] output_zero,output reg [255:0] values
);
 localparam IDLE=0,FIRST=1,FDRAIN=2,SECOND=3,SDRAIN=4;
 reg [2:0] state,valid_pipe;
 reg second_phase,use_relu;reg [4:0] n,issue_index;
 reg [3:0] lane0,lane1,lane2;
 reg [5:0] shift0,shift1,shift2,post_s;
 reg [15:0] z0,z1;reg [30:0] post_m,factor;
 reg signed [47:0] operand;
 reg signed [16:0] intermediate[0:15];
 reg signed [64:0] product_low;reg signed [63:0] product_high;
 reg signed [79:0] product;
 wire issuing=(state==FIRST||state==SECOND)&&issue_index<n;
 assign busy=state!=IDLE;assign meta_lane=issue_index[3:0];
 wire signed [16:0] factor_low={1'b0,factor[15:0]};
 wire signed [15:0] factor_high={1'b0,factor[30:16]};
 function [15:0] rounded;
  input signed [79:0] p;input [5:0] s;input [15:0] z;
  reg [79:0] magnitude,q,remainder,half,mask;
  reg signed [80:0] signed_q,result;
  begin
   magnitude=p[79]?-p:p;q=magnitude>>s;mask=(80'd1<<s)-1;
   remainder=magnitude&mask;half=80'd1<<(s-1);
   if((remainder>half)||((remainder==half)&&q[0]))q=q+1'b1;
   signed_q=p[79]?-$signed({1'b0,q}):$signed({1'b0,q});
   result=signed_q+$signed({65'd0,z});
   if(result<0)rounded=0;else if(result>65535)rounded=65535;else rounded=result[15:0];
  end
 endfunction
 wire [15:0] converted=rounded(product,shift2,second_phase?z1:z0);
 wire signed [16:0] centered=$signed({1'b0,converted})-$signed({1'b0,z0});
 always @(posedge clk)begin
  product_low<=operand*factor_low;product_high<=operand*factor_high;
  product<={{15{product_low[64]}},product_low}+{product_high,16'd0};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;valid_pipe<=0;done<=0;values<=0;second_phase<=0;
   issue_index<=0;n<=0;operand<=0;factor<=0;use_relu<=0;
   z0<=0;z1<=0;post_m<=0;post_s<=0;
   lane0<=0;lane1<=0;lane2<=0;shift0<=0;shift1<=0;shift2<=0;
  end else begin
   done<=0;valid_pipe<={valid_pipe[1:0],issuing};
   lane0<=issue_index[3:0];lane1<=lane0;lane2<=lane1;
   shift0<=second_phase?post_s:shift;shift1<=shift0;shift2<=shift1;
   if(state==IDLE&&start)begin
    state<=FIRST;n<=count;issue_index<=0;valid_pipe<=0;values<=0;second_phase<=0;
    z0<=conv_zero;z1<=output_zero;post_m<=post_multiplier;post_s<=post_shift;use_relu<=relu;
   end
   if(issuing)begin
    operand<=second_phase?{{31{intermediate[issue_index[3:0]][16]}},intermediate[issue_index[3:0]]}:$signed(accumulators[issue_index[3:0]*48+:48]);
    factor<=second_phase?post_m:multiplier;
    issue_index<=issue_index+1'b1;
    if(issue_index==n-1)state<=second_phase?SDRAIN:FDRAIN;
   end
   if(valid_pipe[2])begin
    if(second_phase)values[lane2*16+:16]<=converted;
    else intermediate[lane2]<=use_relu&&centered<0?17'sd0:centered;
    if({1'b0,lane2}==n-1)begin
     if(second_phase)begin state<=IDLE;done<=1;end
     else begin state<=SECOND;second_phase<=1;issue_index<=0;end
    end
   end
  end
 end
endmodule
