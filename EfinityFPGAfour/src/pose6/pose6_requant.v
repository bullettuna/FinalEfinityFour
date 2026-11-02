`timescale 1ns/1ps
// Two saturating RNE conversions preserve QDQ's Conv -> uint16 ->
// (optional ReLU) -> following activation domain, including the concat path.
// Two registered partial products and a registered sum avoid a long wide-DSP
// cascade. The same exact signed48 x unsigned31 product serves both stages.
module pose6_requant(
 input clk,input rst_n,input start,output busy,output reg done,
 input signed [47:0] accumulator,input [30:0] multiplier,input [5:0] shift,
 input [15:0] conv_zero,input relu,input [30:0] post_multiplier,
 input [5:0] post_shift,input [15:0] output_zero,output reg [15:0] value
);
 reg [2:0] state;
 reg signed [47:0] operand;
 reg [30:0] factor;
 reg signed [79:0] product;
 reg signed [64:0] product_low;
 reg signed [63:0] product_high;
 reg [5:0] s0,s1;
 reg [15:0] z0,z1;
 reg use_relu;
 reg [30:0] m1;
 wire signed [16:0] factor_low={1'b0,factor[15:0]};
 wire signed [15:0] factor_high={1'b0,factor[30:16]};
 assign busy=state!=0;
 function [15:0] rounded;
  input signed [79:0] p;
  input [5:0] s;
  input [15:0] z;
  reg [79:0] magnitude,q,remainder,half,mask;
  reg signed [80:0] signed_q,result;
  begin
   magnitude=p[79]?-p:p;
   q=magnitude>>s;
   mask=(80'd1<<s)-1;
   remainder=magnitude&mask;
   half=80'd1<<(s-1);
   if((remainder>half)||((remainder==half)&&q[0]))q=q+1'b1;
   signed_q=p[79]?-$signed({1'b0,q}):$signed({1'b0,q});
   result=signed_q+$signed({65'd0,z});
   if(result<0)rounded=0;
   else if(result>65535)rounded=65535;
   else rounded=result[15:0];
  end
 endfunction
 wire [15:0] first_value=rounded(product,s0,z0);
 wire signed [16:0] centered=$signed({1'b0,first_value})-$signed({1'b0,z0});
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;done<=0;value<=0;operand<=0;factor<=0;
   s0<=0;s1<=0;z0<=0;z1<=0;use_relu<=0;m1<=0;end
  else begin
   done<=0;
   case(state)
    0:if(start)begin
     operand<=accumulator;factor<=multiplier;s0<=shift;s1<=post_shift;
     z0<=conv_zero;z1<=output_zero;use_relu<=relu;m1<=post_multiplier;state<=1;
    end
    1:state<=2;
    2:state<=3;
    3:begin operand<=use_relu&&centered<0?48'sd0:{{31{centered[16]}},centered};factor<=m1;state<=4;end
    4:state<=5;
    5:state<=6;
    6:begin value<=rounded(product,s1,z1);done<=1;state<=0;end
   endcase
  end
 end
 always @(posedge clk)begin
  product_low<=operand*factor_low;
  product_high<=operand*factor_high;
  product<={{15{product_low[64]}},product_low}+{product_high,16'd0};
 end
endmodule
