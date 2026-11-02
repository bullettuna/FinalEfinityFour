`timescale 1ns/1ps
// One retained, processed frame. DDR sectors are completely buffered before
// UART serialization, so a slow PC never holds an AXI response outstanding.
module photo_uart_export #(parameter WIDTH=960,HEIGHT=540)(
 input clk,input rst_n,input start,input [1:0] mode,input median_enable,
 input [1:0] cleanup_level,input [10:0] min_pixels,high_threshold,low_threshold,
 output busy,output reg done,output reg error,
 output reg read_start,output reg [19:0] read_offset,
 input read_done,input read_error,input read_valid,input [8:0] read_index,input [7:0] read_byte,
 output reg tx_valid,output reg [7:0] tx_data,output reg tx_last,input tx_accept,input tx_done
);
 localparam IDLE=0,HEADER=1,REQUEST=2,LOAD=3,PIX_ADDR=4,PIX_DATA=5,
  NEXT_PIXEL=6,TRAILER=7,TX_WAIT=8,FILL=9;
 localparam [31:0] EDGE_BYTES=WIDTH*HEIGHT/8,GRAY_BYTES=WIDTH*HEIGHT;
 localparam [15:0] IMAGE_WIDTH=WIDTH,IMAGE_HEIGHT=HEIGHT;
 reg [3:0] state,return_state;
 reg [255:0] header;
 reg [31:0] sequence_number,crc,payload_bytes,sent_bytes;
 reg [5:0] header_index;
 reg [3:0] tail_index;
 reg [7:0] pixel_index,packed_bits,low_byte;
 reg [9:0] received_bytes;
 reg binary_mode,failed,accepted,crc_enable;
 (* ram_style="block" *) reg [15:0] sector[0:255];
 reg [15:0] pixel;
 wire edge_bit=|pixel;
 assign busy=state!=IDLE;
 function [31:0] crc_byte;
  input [31:0] c;input [7:0] b;
  reg [31:0] v;integer k;
  begin v=c^{24'd0,b};for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 always @(posedge clk)begin
  if(state==LOAD&&read_valid)begin
   if(!read_index[0])low_byte<=read_byte;
   else sector[read_index[8:1]]<={read_byte,low_byte};
  end
  if(state==PIX_ADDR)pixel<=sector[pixel_index];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;return_state<=IDLE;header<=0;sequence_number<=0;crc<=32'hffffffff;
   payload_bytes<=0;sent_bytes<=0;header_index<=0;tail_index<=0;pixel_index<=0;packed_bits<=0;
   received_bytes<=0;binary_mode<=0;failed<=0;accepted<=0;crc_enable<=0;
   done<=0;error<=0;read_start<=0;read_offset<=0;tx_valid<=0;tx_data<=0;tx_last<=0;
  end else begin
   done<=0;error<=0;read_start<=0;
   case(state)
    IDLE:if(start)begin
     binary_mode<=mode==2;payload_bytes<=mode==2?WIDTH*HEIGHT/8:WIDTH*HEIGHT;
     // Little endian 32-byte I2PX v1 header; flags bit0 = bottom-up rows.
     header<={32'd0,{5'd0,low_threshold},{5'd0,high_threshold},{5'd0,min_pixels},
      8'd1,{6'd0,cleanup_level},{7'd0,median_enable},{6'd0,mode},sequence_number+32'd1,
      (mode==2?EDGE_BYTES:GRAY_BYTES),IMAGE_HEIGHT,IMAGE_WIDTH,
      (mode==2?8'd1:8'd2),8'd1,8'h58,8'h50,8'h32,8'h49};
     sequence_number<=sequence_number+1'b1;crc<=32'hffffffff;sent_bytes<=0;
     header_index<=0;tail_index<=0;read_offset<=0;failed<=0;state<=HEADER;
    end
    HEADER:begin
     tx_data<=header[header_index*8+:8];tx_valid<=1;tx_last<=0;accepted<=0;crc_enable<=1;
     header_index<=header_index+1'b1;return_state<=header_index==31?REQUEST:HEADER;state<=TX_WAIT;
    end
    REQUEST:begin read_start<=1;received_bytes<=0;state<=LOAD;end
    LOAD:begin
     if(read_valid)received_bytes<=received_bytes+1'b1;
     if(read_error)begin failed<=1;state<=FILL;end
     else if(read_done)begin
      if(received_bytes!=512)begin failed<=1;state<=FILL;end
      else begin pixel_index<=0;packed_bits<=0;state<=PIX_ADDR;end
     end
    end
    PIX_ADDR:state<=PIX_DATA;
    PIX_DATA:begin
     packed_bits<={packed_bits[6:0],edge_bit};
     if(!binary_mode||pixel_index[2:0]==7)begin
      tx_data<=binary_mode?{packed_bits[6:0],edge_bit}:{pixel[10:5],pixel[10:9]};
      tx_valid<=1;accepted<=0;crc_enable<=1;sent_bytes<=sent_bytes+1'b1;
      return_state<=NEXT_PIXEL;state<=TX_WAIT;
     end else state<=NEXT_PIXEL;
    end
    NEXT_PIXEL:begin
     if(pixel_index==255)begin
      read_offset<=read_offset+512;
      state<=sent_bytes==payload_bytes?TRAILER:REQUEST;
     end else begin pixel_index<=pixel_index+1'b1;state<=PIX_ADDR;end
    end
    // Preserve the advertised length on a DDR error, but end in FAIL.
    // The PC must verify BOTH the CRC and the success marker before saving.
    FILL:begin
     if(sent_bytes==payload_bytes)state<=TRAILER;
     else begin
      tx_data<=0;tx_valid<=1;accepted<=0;crc_enable<=1;sent_bytes<=sent_bytes+1'b1;
      return_state<=FILL;state<=TX_WAIT;
     end
    end
    TRAILER:begin
     case(tail_index)
      0:tx_data<=~crc[7:0];1:tx_data<=~crc[15:8];2:tx_data<=~crc[23:16];3:tx_data<=~crc[31:24];
      4:tx_data<=failed?"F":"D";5:tx_data<=failed?"A":"O";
      6:tx_data<=failed?"I":"N";7:tx_data<=failed?"L":"E";
     endcase
     tx_valid<=1;tx_last<=tail_index==7;accepted<=0;crc_enable<=0;
     return_state<=tail_index==7?IDLE:TRAILER;tail_index<=tail_index+1'b1;state<=TX_WAIT;
    end
    TX_WAIT:begin
     if(tx_valid&&tx_accept)begin
      tx_valid<=0;accepted<=1;if(crc_enable)crc<=crc_byte(crc,tx_data);
     end
     if(accepted&&tx_done)begin
      state<=return_state;accepted<=0;
      if(return_state==IDLE)begin done<=1;error<=failed;tx_last<=0;end
     end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
