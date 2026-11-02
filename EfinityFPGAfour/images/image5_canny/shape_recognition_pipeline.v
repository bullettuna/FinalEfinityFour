`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Shape recognition based on the selected Sobel/Canny edge image.
// Edge detection remains the required front end; morphology only reconnects
// short gaps before connected-component and geometric-feature analysis. The
// original thin edge and RGB background bypass morphology for display only.
//////////////////////////////////////////////////////////////////////////////////

module shape_recognition_pipeline
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter [11:0] ROI_X_MIN = 12'd320,
    parameter [11:0] ROI_X_MAX = 12'd1599,
    parameter [10:0] ROI_Y_MIN = 11'd180,
    parameter [10:0] ROI_Y_MAX = 11'd899
)
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_edge,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    input               processing_enable,
    input               rect_line_fit_enable,
    input       [1:0]   line_support_level,
    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue,
    output              bbox_valid,
    output      [11:0]  bbox_x_min,
    output      [11:0]  bbox_x_max,
    output      [10:0]  bbox_y_min,
    output      [10:0]  bbox_y_max,
    output      [21:0]  object_area,
    output      [1:0]   shape_type,
    output              bbox2_valid,
    output      [11:0]  bbox2_x_min,
    output      [11:0]  bbox2_x_max,
    output      [10:0]  bbox2_y_min,
    output      [10:0]  bbox2_y_max,
    output      [1:0]   shape2_type
);

wire close_vsync;
wire close_href;
wire close_hsync;
wire close_mask;
wire close_edge;
wire [1:0] close_direction;
wire [7:0] close_red;
wire [7:0] close_green;
wire [7:0] close_blue;
wire edge_mask = per_frame_href && (per_img_edge != 8'd0);

binary_close3x3 #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP)
) u_binary_close3x3 (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href (per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_mask   (edge_mask),
    .per_img_edge   (edge_mask),
    .per_img_direction(2'd0),
    .per_img_red    (per_img_red),
    .per_img_green  (per_img_green),
    .per_img_blue   (per_img_blue),
    .post_frame_vsync(close_vsync),
    .post_frame_href (close_href),
    .post_frame_hsync(close_hsync),
    .post_img_mask   (close_mask),
    .post_img_edge   (close_edge),
    .post_img_direction(close_direction),
    .post_img_red    (close_red),
    .post_img_green  (close_green),
    .post_img_blue   (close_blue)
);

// Only pixels inside the configured ROI participate in CCL and classification.
// The top-level configuration uses the centered 1280x720 region (two-thirds
// of the active width and height); the gate remains parameterized.
reg close_href_d;
reg [11:0] roi_x_pos;
reg [10:0] roi_y_pos;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        close_href_d <= 1'b0;
        roi_x_pos    <= 12'd0;
        roi_y_pos    <= 11'd0;
    end else begin
        close_href_d <= close_href;
        if (!close_vsync) begin
            roi_x_pos <= 12'd0;
            roi_y_pos <= 11'd0;
        end else if (close_href) begin
            roi_x_pos <= roi_x_pos + 1'b1;
        end else if (close_href_d) begin
            roi_x_pos <= 12'd0;
            roi_y_pos <= roi_y_pos + 1'b1;
        end
    end
end

wire inside_roi = (roi_x_pos >= ROI_X_MIN) && (roi_x_pos <= ROI_X_MAX) &&
                  (roi_y_pos >= ROI_Y_MIN) && (roi_y_pos <= ROI_Y_MAX);
wire roi_close_mask = close_mask && inside_roi;
wire roi_close_edge = close_edge && inside_roi;

// Geometry must use the same gap-closed contour that produced the selected
// connected-component box. The thin, unmodified edge remains separate for
// the red display overlay below. Previously the fitter received close_edge,
// so morphology repaired CCL but not line spans or rectangle corners.
wire roi_analysis_edge = roi_close_mask;

shape_frame_analyzer #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP),
    .MIN_AREA (MIN_AREA),
    .ROI_X_MIN(ROI_X_MIN), .ROI_X_MAX(ROI_X_MAX),
    .ROI_Y_MIN(ROI_Y_MIN), .ROI_Y_MAX(ROI_Y_MAX)
) u_shape_frame_analyzer (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(close_vsync),
    .per_frame_href (close_href),
    .per_img_mask   (roi_close_mask),
    .per_img_edge   (roi_analysis_edge),
    .per_img_direction(close_direction),
    .processing_enable(processing_enable),
    .rect_line_fit_enable(rect_line_fit_enable),
    .line_support_level(line_support_level),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .object_area(object_area),
    .shape_type(shape_type),
    .bbox2_valid(bbox2_valid),
    .bbox2_x_min(bbox2_x_min), .bbox2_x_max(bbox2_x_max),
    .bbox2_y_min(bbox2_y_min), .bbox2_y_max(bbox2_y_max)
);

shape_object_classifier #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA)
) u_shape_object_classifier_2 (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(close_vsync), .per_frame_href(close_href),
    .per_img_mask(roi_close_mask), .per_img_edge(roi_analysis_edge),
    .per_img_direction(close_direction), .processing_enable(processing_enable),
    .line_support_level(line_support_level),
    .bbox_valid(bbox2_valid),
    .bbox_x_min(bbox2_x_min), .bbox_x_max(bbox2_x_max),
    .bbox_y_min(bbox2_y_min), .bbox_y_max(bbox2_y_max),
    .shape_type(shape2_type)
);

wire box_vsync, box_href, box_hsync;
wire [7:0] box_red, box_green, box_blue;
shape_overlay #(
    .ROI_X_MIN(ROI_X_MIN), .ROI_X_MAX(ROI_X_MAX),
    .ROI_Y_MIN(ROI_Y_MIN), .ROI_Y_MAX(ROI_Y_MAX)
) u_shape_overlay (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(close_vsync),
    .per_frame_href (close_href),
    .per_frame_hsync(close_hsync),
    .per_img_mask   (roi_close_edge),
    .per_img_red    (close_red),
    .per_img_green  (close_green),
    .per_img_blue   (close_blue),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .shape_type(shape_type),
    .bbox2_valid(bbox2_valid),
    .bbox2_x_min(bbox2_x_min), .bbox2_x_max(bbox2_x_max),
    .bbox2_y_min(bbox2_y_min), .bbox2_y_max(bbox2_y_max),
    .shape2_type(shape2_type),
    .post_frame_vsync(box_vsync),
    .post_frame_href (box_href),
    .post_frame_hsync(box_hsync),
    .post_img_red(box_red),
    .post_img_green(box_green),
    .post_img_blue(box_blue)
);

shape_label_overlay #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP)
) u_shape_label_overlay (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(box_vsync), .per_frame_href(box_href),
    .per_frame_hsync(box_hsync),
    .per_img_red(box_red), .per_img_green(box_green), .per_img_blue(box_blue),
    .bbox_valid(bbox_valid), .bbox_x_min(bbox_x_min), .bbox_y_min(bbox_y_min),
    .shape_type(shape_type),
    .bbox2_valid(bbox2_valid), .bbox2_x_min(bbox2_x_min), .bbox2_y_min(bbox2_y_min),
    .shape2_type(shape2_type),
    .post_frame_vsync(post_frame_vsync), .post_frame_href(post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_red(post_img_red), .post_img_green(post_img_green), .post_img_blue(post_img_blue)
);

endmodule
