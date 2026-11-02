`timescale 1ns/1ps
// Only the point stream is gated. The immutable buffer never stalls inference.
// OFF cancels normal packets; the shared PHY completes any current WR# pulse.
// Explicit integer-oracle one-shot replies remain available with stream OFF.
module pose7_usb_sender(
 input clk,rst_n,stream_enable,publish,one_shot,
 input [527:0] points,input [31:0] cycles,model_crc,input_crc,heatmap_crc,input [7:0] flags,
 input ready,output valid,output [7:0] data,output reg available,output run_enable,output release_result
);
 reg diagnostic,completion;
 reg [527:0] held_points;
 reg [31:0] held_cycles,held_model_crc,held_input_crc,held_heatmap_crc;
 reg [7:0] held_flags;
 wire cancel=!stream_enable&&!(available&&diagnostic);
 assign run_enable=available&&!cancel;
 pose7_usb_packet u_packet(.clk(clk),.rst_n(rst_n),.cancel(cancel),.available(available),.release_result(release_result),
  .points(held_points),.cycles(held_cycles),.model_crc(held_model_crc),.input_crc(held_input_crc),
  .heatmap_crc(held_heatmap_crc),.flags(held_flags),.valid(valid),.data(data),.ready(ready));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin available<=0;diagnostic<=0;completion<=0;held_points<=0;held_cycles<=0;held_model_crc<=0;held_input_crc<=0;held_heatmap_crc<=0;held_flags<=0;end
  else begin
   if(release_result)completion<=1;
   // ready returns only after the PHY has completed its held final CRC byte.
   if(completion&&ready)begin available<=0;completion<=0;end
   if(available&&cancel)begin available<=0;completion<=0;end
   if(publish&&!available&&!release_result&&(stream_enable||one_shot))begin
    available<=1;diagnostic<=one_shot;completion<=0;
    held_points<=points;held_cycles<=cycles;held_model_crc<=model_crc;held_input_crc<=input_crc;held_heatmap_crc<=heatmap_crc;held_flags<=flags;
   end
  end
 end
endmodule
