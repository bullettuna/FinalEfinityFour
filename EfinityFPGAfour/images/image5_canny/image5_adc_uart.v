`timescale 1ns/1ps
// Image5 acquisition-only UART: debounced keys and explicitly requested snapshots.
// No periodic output; no knob-to-Canny connection. A query snapshots all fields
// before transmission so a changing ADC cannot tear a diagnostic line.
module image5_adc_uart(
 input clk,input rst_n,input query,output query_ready,
 input [11:0] raw_ch0,raw_ch1,knob_value,key_voltage,input knob_ready,
 input key_event,input [1:0] key_code,
 output tx_valid,output [7:0] tx_data,output tx_last,input tx_accept,input tx_done
);
 wire key_valid,key_last;wire [7:0] key_data;
 reg pending,status_active,status_waiting,key_frame;
 reg [47:0] pending_values,active_values;
 reg pending_ready,active_ready;
 reg [5:0] index;
 reg [7:0] status_data;
 localparam LAST=51;
 adc_uart_reporter u_keys(.clk(clk),.rst_n(rst_n),.key_event(key_event),.key_code(key_code),
  .tx_valid(key_valid),.tx_data(key_data),.tx_last(key_last),
  .tx_accept(!status_active&&tx_accept),.tx_done(!status_active&&tx_done));
 assign query_ready=!pending;
 assign tx_valid=status_active?!status_waiting:key_valid;
 assign tx_data=status_active?status_data:key_data;
 assign tx_last=status_active?(index==LAST):key_last;
 function [7:0] hex_digit;
  input [3:0] nibble;
  begin hex_digit=nibble<10?8'd48+{4'd0,nibble}:8'd55+{4'd0,nibble};end
 endfunction
 always @* begin
  status_data=0;
  case(index)
   7: status_data=hex_digit(active_values[47 -:4]);
   8: status_data=hex_digit(active_values[43 -:4]);
   9: status_data=hex_digit(active_values[39 -:4]);
   18: status_data=hex_digit(active_values[35 -:4]);
   19: status_data=hex_digit(active_values[31 -:4]);
   20: status_data=hex_digit(active_values[27 -:4]);
   29: status_data=hex_digit(active_values[23 -:4]);
   30: status_data=hex_digit(active_values[19 -:4]);
   31: status_data=hex_digit(active_values[15 -:4]);
   39: status_data=hex_digit(active_values[11 -:4]);
   40: status_data=hex_digit(active_values[7 -:4]);
   41: status_data=hex_digit(active_values[3 -:4]);
   0: status_data=8'h61;
   1: status_data=8'h64;
   2: status_data=8'h63;
   3: status_data=8'h30;
   4: status_data=8'h3d;
   5: status_data=8'h30;
   6: status_data=8'h78;
   10: status_data=8'h20;
   11: status_data=8'h61;
   12: status_data=8'h64;
   13: status_data=8'h63;
   14: status_data=8'h31;
   15: status_data=8'h3d;
   16: status_data=8'h30;
   17: status_data=8'h78;
   21: status_data=8'h20;
   22: status_data=8'h6b;
   23: status_data=8'h6e;
   24: status_data=8'h6f;
   25: status_data=8'h62;
   26: status_data=8'h3d;
   27: status_data=8'h30;
   28: status_data=8'h78;
   32: status_data=8'h20;
   33: status_data=8'h6b;
   34: status_data=8'h65;
   35: status_data=8'h79;
   36: status_data=8'h3d;
   37: status_data=8'h30;
   38: status_data=8'h78;
   42: status_data=8'h20;
   43: status_data=8'h72;
   44: status_data=8'h65;
   45: status_data=8'h61;
   46: status_data=8'h64;
   47: status_data=8'h79;
   48: status_data=8'h3d;
   50: status_data=8'h0d;
   51: status_data=8'h0a;
   49: status_data=active_ready?"1":"0";
   default:status_data=0;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pending<=0;status_active<=0;status_waiting<=0;key_frame<=0;index<=0;
   pending_values<=0;active_values<=0;pending_ready<=0;active_ready<=0;
  end else begin
   if(!status_active)begin
    if(key_valid&&tx_accept)key_frame<=1;
    if(key_frame&&tx_done&&key_last)key_frame<=0;
    // key_valid alone is not a whole-line busy signal: it falls between bytes.
    if(pending&&!key_frame&&!key_valid)begin
     pending<=0;status_active<=1;status_waiting<=0;index<=0;
     active_values<=pending_values;active_ready<=pending_ready;
    end
   end else if(!status_waiting&&tx_accept)status_waiting<=1;
   else if(status_waiting&&tx_done)begin
    status_waiting<=0;
    if(index==LAST)status_active<=0;
    else index<=index+1'b1;
   end
   if(query&&query_ready)begin
    pending<=1;pending_values<={raw_ch0,raw_ch1,knob_value,key_voltage};
    pending_ready<=knob_ready;
   end
  end
 end
endmodule
