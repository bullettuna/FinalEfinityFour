`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming 3x3 median-filter wrapper for an 8-bit grayscale video stream.
//
// Disabled: true zero-latency bypass, preserving the existing project behavior.
// Enabled : project-native two-line window followed by the pipelined exact
//           median kernel.  Timing and data are switched as one aligned path.
//////////////////////////////////////////////////////////////////////////////////

module median3x3_filter
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080
)
(
    input               clk,
    input               rst_n,
    input               median_enable,

    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_gray,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_gray
);

wire       matrix_frame_vsync;
wire       matrix_frame_href;
wire       matrix_frame_hsync;
wire [7:0] matrix_p11, matrix_p12, matrix_p13;
wire [7:0] matrix_p21, matrix_p22, matrix_p23;
wire [7:0] matrix_p31, matrix_p32, matrix_p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_median_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         (per_img_gray),
    .matrix_frame_vsync(matrix_frame_vsync),
    .matrix_frame_href (matrix_frame_href),
    .matrix_frame_hsync(matrix_frame_hsync),
    .matrix_p11        (matrix_p11),
    .matrix_p12        (matrix_p12),
    .matrix_p13        (matrix_p13),
    .matrix_p21        (matrix_p21),
    .matrix_p22        (matrix_p22),
    .matrix_p23        (matrix_p23),
    .matrix_p31        (matrix_p31),
    .matrix_p32        (matrix_p32),
    .matrix_p33        (matrix_p33)
);

wire       filtered_frame_vsync;
wire       filtered_frame_href;
wire       filtered_frame_hsync;
wire [7:0] filtered_img_gray;

median3x3_kernel u_median3x3_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_frame_vsync),
    .in_frame_href   (matrix_frame_href),
    .in_frame_hsync  (matrix_frame_hsync),
    .p11             (matrix_p11),
    .p12             (matrix_p12),
    .p13             (matrix_p13),
    .p21             (matrix_p21),
    .p22             (matrix_p22),
    .p23             (matrix_p23),
    .p31             (matrix_p31),
    .p32             (matrix_p32),
    .p33             (matrix_p33),
    .out_frame_vsync (filtered_frame_vsync),
    .out_frame_href  (filtered_frame_href),
    .out_frame_hsync (filtered_frame_hsync),
    .out_img_median  (filtered_img_gray)
);

assign post_frame_vsync = median_enable ? filtered_frame_vsync : per_frame_vsync;
assign post_frame_href  = median_enable ? filtered_frame_href  : per_frame_href;
assign post_frame_hsync = median_enable ? filtered_frame_hsync : per_frame_hsync;
assign post_img_gray    = median_enable ? filtered_img_gray    : per_img_gray;

endmodule
