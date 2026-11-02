`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming RGB888 3x3 median-filter wrapper.
//
// One shared 24-bit matrix generator keeps the R/G/B windows at exactly the
// same pixel coordinates.  Each channel then uses the existing exact median
// kernel.  When disabled, timing and RGB data use the original zero-latency
// bypass, matching median3x3_filter and the frame-boundary control scheme.
//////////////////////////////////////////////////////////////////////////////////

module rgb_median3x3_filter
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
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire        matrix_frame_vsync;
wire        matrix_frame_href;
wire        matrix_frame_hsync;
wire [23:0] matrix_p11, matrix_p12, matrix_p13;
wire [23:0] matrix_p21, matrix_p22, matrix_p23;
wire [23:0] matrix_p31, matrix_p32, matrix_p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(24)
) u_rgb_median_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue}),
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
wire [7:0] filtered_img_red;
wire [7:0] filtered_img_green;
wire [7:0] filtered_img_blue;

median3x3_kernel u_red_median3x3_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_frame_vsync),
    .in_frame_href   (matrix_frame_href),
    .in_frame_hsync  (matrix_frame_hsync),
    .p11(matrix_p11[23:16]), .p12(matrix_p12[23:16]), .p13(matrix_p13[23:16]),
    .p21(matrix_p21[23:16]), .p22(matrix_p22[23:16]), .p23(matrix_p23[23:16]),
    .p31(matrix_p31[23:16]), .p32(matrix_p32[23:16]), .p33(matrix_p33[23:16]),
    .out_frame_vsync (filtered_frame_vsync),
    .out_frame_href  (filtered_frame_href),
    .out_frame_hsync (filtered_frame_hsync),
    .out_img_median  (filtered_img_red)
);

median3x3_kernel u_green_median3x3_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_frame_vsync),
    .in_frame_href   (matrix_frame_href),
    .in_frame_hsync  (matrix_frame_hsync),
    .p11(matrix_p11[15:8]), .p12(matrix_p12[15:8]), .p13(matrix_p13[15:8]),
    .p21(matrix_p21[15:8]), .p22(matrix_p22[15:8]), .p23(matrix_p23[15:8]),
    .p31(matrix_p31[15:8]), .p32(matrix_p32[15:8]), .p33(matrix_p33[15:8]),
    .out_frame_vsync (),
    .out_frame_href  (),
    .out_frame_hsync (),
    .out_img_median  (filtered_img_green)
);

median3x3_kernel u_blue_median3x3_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_frame_vsync),
    .in_frame_href   (matrix_frame_href),
    .in_frame_hsync  (matrix_frame_hsync),
    .p11(matrix_p11[7:0]), .p12(matrix_p12[7:0]), .p13(matrix_p13[7:0]),
    .p21(matrix_p21[7:0]), .p22(matrix_p22[7:0]), .p23(matrix_p23[7:0]),
    .p31(matrix_p31[7:0]), .p32(matrix_p32[7:0]), .p33(matrix_p33[7:0]),
    .out_frame_vsync (),
    .out_frame_href  (),
    .out_frame_hsync (),
    .out_img_median  (filtered_img_blue)
);

assign post_frame_vsync = median_enable ? filtered_frame_vsync : per_frame_vsync;
assign post_frame_href  = median_enable ? filtered_frame_href  : per_frame_href;
assign post_frame_hsync = median_enable ? filtered_frame_hsync : per_frame_hsync;
assign post_img_red     = median_enable ? filtered_img_red     : per_img_red;
assign post_img_green   = median_enable ? filtered_img_green   : per_img_green;
assign post_img_blue    = median_enable ? filtered_img_blue    : per_img_blue;

endmodule
