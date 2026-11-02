`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// RGB color-edge detector and overlay for one RGB888 pixel per clock.
//
// A single 24-bit 3x3 window guarantees that the R/G/B samples always describe
// the same pixel coordinates.  The three channels are evaluated independently
// by the project-native Sobel kernel and ORed into one edge mask.
//
// Edge rendering policy, migrated from the supplied color implementation:
//   1. a window containing a near-black sample -> white edge;
//   2. a strong RGB range across the window    -> yellow edge;
//   3. otherwise                              -> complement of center RGB.
// Non-edge pixels retain the aligned original color image.
//
// The range calculation is deliberately pipelined as a balanced row tree.  It
// avoids the long eight-comparator priority chain in the supplied version and
// leaves only a compare/mux between the final pipeline registers.
//////////////////////////////////////////////////////////////////////////////////

module rgb_color_edge_overlay
#(
    parameter [13:0] IMG_HDISP  = 14'd1920,
    parameter [13:0] IMG_VDISP  = 14'd1080,
    parameter [9:0]  STRONG_DIFF = 10'd300,
    parameter [7:0]  BLACK_TH     = 8'd20
)
(
    input               clk,
    input               rst_n,
    input               overlay_enable,

    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    input       [10:0]  edge_threshold,

    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

function [7:0] min3;
    input [7:0] a;
    input [7:0] b;
    input [7:0] c;
    reg   [7:0] ab;
    begin
        ab = (a < b) ? a : b;
        min3 = (ab < c) ? ab : c;
    end
endfunction

function [7:0] max3;
    input [7:0] a;
    input [7:0] b;
    input [7:0] c;
    reg   [7:0] ab;
    begin
        ab = (a > b) ? a : b;
        max3 = (ab > c) ? ab : c;
    end
endfunction

wire        matrix_vsync;
wire        matrix_href;
wire        matrix_hsync;
wire [23:0] p11, p12, p13;
wire [23:0] p21, p22, p23;
wire [23:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(24)
) u_rgb_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (p11),
    .matrix_p12        (p12),
    .matrix_p13        (p13),
    .matrix_p21        (p21),
    .matrix_p22        (p22),
    .matrix_p23        (p23),
    .matrix_p31        (p31),
    .matrix_p32        (p32),
    .matrix_p33        (p33)
);

wire [7:0] r11 = p11[23:16];
wire [7:0] r12 = p12[23:16];
wire [7:0] r13 = p13[23:16];
wire [7:0] r21 = p21[23:16];
wire [7:0] r22 = p22[23:16];
wire [7:0] r23 = p23[23:16];
wire [7:0] r31 = p31[23:16];
wire [7:0] r32 = p32[23:16];
wire [7:0] r33 = p33[23:16];

wire [7:0] g11 = p11[15:8];
wire [7:0] g12 = p12[15:8];
wire [7:0] g13 = p13[15:8];
wire [7:0] g21 = p21[15:8];
wire [7:0] g22 = p22[15:8];
wire [7:0] g23 = p23[15:8];
wire [7:0] g31 = p31[15:8];
wire [7:0] g32 = p32[15:8];
wire [7:0] g33 = p33[15:8];

wire [7:0] b11 = p11[7:0];
wire [7:0] b12 = p12[7:0];
wire [7:0] b13 = p13[7:0];
wire [7:0] b21 = p21[7:0];
wire [7:0] b22 = p22[7:0];
wire [7:0] b23 = p23[7:0];
wire [7:0] b31 = p31[7:0];
wire [7:0] b32 = p32[7:0];
wire [7:0] b33 = p33[7:0];

wire       edge_r_vsync;
wire       edge_r_href;
wire       edge_r_hsync;
wire [7:0] edge_r;
wire [7:0] edge_g;
wire [7:0] edge_b;

sobel_kernel_3x3 u_red_sobel (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(matrix_vsync), .in_frame_href(matrix_href),
    .in_frame_hsync(matrix_hsync),
    .p11(r11), .p12(r12), .p13(r13),
    .p21(r21), .p22(r22), .p23(r23),
    .p31(r31), .p32(r32), .p33(r33),
    .edge_threshold(edge_threshold),
    .out_frame_vsync(edge_r_vsync), .out_frame_href(edge_r_href),
    .out_frame_hsync(edge_r_hsync), .out_img_edge(edge_r)
);

sobel_kernel_3x3 u_green_sobel (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(matrix_vsync), .in_frame_href(matrix_href),
    .in_frame_hsync(matrix_hsync),
    .p11(g11), .p12(g12), .p13(g13),
    .p21(g21), .p22(g22), .p23(g23),
    .p31(g31), .p32(g32), .p33(g33),
    .edge_threshold(edge_threshold),
    .out_frame_vsync(), .out_frame_href(), .out_frame_hsync(),
    .out_img_edge(edge_g)
);

sobel_kernel_3x3 u_blue_sobel (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(matrix_vsync), .in_frame_href(matrix_href),
    .in_frame_hsync(matrix_hsync),
    .p11(b11), .p12(b12), .p13(b13),
    .p21(b21), .p22(b22), .p23(b23),
    .p31(b31), .p32(b32), .p33(b33),
    .edge_threshold(edge_threshold),
    .out_frame_vsync(), .out_frame_href(), .out_frame_hsync(),
    .out_img_edge(edge_b)
);

wire p11_black = (r11 < BLACK_TH) && (g11 < BLACK_TH) && (b11 < BLACK_TH);
wire p12_black = (r12 < BLACK_TH) && (g12 < BLACK_TH) && (b12 < BLACK_TH);
wire p13_black = (r13 < BLACK_TH) && (g13 < BLACK_TH) && (b13 < BLACK_TH);
wire p21_black = (r21 < BLACK_TH) && (g21 < BLACK_TH) && (b21 < BLACK_TH);
wire p22_black = (r22 < BLACK_TH) && (g22 < BLACK_TH) && (b22 < BLACK_TH);
wire p23_black = (r23 < BLACK_TH) && (g23 < BLACK_TH) && (b23 < BLACK_TH);
wire p31_black = (r31 < BLACK_TH) && (g31 < BLACK_TH) && (b31 < BLACK_TH);
wire p32_black = (r32 < BLACK_TH) && (g32 < BLACK_TH) && (b32 < BLACK_TH);
wire p33_black = (r33 < BLACK_TH) && (g33 < BLACK_TH) && (b33 < BLACK_TH);

// Stage 1: three balanced row reductions per channel.
reg [7:0] r_min_row1_s1, r_min_row2_s1, r_min_row3_s1;
reg [7:0] r_max_row1_s1, r_max_row2_s1, r_max_row3_s1;
reg [7:0] g_min_row1_s1, g_min_row2_s1, g_min_row3_s1;
reg [7:0] g_max_row1_s1, g_max_row2_s1, g_max_row3_s1;
reg [7:0] b_min_row1_s1, b_min_row2_s1, b_min_row3_s1;
reg [7:0] b_max_row1_s1, b_max_row2_s1, b_max_row3_s1;
reg [2:0] black_rows_s1;
reg [23:0] center_rgb_s1;
reg        overlay_enable_s1;

// Stage 2: reduce the three row results to the full-window range.
reg [7:0] r_min_s2, r_max_s2;
reg [7:0] g_min_s2, g_max_s2;
reg [7:0] b_min_s2, b_max_s2;
reg       black_s2;
reg [23:0] center_rgb_s2;
reg        overlay_enable_s2;

// Stage 3: calculate the three per-channel ranges.
reg [7:0] r_range_s3, g_range_s3, b_range_s3;
reg       black_s3;
reg [23:0] center_rgb_s3;
reg        overlay_enable_s3;

// Stage 4: add ranges and capture the aligned Sobel result and timing.
reg [9:0] spread_s4;
reg       black_s4;
reg       edge_s4;
reg       vsync_s4, href_s4, hsync_s4;
reg [23:0] center_rgb_s4;
reg        overlay_enable_s4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_min_row1_s1 <= 8'd0; r_min_row2_s1 <= 8'd0; r_min_row3_s1 <= 8'd0;
        r_max_row1_s1 <= 8'd0; r_max_row2_s1 <= 8'd0; r_max_row3_s1 <= 8'd0;
        g_min_row1_s1 <= 8'd0; g_min_row2_s1 <= 8'd0; g_min_row3_s1 <= 8'd0;
        g_max_row1_s1 <= 8'd0; g_max_row2_s1 <= 8'd0; g_max_row3_s1 <= 8'd0;
        b_min_row1_s1 <= 8'd0; b_min_row2_s1 <= 8'd0; b_min_row3_s1 <= 8'd0;
        b_max_row1_s1 <= 8'd0; b_max_row2_s1 <= 8'd0; b_max_row3_s1 <= 8'd0;
        black_rows_s1 <= 3'b000;
        center_rgb_s1 <= 24'd0;
        overlay_enable_s1 <= 1'b0;

        r_min_s2 <= 8'd0; r_max_s2 <= 8'd0;
        g_min_s2 <= 8'd0; g_max_s2 <= 8'd0;
        b_min_s2 <= 8'd0; b_max_s2 <= 8'd0;
        black_s2 <= 1'b0;
        center_rgb_s2 <= 24'd0;
        overlay_enable_s2 <= 1'b0;

        r_range_s3 <= 8'd0; g_range_s3 <= 8'd0; b_range_s3 <= 8'd0;
        black_s3 <= 1'b0;
        center_rgb_s3 <= 24'd0;
        overlay_enable_s3 <= 1'b0;

        spread_s4 <= 10'd0;
        black_s4 <= 1'b0;
        edge_s4 <= 1'b0;
        vsync_s4 <= 1'b0; href_s4 <= 1'b0; hsync_s4 <= 1'b0;
        center_rgb_s4 <= 24'd0;
        overlay_enable_s4 <= 1'b0;

        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_img_red     <= 8'd0;
        post_img_green   <= 8'd0;
        post_img_blue    <= 8'd0;
    end else begin
        r_min_row1_s1 <= min3(r11, r12, r13);
        r_min_row2_s1 <= min3(r21, r22, r23);
        r_min_row3_s1 <= min3(r31, r32, r33);
        r_max_row1_s1 <= max3(r11, r12, r13);
        r_max_row2_s1 <= max3(r21, r22, r23);
        r_max_row3_s1 <= max3(r31, r32, r33);
        g_min_row1_s1 <= min3(g11, g12, g13);
        g_min_row2_s1 <= min3(g21, g22, g23);
        g_min_row3_s1 <= min3(g31, g32, g33);
        g_max_row1_s1 <= max3(g11, g12, g13);
        g_max_row2_s1 <= max3(g21, g22, g23);
        g_max_row3_s1 <= max3(g31, g32, g33);
        b_min_row1_s1 <= min3(b11, b12, b13);
        b_min_row2_s1 <= min3(b21, b22, b23);
        b_min_row3_s1 <= min3(b31, b32, b33);
        b_max_row1_s1 <= max3(b11, b12, b13);
        b_max_row2_s1 <= max3(b21, b22, b23);
        b_max_row3_s1 <= max3(b31, b32, b33);
        black_rows_s1 <= {
            p31_black | p32_black | p33_black,
            p21_black | p22_black | p23_black,
            p11_black | p12_black | p13_black
        };
        center_rgb_s1 <= p22;
        overlay_enable_s1 <= overlay_enable;

        r_min_s2 <= min3(r_min_row1_s1, r_min_row2_s1, r_min_row3_s1);
        r_max_s2 <= max3(r_max_row1_s1, r_max_row2_s1, r_max_row3_s1);
        g_min_s2 <= min3(g_min_row1_s1, g_min_row2_s1, g_min_row3_s1);
        g_max_s2 <= max3(g_max_row1_s1, g_max_row2_s1, g_max_row3_s1);
        b_min_s2 <= min3(b_min_row1_s1, b_min_row2_s1, b_min_row3_s1);
        b_max_s2 <= max3(b_max_row1_s1, b_max_row2_s1, b_max_row3_s1);
        black_s2 <= |black_rows_s1;
        center_rgb_s2 <= center_rgb_s1;
        overlay_enable_s2 <= overlay_enable_s1;

        r_range_s3 <= r_max_s2 - r_min_s2;
        g_range_s3 <= g_max_s2 - g_min_s2;
        b_range_s3 <= b_max_s2 - b_min_s2;
        black_s3 <= black_s2;
        center_rgb_s3 <= center_rgb_s2;
        overlay_enable_s3 <= overlay_enable_s2;

        spread_s4 <= {2'b00, r_range_s3} +
                     {2'b00, g_range_s3} +
                     {2'b00, b_range_s3};
        black_s4 <= black_s3;
        edge_s4 <= (edge_r != 8'd0) || (edge_g != 8'd0) || (edge_b != 8'd0);
        vsync_s4 <= edge_r_vsync;
        href_s4  <= edge_r_href;
        hsync_s4 <= edge_r_hsync;
        center_rgb_s4 <= center_rgb_s3;
        overlay_enable_s4 <= overlay_enable_s3;

        post_frame_vsync <= vsync_s4;
        post_frame_href  <= href_s4;
        post_frame_hsync <= hsync_s4;
        if (!href_s4) begin
            {post_img_red, post_img_green, post_img_blue} <= 24'd0;
        end else if (overlay_enable_s4 && edge_s4) begin
            if (black_s4)
                {post_img_red, post_img_green, post_img_blue} <= 24'hFFFFFF;
            else if (spread_s4 > STRONG_DIFF)
                {post_img_red, post_img_green, post_img_blue} <= 24'hFFFF00;
            else
                {post_img_red, post_img_green, post_img_blue} <=
                    24'hFFFFFF - center_rgb_s4;
        end else begin
            {post_img_red, post_img_green, post_img_blue} <= center_rgb_s4;
        end
    end
end

endmodule
