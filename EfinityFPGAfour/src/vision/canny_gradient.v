`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Canny gradient stage — colour-aware.
//
// Sobel derivatives are evaluated independently on R, G and B, allowing the
// Canny path to detect hue-only boundaries. The strongest channel determines
// magnitude and direction. Three pipeline stages preserve 148.5 MHz timing.
//////////////////////////////////////////////////////////////////////////////////

module canny_gradient
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
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [10:0]  post_magnitude,
    output      [1:0]   post_direction,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
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
) u_gradient_matrix_3x3 (
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

canny_gradient_kernel_3x3 u_canny_gradient_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_vsync),
    .in_frame_href   (matrix_href),
    .in_frame_hsync  (matrix_hsync),
    .p11             (p11), .p12(p12), .p13(p13),
    .p21             (p21), .p22(p22), .p23(p23),
    .p31             (p31), .p32(p32), .p33(p33),
    .out_frame_vsync(post_frame_vsync),
    .out_frame_href (post_frame_href),
    .out_frame_hsync(post_frame_hsync),
    .out_magnitude  (post_magnitude),
    .out_direction  (post_direction),
    .out_rgb        ({post_img_red, post_img_green, post_img_blue})
);

endmodule

module canny_gradient_kernel_3x3
(
    input               clk,
    input               rst_n,
    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [31:0]  p11, p12, p13,
    input       [31:0]  p21, p22, p23,
    input       [31:0]  p31, p32, p33,
    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [10:0]  out_magnitude,
    output reg  [1:0]   out_direction,
    output reg  [23:0]  out_rgb
);

localparam [1:0] DIR_HORIZONTAL = 2'b00;
localparam [1:0] DIR_DIAG_RISE  = 2'b01;
localparam [1:0] DIR_VERTICAL   = 2'b10;
localparam [1:0] DIR_DIAG_FALL  = 2'b11;

wire [7:0] r11 = p11[31:24], r12 = p12[31:24], r13 = p13[31:24];
wire [7:0] r21 = p21[31:24], r22 = p22[31:24], r23 = p23[31:24];
wire [7:0] r31 = p31[31:24], r32 = p32[31:24], r33 = p33[31:24];
wire [7:0] g11 = p11[23:16], g12 = p12[23:16], g13 = p13[23:16];
wire [7:0] g21 = p21[23:16], g22 = p22[23:16], g23 = p23[23:16];
wire [7:0] g31 = p31[23:16], g32 = p32[23:16], g33 = p33[23:16];
wire [7:0] b11 = p11[15:8],  b12 = p12[15:8],  b13 = p13[15:8];
wire [7:0] b21 = p21[15:8],  b22 = p22[15:8],  b23 = p23[15:8];
wire [7:0] b31 = p31[15:8],  b32 = p32[15:8],  b33 = p33[15:8];

function signed [10:0] sobel_x;
    input [7:0] a11, a12, a13, a21, a22, a23, a31, a32, a33;
    begin
        sobel_x = ($signed({3'b000, a13}) + ($signed({3'b000, a23}) <<< 1) + $signed({3'b000, a33})) -
                  ($signed({3'b000, a11}) + ($signed({3'b000, a21}) <<< 1) + $signed({3'b000, a31}));
    end
endfunction

function signed [10:0] sobel_y;
    input [7:0] a11, a12, a13, a21, a22, a23, a31, a32, a33;
    begin
        sobel_y = ($signed({3'b000, a11}) + ($signed({3'b000, a12}) <<< 1) + $signed({3'b000, a13})) -
                  ($signed({3'b000, a31}) + ($signed({3'b000, a32}) <<< 1) + $signed({3'b000, a33}));
    end
endfunction

function [10:0] abs11;
    input signed [10:0] value;
    reg   [10:0] bits;
    begin
        bits = value;
        abs11 = bits[10] ? (~bits + 11'd1) : bits;
    end
endfunction

reg signed [10:0] gx_r, gy_r, gx_g, gy_g, gx_b, gy_b;
reg        [23:0] rgb_s1;
reg               vsync_s1, href_s1, hsync_s1;

wire [10:0] gx_r_abs = abs11(gx_r);
wire [10:0] gy_r_abs = abs11(gy_r);
wire [10:0] gx_g_abs = abs11(gx_g);
wire [10:0] gy_g_abs = abs11(gy_g);
wire [10:0] gx_b_abs = abs11(gx_b);
wire [10:0] gy_b_abs = abs11(gy_b);
wire [10:0] mag_r = gx_r_abs + gy_r_abs;
wire [10:0] mag_g = gx_g_abs + gy_g_abs;
wire [10:0] mag_b = gx_b_abs + gy_b_abs;

wire        r_dom = (mag_r >= mag_g) && (mag_r >= mag_b);
wire        g_dom = (mag_g >= mag_r) && (mag_g >= mag_b);
wire signed [10:0] dom_gx = r_dom ? gx_r : (g_dom ? gx_g : gx_b);
wire signed [10:0] dom_gy = r_dom ? gy_r : (g_dom ? gy_g : gy_b);

reg [10:0]        mag_r_s2, mag_g_s2, mag_b_s2;
reg signed [10:0] dom_gx_s2, dom_gy_s2;
reg [23:0]        rgb_s2;
reg               vsync_s2, href_s2, hsync_s2;

wire [10:0] max_rg = (mag_r_s2 >= mag_g_s2) ? mag_r_s2 : mag_g_s2;
wire [10:0] max_rgb = (max_rg >= mag_b_s2) ? max_rg : mag_b_s2;
wire [10:0] dom_gx_abs = abs11(dom_gx_s2);
wire [10:0] dom_gy_abs = abs11(dom_gy_s2);
wire [18:0] dom_gx_scaled_256 = {dom_gx_abs, 8'b0};
wire [18:0] dom_gy_scaled_256 = {dom_gy_abs, 8'b0};
wire [18:0] dom_gx_scaled_106 = ({8'd0, dom_gx_abs} << 6) + ({8'd0, dom_gx_abs} << 5) +
                                ({8'd0, dom_gx_abs} << 3) + ({8'd0, dom_gx_abs} << 1);
wire [18:0] dom_gy_scaled_106 = ({8'd0, dom_gy_abs} << 6) + ({8'd0, dom_gy_abs} << 5) +
                                ({8'd0, dom_gy_abs} << 3) + ({8'd0, dom_gy_abs} << 1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gx_r <= 11'sd0; gy_r <= 11'sd0; gx_g <= 11'sd0;
        gy_g <= 11'sd0; gx_b <= 11'sd0; gy_b <= 11'sd0;
        rgb_s1 <= 24'd0; vsync_s1 <= 1'b0; href_s1 <= 1'b0; hsync_s1 <= 1'b0;
        mag_r_s2 <= 11'd0; mag_g_s2 <= 11'd0; mag_b_s2 <= 11'd0;
        dom_gx_s2 <= 11'sd0; dom_gy_s2 <= 11'sd0;
        rgb_s2 <= 24'd0; vsync_s2 <= 1'b0; href_s2 <= 1'b0; hsync_s2 <= 1'b0;
        out_frame_vsync <= 1'b0; out_frame_href <= 1'b0; out_frame_hsync <= 1'b0;
        out_magnitude <= 11'd0; out_direction <= DIR_HORIZONTAL; out_rgb <= 24'd0;
    end else begin
        gx_r <= sobel_x(r11, r12, r13, r21, r22, r23, r31, r32, r33);
        gy_r <= sobel_y(r11, r12, r13, r21, r22, r23, r31, r32, r33);
        gx_g <= sobel_x(g11, g12, g13, g21, g22, g23, g31, g32, g33);
        gy_g <= sobel_y(g11, g12, g13, g21, g22, g23, g31, g32, g33);
        gx_b <= sobel_x(b11, b12, b13, b21, b22, b23, b31, b32, b33);
        gy_b <= sobel_y(b11, b12, b13, b21, b22, b23, b31, b32, b33);
        rgb_s1 <= p22[31:8];
        vsync_s1 <= in_frame_vsync; href_s1 <= in_frame_href; hsync_s1 <= in_frame_hsync;

        mag_r_s2 <= mag_r; mag_g_s2 <= mag_g; mag_b_s2 <= mag_b;
        dom_gx_s2 <= dom_gx; dom_gy_s2 <= dom_gy;
        rgb_s2 <= rgb_s1;
        vsync_s2 <= vsync_s1; href_s2 <= href_s1; hsync_s2 <= hsync_s1;

        out_frame_vsync <= vsync_s2;
        out_frame_href  <= href_s2;
        out_frame_hsync <= hsync_s2;
        out_rgb         <= href_s2 ? rgb_s2 : 24'd0;
        out_magnitude   <= href_s2 ? max_rgb : 11'd0;
        if (dom_gy_scaled_256 <= dom_gx_scaled_106)
            out_direction <= DIR_HORIZONTAL;
        else if (dom_gx_scaled_256 <= dom_gy_scaled_106)
            out_direction <= DIR_VERTICAL;
        else if (dom_gx_s2[10] == dom_gy_s2[10])
            out_direction <= DIR_DIAG_RISE;
        else
            out_direction <= DIR_DIAG_FALL;
    end
end

endmodule
