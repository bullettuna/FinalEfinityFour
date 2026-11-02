`timescale 1ns/1ps
// Four NHWC heatmaps, first-index argmax, then +/- quarter-cell gradient.
// Coordinates are native 640x360 in Q14.2, peaks remain raw uint16 values.
module pose6_decode(
 input clk,input rst_n,input start,output busy,output reg done,
 output reg [191:0] points,output reg [31:0] heatmap_crc,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input [127:0] response_data
);
 localparam IDLE=0,SCANREQ=1,SCANWAIT=2,SCANWORD=3,POINT=4,NEIGHBOR=5,NREQ=6,NWAIT=7,SAVE=8;
 reg [3:0] state;
 reg [13:0] word_index;
 reg [2:0] unpack;
 reg [127:0] data;
 reg [15:0] peak[0:3];reg [11:0] index[0:3];
 reg [1:0] point;
 reg [2:0] neighbor;
 reg [15:0] neighbors[0:3];
 reg [31:0] crc;
 wire [1:0] channel=unpack[1:0];
 wire [15:0] sample=data[unpack*16+:16];
 wire [5:0] px=index[point][5:0],py=index[point][11:6];
 wire border=(neighbor<2&&(px==0||px==63))||(neighbor>=2&&(py==0||py==35));
 wire [11:0] neighbor_pixel=neighbor==0?index[point]-1:neighbor==1?index[point]+1:
  neighbor==2?index[point]-64:index[point]+64;
 wire [31:0] neighbor_address=32'h02230000+((neighbor_pixel*4+point)<<1);
 function [31:0] crc_byte;
 input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
 begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 wire [31:0] next_crc=crc_byte(crc_byte(crc,sample[7:0]),sample[15:8]);
 wire [15:0] xq=px*40+20+(neighbors[1]>neighbors[0]?10:neighbors[1]<neighbors[0]?-10:0);
 wire [15:0] yq=py*40+20+(neighbors[3]>neighbors[2]?10:neighbors[3]<neighbors[2]?-10:0);
 assign busy=state!=IDLE;
 assign command_valid=state==SCANREQ||state==NREQ;
 assign command_write=0;assign command_data=0;
 assign command_address=state==SCANREQ?32'h02230000+(word_index<<1):{neighbor_address[31:4],4'b0};
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;word_index<=0;unpack<=0;data<=0;point<=0;neighbor<=0;crc<=0;
   points<=0;heatmap_crc<=0;done<=0;
   for(i=0;i<4;i=i+1)begin peak[i]<=0;index[i]<=0;neighbors[i]<=0;end
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     word_index<=0;crc<=32'hffffffff;state<=SCANREQ;
     for(i=0;i<4;i=i+1)begin peak[i]<=0;index[i]<=0;end
    end
    SCANREQ:if(command_ready)state<=SCANWAIT;
    SCANWAIT:if(response_valid)begin data<=response_data;unpack<=0;state<=SCANWORD;end
    SCANWORD:begin
     crc<=next_crc;
     if(sample>peak[channel])begin peak[channel]<=sample;index[channel]<=(word_index+unpack)>>2;end
     if(unpack==7)begin
      if(word_index==9208)begin heatmap_crc<=~next_crc;point<=0;state<=POINT;end
      else begin word_index<=word_index+8;state<=SCANREQ;end
     end else unpack<=unpack+1'b1;
    end
    POINT:begin neighbor<=0;state<=NEIGHBOR;end
    NEIGHBOR:begin
     if(border)begin neighbors[neighbor]<=0;
      if(neighbor==3)state<=SAVE;else neighbor<=neighbor+1'b1;
     end else state<=NREQ;
    end
    NREQ:if(command_ready)state<=NWAIT;
    NWAIT:if(response_valid)begin
     neighbors[neighbor]<=response_data[neighbor_address[3:1]*16+:16];
     if(neighbor==3)state<=SAVE;else begin neighbor<=neighbor+1'b1;state<=NEIGHBOR;end
    end
    SAVE:begin
     points[point*48+:48]<={peak[point],yq,xq};
     if(point==3)begin done<=1;state<=IDLE;end else begin point<=point+1'b1;state<=POINT;end
    end
   endcase
  end
 end
endmodule
