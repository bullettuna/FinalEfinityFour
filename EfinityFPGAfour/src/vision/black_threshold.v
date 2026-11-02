`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// One-stage black-pixel segmenter.
//
// Foreground convention: 1 means a dark object pixel.  The threshold and all
// video timing signals are registered with the comparison result so downstream
// streaming filters see a cycle-aligned bundle.
//////////////////////////////////////////////////////////////////////////////////

module black_threshold
(
    input               clk,
    input               rst_n,
    input       [7:0]   black_threshold_level,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_gray,
    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg          post_img_mask
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_img_mask    <= 1'b0;
    end else begin
        post_frame_vsync <= per_frame_vsync;
        post_frame_href  <= per_frame_href;
        post_frame_hsync <= per_frame_hsync;
        post_img_mask    <= per_frame_href &&
                            (per_img_gray <= black_threshold_level);
    end
end

endmodule
