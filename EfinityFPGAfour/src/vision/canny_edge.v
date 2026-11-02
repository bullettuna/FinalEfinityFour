`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Complete one-pixel-per-clock streaming Canny edge detector:
//   3x3 Gaussian -> Sobel magnitude/direction -> NMS -> double threshold
//   -> local 8-connected hysteresis.
//
// RGB888 is carried as an aligned sideband for the colour-overlay display mode.
//////////////////////////////////////////////////////////////////////////////////

module canny_edge
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080
)
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_gray,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    input       [10:0]  low_threshold,
    input       [10:0]  high_threshold,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_edge,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire        gauss_vsync, gauss_href, gauss_hsync;
wire [7:0]  gauss_gray, gauss_r, gauss_g, gauss_b;

gaussian3x3_filter #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_canny_gaussian (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href(per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_gray(per_img_gray),
    .per_img_red(per_img_red), .per_img_green(per_img_green),
    .per_img_blue(per_img_blue),
    .post_frame_vsync(gauss_vsync),
    .post_frame_href(gauss_href),
    .post_frame_hsync(gauss_hsync),
    .post_img_gray(gauss_gray),
    .post_img_red(gauss_r), .post_img_green(gauss_g),
    .post_img_blue(gauss_b)
);

wire        gradient_vsync, gradient_href, gradient_hsync;
wire [10:0] gradient_magnitude;
wire [1:0]  gradient_direction;
wire [7:0]  gradient_r, gradient_g, gradient_b;

canny_gradient #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_canny_gradient (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(gauss_vsync),
    .per_frame_href(gauss_href),
    .per_frame_hsync(gauss_hsync),
    .per_img_gray(gauss_gray),
    .per_img_red(gauss_r), .per_img_green(gauss_g), .per_img_blue(gauss_b),
    .post_frame_vsync(gradient_vsync),
    .post_frame_href(gradient_href),
    .post_frame_hsync(gradient_hsync),
    .post_magnitude(gradient_magnitude),
    .post_direction(gradient_direction),
    .post_img_red(gradient_r), .post_img_green(gradient_g),
    .post_img_blue(gradient_b)
);

wire        nms_vsync, nms_href, nms_hsync;
wire [10:0] nms_magnitude;
wire [7:0]  nms_r, nms_g, nms_b;

canny_nms #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_canny_nms (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(gradient_vsync),
    .per_frame_href(gradient_href),
    .per_frame_hsync(gradient_hsync),
    .per_magnitude(gradient_magnitude),
    .per_direction(gradient_direction),
    .per_img_red(gradient_r), .per_img_green(gradient_g),
    .per_img_blue(gradient_b),
    .post_frame_vsync(nms_vsync),
    .post_frame_href(nms_href),
    .post_frame_hsync(nms_hsync),
    .post_magnitude(nms_magnitude),
    .post_img_red(nms_r), .post_img_green(nms_g), .post_img_blue(nms_b)
);

wire       threshold_vsync, threshold_href, threshold_hsync;
wire [1:0] threshold_class;
wire [7:0] threshold_r, threshold_g, threshold_b;

canny_double_threshold u_canny_double_threshold (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(nms_vsync),
    .per_frame_href(nms_href),
    .per_frame_hsync(nms_hsync),
    .per_magnitude(nms_magnitude),
    .low_threshold(low_threshold),
    .high_threshold(high_threshold),
    .per_img_red(nms_r), .per_img_green(nms_g), .per_img_blue(nms_b),
    .post_frame_vsync(threshold_vsync),
    .post_frame_href(threshold_href),
    .post_frame_hsync(threshold_hsync),
    .post_edge_class(threshold_class),
    .post_img_red(threshold_r), .post_img_green(threshold_g),
    .post_img_blue(threshold_b)
);

canny_hysteresis #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_canny_hysteresis (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(threshold_vsync),
    .per_frame_href(threshold_href),
    .per_frame_hsync(threshold_hsync),
    .per_edge_class(threshold_class),
    .per_img_red(threshold_r), .per_img_green(threshold_g),
    .per_img_blue(threshold_b),
    .post_frame_vsync(post_frame_vsync),
    .post_frame_href(post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_edge(post_img_edge),
    .post_img_red(post_img_red), .post_img_green(post_img_green),
    .post_img_blue(post_img_blue)
);

endmodule
