`timescale 1ns/1ps
// One sequential snapshot scan, with the exact training 2/3 by 2/3 OR bins.
module pose7_input_pool_latest(
 input [31:0] source_base,
 input clk,rst_n,start,output busy,output reg done,output reg [31:0] input_crc,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input [127:0] response_data
);
 localparam IDLE=0,READ=1,RWAIT=2,SCAN=3,WRITE=4,WWAIT=5;
 reg [31:0] latched_base;
 reg [2:0] state;reg [13:0] word_index;reg [3:0] byte_index;
 reg [7:0] x,y;reg [1:0] dx,dy;
 reg horizontal,resume_read,finish_after_write;
 reg [127:0] data,buffer_data;reg [2:0] lane;
 reg [15:0] output_word;reg [31:0] crc;
 (* ram_style="block" *)reg row_or[0:255];reg row_value;
 wire bit_value=data[byte_index*8+:8]!=0;
 wire merged=(dy==0?1'b0:row_value)||horizontal||bit_value;
 wire horizontal_last=dx==(x[0]?2:1);
 wire vertical_last=dy==(y[0]?2:1);
 wire last_pixel=word_index==14399&&byte_index==15;
 wire [7:0] binary_byte=merged?8'hff:0;
 always @(posedge clk)begin
  row_value<=row_or[x];
  if(state==SCAN&&horizontal_last)row_or[x]<=merged;
 end
 function [31:0] crc_byte;
  input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
  begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 assign busy=state!=IDLE;assign command_valid=state==READ||state==WRITE;
 assign command_write=state==WRITE;assign command_data=buffer_data;
 assign command_address=state==WRITE?32'h02100000+({16'd0,output_word}<<4):latched_base+({18'd0,word_index}<<4);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   latched_base<=0;state<=IDLE;done<=0;input_crc<=0;word_index<=0;byte_index<=0;
   x<=0;y<=0;dx<=0;dy<=0;horizontal<=0;resume_read<=0;finish_after_write<=0;
   data<=0;buffer_data<=0;lane<=0;output_word<=0;crc<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     latched_base<=source_base;state<=READ;word_index<=0;byte_index<=0;x<=0;y<=0;dx<=0;dy<=0;
     horizontal<=0;lane<=0;output_word<=0;crc<=32'hffffffff;
    end
    READ:if(command_ready)state<=RWAIT;
    RWAIT:if(response_valid)begin data<=response_data;byte_index<=0;state<=SCAN;end
    SCAN:begin
     byte_index<=byte_index+1'b1;
     if(byte_index==15)begin word_index<=word_index+1'b1;state<=READ;end
     if(horizontal_last)begin
      horizontal<=0;dx<=0;
      if(x==255)begin
       x<=0;
       if(vertical_last)begin dy<=0;y<=y+1'b1;end else dy<=dy+1'b1;
      end else x<=x+1'b1;
      if(vertical_last)begin
       crc<=crc_byte(crc_byte(crc,binary_byte),binary_byte);
       buffer_data[lane*16+:16]<=merged?16'hffff:0;lane<=lane+1'b1;
       if(lane==7)begin state<=WRITE;resume_read<=byte_index==15;finish_after_write<=last_pixel;end
      end
     end else begin horizontal<=horizontal||bit_value;dx<=dx+1'b1;end
    end
    WRITE:if(command_ready)state<=WWAIT;
    WWAIT:if(response_valid)begin
     output_word<=output_word+1'b1;
     if(finish_after_write)begin state<=IDLE;done<=1;input_crc<=~crc;end
     else state<=resume_read?READ:SCAN;
    end
   endcase
  end
 end
endmodule
