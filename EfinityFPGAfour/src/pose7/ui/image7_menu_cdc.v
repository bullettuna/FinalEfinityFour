`timescale 1ns/1ps
// One stable bundled record per handshake; acknowledge only after committing
// in vertical blanking. Multi-bit fields never tear during an active frame.
module image7_menu_cdc #(parameter WIDTH=140)(
 input sclk,srst_n,pclk,prst_n,in_vsync,
 input [WIDTH-1:0] source,
 output reg [WIDTH-1:0] active
);
 reg [WIDTH-1:0] held;
 reg request,ack;
 (* async_reg="true" *) reg ack_meta,ack_sync,req_meta,req_sync;
 (* async_reg="true" *) reg [WIDTH-1:0] data_meta,data_sync;
 always @(posedge sclk or negedge srst_n) begin
  if(!srst_n)begin held<=0;request<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=ack;ack_sync<=ack_meta;
   if(request==ack_sync && held!=source)begin held<=source;request<=!request;end
  end
 end
 always @(posedge pclk or negedge prst_n) begin
  if(!prst_n)begin req_meta<=0;req_sync<=0;data_meta<=0;data_sync<=0;active<=0;ack<=0;end
  else begin
   req_meta<=request;req_sync<=req_meta;
   data_meta<=held;data_sync<=data_meta;
   if(!in_vsync && req_sync!=ack)begin active<=data_sync;ack<=req_sync;end
  end
 end
endmodule
