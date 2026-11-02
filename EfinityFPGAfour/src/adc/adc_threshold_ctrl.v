`timescale 1ns/1ps
// Last explicit control wins.  Two knob policies are available:
//   KNOB_DIRECT=1 : the moving CH0 knob writes high/low thresholds directly
//                   (image2 and earlier profiles).
//   KNOB_DIRECT=0 : the knob never touches Canny directly (image1); only the
//                   on-screen menu's CANNY/H/L EDIT items write thresholds.
//                   This removes the power-on position grab that used to
//                   override the 17/8 defaults as soon as the first averaged
//                   sample arrived.
module adc_threshold_ctrl #(
    parameter [10:0] DEFAULT_HIGH = 11'd45,
    parameter [10:0] DEFAULT_LOW = 11'd22,
    parameter integer KNOB_DEADBAND = 8,
    parameter KNOB_DIRECT = 1'b1
)(
    input clk, input rst_n,
    input [11:0] knob_value, input knob_ready, input knob_enable,
    input uart_update, input [10:0] uart_high, input [10:0] uart_low,
    output reg [10:0] high_threshold, output reg [10:0] low_threshold
);
reg knob_seen;
reg [11:0] last_knob;
wire [11:0] delta = knob_value >= last_knob ? knob_value-last_knob : last_knob-knob_value;
wire [10:0] mapped_high = knob_value[11:1];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        high_threshold <= DEFAULT_HIGH;
        low_threshold <= DEFAULT_LOW;
        knob_seen <= 0;
        last_knob <= 0;
    end else if (uart_update) begin
        high_threshold <= uart_high;
        low_threshold <= uart_low > uart_high ? uart_high : uart_low;
        if (knob_ready) begin knob_seen <= 1; last_knob <= knob_value; end
    end else if (KNOB_DIRECT && knob_ready && !knob_enable) begin
        // The menu owns the knob: remember where it is, change nothing.
        knob_seen <= 1;
        last_knob <= knob_value;
    end else if (KNOB_DIRECT && knob_ready && (!knob_seen || delta >= KNOB_DEADBAND)) begin
        high_threshold <= mapped_high;
        low_threshold <= {1'b0,knob_value[11:2]};
        knob_seen <= 1;
        last_knob <= knob_value;
    end
end
endmodule
