`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Apply the project's RGB-Sobel colour policy to an externally supplied,
// pixel-aligned binary edge mask.  The policy is identical to
// rgb_color_edge_overlay:
//   1. a 3x3 window containing a near-black sample -> white edge;
//   2. a strong summed RGB range across the window -> yellow edge;
//   3. otherwise -> complement of the centre RGB pixel.
//////////////////////////////////////////////////////////////////////////////////

module rgb_edge_colorizer
#(
    parameter [13:0] IMG_HDISP   = 14'd1920,
    parameter [13:0] IMG_VDISP   = 14'd1080,
    parameter [9:0]  STRONG_DIFF = 10'd300,
    parameter [7:0]  BLACK_TH    = 8'd20,
    parameter [13:0] TOP_EDGE_GUARD = 14'd0
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
    input       [7:0]   per_img_edge,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
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

// The camera's first two Bayer rows are neutral fallback pixels. Their
// transition to demosaiced colour propagates through the four Canny windows
// and can become a false horizontal edge, then a red complementary-colour
// band in O mode. Suppress only startup edge tags before the colour window;
// keep every background pixel and all RGB/DE/HS/VS pipeline timing unchanged.
reg [13:0] input_row;
reg input_href_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_row <= 14'd0;
        input_href_d <= 1'b0;
    end else begin
        input_href_d <= per_frame_href;
        if (!per_frame_vsync)
            input_row <= 14'd0;
        else if (input_href_d && !per_frame_href)
            input_row <= input_row < IMG_VDISP-1'b1 ? input_row+1'b1 : 14'd0;
    end
end
wire [7:0] qualified_edge = input_row < TOP_EDGE_GUARD ? 8'd0 : per_img_edge;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(32)
) u_edge_colour_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue,
                         qualified_edge}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21        (p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31        (p31), .matrix_p32(p32), .matrix_p33(p33)
);

rgb_edge_colorizer_kernel_3x3 #(
    .STRONG_DIFF(STRONG_DIFF),
    .BLACK_TH   (BLACK_TH)
) u_rgb_edge_colorizer_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .overlay_enable  (overlay_enable),
    .in_frame_vsync  (matrix_vsync),
    .in_frame_href   (matrix_href),
    .in_frame_hsync  (matrix_hsync),
    .p11(p11[31:8]), .p12(p12[31:8]), .p13(p13[31:8]),
    .p21(p21[31:8]), .p22(p22[31:8]), .p23(p23[31:8]),
    .p31(p31[31:8]), .p32(p32[31:8]), .p33(p33[31:8]),
    .center_edge     (p22[7:0] != 8'd0),
    .out_frame_vsync(post_frame_vsync),
    .out_frame_href (post_frame_href),
    .out_frame_hsync(post_frame_hsync),
    .out_rgb        ({post_img_red, post_img_green, post_img_blue})
);

endmodule


module rgb_edge_colorizer_kernel_3x3
#(
    parameter [9:0] STRONG_DIFF = 10'd300,
    parameter [7:0] BLACK_TH    = 8'd20
)
(
    input               clk,
    input               rst_n,
    input               overlay_enable,
    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [23:0]  p11, p12, p13,
    input       [23:0]  p21, p22, p23,
    input       [23:0]  p31, p32, p33,
    input               center_edge,
    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [23:0]  out_rgb
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

wire p11_black = (p11[23:16] < BLACK_TH) &&
                 (p11[15:8] < BLACK_TH) && (p11[7:0] < BLACK_TH);
wire p12_black = (p12[23:16] < BLACK_TH) &&
                 (p12[15:8] < BLACK_TH) && (p12[7:0] < BLACK_TH);
wire p13_black = (p13[23:16] < BLACK_TH) &&
                 (p13[15:8] < BLACK_TH) && (p13[7:0] < BLACK_TH);
wire p21_black = (p21[23:16] < BLACK_TH) &&
                 (p21[15:8] < BLACK_TH) && (p21[7:0] < BLACK_TH);
wire p22_black = (p22[23:16] < BLACK_TH) &&
                 (p22[15:8] < BLACK_TH) && (p22[7:0] < BLACK_TH);
wire p23_black = (p23[23:16] < BLACK_TH) &&
                 (p23[15:8] < BLACK_TH) && (p23[7:0] < BLACK_TH);
wire p31_black = (p31[23:16] < BLACK_TH) &&
                 (p31[15:8] < BLACK_TH) && (p31[7:0] < BLACK_TH);
wire p32_black = (p32[23:16] < BLACK_TH) &&
                 (p32[15:8] < BLACK_TH) && (p32[7:0] < BLACK_TH);
wire p33_black = (p33[23:16] < BLACK_TH) &&
                 (p33[15:8] < BLACK_TH) && (p33[7:0] < BLACK_TH);

reg [7:0] r_min_row1_s1, r_min_row2_s1, r_min_row3_s1;
reg [7:0] r_max_row1_s1, r_max_row2_s1, r_max_row3_s1;
reg [7:0] g_min_row1_s1, g_min_row2_s1, g_min_row3_s1;
reg [7:0] g_max_row1_s1, g_max_row2_s1, g_max_row3_s1;
reg [7:0] b_min_row1_s1, b_min_row2_s1, b_min_row3_s1;
reg [7:0] b_max_row1_s1, b_max_row2_s1, b_max_row3_s1;
reg [2:0] black_rows_s1;
reg [23:0] center_rgb_s1;
reg edge_s1, overlay_s1, vsync_s1, href_s1, hsync_s1;

reg [7:0] r_min_s2, r_max_s2, g_min_s2, g_max_s2, b_min_s2, b_max_s2;
reg black_s2;
reg [23:0] center_rgb_s2;
reg edge_s2, overlay_s2, vsync_s2, href_s2, hsync_s2;

reg [7:0] r_range_s3, g_range_s3, b_range_s3;
reg black_s3;
reg [23:0] center_rgb_s3;
reg edge_s3, overlay_s3, vsync_s3, href_s3, hsync_s3;

reg [9:0] spread_s4;
reg black_s4;
reg [23:0] center_rgb_s4;
reg edge_s4, overlay_s4, vsync_s4, href_s4, hsync_s4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_min_row1_s1 <= 0; r_min_row2_s1 <= 0; r_min_row3_s1 <= 0;
        r_max_row1_s1 <= 0; r_max_row2_s1 <= 0; r_max_row3_s1 <= 0;
        g_min_row1_s1 <= 0; g_min_row2_s1 <= 0; g_min_row3_s1 <= 0;
        g_max_row1_s1 <= 0; g_max_row2_s1 <= 0; g_max_row3_s1 <= 0;
        b_min_row1_s1 <= 0; b_min_row2_s1 <= 0; b_min_row3_s1 <= 0;
        b_max_row1_s1 <= 0; b_max_row2_s1 <= 0; b_max_row3_s1 <= 0;
        black_rows_s1 <= 0; center_rgb_s1 <= 0;
        edge_s1 <= 0; overlay_s1 <= 0; vsync_s1 <= 0; href_s1 <= 0; hsync_s1 <= 0;

        r_min_s2 <= 0; r_max_s2 <= 0; g_min_s2 <= 0; g_max_s2 <= 0;
        b_min_s2 <= 0; b_max_s2 <= 0; black_s2 <= 0; center_rgb_s2 <= 0;
        edge_s2 <= 0; overlay_s2 <= 0; vsync_s2 <= 0; href_s2 <= 0; hsync_s2 <= 0;

        r_range_s3 <= 0; g_range_s3 <= 0; b_range_s3 <= 0;
        black_s3 <= 0; center_rgb_s3 <= 0;
        edge_s3 <= 0; overlay_s3 <= 0; vsync_s3 <= 0; href_s3 <= 0; hsync_s3 <= 0;

        spread_s4 <= 0; black_s4 <= 0; center_rgb_s4 <= 0;
        edge_s4 <= 0; overlay_s4 <= 0; vsync_s4 <= 0; href_s4 <= 0; hsync_s4 <= 0;

        out_frame_vsync <= 0; out_frame_href <= 0; out_frame_hsync <= 0;
        out_rgb <= 24'd0;
    end else begin
        r_min_row1_s1 <= min3(p11[23:16], p12[23:16], p13[23:16]);
        r_min_row2_s1 <= min3(p21[23:16], p22[23:16], p23[23:16]);
        r_min_row3_s1 <= min3(p31[23:16], p32[23:16], p33[23:16]);
        r_max_row1_s1 <= max3(p11[23:16], p12[23:16], p13[23:16]);
        r_max_row2_s1 <= max3(p21[23:16], p22[23:16], p23[23:16]);
        r_max_row3_s1 <= max3(p31[23:16], p32[23:16], p33[23:16]);
        g_min_row1_s1 <= min3(p11[15:8], p12[15:8], p13[15:8]);
        g_min_row2_s1 <= min3(p21[15:8], p22[15:8], p23[15:8]);
        g_min_row3_s1 <= min3(p31[15:8], p32[15:8], p33[15:8]);
        g_max_row1_s1 <= max3(p11[15:8], p12[15:8], p13[15:8]);
        g_max_row2_s1 <= max3(p21[15:8], p22[15:8], p23[15:8]);
        g_max_row3_s1 <= max3(p31[15:8], p32[15:8], p33[15:8]);
        b_min_row1_s1 <= min3(p11[7:0], p12[7:0], p13[7:0]);
        b_min_row2_s1 <= min3(p21[7:0], p22[7:0], p23[7:0]);
        b_min_row3_s1 <= min3(p31[7:0], p32[7:0], p33[7:0]);
        b_max_row1_s1 <= max3(p11[7:0], p12[7:0], p13[7:0]);
        b_max_row2_s1 <= max3(p21[7:0], p22[7:0], p23[7:0]);
        b_max_row3_s1 <= max3(p31[7:0], p32[7:0], p33[7:0]);
        black_rows_s1 <= {
            p31_black | p32_black | p33_black,
            p21_black | p22_black | p23_black,
            p11_black | p12_black | p13_black
        };
        center_rgb_s1 <= p22;
        edge_s1 <= center_edge;
        overlay_s1 <= overlay_enable;
        vsync_s1 <= in_frame_vsync; href_s1 <= in_frame_href; hsync_s1 <= in_frame_hsync;

        r_min_s2 <= min3(r_min_row1_s1, r_min_row2_s1, r_min_row3_s1);
        r_max_s2 <= max3(r_max_row1_s1, r_max_row2_s1, r_max_row3_s1);
        g_min_s2 <= min3(g_min_row1_s1, g_min_row2_s1, g_min_row3_s1);
        g_max_s2 <= max3(g_max_row1_s1, g_max_row2_s1, g_max_row3_s1);
        b_min_s2 <= min3(b_min_row1_s1, b_min_row2_s1, b_min_row3_s1);
        b_max_s2 <= max3(b_max_row1_s1, b_max_row2_s1, b_max_row3_s1);
        black_s2 <= |black_rows_s1;
        center_rgb_s2 <= center_rgb_s1;
        edge_s2 <= edge_s1; overlay_s2 <= overlay_s1;
        vsync_s2 <= vsync_s1; href_s2 <= href_s1; hsync_s2 <= hsync_s1;

        r_range_s3 <= r_max_s2 - r_min_s2;
        g_range_s3 <= g_max_s2 - g_min_s2;
        b_range_s3 <= b_max_s2 - b_min_s2;
        black_s3 <= black_s2;
        center_rgb_s3 <= center_rgb_s2;
        edge_s3 <= edge_s2; overlay_s3 <= overlay_s2;
        vsync_s3 <= vsync_s2; href_s3 <= href_s2; hsync_s3 <= hsync_s2;

        spread_s4 <= {2'b00, r_range_s3} +
                     {2'b00, g_range_s3} + {2'b00, b_range_s3};
        black_s4 <= black_s3;
        center_rgb_s4 <= center_rgb_s3;
        edge_s4 <= edge_s3; overlay_s4 <= overlay_s3;
        vsync_s4 <= vsync_s3; href_s4 <= href_s3; hsync_s4 <= hsync_s3;

        out_frame_vsync <= vsync_s4;
        out_frame_href  <= href_s4;
        out_frame_hsync <= hsync_s4;
        if (!href_s4)
            out_rgb <= 24'd0;
        else if (overlay_s4 && edge_s4) begin
            if (black_s4)
                out_rgb <= 24'hFFFFFF;
            else if (spread_s4 > STRONG_DIFF)
                out_rgb <= 24'hFFFF00;
            else
                out_rgb <= 24'hFFFFFF - center_rgb_s4;
        end else
            out_rgb <= center_rgb_s4;
    end
end

endmodule
