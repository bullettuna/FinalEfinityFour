`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Delay an RGB888 stream by the same spatial and pipeline latency as one
// 3x3-window + three-stage image-processing block.
//
// This is used only to align the original color image with the median/Sobel
// edge path.  The shared window generator makes the spatial delay identical;
// selecting p22 lets synthesis remove unused 24-bit neighbours and the unused
// second historical row.
//////////////////////////////////////////////////////////////////////////////////

module rgb_window_delay
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080
)
(
    input               clk,
    input               rst_n,
    input               delay_enable,
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

wire        matrix_vsync;
wire        matrix_href;
wire        matrix_hsync;
wire [23:0] matrix_p11_unused, matrix_p12_unused, matrix_p13_unused;
wire [23:0] matrix_p21_unused, matrix_p22, matrix_p23_unused;
wire [23:0] matrix_p31_unused, matrix_p32_unused, matrix_p33_unused;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(24)
) u_rgb_delay_matrix (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (matrix_p11_unused),
    .matrix_p12        (matrix_p12_unused),
    .matrix_p13        (matrix_p13_unused),
    .matrix_p21        (matrix_p21_unused),
    .matrix_p22        (matrix_p22),
    .matrix_p23        (matrix_p23_unused),
    .matrix_p31        (matrix_p31_unused),
    .matrix_p32        (matrix_p32_unused),
    .matrix_p33        (matrix_p33_unused)
);

reg [2:0]  vsync_delay;
reg [2:0]  href_delay;
reg [2:0]  hsync_delay;
reg [23:0] rgb_delay_1;
reg [23:0] rgb_delay_2;
reg [23:0] rgb_delay_3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_delay <= 3'b000;
        href_delay  <= 3'b000;
        hsync_delay <= 3'b000;
        rgb_delay_1 <= 24'd0;
        rgb_delay_2 <= 24'd0;
        rgb_delay_3 <= 24'd0;
    end else begin
        vsync_delay <= {vsync_delay[1:0], matrix_vsync};
        href_delay  <= {href_delay[1:0],  matrix_href};
        hsync_delay <= {hsync_delay[1:0], matrix_hsync};
        rgb_delay_1 <= matrix_p22;
        rgb_delay_2 <= rgb_delay_1;
        rgb_delay_3 <= rgb_delay_2;
    end
end

wire [23:0] delayed_rgb = href_delay[2] ? rgb_delay_3 : 24'd0;

assign post_frame_vsync = delay_enable ? vsync_delay[2] : per_frame_vsync;
assign post_frame_href  = delay_enable ? href_delay[2]  : per_frame_href;
assign post_frame_hsync = delay_enable ? hsync_delay[2] : per_frame_hsync;
assign post_img_red     = delay_enable ? delayed_rgb[23:16] : per_img_red;
assign post_img_green   = delay_enable ? delayed_rgb[15:8]  : per_img_green;
assign post_img_blue    = delay_enable ? delayed_rgb[7:0]   : per_img_blue;

// Keep tool diagnostics quiet while allowing synthesis to remove neighbours.
wire unused_matrix_pixels = &{1'b0,
    matrix_p11_unused, matrix_p12_unused, matrix_p13_unused,
    matrix_p21_unused, matrix_p23_unused,
    matrix_p31_unused, matrix_p32_unused, matrix_p33_unused};

endmodule

