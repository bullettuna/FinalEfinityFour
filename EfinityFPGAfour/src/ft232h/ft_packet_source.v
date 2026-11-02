`timescale 1ns/1ps
// FT5! v1: 24-byte little-endian header (CRC32 over first 20 bytes),
// payload, then CRC32(payload). Reflected IEEE CRC32 matches Python zlib.
module ft_packet_source #(parameter COUNTER_BYTES=4096)(
 input clk,input rst_n,input [1:0] mode,input edge_packed,input snapshot_available,input [15:0] frame_width,frame_height,input snapshot_valid,
 output reg snapshot_release,output [20:0] snapshot_address,input [7:0] snapshot_data,
 output valid,output [7:0] data,input ready
);
 localparam WAIT=0,HEADER=1,PAYLOAD=2,FOOTER=3,REARM=4;
 reg [2:0] state;reg [4:0] hi;reg [1:0] tail,wait_ram;
 reg [31:0] seq,index,hcrc,pcrc;reg [7:0] kind;
 wire [31:0] pixels=frame_width*frame_height;
 wire [31:0] length=kind==0?COUNTER_BYTES:kind==3?(pixels>>3):pixels;
 wire [15:0] w=kind==0?0:frame_width,h=kind==0?0:frame_height;
 function [31:0] crc;
 input [31:0] previous;input [7:0] byte_value;integer b;reg [31:0] c;
 begin c=previous^byte_value;for(b=0;b<8;b=b+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc=c;end
 endfunction
 reg [7:0] header_byte;
 always @*case(hi)
  0:header_byte="F";1:header_byte="T";2:header_byte="5";3:header_byte="!";
  4:header_byte=1;5:header_byte=kind;6:header_byte=0;7:header_byte=24;
  8,9,10,11:header_byte=seq>>((hi-8)*8);
  12:header_byte=w[7:0];13:header_byte=w[15:8];14:header_byte=h[7:0];15:header_byte=h[15:8];
  16,17,18,19:header_byte=length>>((hi-16)*8);
  default:header_byte=(~hcrc)>>((hi-20)*8);
 endcase
 assign snapshot_address=index[20:0];
 assign valid=(state==HEADER||state==PAYLOAD||state==FOOTER)&&wait_ram==0&&(state!=PAYLOAD||kind==0||snapshot_valid);
 assign data=state==HEADER?header_byte:state==PAYLOAD?(kind==0?index[7:0]:snapshot_data):(~pcrc)>>(tail*8);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=WAIT;hi<=0;tail<=0;wait_ram<=0;seq<=0;index<=0;hcrc<=32'hffffffff;pcrc<=32'hffffffff;kind<=0;snapshot_release<=0;end
  else begin
   snapshot_release<=0;if(wait_ram!=0)wait_ram<=wait_ram-1'b1;
   if(state==REARM&&!snapshot_available)state<=WAIT;
   if(state==WAIT&&(mode==1||snapshot_available))begin
    kind<=mode==3&&edge_packed?3:mode-1'b1;state<=HEADER;hi<=0;index<=0;hcrc<=32'hffffffff;pcrc<=32'hffffffff;
   end
   if(valid&&ready)case(state)
    HEADER:begin
     if(hi<20)hcrc<=crc(hcrc,data);
     if(hi==23)begin state<=PAYLOAD;index<=0;wait_ram<=2;end else hi<=hi+1'b1;
    end
    PAYLOAD:begin
     pcrc<=crc(pcrc,data);
     if(index==length-1)begin state<=FOOTER;tail<=0;end
     else begin index<=index+1'b1;wait_ram<=2;end
    end
    FOOTER:if(tail==3)begin
     state<=kind==0?WAIT:REARM;seq<=seq+1'b1;if(kind!=0)snapshot_release<=1;
    end else tail<=tail+1'b1;
   endcase
  end
 end
endmodule
