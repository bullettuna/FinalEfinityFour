`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Direction-aware non-maximum suppression for the streaming Canny pipeline.
// The 24-bit RGB sideband, two-bit direction and 11-bit magnitude share one
// 37-bit window so the colour overlay cannot drift relative to the edge mask.
//////////////////////////////////////////////////////////////////////////////////

module canny_nms
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
    input       [10:0]  per_magnitude,
    input       [1:0]   per_direction,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [10:0]  post_magnitude,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire        matrix_vsync;
wire        matrix_href;
wire        matrix_hsync;
wire [36:0] p11, p12, p13;
wire [36:0] p21, p22, p23;
wire [36:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(37)
) u_nms_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue,
                         per_direction, per_magnitude}),
    .matrix_frame_vsync(matrix_vsync),
    .matrix_frame_href (matrix_href),
    .matrix_frame_hsync(matrix_hsync),
    .matrix_p11        (p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21        (p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31        (p31), .matrix_p32(p32), .matrix_p33(p33)
);

canny_nms_kernel_3x3 u_canny_nms_kernel (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (matrix_vsync),
    .in_frame_href   (matrix_href),
    .in_frame_hsync  (matrix_hsync),
    .m11(p11[10:0]), .m12(p12[10:0]), .m13(p13[10:0]),
    .m21(p21[10:0]), .m22(p22[10:0]), .m23(p23[10:0]),
    .m31(p31[10:0]), .m32(p32[10:0]), .m33(p33[10:0]),
    .center_direction(p22[12:11]),
    .center_rgb      (p22[36:13]),
    .out_frame_vsync(post_frame_vsync),
    .out_frame_href (post_frame_href),
    .out_frame_hsync(post_frame_hsync),
    .out_magnitude  (post_magnitude),
    .out_rgb        ({post_img_red, post_img_green, post_img_blue})
);

endmodule


module canny_nms_kernel_3x3
(
    input               clk,
    input               rst_n,
    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [10:0]  m11, m12, m13,
    input       [10:0]  m21, m22, m23,
    input       [10:0]  m31, m32, m33,
    input       [1:0]   center_direction,
    input       [23:0]  center_rgb,
    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [10:0]  out_magnitude,
    output reg  [23:0]  out_rgb
);

reg [10:0] neighbour_a;
reg [10:0] neighbour_b;

always @(*) begin
    case (center_direction)
        2'b00: begin neighbour_a = m21; neighbour_b = m23; end
        2'b01: begin neighbour_a = m13; neighbour_b = m31; end
        2'b10: begin neighbour_a = m12; neighbour_b = m32; end
        default: begin neighbour_a = m11; neighbour_b = m33; end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_frame_vsync <= 1'b0;
        out_frame_href  <= 1'b0;
        out_frame_hsync <= 1'b0;
        out_magnitude   <= 11'd0;
        out_rgb         <= 24'd0;
    end else begin
        out_frame_vsync <= in_frame_vsync;
        out_frame_href  <= in_frame_href;
        out_frame_hsync <= in_frame_hsync;
        out_rgb         <= in_frame_href ? center_rgb : 24'd0;

        if (in_frame_href && (m22 != 11'd0) &&
            (m22 >= neighbour_a) && (m22 >= neighbour_b))
            out_magnitude <= m22;
        else
            out_magnitude <= 11'd0;
    end
end

// Kept in the complete kernel interface for self-checking testbenches.
wire unused_m = &{1'b0, m22};

endmodule
