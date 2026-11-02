`timescale 1ns/1ps
// FT5! v2 kind=5, 86-byte payload, eleven anatomical points. Latch a whole result until CRC footer
// is physically accepted; backpressure cannot mix different frames.
module pose7_usb_packet(
 input clk,input rst_n,input cancel,input available,output reg release_result,
 input [527:0] points,input [31:0] cycles,model_crc,input_crc,heatmap_crc,
 input [7:0] flags,output valid,output [7:0] data,input ready
);
 reg [2:0] state;reg [6:0] index;reg [31:0] sequence_id,hcrc,pcrc;
 reg [687:0] payload;
 function [31:0] crc_byte;
 input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
 begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 reg [7:0] header;
 always @*case(index)
  0:header="F";1:header="T";2:header="5";3:header="!";
  4:header=2;5:header=5;6:header=0;7:header=24;
  8,9,10,11:header=sequence_id>>((index-8)*8);
  12:header=8'h80;13:header=2;14:header=8'h68;15:header=1;
  16:header=86;17,18,19:header=0;
  default:header=(~hcrc)>>((index-20)*8);
 endcase
 assign valid=!cancel&&state>=1&&state<=3;
 assign data=state==1?header:state==2?payload[index*8+:8]:(~pcrc)>>(index*8);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;index<=0;sequence_id<=0;hcrc<=0;pcrc<=0;payload<=0;release_result<=0;end
  else if(cancel)begin
   state<=0;index<=0;release_result<=0;
  end else begin
   release_result<=0;
   if(state==4&&!available)state<=0;
   if(state==0&&available)begin
    payload<={points,heatmap_crc,input_crc,model_crc,cycles,8'd0,flags,8'd11,8'd2};
    state<=1;index<=0;hcrc<=32'hffffffff;pcrc<=32'hffffffff;
   end
   if(valid&&ready)case(state)
    1:begin
     if(index<20)hcrc<=crc_byte(hcrc,data);
     if(index==23)begin index<=0;state<=2;end else index<=index+1'b1;
    end
    2:begin
     pcrc<=crc_byte(pcrc,data);
     if(index==85)begin index<=0;state<=3;end else index<=index+1'b1;
    end
    3:if(index==3)begin state<=4;sequence_id<=sequence_id+1'b1;release_result<=1;end else index<=index+1'b1;
   endcase
  end
 end
endmodule
