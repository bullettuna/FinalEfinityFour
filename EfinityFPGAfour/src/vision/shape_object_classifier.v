`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Per-component geometric classifier used by the second CCL object slot.
// The primary slot remains in shape_frame_analyzer for backward compatibility;
// this module receives an already-selected independent bounding box and runs
// the same circle geometry and four-lane Hough rectangle validation on it.
//////////////////////////////////////////////////////////////////////////////////

module shape_object_classifier
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [10:0] IMG_VDISP = 11'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter [3:0]  BBOX_JITTER = 4'd4,
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
    input       [1:0]   line_support_level,
    input               bbox_valid,
    input       [11:0]  bbox_x_min,
    input       [11:0]  bbox_x_max,
    input       [10:0]  bbox_y_min,
    input       [10:0]  bbox_y_max,
    output reg  [1:0]   shape_type
);

localparam [1:0] SHAPE_UNKNOWN   = 2'd0;
localparam [1:0] SHAPE_RECTANGLE = 2'd1;
localparam [1:0] SHAPE_CIRCLE    = 2'd2;
localparam [4:0] CLASSIFICATION_TIMEOUT_FRAMES = 5'd8;

reg vsync_d;
reg href_d;
reg [11:0] x_pos;
reg [10:0] y_pos;
wire frame_start = per_frame_vsync && !vsync_d;
wire frame_end   = !per_frame_vsync && vsync_d;

wire [11:0] box_width = bbox_x_max - bbox_x_min + 1'b1;
wire [10:0] box_height = bbox_y_max - bbox_y_min + 1'b1;
wire [11:0] box_min_dimension =
    (box_width <= {1'b0, box_height}) ? box_width : {1'b0, box_height};
wire [11:0] proportional_jitter = box_min_dimension >> 4;
wire [11:0] bbox_tolerance = (proportional_jitter > {8'd0, BBOX_JITTER}) ?
                             proportional_jitter : {8'd0, BBOX_JITTER};

reg previous_bbox_valid;
reg [11:0] previous_x_min, previous_x_max;
reg [10:0] previous_y_min, previous_y_max;
wire [11:0] delta_x_min = (bbox_x_min >= previous_x_min) ?
                          (bbox_x_min - previous_x_min) :
                          (previous_x_min - bbox_x_min);
wire [11:0] delta_x_max = (bbox_x_max >= previous_x_max) ?
                          (bbox_x_max - previous_x_max) :
                          (previous_x_max - bbox_x_max);
wire [10:0] delta_y_min = (bbox_y_min >= previous_y_min) ?
                          (bbox_y_min - previous_y_min) :
                          (previous_y_min - bbox_y_min);
wire [10:0] delta_y_max = (bbox_y_max >= previous_y_max) ?
                          (bbox_y_max - previous_y_max) :
                          (previous_y_max - bbox_y_max);
wire bbox_changed = bbox_valid && previous_bbox_valid &&
    ((delta_x_min > bbox_tolerance) || (delta_x_max > bbox_tolerance) ||
     ({1'b0, delta_y_min} > bbox_tolerance) ||
     ({1'b0, delta_y_max} > bbox_tolerance));

wire [11:0] feature_margin_x = (box_width[11:3] < 12'd2) ?
                                12'd2 : {3'd0, box_width[11:3]};
wire [10:0] feature_margin_y = (box_height[10:3] < 11'd2) ?
                                11'd2 : {3'd0, box_height[10:3]};
wire inside_box = bbox_valid &&
                  (x_pos >= bbox_x_min) && (x_pos <= bbox_x_max) &&
                  (y_pos >= bbox_y_min) && (y_pos <= bbox_y_max);
wire near_left   = x_pos <= (bbox_x_min + feature_margin_x);
wire near_right  = (x_pos + feature_margin_x) >= bbox_x_max;
wire near_top    = y_pos <= (bbox_y_min + feature_margin_y);
wire near_bottom = (y_pos + feature_margin_y) >= bbox_y_max;
wire in_corner_zone = (near_left || near_right) &&
                      (near_top || near_bottom);

reg [21:0] foreground_count;
reg [21:0] corner_hits;
reg [21:0] top_hits, bottom_hits, left_hits, right_hits;
reg [21:0] direction_0_hits, direction_1_hits;
reg [21:0] direction_2_hits, direction_3_hits;
reg [21:0] circle_radial_hits, circle_edge_hits;
reg [7:0]  circle_sector_seen;

// Fixed-point octagonal-radius circle model.  This is intentionally identical
// to the primary-object model so the two result slots use the same criteria.
wire [12:0] bbox_center_x2 = {1'b0, bbox_x_min} + {1'b0, bbox_x_max};
wire [11:0] bbox_center_y2 = {1'b0, bbox_y_min} + {1'b0, bbox_y_max};
wire [12:0] pixel_x2 = {x_pos, 1'b0};
wire [11:0] pixel_y2 = {y_pos, 1'b0};
wire pixel_right = pixel_x2 >= bbox_center_x2;
wire pixel_below = pixel_y2 >= bbox_center_y2;
wire [12:0] radius_dx2 = pixel_right ? (pixel_x2 - bbox_center_x2) :
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
wire [12:0] box_span_x = {1'b0, bbox_x_max} - {1'b0, bbox_x_min};
wire [12:0] box_span_y = {2'b00, bbox_y_max} - {2'b00, bbox_y_min};
wire [13:0] nominal_radius_sum = {1'b0, box_span_x} + {1'b0, box_span_y};
wire [12:0] nominal_radius2 = nominal_radius_sum[13:1];
wire [16:0] octagonal_radius_x8 = {octagonal_radius, 3'b000};
wire [16:0] nominal_radius_x7 =
    ({4'b0000, nominal_radius2} << 3) - {4'b0000, nominal_radius2};
wire [16:0] nominal_radius_x9 =
    ({4'b0000, nominal_radius2} << 3) + {4'b0000, nominal_radius2};
wire circle_radial_sample = (octagonal_radius_x8 >= nominal_radius_x7) &&
                            (octagonal_radius_x8 <= nominal_radius_x9);
wire [2:0] circle_sector =
    pixel_right ?
        (pixel_below ? (radius_x_dominant ? 3'd0 : 3'd1) :
                       (radius_x_dominant ? 3'd7 : 3'd6)) :
        (pixel_below ? (radius_x_dominant ? 3'd3 : 3'd2) :
                       (radius_x_dominant ? 3'd4 : 3'd5));

wire [13:0] width_x4  = {box_width, 2'b00};
wire [13:0] height_x4 = {1'b0, box_height, 2'b00};
wire [13:0] width_x3  = {2'b00, box_width} + ({2'b00, box_width} << 1);
wire [13:0] height_x3 = {3'b000, box_height} + ({3'b000, box_height} << 1);
wire near_square = (width_x4 >= height_x3) && (height_x4 >= width_x3);
wire side_coverage_ok =
    (top_hits >= {11'd0, box_width[11:1]}) &&
    (bottom_hits >= {11'd0, box_width[11:1]}) &&
    (left_hits >= {12'd0, box_height[10:1]}) &&
    (right_hits >= {12'd0, box_height[10:1]});
wire [22:0] box_area = box_width * box_height;
wire outline_density_ok = {foreground_count, 1'b0} < box_area;
wire rectangle_corner_score = ({3'b000, corner_hits} << 3) >=
                              {3'b000, foreground_count};
wire [23:0] direction_total = {2'd0, direction_0_hits} +
                              {2'd0, direction_1_hits} +
                              {2'd0, direction_2_hits} +
                              {2'd0, direction_3_hits};
wire circle_direction_balance = (direction_total >= {2'd0, MIN_AREA}) &&
    (({8'd0, direction_0_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_1_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_2_hits} << 6) >= {6'd0, direction_total}) &&
    (({8'd0, direction_3_hits} << 6) >= {6'd0, direction_total});
wire [3:0] circle_sector_count =
    {3'd0, circle_sector_seen[0]} + {3'd0, circle_sector_seen[1]} +
    {3'd0, circle_sector_seen[2]} + {3'd0, circle_sector_seen[3]} +
    {3'd0, circle_sector_seen[4]} + {3'd0, circle_sector_seen[5]} +
    {3'd0, circle_sector_seen[6]} + {3'd0, circle_sector_seen[7]};
wire circle_geometry_score = side_coverage_ok && near_square &&
    circle_direction_balance &&
    (circle_sector_count >= CIRCLE_MIN_SECTORS) &&
    (circle_edge_hits >= MIN_AREA) &&
    ({circle_radial_hits, 1'b0} >= {1'b0, circle_edge_hits}) &&
    !rectangle_corner_score;

wire rectangle_score;
wire rectangle_candidate;
wire rectangle_ready;
wire rectangle_result_valid;
shape_hough_rectangle_parallel4 #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA),
    .BBOX_JITTER(BBOX_JITTER)
) u_shape_hough_rectangle_parallel4 (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(processing_enable), .line_support_level(line_support_level),
    .pixel_valid(per_frame_vsync && per_frame_href), .edge_pixel(per_img_edge),
    .x_pos(x_pos), .y_pos(y_pos), .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(rectangle_score), .rectangle_candidate(rectangle_candidate),
    .fit_ready(rectangle_ready), .result_valid(rectangle_result_valid)
);

wire classification_input_valid = bbox_valid &&
                                  (foreground_count >= MIN_AREA) &&
                                  outline_density_ok;
// Keep the same two-stage arbitration as the primary object classifier.  The
// results are frame statistics, hence one pixel clock of latency cannot change
// a decision but removes the long geometry cone from shape_type's D input.
reg classification_input_valid_stage;
reg circle_geometry_score_stage;
reg rectangle_score_stage;
reg rectangle_ready_stage;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        classification_input_valid_stage <= 1'b0;
        circle_geometry_score_stage      <= 1'b0;
        rectangle_score_stage            <= 1'b0;
        rectangle_ready_stage            <= 1'b0;
    end else begin
        classification_input_valid_stage <= classification_input_valid;
        circle_geometry_score_stage      <= circle_geometry_score;
        rectangle_score_stage            <= rectangle_score;
        rectangle_ready_stage            <= rectangle_ready;
    end
end
wire [1:0] raw_shape_type = !classification_input_valid_stage ? SHAPE_UNKNOWN :
                            (circle_geometry_score_stage && rectangle_ready_stage) ? SHAPE_CIRCLE :
                            rectangle_score_stage ? SHAPE_RECTANGLE : SHAPE_UNKNOWN;

reg [1:0] pending_shape_type;
reg [1:0] pending_shape_count;
reg [2:0] unknown_hold_count;
reg [4:0] classification_age_frames;
reg reject_pending_result;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vsync_d <= 1'b0;
        href_d <= 1'b0;
        x_pos <= 12'd0;
        y_pos <= 11'd0;
        foreground_count <= 22'd0;
        corner_hits <= 22'd0;
        top_hits <= 22'd0;
        bottom_hits <= 22'd0;
        left_hits <= 22'd0;
        right_hits <= 22'd0;
        direction_0_hits <= 22'd0;
        direction_1_hits <= 22'd0;
        direction_2_hits <= 22'd0;
        direction_3_hits <= 22'd0;
        circle_radial_hits <= 22'd0;
        circle_edge_hits <= 22'd0;
        circle_sector_seen <= 8'd0;
        previous_bbox_valid <= 1'b0;
        previous_x_min <= 12'd0;
        previous_x_max <= 12'd0;
        previous_y_min <= 11'd0;
        previous_y_max <= 11'd0;
        shape_type <= SHAPE_UNKNOWN;
        pending_shape_type <= SHAPE_UNKNOWN;
        pending_shape_count <= 2'd0;
        unknown_hold_count <= 3'd0;
        classification_age_frames <= 5'd0;
        reject_pending_result <= 1'b1;
    end else begin
        vsync_d <= per_frame_vsync;
        href_d <= per_frame_href;
        if (frame_start) begin
            x_pos <= 12'd0;
            y_pos <= 11'd0;
            foreground_count <= 22'd0;
            corner_hits <= 22'd0;
            top_hits <= 22'd0;
            bottom_hits <= 22'd0;
            left_hits <= 22'd0;
            right_hits <= 22'd0;
            direction_0_hits <= 22'd0;
            direction_1_hits <= 22'd0;
            direction_2_hits <= 22'd0;
            direction_3_hits <= 22'd0;
            circle_radial_hits <= 22'd0;
            circle_edge_hits <= 22'd0;
            circle_sector_seen <= 8'd0;
        end else begin
            if (per_frame_vsync && per_frame_href) begin
                if (per_img_mask && inside_box) begin
                    foreground_count <= foreground_count + 1'b1;
                    if (in_corner_zone) corner_hits <= corner_hits + 1'b1;
                    if (near_top) top_hits <= top_hits + 1'b1;
                    if (near_bottom) bottom_hits <= bottom_hits + 1'b1;
                    if (near_left) left_hits <= left_hits + 1'b1;
                    if (near_right) right_hits <= right_hits + 1'b1;
                end
                if (per_img_edge && inside_box) begin
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
                if (y_pos < (IMG_VDISP - 1'b1)) y_pos <= y_pos + 1'b1;
            end
        end

        if (frame_end) begin
            reject_pending_result <= !bbox_valid || bbox_changed;
            previous_bbox_valid <= bbox_valid;
            if (bbox_valid) begin
                previous_x_min <= bbox_x_min;
                previous_x_max <= bbox_x_max;
                previous_y_min <= bbox_y_min;
                previous_y_max <= bbox_y_max;
            end
            if (!processing_enable || !bbox_valid || bbox_changed ||
                (classification_age_frames >= (CLASSIFICATION_TIMEOUT_FRAMES - 1'b1))) begin
                shape_type <= SHAPE_UNKNOWN;
                pending_shape_type <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                unknown_hold_count <= 3'd0;
                classification_age_frames <= 5'd0;
            end else begin
                classification_age_frames <= classification_age_frames + 1'b1;
            end
        end

        if (rectangle_result_valid && !reject_pending_result && !bbox_changed &&
            processing_enable && bbox_valid) begin
            classification_age_frames <= 5'd0;
            if (raw_shape_type == SHAPE_UNKNOWN) begin
                pending_shape_type <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                if (shape_type == SHAPE_UNKNOWN) begin
                    unknown_hold_count <= 3'd0;
                end else if (unknown_hold_count >= 3'd2) begin
                    shape_type <= SHAPE_UNKNOWN;
                    unknown_hold_count <= 3'd0;
                end else begin
                    unknown_hold_count <= unknown_hold_count + 1'b1;
                end
            end else if (shape_type == SHAPE_UNKNOWN) begin
                shape_type <= raw_shape_type;
                pending_shape_type <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                unknown_hold_count <= 3'd0;
            end else if (raw_shape_type == shape_type) begin
                pending_shape_type <= SHAPE_UNKNOWN;
                pending_shape_count <= 2'd0;
                unknown_hold_count <= 3'd0;
            end else if (pending_shape_type == raw_shape_type) begin
                if (pending_shape_count >= 2'd1) begin
                    shape_type <= raw_shape_type;
                    pending_shape_type <= SHAPE_UNKNOWN;
                    pending_shape_count <= 2'd0;
                end else begin
                    pending_shape_count <= pending_shape_count + 1'b1;
                end
                unknown_hold_count <= 3'd0;
            end else begin
                pending_shape_type <= raw_shape_type;
                pending_shape_count <= 2'd1;
                unknown_hold_count <= 3'd0;
            end
        end

        if (!processing_enable) begin
            shape_type <= SHAPE_UNKNOWN;
            pending_shape_type <= SHAPE_UNKNOWN;
            pending_shape_count <= 2'd0;
            unknown_hold_count <= 3'd0;
            classification_age_frames <= 5'd0;
            reject_pending_result <= 1'b1;
        end
    end
end

endmodule
