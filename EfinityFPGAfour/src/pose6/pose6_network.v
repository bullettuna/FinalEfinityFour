`timescale 1ns/1ps
// Execute ten convolutions and two nearest/concat glue passes. The first
// version materializes glue in DDR (not BRAM) to keep addressing auditable.
module pose6_network(
 input clk,input rst_n,input start,output busy,output reg done,output fault,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input [127:0] response_data
);
 localparam IDLE=0,CSTART=1,CWAIT=2,GSET=3,GWORD=4,GREQ=5,GWAIT=6,GSTORE=7,GWREQ=8,GWWAIT=9,GNEXT=10;
 reg [3:0] state,layer;
 reg glue;
 reg [7:0] y,x;
 reg [5:0] c;
 reg [127:0] buffer_data,cache_data;
 reg [31:0] cache_tag,write_address;
 reg cache_valid;
 reg [2:0] packed_lane;
 reg [15:0] word_data;
 wire cv,cw,cdone,cbusy,cfault;wire [31:0] ca;wire [127:0] cd;
 wire convolution=state==CSTART||state==CWAIT;
 pose6_conv u_conv(.clk(clk),.rst_n(rst_n),.start(state==CSTART),.layer_index(layer),
  .busy(cbusy),.done(cdone),.fault(cfault),.command_valid(cv),.command_ready(command_ready&&convolution),
  .command_write(cw),.command_address(ca),.command_data(cd),
  .response_valid(response_valid&&convolution),.response_data(response_data));
 wire [31:0] source_address=!glue?
  32'h021a0000+((((y>>1)*16+(x>>1))*48+c)<<1):c<32?
  32'h021c0000+((((y>>1)*32+(x>>1))*32+c)<<1):
  32'h021d0000+(((y*64+x)*4+c-32)<<1);
 wire [31:0] destination_address=!glue?
  32'h021b0000+(((y*32+x)*48+c)<<1):32'h021e0000+(((y*64+x)*36+c)<<1);
 assign busy=state!=IDLE;assign fault=cfault;
 assign command_valid=convolution?cv:(state==GREQ||state==GWREQ);
 assign command_write=convolution?cw:state==GWREQ;
 assign command_address=convolution?ca:state==GWREQ?write_address:{source_address[31:4],4'b0};
 assign command_data=convolution?cd:buffer_data;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;layer<=0;glue<=0;y<=0;x<=0;c<=0;buffer_data<=0;cache_data<=0;
   cache_tag<=0;write_address<=0;cache_valid<=0;packed_lane<=0;word_data<=0;done<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin layer<=0;state<=CSTART;end
    CSTART:state<=CWAIT;
    CWAIT:if(cdone)begin
     if(layer==5)begin glue<=0;state<=GSET;end
     else if(layer==7)begin glue<=1;state<=GSET;end
     else if(layer==9)begin done<=1;state<=IDLE;end
     else begin layer<=layer+1'b1;state<=CSTART;end
    end
    GSET:begin y<=0;x<=0;c<=0;cache_valid<=0;packed_lane<=0;state<=GWORD;end
    GWORD:begin
     if(cache_valid&&cache_tag=={source_address[31:4],4'b0})begin
      word_data<=cache_data[source_address[3:1]*16+:16];state<=GSTORE;
     end else state<=GREQ;
    end
    GREQ:if(command_ready)state<=GWAIT;
    GWAIT:if(response_valid)begin
     cache_data<=response_data;cache_tag<={source_address[31:4],4'b0};cache_valid<=1;
     word_data<=response_data[source_address[3:1]*16+:16];state<=GSTORE;
    end
    GSTORE:begin
     buffer_data[packed_lane*16+:16]<=word_data;
     if(packed_lane==0)write_address<={destination_address[31:4],4'b0};
     packed_lane<=packed_lane+1'b1;state<=packed_lane==7?GWREQ:GNEXT;
    end
    GWREQ:if(command_ready)state<=GWWAIT;
    GWWAIT:if(response_valid)state<=GNEXT;
    GNEXT:begin
     if(c+1<(!glue?48:36))begin c<=c+1'b1;state<=GWORD;end
     else begin c<=0;
      if(x+1<(!glue?32:64))begin x<=x+1'b1;state<=GWORD;end
      else begin x<=0;
       if(y+1<(!glue?18:36))begin y<=y+1'b1;state<=GWORD;end
       else begin layer<=layer+1'b1;state<=CSTART;end
      end
     end
    end
   endcase
  end
 end
endmodule
