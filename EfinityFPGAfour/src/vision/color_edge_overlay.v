`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Apply a binary Sobel mask to an already aligned RGB888 stream.
// A non-zero mask pixel is rendered in the selected color; all other pixels
// retain the camera image.  Timing is not changed in this final stage.
//////////////////////////////////////////////////////////////////////////////////

module color_edge_overlay
(
    input               overlay_enable,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    input       [7:0]   per_img_edge,
    input       [7:0]   edge_color_red,
    input       [7:0]   edge_color_green,
    input       [7:0]   edge_color_blue,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire draw_edge = overlay_enable && per_frame_href && (per_img_edge != 8'd0);

assign post_frame_vsync = per_frame_vsync;
assign post_frame_href  = per_frame_href;
assign post_frame_hsync = per_frame_hsync;
assign post_img_red     = per_frame_href ?
                          (draw_edge ? edge_color_red   : per_img_red)   : 8'd0;
assign post_img_green   = per_frame_href ?
                          (draw_edge ? edge_color_green : per_img_green) : 8'd0;
assign post_img_blue    = per_frame_href ?
                          (draw_edge ? edge_color_blue  : per_img_blue)  : 8'd0;

endmodule
