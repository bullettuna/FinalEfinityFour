`timescale 1ns/1ps
// Preserve training's second OR pool: integer bins from the existing
// 640x360 image5 snapshot to 256x144. Bins alternate widths/heights 2,3.
// Never substitute a single direct 1080p->256 OR operation.
module pose6_input_pool(
 input clk,input rst_n,input start,output busy,output reg done,output reg [31:0] input_crc,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input [127:0] response_data
);
 localparam IDLE=0,PIXEL=1,READ=2,WAITREAD=3,ACCUMULATE=4,STORE=5,WRITE=6,WAITWRITE=7,NEXT=8;
 reg [3:0] state;
 reg [7:0] x,y;reg [1:0] dx,dy;
 reg pooled,edge_bit;
 reg [127:0] cache_data,buffer_data;
 reg [31:0] cache_tag;
 reg cache_valid;reg [2:0] packed_lane;
 reg [31:0] crc;
 function [31:0] crc_byte;
 input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
 begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 wire [7:0] binary_byte=pooled?8'hff:0;
 // floor(5*x/2); end-start is 2 for even x and 3 for odd x.
 wire [9:0] sx=(x*5)>>1;
 wire [9:0] sy=(y*5)>>1;
 wire [31:0] source=32'h01800000+(sy+dy)*640+sx+dx;
 wire [31:0] destination=32'h02100000+((y*256+x)<<1);
 assign busy=state!=IDLE;
 assign command_valid=state==READ||state==WRITE;
 assign command_write=state==WRITE;
 assign command_address=state==WRITE?{destination[31:4],4'b0}:{source[31:4],4'b0};
 assign command_data=buffer_data;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;x<=0;y<=0;dx<=0;dy<=0;pooled<=0;edge_bit<=0;
   cache_data<=0;buffer_data<=0;cache_tag<=0;cache_valid<=0;packed_lane<=0;done<=0;crc<=0;input_crc<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin x<=0;y<=0;dx<=0;dy<=0;pooled<=0;cache_valid<=0;packed_lane<=0;state<=PIXEL;crc<=32'hffffffff;end
    PIXEL:if(cache_valid&&cache_tag=={source[31:4],4'b0})begin
     edge_bit<=cache_data[source[3:0]*8+:8]!=0;state<=ACCUMULATE;
    end else state<=READ;
    READ:if(command_ready)state<=WAITREAD;
    WAITREAD:if(response_valid)begin
     cache_data<=response_data;cache_tag<={source[31:4],4'b0};cache_valid<=1;
     edge_bit<=response_data[source[3:0]*8+:8]!=0;state<=ACCUMULATE;
    end
    ACCUMULATE:begin
     pooled<=pooled||edge_bit;
     if(dx+1<(x[0]?3:2))begin dx<=dx+1'b1;state<=PIXEL;end
     else begin dx<=0;
      if(dy+1<(y[0]?3:2))begin dy<=dy+1'b1;state<=PIXEL;end
      else begin dy<=0;state<=STORE;end
     end
    end
    STORE:begin
     crc<=crc_byte(crc_byte(crc,binary_byte),binary_byte);
     buffer_data[packed_lane*16+:16]<=pooled?16'hffff:0;
     packed_lane<=packed_lane+1'b1;state<=packed_lane==7?WRITE:NEXT;
    end
    WRITE:if(command_ready)state<=WAITWRITE;
    WAITWRITE:if(response_valid)state<=NEXT;
    NEXT:begin
     pooled<=0;
     if(x==255)begin x<=0;
      if(y==143)begin input_crc<=~crc;done<=1;state<=IDLE;end else begin y<=y+1'b1;state<=PIXEL;end
     end else begin x<=x+1'b1;state<=PIXEL;end
    end
   endcase
  end
 end
endmodule
