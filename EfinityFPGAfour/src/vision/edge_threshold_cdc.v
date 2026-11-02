`timescale 1ns/1ps
// Freeze high/low as one mailbox until the video domain captures it at a frame
// boundary. Rapid requests coalesce; no multi-bit threshold bus is sampled live.
module edge_threshold_cdc #(
    parameter [10:0] DEFAULT_HIGH = 11'd45,
    parameter [10:0] DEFAULT_LOW = 11'd22
)(
    input clk, input rst_n,
    input [10:0] high_request, input [10:0] low_request,
    input pclk, input prst_n, input frame_vsync,
    output reg [10:0] high_active, output reg [10:0] low_active
);
reg [21:0] held_pair;
reg request_toggle;
reg acknowledge_toggle;
(* async_reg="true" *) reg ack_meta,ack_sync;
(* async_reg="true" *) reg request_meta,request_sync;
reg vsync_d;
wire [10:0] checked_low = low_request > high_request ? high_request : low_request;
wire [21:0] requested_pair = {high_request,checked_low};
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        held_pair <= {DEFAULT_HIGH,DEFAULT_LOW};
        request_toggle <= 0;
        ack_meta <= 0; ack_sync <= 0;
    end else begin
        ack_meta <= acknowledge_toggle;
        ack_sync <= ack_meta;
        if (ack_sync == request_toggle && held_pair != requested_pair) begin
            held_pair <= requested_pair;
            request_toggle <= !request_toggle;
        end
    end
end
always @(posedge pclk or negedge prst_n) begin
    if (!prst_n) begin
        request_meta <= 0; request_sync <= 0;
        acknowledge_toggle <= 0;
        vsync_d <= 0;
        high_active <= DEFAULT_HIGH;
        low_active <= DEFAULT_LOW;
    end else begin
        request_meta <= request_toggle;
        request_sync <= request_meta;
        vsync_d <= frame_vsync;
        if (!vsync_d && frame_vsync && request_sync != acknowledge_toggle) begin
            high_active <= held_pair[21:11];
            low_active <= held_pair[10:0];
            acknowledge_toggle <= request_sync;
        end
    end
end
endmodule
