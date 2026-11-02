`timescale 1ns/1ps
// Native image2 SD4 driver + read-only FAT32 package + checked DDR writes.
module pose6_sd_boot #(parameter CLOCK_HZ=96000000)(
 input clk,rst_n,start,
 output reg busy,done,ready,error,output reg [7:0] error_code,
 output [5:0] error_command,output [3:0] sd_error_reason,
 output sd_clk,sd_cmd_o,sd_cmd_oe,input sd_cmd_i,
 input [3:0] sd_dat_i,output [3:0] sd_dat_o,sd_dat_oe,
 output command_valid,input command_ready,output command_write,
 output [31:0] command_address,output [127:0] command_data,
 input response_valid,memory_fault,
 output card_initialized,fat_valid,file_found,header_valid,crc_valid,
 output [31:0] file_size,read_bytes
);
 `include "images/image6_pose_int16/pose6_model_identity.vh"
 `include "images/image6_pose_int16/pose6_boot_identity.vh"
 wire hi,hid,hie,hbusy,bs,bb,bd,be,rxv,initialized,hc;
 wire [31:0] lba,capacity;wire [7:0] rxd;wire [8:0] index;
 sd4_host #(.CLK_HZ(CLOCK_HZ),.INIT_DIV(CLOCK_HZ/800000),.FAST_DIV(8),.POWER_CYCLES(CLOCK_HZ/100)) host(
  .clk(clk),.rst_n(rst_n),.sd_clk(sd_clk),.sd_cmd_o(sd_cmd_o),.sd_cmd_oe(sd_cmd_oe),.sd_cmd_i(sd_cmd_i),
  .sd_dat_i(sd_dat_i),.sd_dat_o(sd_dat_o),.sd_dat_oe(sd_dat_oe),
  .init_start(hi),.init_busy(hbusy),.init_done(hid),.init_error(hie),.error_command(error_command),.error_reason(sd_error_reason),
  .high_capacity(hc),.initialized(initialized),.capacity_mb(capacity),
  .block_start(bs),.block_write(1'b0),.block_lba(lba),.block_busy(bb),.block_done(bd),.block_error(be),
  .block_rx_valid(rxv),.block_rx_data(rxd),.block_byte_index(index),.block_tx_byte(8'hff));
 wire file_busy,file_done,file_error,valid;
 wire [7:0] file_error_code,data;wire [31:0] offset;
 reg failed,file_finished;
 reg [511:0] header;
 reg [31:0] header_crc,model_crc,input_crc;
 reg header_ok,pending,inflight;
 reg [127:0] staging,write_data;
 reg [31:0] write_address;
 wire take=busy&&!failed&&!pending&&!inflight;
 assign card_initialized=initialized;
 assign header_valid=header_ok;
 assign crc_valid=ready;
 assign read_bytes=offset;
 pose6_fat_reader #(.FILE_BYTES(POSE6_BOOT_BYTES),.CLOCK_HZ(CLOCK_HZ)) reader(
  .clk(clk),.rst_n(rst_n),.start(start),.abort(failed),.busy(file_busy),.done(file_done),.error(file_error),.error_code(file_error_code),
  .init_start(hi),.init_done(hid),.init_error(hie),.block_start(bs),.block_lba(lba),.block_busy(bb),.block_done(bd),.block_error(be),
  .block_rx_valid(rxv),.block_byte_index(index),.block_rx_data(rxd),
  .byte_valid(valid),.byte_ready(take),.byte_data(data),.byte_offset(offset),
  .fat_valid(fat_valid),.file_found(file_found),.file_size(file_size));
 function [31:0] crc_byte;
  input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
  begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 wire [31:0] payload_offset=offset-64;
 assign command_valid=pending&&!inflight;
 assign command_write=1'b1;assign command_address=write_address;assign command_data=write_data;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;done<=0;ready<=0;error<=0;error_code<=0;failed<=0;file_finished<=0;
   header<=0;header_crc<=32'hffffffff;model_crc<=32'hffffffff;input_crc<=32'hffffffff;
   header_ok<=0;pending<=0;inflight<=0;staging<=0;write_data<=0;write_address<=0;end
  else begin
   done<=0;
   if(start&&!busy)begin busy<=1;ready<=0;error<=0;failed<=0;error_code<=0;file_finished<=0;
    header_ok<=0;header_crc<=32'hffffffff;model_crc<=32'hffffffff;input_crc<=32'hffffffff;end
   if(command_valid&&command_ready)inflight<=1;
   if(inflight&&response_valid)begin pending<=0;inflight<=0;end
   if(busy&&memory_fault)begin failed<=1;error_code<=8'h23;end
   if(busy&&file_error)begin failed<=1;if(!failed)error_code<=file_error_code;end
   if(busy&&valid&&take)begin
    if(offset<64)begin
     header[offset*8+:8]<=data;
     if(offset<60)header_crc<=crc_byte(header_crc,data);
     if(offset==63)begin
      if(header[63:0]!=64'h313045534f503649|| // little-endian I6POSE01
         header[95:64]!=POSE6_MODEL_BYTES||header[127:96]!=73728||
         header[159:128]!=POSE6_MODEL_CRC||header[191:160]!=POSE6_TEST_INPUT_CRC||
         header[223:192]!=POSE6_TEST_HEATMAP_CRC||header[415:224]!=POSE6_TEST_POINTS||
         header[447:416]!=1||header[479:448]!=0||{data,header[503:480]}!=~header_crc)
       begin failed<=1;error_code<=8'h20;end
      else header_ok<=1;
     end
    end else if(header_ok)begin
     staging[payload_offset[3:0]*8+:8]<=data;
     if(payload_offset<POSE6_MODEL_BYTES)model_crc<=crc_byte(model_crc,data);
     else input_crc<=crc_byte(input_crc,data);
     if(payload_offset[3:0]==15)begin
      write_data<={data,staging[119:0]};pending<=1;
      write_address<=payload_offset<POSE6_MODEL_BYTES?32'h02000000+payload_offset-15:
                     32'h02100000+payload_offset-POSE6_MODEL_BYTES-15;
     end
    end
   end
   if(file_done)file_finished<=1;
   if(busy&&failed&&!pending&&!inflight&&!file_busy)begin busy<=0;error<=1;end
   if(busy&&file_finished&&!pending&&!inflight&&!failed)begin
    busy<=0;
    if(header_ok&&~model_crc==POSE6_MODEL_CRC&&~input_crc==POSE6_TEST_INPUT_CRC)begin ready<=1;done<=1;end
    else begin error<=1;error_code<=8'h21;end
   end
  end
 end
endmodule
