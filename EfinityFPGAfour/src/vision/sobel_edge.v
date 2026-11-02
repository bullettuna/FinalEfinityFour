`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming Sobel edge detector for one 8-bit grayscale pixel per clock.
//
// Architecture follows the conventional FPGA video pipeline used by the Efinix
// EVSoC reference accelerator and the reviewed elinx-fpga-vision design:
//   two-line 3x3 window -> signed Gx/Gy -> |Gx|+|Gy| -> threshold.
// The project-native matrix generator is reused so no foreign vendor RAM IP is
// introduced.  All arithmetic stages carry VS/HS/HREF beside their pixel data.
//////////////////////////////////////////////////////////////////////////////////

module sobel_edge
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
    input       [10:0]  edge_threshold,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_edge
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
) u_gray_matrix_3x3 (
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

sobel_kernel_3x3 u_sobel_kernel_3x3 (
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
    .edge_threshold  (edge_threshold),
    .out_frame_vsync (post_frame_vsync),
    .out_frame_href  (post_frame_href),
    .out_frame_hsync (post_frame_hsync),
    .out_img_edge    (post_img_edge)
);

endmodule


//////////////////////////////////////////////////////////////////////////////////
// Pipelined 3x3 Sobel kernel.
//
// Gx = (p13 + 2*p23 + p33) - (p11 + 2*p21 + p31)
// Gy = (p11 + 2*p12 + p13) - (p31 + 2*p32 + p33)
// magnitude ~= |Gx| + |Gy|, range 0..2040 (11 unsigned bits).
//////////////////////////////////////////////////////////////////////////////////

module sobel_kernel_3x3
(
    input               clk,
    input               rst_n,

    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [7:0]   p11, p12, p13,
    input       [7:0]   p21, p22, p23,
    input       [7:0]   p31, p32, p33,
    input       [10:0]  edge_threshold,

    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [7:0]   out_img_edge
);

// Stage 1: signed horizontal and vertical gradients.  Every pixel term is
// explicitly widened before shifting, avoiding the Verilog expression-width
// truncation that occurs when an 8-bit value is shifted left directly.
reg signed [10:0] gx_s1;
reg signed [10:0] gy_s1;
reg        [10:0] threshold_s1;
reg               vsync_s1;
reg               href_s1;
reg               hsync_s1;

// Stage 2: absolute-value magnitude approximation.  The exact Sobel maximum is
// 2040, so an unsigned 11-bit register preserves the complete result.
wire [10:0] gx_abs = gx_s1[10] ? (~gx_s1 + 11'd1) : gx_s1;
wire [10:0] gy_abs = gy_s1[10] ? (~gy_s1 + 11'd1) : gy_s1;
reg  [10:0] magnitude_s2;
reg  [10:0] threshold_s2;
reg         vsync_s2;
reg         href_s2;
reg         hsync_s2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gx_s1          <= 11'sd0;
        gy_s1          <= 11'sd0;
        threshold_s1   <= 11'd0;
        vsync_s1       <= 1'b0;
        href_s1        <= 1'b0;
        hsync_s1       <= 1'b0;
        magnitude_s2   <= 11'd0;
        threshold_s2   <= 11'd0;
        vsync_s2       <= 1'b0;
        href_s2        <= 1'b0;
        hsync_s2       <= 1'b0;
        out_frame_vsync <= 1'b0;
        out_frame_href  <= 1'b0;
        out_frame_hsync <= 1'b0;
        out_img_edge    <= 8'd0;
    end else begin
        gx_s1 <= ($signed({3'b000, p13}) +
                  ($signed({3'b000, p23}) <<< 1) +
                  $signed({3'b000, p33})) -
                 ($signed({3'b000, p11}) +
                  ($signed({3'b000, p21}) <<< 1) +
                  $signed({3'b000, p31}));

        gy_s1 <= ($signed({3'b000, p11}) +
                  ($signed({3'b000, p12}) <<< 1) +
                  $signed({3'b000, p13})) -
                 ($signed({3'b000, p31}) +
                 ($signed({3'b000, p32}) <<< 1) +
                  $signed({3'b000, p33}));

        threshold_s1 <= edge_threshold;

        vsync_s1 <= in_frame_vsync;
        href_s1  <= in_frame_href;
        hsync_s1 <= in_frame_hsync;

        magnitude_s2 <= gx_abs + gy_abs;
        threshold_s2 <= threshold_s1;
        vsync_s2     <= vsync_s1;
        href_s2      <= href_s1;
        hsync_s2     <= hsync_s1;

        out_frame_vsync <= vsync_s2;
        out_frame_href  <= href_s2;
        out_frame_hsync <= hsync_s2;
        if (!href_s2)
            out_img_edge <= 8'd0;
        else if (magnitude_s2 > threshold_s2)
            out_img_edge <= 8'hFF;
        else
            out_img_edge <= 8'h00;
    end
end

// p22 is the center sample and is intentionally not part of either Sobel
// derivative.  It remains in the interface to keep the complete 3x3 window.
wire unused_p22 = &{1'b0, p22};

endmodule
