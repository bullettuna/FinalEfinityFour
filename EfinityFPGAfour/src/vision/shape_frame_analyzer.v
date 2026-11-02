`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Connected-component shape analyzer for binary Sobel/Canny edge contours.
//
// LinkRunCCA separates independent foreground regions and emits one bounding box
// per completed component. This wrapper rejects border/small components and keeps
// the largest valid component. Shape features are measured inside that selected
// box on the following frame, so no full-frame buffer is required.
//////////////////////////////////////////////////////////////////////////////////

module shape_frame_analyzer
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter [11:0] BORDER_MARGIN_X = 12'd4,
    parameter [10:0] BORDER_MARGIN_Y = 11'd4,
    parameter [11:0] MIN_BOX_WIDTH   = 12'd24,
    parameter [10:0] MIN_BOX_HEIGHT  = 11'd24,
    parameter [11:0] ROI_X_MIN       = 12'd320,
    parameter [11:0] ROI_X_MAX       = 12'd1599,
    parameter [10:0] ROI_Y_MIN       = 11'd180,
    parameter [10:0] ROI_Y_MAX       = 11'd899,
    parameter [3:0]  ROI_MARGIN      = 4'd4,
    parameter [4:0]  LINE_FIT_MIN_TOLERANCE = 5'd4,
    parameter [3:0]  LINE_FIT_BBOX_JITTER = 4'd4,
    // Circle points must occupy at least this many of the eight angular
    // sectors around the candidate center. Seven tolerates one short Canny
    // gap while still rejecting an isolated arc.
    parameter [3:0]  CIRCLE_MIN_SECTORS = 4'd7
)
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_img_mask,
    input               per_img_edge,
    input       [1:0]   per_img_direction,
    input               processing_enable,
    input               rect_line_fit_enable,
    input       [1:0]   line_support_level,
    output reg          bbox_valid,
    output reg  [11:0]  bbox_x_min,
    output reg  [11:0]  bbox_x_max,
    output reg  [10:0]  bbox_y_min,
    output reg  [10:0]  bbox_y_max,
    output reg  [21:0]  object_area,
    output reg  [1:0]   shape_type,
    output reg          bbox2_valid,
    output reg  [11:0]  bbox2_x_min,
    output reg  [11:0]  bbox2_x_max,
    output reg  [10:0]  bbox2_y_min,
    output reg  [10:0]  bbox2_y_max
);

localparam [1:0] SHAPE_UNKNOWN   = 2'd0;
localparam [1:0] SHAPE_RECTANGLE = 2'd1;
localparam [1:0] SHAPE_CIRCLE    = 2'd2;
// A four-lane sweep normally reports after four search frames plus one
// validation frame.  Eight frames leaves restart margin but prevents an old
// classification from remaining latched indefinitely.
localparam [4:0] CLASSIFICATION_TIMEOUT_FRAMES = 5'd8;

localparam integer CCL_X_BITS    = $clog2(IMG_HDISP);
localparam integer CCL_Y_BITS    = $clog2(IMG_VDISP);
localparam integer CCL_DATA_BITS = 2 * (CCL_X_BITS + CCL_Y_BITS);
// 4096 run labels cover large 1080p outlines and moderate edge noise while
// remaining comfortably inside the Ti60 block-RAM budget.
localparam integer CCL_ADDRESS_BITS = 12;

reg vsync_d;
reg href_d;
reg [11:0] x_pos;
reg [10:0] y_pos;

wire frame_start = per_frame_vsync && !vsync_d;
wire frame_end   = !per_frame_vsync && vsync_d;
wire ccl_reset   = !rst_n || frame_start;
wire ccl_pixel_valid = per_frame_vsync && per_frame_href;

wire ccl_box_valid;
wire ccl_label_overflow;
wire [CCL_DATA_BITS-1:0] ccl_box;

linkruncca_core #(
    .IMAGE_WIDTH (IMG_HDISP),
    .IMAGE_HEIGHT(IMG_VDISP),
    .ADDRESS_BITS(CCL_ADDRESS_BITS)
) u_linkruncca_core (
    .clk(clk),
    .rst(ccl_reset),
    .datavalid(ccl_pixel_valid),
    .pix_in(per_img_mask),
    .datavalid_out(ccl_box_valid),
    .box_out(ccl_box),
    .label_overflow(ccl_label_overflow)
);

wire [CCL_X_BITS-1:0] ccl_x_min =
    ccl_box[CCL_DATA_BITS-1:CCL_DATA_BITS-CCL_X_BITS];
wire [CCL_X_BITS-1:0] ccl_x_max =
    ccl_box[CCL_DATA_BITS-CCL_X_BITS-1:2*CCL_Y_BITS];
wire [CCL_Y_BITS-1:0] ccl_y_min = ccl_box[2*CCL_Y_BITS-1:CCL_Y_BITS];
wire [CCL_Y_BITS-1:0] ccl_y_max = ccl_box[CCL_Y_BITS-1:0];

wire [11:0] candidate_x_min = ccl_x_min;
wire [11:0] candidate_x_max = ccl_x_max;
wire [10:0] candidate_y_min = ccl_y_min;
wire [10:0] candidate_y_max = ccl_y_max;
wire candidate_order_ok = (candidate_x_max >= candidate_x_min) &&
                          (candidate_y_max >= candidate_y_min);
wire [11:0] candidate_width = candidate_x_max - candidate_x_min + 1'b1;
wire [10:0] candidate_height = candidate_y_max - candidate_y_min + 1'b1;
wire [21:0] candidate_box_area = candidate_width * candidate_height;

wire candidate_inside_frame =
    (candidate_x_min >= BORDER_MARGIN_X) &&
    (candidate_x_max < (IMG_HDISP[11:0] - BORDER_MARGIN_X)) &&
    (candidate_y_min >= BORDER_MARGIN_Y) &&
    (candidate_y_max < (IMG_VDISP[10:0] - BORDER_MARGIN_Y));
wire candidate_inside_roi =
    (candidate_x_min >= (ROI_X_MIN + ROI_MARGIN)) &&
    (candidate_x_max <= (ROI_X_MAX - ROI_MARGIN)) &&
    (candidate_y_min >= (ROI_Y_MIN + ROI_MARGIN)) &&
    (candidate_y_max <= (ROI_Y_MAX - ROI_MARGIN));
wire candidate_size_ok =
    (candidate_width >= MIN_BOX_WIDTH) &&
    (candidate_height >= MIN_BOX_HEIGHT) &&
    (candidate_box_area >= MIN_AREA);
wire candidate_accepted = ccl_box_valid && !ccl_label_overflow &&
                          candidate_order_ok &&
                          candidate_inside_frame && candidate_inside_roi &&
                          candidate_size_ok;

reg        best_found;
reg [11:0] best_x_min;
reg [11:0] best_x_max;
reg [10:0] best_y_min;
reg [10:0] best_y_max;
reg [21:0] best_box_area;
reg        second_found;
reg [11:0] second_x_min;
reg [11:0] second_x_max;
reg [10:0] second_y_min;
reg [10:0] second_y_max;
reg [21:0] second_box_area;

// A thick outline produces an inner and outer Canny contour.  They are two
// CCL components, but one physical object, so retain two spatially distinct
// candidates rather than blindly taking the two largest boxes.
wire [11:0] best_width = best_x_max - best_x_min + 1'b1;
wire [10:0] best_height = best_y_max - best_y_min + 1'b1;
wire [11:0] second_width = second_x_max - second_x_min + 1'b1;
wire [10:0] second_height = second_y_max - second_y_min + 1'b1;
wire candidate_nested_in_best = best_found &&
    (((candidate_x_min >= best_x_min) && (candidate_x_max <= best_x_max) &&
      (candidate_y_min >= best_y_min) && (candidate_y_max <= best_y_max)) ||
     ((best_x_min >= candidate_x_min) && (best_x_max <= candidate_x_max) &&
      (best_y_min >= candidate_y_min) && (best_y_max <= candidate_y_max)));
wire candidate_nested_in_second = second_found &&
    (((candidate_x_min >= second_x_min) && (candidate_x_max <= second_x_max) &&
      (candidate_y_min >= second_y_min) && (candidate_y_max <= second_y_max)) ||
     ((second_x_min >= candidate_x_min) && (second_x_max <= candidate_x_max) &&
      (second_y_min >= candidate_y_min) && (second_y_max <= candidate_y_max)));
wire candidate_same_scale_as_best = best_found &&
    (candidate_width >= (best_width >> 1)) &&
    (best_width >= (candidate_width >> 1)) &&
    (candidate_height >= (best_height >> 1)) &&
    (best_height >= (candidate_height >> 1));
wire candidate_same_scale_as_second = second_found &&
    (candidate_width >= (second_width >> 1)) &&
    (second_width >= (candidate_width >> 1)) &&
    (candidate_height >= (second_height >> 1)) &&
    (second_height >= (candidate_height >> 1));
wire candidate_duplicate_best = candidate_nested_in_best &&
                               candidate_same_scale_as_best;
wire candidate_duplicate_second = candidate_nested_in_second &&
                                 candidate_same_scale_as_second;

// Feature counters for the box selected in the preceding frame.
reg [21:0] foreground_count;
reg [21:0] corner_hits;
reg [21:0] top_hits;
reg [21:0] bottom_hits;
reg [21:0] left_hits;
reg [21:0] right_hits;
reg [21:0] direction_0_hits;
reg [21:0] direction_1_hits;
reg [21:0] direction_2_hits;
reg [21:0] direction_3_hits;
reg [21:0] circle_radial_hits;
reg [21:0] circle_edge_hits;
reg [7:0]  circle_sector_seen;

wire [11:0] stable_width  = bbox_x_max - bbox_x_min + 1'b1;
wire [10:0] stable_height = bbox_y_max - bbox_y_min + 1'b1;
wire [11:0] stable_min_dimension =
    (stable_width <= {1'b0, stable_height}) ?
    stable_width : {1'b0, stable_height};
wire [11:0] proportional_bbox_jitter = stable_min_dimension >> 4;
wire [11:0] target_bbox_jitter =
    (proportional_bbox_jitter > {8'd0, LINE_FIT_BBOX_JITTER}) ?
    proportional_bbox_jitter : {8'd0, LINE_FIT_BBOX_JITTER};
wire [11:0] bbox_delta_x_min = (best_x_min >= bbox_x_min) ?
                               (best_x_min - bbox_x_min) :
                               (bbox_x_min - best_x_min);
wire [11:0] bbox_delta_x_max = (best_x_max >= bbox_x_max) ?
                               (best_x_max - bbox_x_max) :
                               (bbox_x_max - best_x_max);
wire [10:0] bbox_delta_y_min = (best_y_min >= bbox_y_min) ?
                               (best_y_min - bbox_y_min) :
                               (bbox_y_min - best_y_min);
wire [10:0] bbox_delta_y_max = (best_y_max >= bbox_y_max) ?
                               (best_y_max - bbox_y_max) :
                               (bbox_y_max - best_y_max);
wire best_matches_published_bbox = bbox_valid && best_found &&
    (bbox_delta_x_min <= target_bbox_jitter) &&
    (bbox_delta_x_max <= target_bbox_jitter) &&
    ({1'b0, bbox_delta_y_min} <= target_bbox_jitter) &&
    ({1'b0, bbox_delta_y_max} <= target_bbox_jitter);
wire target_invalid_this_frame = !processing_enable || !best_found ||
                                 ccl_label_overflow ||
                                 (bbox_valid && !best_matches_published_bbox);
wire [11:0] feature_margin_x = (stable_width[11:3] < 12'd2) ?
                                12'd2 : {3'd0, stable_width[11:3]};
wire [10:0] feature_margin_y = (stable_height[10:3] < 11'd2) ?
                                11'd2 : {3'd0, stable_height[10:3]};

wire inside_stable_box = bbox_valid &&
                         (x_pos >= bbox_x_min) && (x_pos <= bbox_x_max) &&
                         (y_pos >= bbox_y_min) && (y_pos <= bbox_y_max);
wire near_left   = x_pos <= (bbox_x_min + feature_margin_x);
wire near_right  = (x_pos + feature_margin_x) >= bbox_x_max;
wire near_top    = y_pos <= (bbox_y_min + feature_margin_y);
wire near_bottom = (y_pos + feature_margin_y) >= bbox_y_max;
wire in_corner_zone = (near_left || near_right) &&
                      (near_top || near_bottom);

// FPGA-friendly circle fit derived from edge-to-center radius consistency.
// Coordinates are doubled so an even-sized box keeps its half-pixel center
// without division.  max(dx,dy) + 3/8*min(dx,dy) is an octagonal
// approximation of Euclidean radius: a circle stays in a narrow band, while
// the radius of a square/rectangle changes strongly between side centres and
// corners.  The test uses only subtractors, comparisons and shifts on the
// pixel-rate path; no square root, divider or multiplier is required.
wire [12:0] bbox_center_x2 = {1'b0, bbox_x_min} +
                             {1'b0, bbox_x_max};
wire [11:0] bbox_center_y2 = {1'b0, bbox_y_min} +
                             {1'b0, bbox_y_max};
wire [12:0] pixel_x2 = {x_pos, 1'b0};
wire [11:0] pixel_y2 = {y_pos, 1'b0};
wire pixel_right = pixel_x2 >= bbox_center_x2;
wire pixel_below = pixel_y2 >= bbox_center_y2;
wire [12:0] radius_dx2 = pixel_right ?
                         (pixel_x2 - bbox_center_x2) :
                         (bbox_center_x2 - pixel_x2);
wire [12:0] radius_dy2 = pixel_below ?
                         ({1'b0, pixel_y2} - {1'b0, bbox_center_y2}) :
                         ({1'b0, bbox_center_y2} - {1'b0, pixel_y2});
wire radius_x_dominant = radius_dx2 >= radius_dy2;
wire [12:0] radius_max = radius_x_dominant ? radius_dx2 : radius_dy2;
wire [12:0] radius_min = radius_x_dominant ? radius_dy2 : radius_dx2;
wire [13:0] octagonal_radius = {1'b0, radius_max} +
                               ({1'b0, radius_min} >> 2) +
                               ({1'b0, radius_min} >> 3);
wire [12:0] stable_span_x = {1'b0, bbox_x_max} -
                            {1'b0, bbox_x_min};
wire [12:0] stable_span_y = {2'b00, bbox_y_max} -
                            {2'b00, bbox_y_min};
// For a near-square candidate, the average full span equals the doubled
// nominal radius. Averaging X/Y also absorbs one-pixel CCL quantisation.
wire [13:0] nominal_radius_sum = {1'b0, stable_span_x} +
                                 {1'b0, stable_span_y};
wire [12:0] nominal_radius2 = nominal_radius_sum[13:1];
wire [16:0] octagonal_radius_x8 = {octagonal_radius, 3'b000};
wire [16:0] nominal_radius_x7 =
    ({4'b0000, nominal_radius2} << 3) -
    {4'b0000, nominal_radius2};
wire [16:0] nominal_radius_x9 =
    ({4'b0000, nominal_radius2} << 3) +
    {4'b0000, nominal_radius2};
// Use the outer +/-12.5% radius band. A thick black ring produces separate
// inner and outer Canny contours; the outer contour is longer, so requiring
// half of all edge samples preserves that valid case. A rotated rectangle has
// only short regions near its vertices in this narrow band and is rejected.
wire circle_radial_sample =
    (octagonal_radius_x8 >= nominal_radius_x7) &&
    (octagonal_radius_x8 <= nominal_radius_x9);

// Eight octants. The numbering is cyclic but otherwise arbitrary; only the
// number of occupied sectors is used by the classifier.
wire [2:0] circle_sector =
    pixel_right ?
        (pixel_below ? (radius_x_dominant ? 3'd0 : 3'd1) :
                       (radius_x_dominant ? 3'd7 : 3'd6)) :
        (pixel_below ? (radius_x_dominant ? 3'd3 : 3'd2) :
                       (radius_x_dominant ? 3'd4 : 3'd5));

// Ratios are cross-multiplied so the pixel-rate path contains no divider.
wire [13:0] width_x4  = {stable_width, 2'b00};
wire [13:0] height_x4 = {1'b0, stable_height, 2'b00};
wire [13:0] width_x3  = {2'b00, stable_width} +
                         ({2'b00, stable_width} << 1);
wire [13:0] height_x3 = {3'b000, stable_height} +
                         ({3'b000, stable_height} << 1);
wire near_square = (width_x4 >= height_x3) && (height_x4 >= width_x3);

wire side_coverage_ok =
    (top_hits >= {11'd0, stable_width[11:1]}) &&
    (bottom_hits >= {11'd0, stable_width[11:1]}) &&
    (left_hits >= {12'd0, stable_height[10:1]}) &&
    (right_hits >= {12'd0, stable_height[10:1]});

wire [22:0] stable_box_area = stable_width * stable_height;
wire [22:0] foreground_x2 = {foreground_count, 1'b0};
wire outline_density_ok = foreground_x2 < stable_box_area;
wire [24:0] corner_hits_x8 = {3'b000, corner_hits} << 3;
wire [24:0] foreground_extended = {3'b000, foreground_count};
wire rectangle_corner_score = corner_hits_x8 >= foreground_extended;

// A rectangle, including a rotated one, concentrates tangent directions in
// one perpendicular pair (0/2 or 1/3). A circle distributes them around all
// four bins.
wire [23:0] direction_total = {2'd0, direction_0_hits} +
                              {2'd0, direction_1_hits} +
                              {2'd0, direction_2_hits} +
                              {2'd0, direction_3_hits};
wire [22:0] direction_pair_02 =
    {1'b0, direction_0_hits} + {1'b0, direction_2_hits};
wire [22:0] direction_pair_13 =
    {1'b0, direction_1_hits} + {1'b0, direction_3_hits};
wire [22:0] direction_dominant_pair =
    (direction_pair_02 >= direction_pair_13) ?
    direction_pair_02 : direction_pair_13;
wire [29:0] direction_pair_x32 =
    {7'd0, direction_dominant_pair} << 5;
wire [29:0] direction_total_x32 = {6'd0, direction_total} << 5;
wire [29:0] direction_total_x31 =
    direction_total_x32 - {6'd0, direction_total};
wire rectangle_direction_score =
    (direction_total >= {2'd0, MIN_AREA}) &&
    (direction_pair_x32 >= direction_total_x31);
wire circle_direction_balance =
    (direction_total >= {2'd0, MIN_AREA}) &&
    (({8'd0, direction_0_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_1_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_2_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_3_hits} << 6) >= {6'd0, direction_total});

wire [3:0] circle_sector_count =
    {3'd0, circle_sector_seen[0]} + {3'd0, circle_sector_seen[1]} +
    {3'd0, circle_sector_seen[2]} + {3'd0, circle_sector_seen[3]} +
    {3'd0, circle_sector_seen[4]} + {3'd0, circle_sector_seen[5]} +
    {3'd0, circle_sector_seen[6]} + {3'd0, circle_sector_seen[7]};
wire circle_sector_coverage = circle_sector_count >= CIRCLE_MIN_SECTORS;
wire circle_radial_consistency =
    (circle_edge_hits >= MIN_AREA) &&
    ({circle_radial_hits, 1'b0} >= {1'b0, circle_edge_hits});

// Four parallel multi-point Hough/projection lanes are now the only rectangle
// engine. Each lane scans four interleaved angle families; together they find
// two parallel line peaks for each of two exactly perpendicular normals, then
// validate support and span on the fitted sides in about five image frames.
// The UART J setting remains in the interface for
// host compatibility, but no longer selects a second parallel hardware path.
wire rectangle_hough_score;
wire rectangle_hough_candidate;
wire rectangle_hough_ready;
wire rectangle_hough_result_valid;
shape_hough_rectangle_parallel4 #(
    .IMG_HDISP(IMG_HDISP),
    .IMG_VDISP(IMG_VDISP),
    .MIN_AREA (MIN_AREA),
    .BBOX_JITTER(LINE_FIT_BBOX_JITTER)
) u_shape_hough_rectangle_parallel4 (
    .clk(clk), .rst_n(rst_n),
    .frame_start(frame_start),
    .frame_end(frame_end),
    .processing_enable(processing_enable),
    .line_support_level(line_support_level),
    .pixel_valid(per_frame_vsync && per_frame_href),
    .edge_pixel(per_img_edge),
    .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(rectangle_hough_score),
    .rectangle_candidate(rectangle_hough_candidate),
    .fit_ready(rectangle_hough_ready),
    .result_valid(rectangle_hough_result_valid)
);

wire selected_rectangle_score = rectangle_hough_score;
wire circle_geometry_score = side_coverage_ok && near_square &&
                             circle_direction_balance &&
                             circle_sector_coverage &&
                             circle_radial_consistency &&
                             !rectangle_corner_score;
// Keep the proven circle geometry independent from the Hough candidate bit.
// Real camera noise can create short tangent-line candidates on a circle; using
// that bit as a veto made both RECT and CIRCLE flicker together.  We only wait
// for the serialized sweep to finish so both decisions refer to the same frame.
wire selected_circle_score = circle_geometry_score &&
                             rectangle_hough_ready;

reg [1:0] pending_shape_type;
reg [1:0] pending_shape_count;
reg [2:0] unknown_hold_count;
reg [4:0] classification_age_frames;
reg       reject_pending_result;

wire classification_input_valid = best_found && !ccl_label_overflow &&
                                  bbox_valid &&
                                  (foreground_count >= MIN_AREA) &&
                                  outline_density_ok;
// Geometry uses wide subtractors, a multiplier and several coverage tests.
// These values are stable for the blanking interval before a Hough result is
// accepted, so registering them here preserves the frame-level decision while
// removing that wide cone from the shape_type update path.
reg classification_input_valid_stage;
reg selected_circle_score_stage;
reg selected_rectangle_score_stage;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        classification_input_valid_stage <= 1'b0;
        selected_circle_score_stage       <= 1'b0;
        selected_rectangle_score_stage    <= 1'b0;
    end else begin
        classification_input_valid_stage <= classification_input_valid;
        selected_circle_score_stage       <= selected_circle_score;
        selected_rectangle_score_stage    <= selected_rectangle_score;
    end
end
// A strong circle model wins arbitration.  The J=0 Hough score deliberately
// tolerates one broken rectangle side, so it can also see tangent peaks on a
// noisy circle; circle-first arbitration removes that known false RECT path.
wire [1:0] raw_shape_type = !classification_input_valid_stage ? SHAPE_UNKNOWN :
                            selected_circle_score_stage ? SHAPE_CIRCLE :
                            selected_rectangle_score_stage ? SHAPE_RECTANGLE :
                            SHAPE_UNKNOWN;
wire classification_tick = rectangle_hough_result_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_d          <= 1'b0;
        href_d           <= 1'b0;
        x_pos            <= 12'd0;
        y_pos            <= 11'd0;
        best_found       <= 1'b0;
        best_x_min       <= 12'd0;
        best_x_max       <= 12'd0;
        best_y_min       <= 11'd0;
        best_y_max       <= 11'd0;
        best_box_area    <= 22'd0;
        second_found     <= 1'b0;
        second_x_min     <= 12'd0;
        second_x_max     <= 12'd0;
        second_y_min     <= 11'd0;
        second_y_max     <= 11'd0;
        second_box_area  <= 22'd0;
        foreground_count <= 22'd0;
        corner_hits      <= 22'd0;
        top_hits         <= 22'd0;
        bottom_hits      <= 22'd0;
        left_hits        <= 22'd0;
        right_hits       <= 22'd0;
        direction_0_hits <= 22'd0;
        direction_1_hits <= 22'd0;
        direction_2_hits <= 22'd0;
        direction_3_hits <= 22'd0;
        circle_radial_hits <= 22'd0;
        circle_edge_hits   <= 22'd0;
        circle_sector_seen <= 8'd0;
        bbox_valid       <= 1'b0;
        bbox_x_min       <= 12'd0;
        bbox_x_max       <= 12'd0;
        bbox_y_min       <= 11'd0;
        bbox_y_max       <= 11'd0;
        object_area      <= 22'd0;
        shape_type       <= SHAPE_UNKNOWN;
        bbox2_valid      <= 1'b0;
        bbox2_x_min      <= 12'd0;
        bbox2_x_max      <= 12'd0;
        bbox2_y_min      <= 11'd0;
        bbox2_y_max      <= 11'd0;
        pending_shape_type  <= SHAPE_UNKNOWN;
        pending_shape_count <= 2'd0;
        unknown_hold_count  <= 3'd0;
        classification_age_frames <= 5'd0;
        reject_pending_result      <= 1'b1;
    end else begin
        vsync_d <= per_frame_vsync;
        href_d  <= per_frame_href;

        if (frame_start) begin
            x_pos            <= 12'd0;
            y_pos            <= 11'd0;
            best_found       <= 1'b0;
            best_x_min       <= 12'd0;
            best_x_max       <= 12'd0;
            best_y_min       <= 11'd0;
            best_y_max       <= 11'd0;
            best_box_area    <= 22'd0;
            second_found     <= 1'b0;
            second_x_min     <= 12'd0;
            second_x_max     <= 12'd0;
            second_y_min     <= 11'd0;
            second_y_max     <= 11'd0;
            second_box_area  <= 22'd0;
            foreground_count <= 22'd0;
            corner_hits      <= 22'd0;
            top_hits         <= 22'd0;
            bottom_hits      <= 22'd0;
            left_hits        <= 22'd0;
            right_hits       <= 22'd0;
            direction_0_hits <= 22'd0;
            direction_1_hits <= 22'd0;
            direction_2_hits <= 22'd0;
            direction_3_hits <= 22'd0;
            circle_radial_hits <= 22'd0;
            circle_edge_hits   <= 22'd0;
            circle_sector_seen <= 8'd0;
        end else begin
            if (per_frame_vsync && per_frame_href) begin
                if (per_img_mask && inside_stable_box) begin
                    foreground_count <= foreground_count + 1'b1;
                    if (in_corner_zone)
                        corner_hits <= corner_hits + 1'b1;
                    if (near_top)
                        top_hits <= top_hits + 1'b1;
                    if (near_bottom)
                        bottom_hits <= bottom_hits + 1'b1;
                    if (near_left)
                        left_hits <= left_hits + 1'b1;
                    if (near_right)
                        right_hits <= right_hits + 1'b1;
                end
                if (per_img_edge && inside_stable_box) begin
                    circle_edge_hits <= circle_edge_hits + 1'b1;
                    if (circle_radial_sample) begin
                        circle_sector_seen[circle_sector] <= 1'b1;
                        circle_radial_hits <= circle_radial_hits + 1'b1;
                    end
                    case (per_img_direction)
                        2'd0: direction_0_hits <= direction_0_hits + 1'b1;
                        2'd1: direction_1_hits <= direction_1_hits + 1'b1;
                        2'd2: direction_2_hits <= direction_2_hits + 1'b1;
                        default: direction_3_hits <= direction_3_hits + 1'b1;
                    endcase
                end
                x_pos <= x_pos + 1'b1;
            end else if (per_frame_vsync && href_d) begin
                x_pos <= 12'd0;
                if (y_pos < (IMG_VDISP - 1'b1))
                    y_pos <= y_pos + 1'b1;
            end

            if (candidate_accepted) begin
                if (candidate_duplicate_best) begin
                    if (candidate_box_area > best_box_area) begin
                        best_x_min    <= candidate_x_min;
                        best_x_max    <= candidate_x_max;
                        best_y_min    <= candidate_y_min;
                        best_y_max    <= candidate_y_max;
                        best_box_area <= candidate_box_area;
                    end
                end else if (candidate_duplicate_second) begin
                    if (candidate_box_area > second_box_area) begin
                        second_x_min    <= candidate_x_min;
                        second_x_max    <= candidate_x_max;
                        second_y_min    <= candidate_y_min;
                        second_y_max    <= candidate_y_max;
                        second_box_area <= candidate_box_area;
                    end
                end else if (!best_found || (candidate_box_area > best_box_area)) begin
                    second_found    <= best_found;
                    second_x_min    <= best_x_min;
                    second_x_max    <= best_x_max;
                    second_y_min    <= best_y_min;
                    second_y_max    <= best_y_max;
                    second_box_area <= best_box_area;
                    best_found      <= 1'b1;
                    best_x_min      <= candidate_x_min;
                    best_x_max      <= candidate_x_max;
                    best_y_min      <= candidate_y_min;
                    best_y_max      <= candidate_y_max;
                    best_box_area   <= candidate_box_area;
                end else if (!second_found ||
                             (candidate_box_area > second_box_area)) begin
                    second_found    <= 1'b1;
                    second_x_min    <= candidate_x_min;
                    second_x_max    <= candidate_x_max;
                    second_y_min    <= candidate_y_min;
                    second_y_max    <= candidate_y_max;
                    second_box_area <= candidate_box_area;
                end
            end
        end

        if (frame_end) begin
            bbox_valid  <= best_found && !ccl_label_overflow;
            bbox2_valid <= second_found && !ccl_label_overflow;
            object_area <= foreground_count;
            reject_pending_result <= target_invalid_this_frame;

            if (best_found) begin
                bbox_x_min <= best_x_min;
                bbox_x_max <= best_x_max;
                bbox_y_min <= best_y_min;
                bbox_y_max <= best_y_max;
            end
            if (second_found) begin
                bbox2_x_min <= second_x_min;
                bbox2_x_max <= second_x_max;
                bbox2_y_min <= second_y_min;
                bbox2_y_max <= second_y_max;
            end

            // Invalidate a published result as soon as the target disappears,
            // processing is disabled, or the selected component jumps beyond
            // the same scale-aware tolerance used by the Hough sweep.  A
            // missing result for eight frames is also treated as stale.
            if (target_invalid_this_frame ||
                (classification_age_frames >=
                 (CLASSIFICATION_TIMEOUT_FRAMES - 1'b1))) begin
                shape_type                <= SHAPE_UNKNOWN;
                pending_shape_type        <= SHAPE_UNKNOWN;
                pending_shape_count       <= 2'd0;
                unknown_hold_count        <= 3'd0;
                classification_age_frames <= 5'd0;
            end else begin
                classification_age_frames <= classification_age_frames + 1'b1;
            end
        end

        if (classification_tick && !reject_pending_result &&
            !target_invalid_this_frame && processing_enable && bbox_valid) begin
            classification_age_frames <= 5'd0;
            // Publish a recognized type immediately from UNKNOWN, but require
            // two consecutive frames before switching between RECT and CIRCLE.
            // Three missed frames are required before dropping to UNKNOWN.
            // This is deliberately separate from the UART's own three-frame
            // debounce so the on-screen box does not flicker either.
            if (raw_shape_type == SHAPE_UNKNOWN) begin
                pending_shape_type  <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                if (shape_type == SHAPE_UNKNOWN) begin
                    unknown_hold_count <= 3'd0;
                end else if (unknown_hold_count >= 3'd2) begin
                    shape_type         <= SHAPE_UNKNOWN;
                    unknown_hold_count <= 3'd0;
                end else begin
                    unknown_hold_count <= unknown_hold_count + 1'b1;
                end
            end else if (shape_type == SHAPE_UNKNOWN) begin
                shape_type          <= raw_shape_type;
                pending_shape_type  <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                unknown_hold_count  <= 3'd0;
            end else if (raw_shape_type == shape_type) begin
                pending_shape_type  <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                unknown_hold_count  <= 3'd0;
            end else if (pending_shape_type == raw_shape_type) begin
                if (pending_shape_count >= 2'd1) begin
                    shape_type          <= raw_shape_type;
                    pending_shape_type  <= SHAPE_UNKNOWN;
                    pending_shape_count <= 2'd0;
                end else begin
                    pending_shape_count <= pending_shape_count + 1'b1;
                end
                unknown_hold_count <= 3'd0;
            end else begin
                pending_shape_type  <= raw_shape_type;
                pending_shape_count <= 2'd1;
                unknown_hold_count  <= 3'd0;
            end
        end

        // UART D must clear a published result without waiting for the next
        // video-frame boundary.  The detector lanes are reset by the same
        // enable, so no result from the interrupted sweep can be accepted.
        if (!processing_enable) begin
            shape_type                <= SHAPE_UNKNOWN;
            pending_shape_type        <= SHAPE_UNKNOWN;
            pending_shape_count       <= 2'd0;
            unknown_hold_count        <= 3'd0;
            classification_age_frames <= 5'd0;
            reject_pending_result      <= 1'b1;
        end
    end
end

endmodule
