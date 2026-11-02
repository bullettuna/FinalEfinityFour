`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"
// Private image5 prefix: !0 stop, !1 counter, !2 gray, !3 packed edges,
// !7 byte edges, !P packing capability 1.
// !? internal readiness A/N, !S requested mode, !V async capability A.
// Bytes belonging to a prefix never reach the legacy Canny UART decoder.
module image5_ft_uart_control #(parameter ADC_QUERY_AVAILABLE=1'b0,MENU_AVAILABLE=1'b0)(
 input clk,input rst_n,input [7:0] rx_data,input rx_valid,input link_ready,input link_stopped,
 output legacy_rx_valid,input legacy_start,input [7:0] legacy_data,
 input command_done,output legacy_done,output reg command_start,output reg [7:0] command_data,
 output reg [1:0] mode,output reg [1:0] resolution,output reg edge_packed,output run_n,
 input adc_query_ready,output reg adc_query,
 input menu_write_valid,input [4:0] menu_write_addr,input [11:0] menu_write_value,
 output configuration_busy
);
 reg prefix,reply_start;reg [7:0] reply;
 reg [8:0] responses[0:7];reg [2:0] wp,rp;reg [3:0] queued;
 reg response_busy,owner_ft;
 wire take=!response_busy&&queued!=0;
 wire [1:0] puts={1'b0,reply_start}+{1'b0,legacy_start};
 wire [2:0] legacy_wp=wp+reply_start;
 wire room=queued+puts-take<=8;
 assign legacy_done=command_done&&response_busy&&!owner_ft;
 // Preserve reply ownership until its byte is physically complete. A later
 // FT request must not steal an earlier Canny UART completion (or vice versa).
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wp<=0;rp<=0;queued<=0;response_busy<=0;owner_ft<=0;command_start<=0;command_data<=0;end
  else begin
   command_start<=0;
   if(command_done)response_busy<=0;
   if(take)begin
    command_start<=1;command_data<=responses[rp][7:0];owner_ft<=responses[rp][8];
    response_busy<=1;rp<=rp+1'b1;
   end
   queued<=queued+(room?puts:0)-take;
   if(room)begin
    if(reply_start)responses[wp]<={1'b1,reply};
    if(legacy_start)responses[legacy_wp]<={1'b0,legacy_data};
    wp<=wp+puts;
   end
  end
 end
 // Reconfiguration first stops the physical writer and drains DDR.
 // !4/!5/!6 select 320/640/1920; reply is the selected digit.
 reg waiting,pending_packed,pending_silent;reg [1:0] pending_mode,pending_resolution;reg [7:0] pending_reply;
 assign configuration_busy=waiting;
 assign legacy_rx_valid=rx_valid&&!prefix&&rx_data!="!";
 assign run_n=rst_n&&link_ready&&mode!=0&&!waiting;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin prefix<=0;reply_start<=0;reply<=0;mode<=0;resolution<=0;edge_packed<=1;
   waiting<=0;pending_packed<=1;pending_silent<=0;pending_mode<=0;pending_resolution<=0;pending_reply<=0;adc_query<=0;end
  else begin
   reply_start<=0;adc_query<=0;
   if(waiting&&link_stopped)begin
    waiting<=0;mode<=pending_mode;resolution<=pending_resolution;edge_packed<=pending_packed;
    if(!pending_silent)begin reply<=pending_reply;reply_start<=1;end
   end
   // Reuse the serial command's graceful stop/drain transaction, silently.
   if(MENU_AVAILABLE&&menu_write_valid&&!waiting&&!rx_valid)begin
    if(menu_write_addr==`M5_USB_MODE||menu_write_addr==`M5_USB_SIZE||menu_write_addr==`M5_USB_STOP)begin
     waiting<=1;pending_silent<=1;pending_mode<=mode;pending_resolution<=resolution;pending_packed<=edge_packed;
     if(menu_write_addr==`M5_USB_STOP)pending_mode<=0;
     else if(menu_write_addr==`M5_USB_SIZE)pending_resolution<=menu_write_value>2?2'd2:menu_write_value[1:0];
     else begin
      pending_mode<=menu_write_value>=3?2'd3:menu_write_value[1:0];
      if(menu_write_value==3||menu_write_value==4)pending_packed<=menu_write_value==3;
     end
    end
   end
   if(rx_valid)begin
    if(prefix)begin
     prefix<=0;
     if(waiting)begin reply_start<=1;reply<="B";end
     else case(rx_data)
      "0","1","2","3","4","5","6","7":begin
       if(!link_ready)begin mode<=0;reply_start<=1;reply<="N";end
       else begin
        waiting<=1;pending_reply<=rx_data;pending_silent<=0;
        pending_mode<=rx_data=="7"?2'd3:rx_data<="3"?rx_data[1:0]:mode;
        pending_resolution<=rx_data>="4"&&rx_data<="6"?rx_data-"4":resolution;
        pending_packed<=rx_data=="3"?1'b1:rx_data=="7"?1'b0:edge_packed;
       end
      end
      "A":begin
       if(ADC_QUERY_AVAILABLE&&adc_query_ready)adc_query<=1;
       else begin reply_start<=1;reply<=ADC_QUERY_AVAILABLE?"B":"!";end
      end
      "?":begin reply_start<=1;reply<=link_ready?"A":"N";end
      "S":begin reply_start<=1;reply<="0"+mode;end
      "R":begin reply_start<=1;reply<="4"+resolution;end
      "V":begin reply_start<=1;reply<="A";end
      "P":begin reply_start<=1;reply<="1";end
      "M":begin reply_start<=1;reply<=MENU_AVAILABLE?"1":"0";end
      default:begin reply_start<=1;reply<="!";end
     endcase
    end else if(rx_data=="!")prefix<=1;
   end
  end
 end
endmodule
