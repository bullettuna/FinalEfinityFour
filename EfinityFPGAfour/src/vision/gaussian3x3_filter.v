`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming 3x3 Gaussian filter with an aligned RGB888 sideband.
//
// Kernel:
//             1 2 1
//      1/16 * 2 4 2
//             1 2 1
//
// All coefficients are powers of two, so the implementation uses additions
// and shifts only. The grayscale and all three RGB channels are each smoothed,
// so the downstream colour-aware Canny gradient sees noise-reduced colour
// samples while remaining correctly aligned.
//////////////////////////////////////////////////////////////////////////////////

module gaussian3x3_filter
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

    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg  [7:0]   post_img_gray,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

wire        matrix_vsync;
wire        matrix_href;
wire        matrix_hsync;
wire [31:0] p11, p12, p13;
wire [31:0] p21, p22, p23;
wire [31:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(32)
) u_gaussian_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue, per_img_gray}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21        (p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31        (p31), .matrix_p32(p32), .matrix_p33(p33)
);

// Per-channel 3x3 taps: gray=[7:0], R=[31:24], G=[23:16], B=[15:8].
wire [7:0] y11 = p11[7:0],   y12 = p12[7:0],   y13 = p13[7:0];
wire [7:0] y21 = p21[7:0],   y22 = p22[7:0],   y23 = p23[7:0];
wire [7:0] y31 = p31[7:0],   y32 = p32[7:0],   y33 = p33[7:0];
wire [7:0] r11 = p11[31:24], r12 = p12[31:24], r13 = p13[31:24];
wire [7:0] r21 = p21[31:24], r22 = p22[31:24], r23 = p23[31:24];
wire [7:0] r31 = p31[31:24], r32 = p32[31:24], r33 = p33[31:24];
wire [7:0] g11 = p11[23:16], g12 = p12[23:16], g13 = p13[23:16];
wire [7:0] g21 = p21[23:16], g22 = p22[23:16], g23 = p23[23:16];
wire [7:0] g31 = p31[23:16], g32 = p32[23:16], g33 = p33[23:16];
wire [7:0] b11 = p11[15:8],  b12 = p12[15:8],  b13 = p13[15:8];
wire [7:0] b21 = p21[15:8],  b22 = p22[15:8],  b23 = p23[15:8];
wire [7:0] b31 = p31[15:8],  b32 = p32[15:8],  b33 = p33[15:8];

// Maximum weighted sum is 16*255 = 4080, which fits in 12 bits.
function [11:0] gauss_sum;
    input [7:0] a11, a12, a13, a21, a22, a23, a31, a32, a33;
    reg   [11:0] corner, cross, center;
    begin
        corner = {4'd0, a11} + {4'd0, a13} + {4'd0, a31} + {4'd0, a33};
        cross  = ({4'd0, a12} + {4'd0, a21} + {4'd0, a23} + {4'd0, a32}) << 1;
        center = {2'd0, a22, 2'b00};
        gauss_sum = corner + cross + center;
    end
endfunction

reg [11:0] wsum_gray_s1, wsum_r_s1, wsum_g_s1, wsum_b_s1;
reg        vsync_s1, href_s1, hsync_s1;
wire [11:0] rounded_gray = wsum_gray_s1 + 12'd8;
wire [11:0] rounded_r    = wsum_r_s1    + 12'd8;
wire [11:0] rounded_g    = wsum_g_s1    + 12'd8;
wire [11:0] rounded_b    = wsum_b_s1    + 12'd8;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wsum_gray_s1    <= 12'd0;
        wsum_r_s1       <= 12'd0;
        wsum_g_s1       <= 12'd0;
        wsum_b_s1       <= 12'd0;
        vsync_s1        <= 1'b0;
        href_s1         <= 1'b0;
        hsync_s1        <= 1'b0;
        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_img_gray    <= 8'd0;
        post_img_red     <= 8'd0;
        post_img_green   <= 8'd0;
        post_img_blue    <= 8'd0;
    end else begin
        wsum_gray_s1 <= gauss_sum(y11, y12, y13, y21, y22, y23, y31, y32, y33);
        wsum_r_s1    <= gauss_sum(r11, r12, r13, r21, r22, r23, r31, r32, r33);
        wsum_g_s1    <= gauss_sum(g11, g12, g13, g21, g22, g23, g31, g32, g33);
        wsum_b_s1    <= gauss_sum(b11, b12, b13, b21, b22, b23, b31, b32, b33);
        vsync_s1        <= matrix_vsync;
        href_s1         <= matrix_href;
        hsync_s1        <= matrix_hsync;

        post_frame_vsync <= vsync_s1;
        post_frame_href  <= href_s1;
        post_frame_hsync <= hsync_s1;
        post_img_gray    <= href_s1 ? rounded_gray[11:4] : 8'd0;
        post_img_red     <= href_s1 ? rounded_r[11:4]    : 8'd0;
        post_img_green   <= href_s1 ? rounded_g[11:4]    : 8'd0;
        post_img_blue    <= href_s1 ? rounded_b[11:4]    : 8'd0;
    end
end

endmodule
