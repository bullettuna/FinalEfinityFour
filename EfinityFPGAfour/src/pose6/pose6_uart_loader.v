`timescale 1ns/1ps
// ~6L + uint32 length + uint32 CRC + payload: load packed model to DDR.
// ~6I: load uint16 NHWC deterministic input. Header reply L accepts payload;
// final K means CRC and DDR writes complete, E failure, B busy. ~6Q => R/N,
// ~6T starts deterministic inference (reply T). Only stopped/idle may upload.
module pose6_uart_loader #(
 parameter MODEL_BYTES=161440,INPUT_BYTES=73728,CLOCK_HZ=96000000,
 parameter [31:0] EXPECTED_MODEL_CRC=32'd0
)(
 input clk,input rst_n,input [7:0] rx_data,input rx_valid,output legacy_rx_valid,
 input can_load,input clear_input,output reg model_ready,output reg input_ready,
 output reg test_start,output reg [31:0] model_crc,input_crc,
 output reg tx_valid,output reg [7:0] tx_data,input tx_accept,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,input memory_fault,
 input diagnostic_busy,output reg diagnostic_start,input external_model_ready,
 input debug_busy,invalidate_model,output reg debug_start,output reg [7:0] debug_opcode
);
 localparam IDLE=0,MAGIC=1,OPCODE=2,HEADER=3,PAYLOAD=4,FINISH=5;
 reg [2:0] state;reg image;
 reg [2:0] header_index;reg [31:0] length,expected_crc,count,crc,timer;
 reg [127:0] staging,write_buffer;
 reg [31:0] write_address;
 reg pending,inflight,failed;
 assign legacy_rx_valid=rx_valid&&state==IDLE&&rx_data!=8'h7e;
 assign command_valid=pending&&!inflight;
 assign command_write=1;assign command_address=write_address;assign command_data=write_buffer;
 function [31:0] crc_byte;
 input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
 begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;image<=0;header_index<=0;length<=0;expected_crc<=0;count<=0;crc<=0;timer<=0;
   staging<=0;write_buffer<=0;write_address<=0;pending<=0;inflight<=0;failed<=0;
   model_ready<=0;input_ready<=0;model_crc<=0;input_crc<=0;test_start<=0;tx_valid<=0;tx_data<=0;diagnostic_start<=0;
   debug_start<=0;debug_opcode<=0;
  end else begin
   test_start<=0;diagnostic_start<=0;
   debug_start<=0;
   if(invalidate_model)begin model_ready<=0;input_ready<=0;end
   if(clear_input)input_ready<=0;
   if(tx_valid&&tx_accept)tx_valid<=0;
   if(command_valid&&command_ready)inflight<=1;
   if(inflight&&response_valid)begin pending<=0;inflight<=0;end
   if(state==IDLE||rx_valid)timer<=0;else if(timer<CLOCK_HZ)timer<=timer+1'b1;
   if(state!=IDLE&&state!=FINISH&&timer==CLOCK_HZ-1)begin failed<=1;state<=FINISH;end
   if(rx_valid)case(state)
    IDLE:if(rx_data==8'h7e)begin state<=MAGIC;failed<=0;end
    MAGIC:if(rx_data=="6")state<=OPCODE;else begin state<=IDLE;tx_data<="E";tx_valid<=1;end
    OPCODE:if(debug_busy||diagnostic_busy)begin tx_data<="B";tx_valid<=1;state<=IDLE;end else case(rx_data)
     "S","F","V","+","-","R","H":begin
      debug_opcode<=rx_data;debug_start<=1;state<=IDLE;
     end
     "L","I":begin
      if(!can_load)begin tx_data<="B";tx_valid<=1;state<=IDLE;end
      else begin image<=rx_data=="I";header_index<=0;length<=0;expected_crc<=0;state<=HEADER;end
     end
     "Q":begin tx_data<=model_ready||external_model_ready?"R":"N";tx_valid<=1;state<=IDLE;end
     "D":begin
      if(diagnostic_busy)begin tx_data<="B";tx_valid<=1;end
      else diagnostic_start<=1;
      state<=IDLE;
     end
     "T":begin
      if(can_load&&(model_ready||external_model_ready)&&input_ready)begin test_start<=1;tx_data<="T";end else tx_data<="B";
      tx_valid<=1;state<=IDLE;
     end
     default:begin tx_data<="E";tx_valid<=1;state<=IDLE;end
    endcase
    HEADER:begin
     if(header_index<4)length[header_index*8+:8]<=rx_data;
     else expected_crc[(header_index-4)*8+:8]<=rx_data;
     if(header_index==7)begin
      if(length!=(image?INPUT_BYTES:MODEL_BYTES)||(!image&&{rx_data,expected_crc[23:0]}!=EXPECTED_MODEL_CRC))begin state<=IDLE;tx_data<="E";tx_valid<=1;end
      else begin
       if(image)input_ready<=0;else model_ready<=0;
       count<=0;crc<=32'hffffffff;failed<=0;state<=PAYLOAD;tx_data<="L";tx_valid<=1;
      end
     end else header_index<=header_index+1'b1;
    end
    PAYLOAD:begin
     staging[count[3:0]*8+:8]<=rx_data;
     crc<=crc_byte(crc,rx_data);count<=count+1'b1;
     if(count[3:0]==15)begin
      if(pending)failed<=1;
      else begin
       write_buffer<={rx_data,staging[119:0]};write_address<=(image?32'h02100000:32'h02000000)+count-15;
       pending<=1;
      end
     end
     if(count+1==length)state<=FINISH;
    end
   endcase
   if(state==FINISH&&!pending&&!inflight)begin
    if(!failed&&!memory_fault&&count==length&&~crc==expected_crc)begin
     if(image)begin input_ready<=1;input_crc<=expected_crc;end
     else begin model_ready<=1;model_crc<=expected_crc;end
     tx_data<="K";
    end else tx_data<="E";
    tx_valid<=1;state<=IDLE;
   end
  end
 end
endmodule
