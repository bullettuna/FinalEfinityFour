`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming 3x3 binary morphology.
//
// This keeps the boolean dilation/erosion structure used by the Efinix EVSoC
// example, but uses this project's frame-aware line-window generator so it is
// vendor-IP independent and follows the existing 1080p video timing contract.
// Foreground convention: 1 means object. DILATE=1 selects OR; DILATE=0 selects
// AND. RGB and the unmodified display edge are carried through the center tap
// of the same window, so the background and thin edge stay pixel-aligned with
// the morphology result. One registered kernel stage follows the project-native
// 3x3 window.
//////////////////////////////////////////////////////////////////////////////////

module binary_morph3x3
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter        DILATE    = 1'b1,
    parameter        COMPUTE_DIRECTION = 1'b0
)
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input               per_img_mask,
    input               per_img_edge,
    input       [1:0]   per_img_direction,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg          post_img_mask,
    output reg          post_img_edge,
    output reg  [1:0]   post_img_direction,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

wire matrix_frame_vsync;
wire matrix_frame_href;
wire matrix_frame_hsync;
wire [27:0] p11, p12, p13;
wire [27:0] p21, p22, p23;
wire [27:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP (IMG_HDISP),
    .IMG_VDISP (IMG_VDISP),
    .DATA_WIDTH(28)
) u_binary_matrix_3x3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .per_frame_vsync   (per_frame_vsync),
    .per_frame_href    (per_frame_href),
    .per_frame_hsync   (per_frame_hsync),
    .per_img_Y         ({per_img_red, per_img_green, per_img_blue,
                         per_img_direction, per_img_edge, per_img_mask}),
    .matrix_frame_vsync(matrix_frame_vsync),
    .matrix_frame_href (matrix_frame_href),
    .matrix_frame_hsync(matrix_frame_hsync),
    .matrix_p11        (p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21        (p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31        (p31), .matrix_p32(p32), .matrix_p33(p33)
);

wire dilated_pixel = p11[0] | p12[0] | p13[0] |
                     p21[0] | p22[0] | p23[0] |
                     p31[0] | p32[0] | p33[0];
wire eroded_pixel  = p11[0] & p12[0] & p13[0] &
                     p21[0] & p22[0] & p23[0] &
                     p31[0] & p32[0] & p33[0];

// Local tangent direction of the original one-pixel edge. Rectangles have
// two dominant perpendicular bins even when rotated; circles distribute edge
// pixels across all four bins. Scores use only immediate connectivity, so no
// multiplier, divider or angle function is required.
wire [1:0] horizontal_score = {1'b0, p21[0]} + {1'b0, p23[0]};
wire [1:0] vertical_score   = {1'b0, p12[0]} + {1'b0, p32[0]};
wire [1:0] diagonal_a_score = {1'b0, p11[0]} + {1'b0, p33[0]};
wire [1:0] diagonal_b_score = {1'b0, p13[0]} + {1'b0, p31[0]};
wire [1:0] detected_direction =
    ((horizontal_score >= vertical_score) &&
     (horizontal_score >= diagonal_a_score) &&
     (horizontal_score >= diagonal_b_score)) ? 2'd0 :
    ((vertical_score >= diagonal_a_score) &&
     (vertical_score >= diagonal_b_score)) ? 2'd2 :
    (diagonal_a_score >= diagonal_b_score) ? 2'd1 : 2'd3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        post_frame_vsync <= 1'b0;
        post_frame_href  <= 1'b0;
        post_frame_hsync <= 1'b0;
        post_img_mask    <= 1'b0;
        post_img_edge    <= 1'b0;
        post_img_direction <= 2'd0;
        post_img_red     <= 8'd0;
        post_img_green   <= 8'd0;
        post_img_blue    <= 8'd0;
    end else begin
        post_frame_vsync <= matrix_frame_vsync;
        post_frame_href  <= matrix_frame_href;
        post_frame_hsync <= matrix_frame_hsync;
        post_img_mask    <= matrix_frame_href &&
                            (DILATE ? dilated_pixel : eroded_pixel);
        post_img_edge    <= matrix_frame_href && p22[1];
        post_img_direction <= matrix_frame_href ?
            (COMPUTE_DIRECTION ? detected_direction : p22[3:2]) : 2'd0;
        if (matrix_frame_href) begin
            post_img_red   <= p22[27:20];
            post_img_green <= p22[19:12];
            post_img_blue  <= p22[11:4];
        end else begin
            post_img_red   <= 8'd0;
            post_img_green <= 8'd0;
            post_img_blue  <= 8'd0;
        end
    end
end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// 3x3 closing removes one-pixel breaks and small white holes while preserving
// the approximate outer contour: foreground dilation followed by erosion.
//////////////////////////////////////////////////////////////////////////////////

module binary_close3x3
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
    input               per_img_mask,
    input               per_img_edge,
    input       [1:0]   per_img_direction,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output              post_img_mask,
    output              post_img_edge,
    output      [1:0]   post_img_direction,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

wire dilate_vsync;
wire dilate_href;
wire dilate_hsync;
wire dilate_mask;
wire dilate_edge;
wire [1:0] dilate_direction;
wire [7:0] dilate_red;
wire [7:0] dilate_green;
wire [7:0] dilate_blue;

binary_morph3x3 #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP),
    .DILATE   (1'b1),
    .COMPUTE_DIRECTION(1'b1)
) u_binary_dilate (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href (per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_mask   (per_img_mask),
    .per_img_edge   (per_img_edge),
    .per_img_direction(per_img_direction),
    .per_img_red    (per_img_red),
    .per_img_green  (per_img_green),
    .per_img_blue   (per_img_blue),
    .post_frame_vsync(dilate_vsync),
    .post_frame_href (dilate_href),
    .post_frame_hsync(dilate_hsync),
    .post_img_mask   (dilate_mask),
    .post_img_edge   (dilate_edge),
    .post_img_direction(dilate_direction),
    .post_img_red    (dilate_red),
    .post_img_green  (dilate_green),
    .post_img_blue   (dilate_blue)
);

binary_morph3x3 #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP),
    .DILATE   (1'b0),
    .COMPUTE_DIRECTION(1'b0)
) u_binary_erode (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(dilate_vsync),
    .per_frame_href (dilate_href),
    .per_frame_hsync(dilate_hsync),
    .per_img_mask   (dilate_mask),
    .per_img_edge   (dilate_edge),
    .per_img_direction(dilate_direction),
    .per_img_red    (dilate_red),
    .per_img_green  (dilate_green),
    .per_img_blue   (dilate_blue),
    .post_frame_vsync(post_frame_vsync),
    .post_frame_href (post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_mask   (post_img_mask),
    .post_img_edge   (post_img_edge),
    .post_img_direction(post_img_direction),
    .post_img_red    (post_img_red),
    .post_img_green  (post_img_green),
    .post_img_blue   (post_img_blue)
);

endmodule
