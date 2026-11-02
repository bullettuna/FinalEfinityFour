`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// One-pass, 8-connected Canny hysteresis suitable for a live video stream.
// A strong centre pixel is always retained.  A weak centre pixel is retained
// only when at least one of its eight neighbours is strong.  This is a local
// hardware hysteresis pass; recursive full-frame propagation can be added later
// with DDR-backed iteration if the application requires it.
//////////////////////////////////////////////////////////////////////////////////

module canny_hysteresis
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
    input       [1:0]   per_edge_class,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_edge,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire        matrix_vsync;
wire        matrix_href;
wire        matrix_hsync;
wire [25:0] p11, p12, p13;
wire [25:0] p21, p22, p23;
wire [25:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(26)
) u_hysteresis_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue, per_edge_class}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21        (p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31        (p31), .matrix_p32(p32), .matrix_p33(p33)
);

canny_hysteresis_kernel_3x3 u_canny_hysteresis_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_vsync),
    .in_frame_href   (matrix_href),
    .in_frame_hsync  (matrix_hsync),
    .c11(p11[1:0]), .c12(p12[1:0]), .c13(p13[1:0]),
    .c21(p21[1:0]), .c22(p22[1:0]), .c23(p23[1:0]),
    .c31(p31[1:0]), .c32(p32[1:0]), .c33(p33[1:0]),
    .center_rgb      (p22[25:2]),
    .out_frame_vsync(post_frame_vsync),
    .out_frame_href (post_frame_href),
    .out_frame_hsync(post_frame_hsync),
    .out_img_edge   (post_img_edge),
    .out_rgb        ({post_img_red, post_img_green, post_img_blue})
);

endmodule


module canny_hysteresis_kernel_3x3
(
    input               clk,
    input               rst_n,
    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [1:0]   c11, c12, c13,
    input       [1:0]   c21, c22, c23,
    input       [1:0]   c31, c32, c33,
    input       [23:0]  center_rgb,
    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [7:0]   out_img_edge,
    output reg  [23:0]  out_rgb
);

wire center_is_strong = (c22 == 2'b10);
wire center_is_weak   = (c22 == 2'b01);
wire neighbour_is_strong =
    (c11 == 2'b10) || (c12 == 2'b10) || (c13 == 2'b10) ||
    (c21 == 2'b10) ||                    (c23 == 2'b10) ||
    (c31 == 2'b10) || (c32 == 2'b10) || (c33 == 2'b10);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_frame_vsync <= 1'b0;
        out_frame_href  <= 1'b0;
        out_frame_hsync <= 1'b0;
        out_img_edge    <= 8'd0;
        out_rgb         <= 24'd0;
    end else begin
        out_frame_vsync <= in_frame_vsync;
        out_frame_href  <= in_frame_href;
        out_frame_hsync <= in_frame_hsync;
        out_rgb         <= in_frame_href ? center_rgb : 24'd0;
        out_img_edge    <= (in_frame_href &&
                           (center_is_strong ||
                            (center_is_weak && neighbour_is_strong))) ?
                           8'hFF : 8'h00;
    end
end

endmodule
