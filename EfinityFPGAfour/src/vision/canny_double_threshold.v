`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Canny double-threshold classifier.
//   2'b00: suppressed / non-edge
//   2'b01: weak edge
//   2'b10: strong edge
//////////////////////////////////////////////////////////////////////////////////

module canny_double_threshold
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [10:0]  per_magnitude,
    input       [10:0]  low_threshold,
    input       [10:0]  high_threshold,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg  [1:0]   post_edge_class,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_edge_class  <= 2'b00;
        post_img_red     <= 8'd0;
        post_img_green   <= 8'd0;
        post_img_blue    <= 8'd0;
    end else begin
        post_frame_vsync <= per_frame_vsync;
        post_frame_href  <= per_frame_href;
        post_frame_hsync <= per_frame_hsync;
        {post_img_red, post_img_green, post_img_blue} <=
            per_frame_href ? {per_img_red, per_img_green, per_img_blue} : 24'd0;

        if (!per_frame_href || (per_magnitude == 11'd0) ||
            (per_magnitude < low_threshold))
            post_edge_class <= 2'b00;
        else if (per_magnitude >= high_threshold)
            post_edge_class <= 2'b10;
        else
            post_edge_class <= 2'b01;
    end
end

endmodule
