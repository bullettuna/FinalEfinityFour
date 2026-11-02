`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Manual RGB white balance for an RGB888 streaming video path.
//
// Each channel uses an unsigned Q8.8 gain:
//   256 = 1.000x, 384 = 1.500x, 512 = 2.000x.
// The rounded result is saturated to 8 bits instead of wrapping at 255.
// The two registered stages sustain one RGB pixel per clock.
//////////////////////////////////////////////////////////////////////////////////

module rgb_white_balance
(
    input               clk,
    input               rst_n,

    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,

    input       [10:0]  red_gain,
    input       [10:0]  green_gain,
    input       [10:0]  blue_gain,

    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

reg [18:0] red_product;
reg [18:0] green_product;
reg [18:0] blue_product;
reg        vsync_d1;
reg        href_d1;
reg        hsync_d1;

function [7:0] round_and_saturate_q8_8;
    input [18:0] product;
    reg   [18:0] rounded_product;
    begin
        rounded_product = product + 19'd128;
        if (rounded_product[18:8] > 11'd255)
            round_and_saturate_q8_8 = 8'hFF;
        else
            round_and_saturate_q8_8 = rounded_product[15:8];
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        red_product      <= 19'd0;
        green_product    <= 19'd0;
        blue_product     <= 19'd0;
        vsync_d1         <= 1'b0;
        href_d1          <= 1'b0;
        hsync_d1         <= 1'b0;
        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_img_red     <= 8'd0;
        post_img_green   <= 8'd0;
        post_img_blue    <= 8'd0;
    end else begin
        // Pixel products only need to advance during active video. This maps
        // naturally onto the multiplier clock-enable pins and avoids toggling
        // the DSP blocks throughout horizontal and vertical blanking.
        if (per_frame_href) begin
            red_product   <= per_img_red * red_gain;
            green_product <= per_img_green * green_gain;
            blue_product  <= per_img_blue * blue_gain;
        end
        vsync_d1      <= per_frame_vsync;
        href_d1       <= per_frame_href;
        hsync_d1      <= per_frame_hsync;

        post_frame_vsync <= vsync_d1;
        post_frame_href  <= href_d1;
        post_frame_hsync <= hsync_d1;
        post_img_red     <= round_and_saturate_q8_8(red_product);
        post_img_green   <= round_and_saturate_q8_8(green_product);
        post_img_blue    <= round_and_saturate_q8_8(blue_product);
    end
end

endmodule
