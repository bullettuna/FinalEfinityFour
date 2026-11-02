`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"
// Hold the entire record until the pixel clock commits it during vertical blank.
// Toggle/ack synchronizers coalesce updates; the payload is never sampled live.
module image5_menu_cdc(
 input clk,rst_n,input [`M5_DISP_WIDTH-1:0] requested,
 input pclk,prst_n,frame_vsync,output reg [`M5_DISP_WIDTH-1:0] active
);
 reg [`M5_DISP_WIDTH-1:0] held;
 reg request_toggle,acknowledge;
 (* async_reg="true" *) reg ack_meta,ack_sync,request_meta,request_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin held<=0;request_toggle<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=acknowledge;ack_sync<=ack_meta;
   if(ack_sync==request_toggle&&requested!=held)begin held<=requested;request_toggle<=!request_toggle;end
  end
 end
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin active<=0;acknowledge<=0;request_meta<=0;request_sync<=0;end
  else begin
   request_meta<=request_toggle;request_sync<=request_meta;
   if(!frame_vsync&&request_sync!=acknowledge)begin active<=held;acknowledge<=request_sync;end
  end
 end
endmodule
