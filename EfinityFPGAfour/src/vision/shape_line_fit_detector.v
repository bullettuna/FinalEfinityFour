`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// FPGA-friendly four-line rectangle fitter.
//
// Each candidate orientation represents two perpendicular normal vectors.  Edge
// points are projected onto both normals (a*x+b*y=rho).  One frame establishes
// the minimum/maximum rho values, which are the four fitted outer lines.  The
// following frame counts edge points close to each line.  A rectangle requires
// all four lines to have long support; a circle only touches such lines around
// four short tangent arcs and therefore fails the support test.
//
// Sixteen orientation families cover 0..90 degrees.  Projection statistics are
// collected in parallel at pixel rate, but the comparatively expensive side/
// corner score is evaluated by one shared unit during vertical blanking.  This
// avoids a sixteen-way combinational score tree on the 148.8 MHz pixel clock.
//////////////////////////////////////////////////////////////////////////////////

module shape_line_fit_detector
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter [4:0]  MIN_LINE_TOLERANCE = 5'd4,
    parameter [3:0]  BBOX_JITTER = 4'd4
)
(
    input               clk,
    input               rst_n,
    input               frame_start,
    input               frame_end,
    input               processing_enable,
    input       [1:0]   line_support_level,
    input               pixel_valid,
    input               edge_pixel,
    input       [11:0]  x_pos,
    input       [10:0]  y_pos,
    input               bbox_valid,
    input       [11:0]  bbox_x_min,
    input       [11:0]  bbox_x_max,
    input       [10:0]  bbox_y_min,
    input       [10:0]  bbox_y_max,
    output reg          rectangle_score,
    output reg          rectangle_candidate,
    output reg          fit_ready,
    output reg          result_valid
);

// Sixteen normal-vector families limit the worst-case angular quantisation
// error to roughly three degrees.  The previous eight-family version left
// large dead zones midway between its 11.25-degree samples.
localparam integer FAMILY_COUNT = 16;

wire inside_box = bbox_valid &&
                  (x_pos >= bbox_x_min) && (x_pos <= bbox_x_max) &&
                  (y_pos >= bbox_y_min) && (y_pos <= bbox_y_max);

wire [11:0] box_width = bbox_x_max - bbox_x_min + 1'b1;
wire [11:0] box_height = {1'b0, bbox_y_max - bbox_y_min + 1'b1};
wire [11:0] box_min_dimension =
    (box_width <= box_height) ? box_width : box_height;

// UART-selectable support fraction. Level 0 preserves the original 1/2 rule;
// lower fractions help thin, rotated rectangles whose short diagonal sides
// contain fewer raster samples than the inflated axis-aligned bounding box.
// The eight-pixel floor continues to reject tiny/noisy fragments.
wire [11:0] support_half = {1'b0, box_min_dimension[11:1]};
wire [11:0] support_three_eighths =
    {2'b00, box_min_dimension[11:2]} +
    {3'b000, box_min_dimension[11:3]};
wire [11:0] support_quarter = {2'b00, box_min_dimension[11:2]};
wire [11:0] support_eighth = {3'b000, box_min_dimension[11:3]};
wire [11:0] selected_line_support =
    (line_support_level == 2'd0) ? support_half :
    (line_support_level == 2'd1) ? support_three_eighths :
    (line_support_level == 2'd2) ? support_quarter : support_eighth;
wire [21:0] minimum_line_support =
    (selected_line_support < 12'd8) ?
    22'd8 : {10'd0, selected_line_support};

// Permit camera/edge jitter and small angular quantisation error.  Projection
// tolerances below are scaled by the length of each integer normal vector.
wire [11:0] dynamic_tolerance = {4'd0, box_min_dimension[11:4]};
wire [11:0] base_tolerance =
    (dynamic_tolerance < {7'd0, MIN_LINE_TOLERANCE}) ?
    {7'd0, MIN_LINE_TOLERANCE} : dynamic_tolerance;

reg [15:0] projection_a [0:FAMILY_COUNT-1];
reg [15:0] projection_b [0:FAMILY_COUNT-1];
reg [15:0] projection_tolerance [0:FAMILY_COUNT-1];
wire [15:0] x_ext = {4'd0, x_pos};
wire [15:0] y_ext = {5'd0, y_pos};
wire [15:0] image_width_ext = {2'd0, IMG_HDISP};
wire [15:0] tolerance_ext = {4'd0, base_tolerance};

// Normal-vector pairs, one perpendicular pair per family:
//   (1,0), (10,1), (5,1), (10,3), (5,2), (2,1), (5,3), (4,3),
//   (1,1), (3,4), (3,5), (1,2), (2,5), (3,10), (1,5), (1,10).
// For every (a,b), A=a*x+b*y and B=-b*x+a*y+b*image_width.
// Positive offsets are added to projections containing negative coefficients.
always @(*) begin
    projection_a[0]  = x_ext;
    projection_b[0]  = y_ext;
    projection_a[1]  = (x_ext << 3) + (x_ext << 1) + y_ext;
    projection_b[1]  = (y_ext << 3) + (y_ext << 1) + image_width_ext - x_ext;
    projection_a[2]  = (x_ext << 2) + x_ext + y_ext;
    projection_b[2]  = (y_ext << 2) + y_ext + image_width_ext - x_ext;
    projection_a[3]  = (x_ext << 3) + (x_ext << 1) +
                       (y_ext << 1) + y_ext;
    projection_b[3]  = (y_ext << 3) + (y_ext << 1) +
                       (image_width_ext << 1) + image_width_ext -
                       (x_ext << 1) - x_ext;
    projection_a[4]  = (x_ext << 2) + x_ext + (y_ext << 1);
    projection_b[4]  = (y_ext << 2) + y_ext +
                       (image_width_ext << 1) - (x_ext << 1);
    projection_a[5]  = (x_ext << 1) + y_ext;
    projection_b[5]  = (y_ext << 1) + image_width_ext - x_ext;
    projection_a[6]  = (x_ext << 2) + x_ext + (y_ext << 1) + y_ext;
    projection_b[6]  = (y_ext << 2) + y_ext +
                       (image_width_ext << 1) + image_width_ext -
                       (x_ext << 1) - x_ext;
    projection_a[7]  = (x_ext << 2) + (y_ext << 1) + y_ext;
    projection_b[7]  = (y_ext << 2) +
                       (image_width_ext << 1) + image_width_ext -
                       (x_ext << 1) - x_ext;
    projection_a[8]  = x_ext + y_ext;
    projection_b[8]  = y_ext + image_width_ext - x_ext;
    projection_a[9]  = (x_ext << 1) + x_ext + (y_ext << 2);
    projection_b[9]  = (y_ext << 1) + y_ext +
                       (image_width_ext << 2) - (x_ext << 2);
    projection_a[10] = (x_ext << 1) + x_ext + (y_ext << 2) + y_ext;
    projection_b[10] = (y_ext << 1) + y_ext +
                       (image_width_ext << 2) + image_width_ext -
                       (x_ext << 2) - x_ext;
    projection_a[11] = x_ext + (y_ext << 1);
    projection_b[11] = y_ext + (image_width_ext << 1) - (x_ext << 1);
    projection_a[12] = (x_ext << 1) + (y_ext << 2) + y_ext;
    projection_b[12] = (y_ext << 1) +
                       (image_width_ext << 2) + image_width_ext -
                       (x_ext << 2) - x_ext;
    projection_a[13] = (x_ext << 1) + x_ext +
                       (y_ext << 3) + (y_ext << 1);
    projection_b[13] = (y_ext << 1) + y_ext +
                       (image_width_ext << 3) + (image_width_ext << 1) -
                       (x_ext << 3) - (x_ext << 1);
    projection_a[14] = x_ext + (y_ext << 2) + y_ext;
    projection_b[14] = y_ext +
                       (image_width_ext << 2) + image_width_ext -
                       (x_ext << 2) - x_ext;
    projection_a[15] = x_ext + (y_ext << 3) + (y_ext << 1);
    projection_b[15] = y_ext +
                       (image_width_ext << 3) + (image_width_ext << 1) -
                       (x_ext << 3) - (x_ext << 1);

    projection_tolerance[0]  = tolerance_ext;
    projection_tolerance[1]  = (tolerance_ext << 3) +
                               (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[2]  = (tolerance_ext << 2) +
                               (tolerance_ext << 1);
    projection_tolerance[3]  = (tolerance_ext << 3) +
                               (tolerance_ext << 2) + tolerance_ext;
    projection_tolerance[4]  = (tolerance_ext << 2) +
                               (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[5]  = (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[6]  = tolerance_ext << 3;
    projection_tolerance[7]  = (tolerance_ext << 2) +
                               (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[8]  = tolerance_ext << 1;
    projection_tolerance[9]  = (tolerance_ext << 2) +
                               (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[10] = tolerance_ext << 3;
    projection_tolerance[11] = (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[12] = (tolerance_ext << 2) +
                               (tolerance_ext << 1) + tolerance_ext;
    projection_tolerance[13] = (tolerance_ext << 3) +
                               (tolerance_ext << 2) + tolerance_ext;
    projection_tolerance[14] = (tolerance_ext << 2) +
                               (tolerance_ext << 1);
    projection_tolerance[15] = (tolerance_ext << 3) +
                               (tolerance_ext << 1) + tolerance_ext;
end

reg [15:0] current_min_a [0:FAMILY_COUNT-1];
reg [15:0] current_max_a [0:FAMILY_COUNT-1];
reg [15:0] current_min_b [0:FAMILY_COUNT-1];
reg [15:0] current_max_b [0:FAMILY_COUNT-1];
reg [21:0] current_edge_count;

reg [15:0] model_min_a [0:FAMILY_COUNT-1];
reg [15:0] model_max_a [0:FAMILY_COUNT-1];
reg [15:0] model_min_b [0:FAMILY_COUNT-1];
reg [15:0] model_max_b [0:FAMILY_COUNT-1];
reg        model_valid;
reg [11:0] model_bbox_x_min;
reg [11:0] model_bbox_x_max;
reg [10:0] model_bbox_y_min;
reg [10:0] model_bbox_y_max;

reg [21:0] support_min_a [0:FAMILY_COUNT-1];
reg [21:0] support_max_a [0:FAMILY_COUNT-1];
reg [21:0] support_min_b [0:FAMILY_COUNT-1];
reg [21:0] support_max_b [0:FAMILY_COUNT-1];

// Frame-stable copies keep bbox subtraction, tolerance scaling and the eight
// coordinate-match comparisons out of the per-edge counter enable paths.
reg        active_model_box_matches;
reg [21:0] active_minimum_line_support;
reg [15:0] active_projection_tolerance [0:FAMILY_COUNT-1];

// Tangential span of each fitted line.  For an A-normal line, B is its
// tangent coordinate (and vice versa) because every vector pair is exactly
// perpendicular and has equal integer length.
reg [15:0] tangent_min_on_min_a [0:FAMILY_COUNT-1];
reg [15:0] tangent_max_on_min_a [0:FAMILY_COUNT-1];
reg [15:0] tangent_min_on_max_a [0:FAMILY_COUNT-1];
reg [15:0] tangent_max_on_max_a [0:FAMILY_COUNT-1];
reg [15:0] tangent_min_on_min_b [0:FAMILY_COUNT-1];
reg [15:0] tangent_max_on_min_b [0:FAMILY_COUNT-1];
reg [15:0] tangent_min_on_max_b [0:FAMILY_COUNT-1];
reg [15:0] tangent_max_on_max_b [0:FAMILY_COUNT-1];

// Live Canny edges move a few pixels as exposure and threshold decisions
// change.  Exact box equality caused the previous fitter to invalidate almost
// every other frame, so accept a small symmetric coordinate tolerance.
wire [11:0] proportional_bbox_jitter = {4'd0, box_min_dimension[11:4]};
wire [11:0] bbox_match_tolerance =
    (proportional_bbox_jitter > {8'd0, BBOX_JITTER}) ?
    proportional_bbox_jitter : {8'd0, BBOX_JITTER};
wire model_box_matches = model_valid && bbox_valid &&
    ({1'b0, model_bbox_x_min} <=
        ({1'b0, bbox_x_min} + bbox_match_tolerance)) &&
    ({1'b0, bbox_x_min} <=
        ({1'b0, model_bbox_x_min} + bbox_match_tolerance)) &&
    ({1'b0, model_bbox_x_max} <=
        ({1'b0, bbox_x_max} + bbox_match_tolerance)) &&
    ({1'b0, bbox_x_max} <=
        ({1'b0, model_bbox_x_max} + bbox_match_tolerance)) &&
    ({1'b0, model_bbox_y_min} <=
        ({1'b0, bbox_y_min} + bbox_match_tolerance)) &&
    ({1'b0, bbox_y_min} <=
        ({1'b0, model_bbox_y_min} + bbox_match_tolerance)) &&
    ({1'b0, model_bbox_y_max} <=
        ({1'b0, bbox_y_max} + bbox_match_tolerance)) &&
    ({1'b0, bbox_y_max} <=
        ({1'b0, model_bbox_y_max} + bbox_match_tolerance));

// The score calculation below is deliberately shared by all sixteen families.
// A LOAD cycle selects one family's registered statistics; the following EVAL
// cycle evaluates that family.  Thirty-two blanking clocks are insignificant
// at 60 fps but remove sixteen copies of the long score/classification cone.
localparam [1:0] SCORE_IDLE = 2'd0;
localparam [1:0] SCORE_LOAD = 2'd1;
localparam [1:0] SCORE_EVAL = 2'd2;

reg [1:0] score_state;
reg [4:0] score_index;
reg       score_model_box_matches;
reg [21:0] score_minimum_line_support;
reg [15:0] score_projection_tolerance [0:FAMILY_COUNT-1];
reg [FAMILY_COUNT-1:0] family_score;
reg [FAMILY_COUNT-1:0] family_candidate;
reg score_accumulator;
reg candidate_accumulator;

// One-family working set.  Registering the array read separately from the
// comparison stage also keeps the 16:1 statistic mux out of the score path.
reg [15:0] score_model_min_a;
reg [15:0] score_model_max_a;
reg [15:0] score_model_min_b;
reg [15:0] score_model_max_b;
reg [21:0] score_support_min_a;
reg [21:0] score_support_max_a;
reg [21:0] score_support_min_b;
reg [21:0] score_support_max_b;
reg [15:0] score_tangent_min_on_min_a;
reg [15:0] score_tangent_max_on_min_a;
reg [15:0] score_tangent_min_on_max_a;
reg [15:0] score_tangent_max_on_max_a;
reg [15:0] score_tangent_min_on_min_b;
reg [15:0] score_tangent_max_on_min_b;
reg [15:0] score_tangent_min_on_max_b;
reg [15:0] score_tangent_max_on_max_b;
reg [15:0] score_tolerance;

wire [15:0] score_separation_a =
    score_model_max_a - score_model_min_a;
wire [15:0] score_separation_b =
    score_model_max_b - score_model_min_b;
wire [15:0] score_minimum_separation = score_tolerance << 2;
wire [15:0] score_span_min_a =
    score_tangent_max_on_min_a - score_tangent_min_on_min_a;
wire [15:0] score_span_max_a =
    score_tangent_max_on_max_a - score_tangent_min_on_max_a;
wire [15:0] score_span_min_b =
    score_tangent_max_on_min_b - score_tangent_min_on_min_b;
wire [15:0] score_span_max_b =
    score_tangent_max_on_max_b - score_tangent_min_on_max_b;
wire [15:0] score_required_a_line_span = score_separation_b >> 1;
wire [15:0] score_required_b_line_span = score_separation_a >> 1;
wire [15:0] score_corner_tolerance = score_tolerance << 1;

wire score_min_a_reaches_corners =
    (score_tangent_min_on_min_a <=
        (score_model_min_b + score_corner_tolerance)) &&
    ((score_tangent_max_on_min_a + score_corner_tolerance) >=
        score_model_max_b);
wire score_max_a_reaches_corners =
    (score_tangent_min_on_max_a <=
        (score_model_min_b + score_corner_tolerance)) &&
    ((score_tangent_max_on_max_a + score_corner_tolerance) >=
        score_model_max_b);
wire score_min_b_reaches_corners =
    (score_tangent_min_on_min_b <=
        (score_model_min_a + score_corner_tolerance)) &&
    ((score_tangent_max_on_min_b + score_corner_tolerance) >=
        score_model_max_a);
wire score_max_b_reaches_corners =
    (score_tangent_min_on_max_b <=
        (score_model_min_a + score_corner_tolerance)) &&
    ((score_tangent_max_on_max_b + score_corner_tolerance) >=
        score_model_max_a);

wire score_min_a_supported =
    (score_support_min_a >= score_minimum_line_support) &&
    (score_span_min_a >= score_required_a_line_span);
wire score_max_a_supported =
    (score_support_max_a >= score_minimum_line_support) &&
    (score_span_max_a >= score_required_a_line_span);
wire score_min_b_supported =
    (score_support_min_b >= score_minimum_line_support) &&
    (score_span_min_b >= score_required_b_line_span);
wire score_max_b_supported =
    (score_support_max_b >= score_minimum_line_support) &&
    (score_span_max_b >= score_required_b_line_span);
wire score_all_sides_supported =
    score_min_a_supported && score_max_a_supported &&
    score_min_b_supported && score_max_b_supported;
wire [2:0] score_closed_side_count =
    {2'd0, score_min_a_reaches_corners} +
    {2'd0, score_max_a_reaches_corners} +
    {2'd0, score_min_b_reaches_corners} +
    {2'd0, score_max_b_reaches_corners};
wire score_separations_valid =
    (score_separation_a > score_minimum_separation) &&
    (score_separation_b > score_minimum_separation);
wire current_family_candidate = score_model_box_matches &&
    score_separations_valid && score_all_sides_supported &&
    (score_closed_side_count >= 3'd2);
wire current_family_score = score_model_box_matches &&
    score_separations_valid && score_all_sides_supported &&
    (score_closed_side_count >= 3'd3);

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_edge_count <= 22'd0;
        model_valid         <= 1'b0;
        model_bbox_x_min    <= 12'd0;
        model_bbox_x_max    <= 12'd0;
        model_bbox_y_min    <= 11'd0;
        model_bbox_y_max    <= 11'd0;
        rectangle_score     <= 1'b0;
        rectangle_candidate <= 1'b0;
        fit_ready           <= 1'b0;
        result_valid        <= 1'b0;
        score_state         <= SCORE_IDLE;
        score_index         <= 5'd0;
        score_model_box_matches <= 1'b0;
        score_minimum_line_support <= 22'd0;
        active_model_box_matches <= 1'b0;
        active_minimum_line_support <= 22'd0;
        family_score        <= {FAMILY_COUNT{1'b0}};
        family_candidate    <= {FAMILY_COUNT{1'b0}};
        score_accumulator   <= 1'b0;
        candidate_accumulator <= 1'b0;
        score_model_min_a   <= 16'd0;
        score_model_max_a   <= 16'd0;
        score_model_min_b   <= 16'd0;
        score_model_max_b   <= 16'd0;
        score_support_min_a <= 22'd0;
        score_support_max_a <= 22'd0;
        score_support_min_b <= 22'd0;
        score_support_max_b <= 22'd0;
        score_tangent_min_on_min_a <= 16'd0;
        score_tangent_max_on_min_a <= 16'd0;
        score_tangent_min_on_max_a <= 16'd0;
        score_tangent_max_on_max_a <= 16'd0;
        score_tangent_min_on_min_b <= 16'd0;
        score_tangent_max_on_min_b <= 16'd0;
        score_tangent_min_on_max_b <= 16'd0;
        score_tangent_max_on_max_b <= 16'd0;
        score_tolerance     <= 16'd0;
        for (i = 0; i < FAMILY_COUNT; i = i + 1) begin
            current_min_a[i] <= 16'hFFFF;
            current_max_a[i] <= 16'd0;
            current_min_b[i] <= 16'hFFFF;
            current_max_b[i] <= 16'd0;
            model_min_a[i]   <= 16'd0;
            model_max_a[i]   <= 16'd0;
            model_min_b[i]   <= 16'd0;
            model_max_b[i]   <= 16'd0;
            support_min_a[i] <= 22'd0;
            support_max_a[i] <= 22'd0;
            support_min_b[i] <= 22'd0;
            support_max_b[i] <= 22'd0;
            tangent_min_on_min_a[i] <= 16'hFFFF;
            tangent_max_on_min_a[i] <= 16'd0;
            tangent_min_on_max_a[i] <= 16'hFFFF;
            tangent_max_on_max_a[i] <= 16'd0;
            tangent_min_on_min_b[i] <= 16'hFFFF;
            tangent_max_on_min_b[i] <= 16'd0;
            tangent_min_on_max_b[i] <= 16'hFFFF;
            tangent_max_on_max_b[i] <= 16'd0;
            score_projection_tolerance[i] <= 16'd0;
            active_projection_tolerance[i] <= 16'd0;
        end
    end else begin
        result_valid <= 1'b0;

        // D=0 or J=0 stops all line-fit state changes.  The first frame after
        // re-enabling establishes a fresh model, so stale statistics can never
        // be reported as a new recognition result.
        if (!processing_enable) begin
            current_edge_count <= 22'd0;
            model_valid         <= 1'b0;
            rectangle_score     <= 1'b0;
            rectangle_candidate <= 1'b0;
            fit_ready           <= 1'b0;
            score_state         <= SCORE_IDLE;
            score_index         <= 5'd0;
            family_score        <= {FAMILY_COUNT{1'b0}};
            family_candidate    <= {FAMILY_COUNT{1'b0}};
            score_accumulator   <= 1'b0;
            candidate_accumulator <= 1'b0;
            active_model_box_matches <= 1'b0;
        end else begin
        if (frame_start) begin
            current_edge_count <= 22'd0;
            active_model_box_matches <= model_box_matches;
            active_minimum_line_support <= minimum_line_support;
            for (i = 0; i < FAMILY_COUNT; i = i + 1) begin
                current_min_a[i] <= 16'hFFFF;
                current_max_a[i] <= 16'd0;
                current_min_b[i] <= 16'hFFFF;
                current_max_b[i] <= 16'd0;
                support_min_a[i] <= 22'd0;
                support_max_a[i] <= 22'd0;
                support_min_b[i] <= 22'd0;
                support_max_b[i] <= 22'd0;
                tangent_min_on_min_a[i] <= 16'hFFFF;
                tangent_max_on_min_a[i] <= 16'd0;
                tangent_min_on_max_a[i] <= 16'hFFFF;
                tangent_max_on_max_a[i] <= 16'd0;
                tangent_min_on_min_b[i] <= 16'hFFFF;
                tangent_max_on_min_b[i] <= 16'd0;
                tangent_min_on_max_b[i] <= 16'hFFFF;
                tangent_max_on_max_b[i] <= 16'd0;
                active_projection_tolerance[i] <= projection_tolerance[i];
            end
        end else if (pixel_valid && edge_pixel && inside_box) begin
            current_edge_count <= current_edge_count + 1'b1;
            for (i = 0; i < FAMILY_COUNT; i = i + 1) begin
                if (projection_a[i] < current_min_a[i])
                    current_min_a[i] <= projection_a[i];
                if (projection_a[i] > current_max_a[i])
                    current_max_a[i] <= projection_a[i];
                if (projection_b[i] < current_min_b[i])
                    current_min_b[i] <= projection_b[i];
                if (projection_b[i] > current_max_b[i])
                    current_max_b[i] <= projection_b[i];

                if (active_model_box_matches) begin
                    if (projection_a[i] <=
                        (model_min_a[i] + active_projection_tolerance[i])) begin
                        support_min_a[i] <= support_min_a[i] + 1'b1;
                        if (projection_b[i] < tangent_min_on_min_a[i])
                            tangent_min_on_min_a[i] <= projection_b[i];
                        if (projection_b[i] > tangent_max_on_min_a[i])
                            tangent_max_on_min_a[i] <= projection_b[i];
                    end
                    if ((projection_a[i] + active_projection_tolerance[i]) >=
                        model_max_a[i]) begin
                        support_max_a[i] <= support_max_a[i] + 1'b1;
                        if (projection_b[i] < tangent_min_on_max_a[i])
                            tangent_min_on_max_a[i] <= projection_b[i];
                        if (projection_b[i] > tangent_max_on_max_a[i])
                            tangent_max_on_max_a[i] <= projection_b[i];
                    end
                    if (projection_b[i] <=
                        (model_min_b[i] + active_projection_tolerance[i])) begin
                        support_min_b[i] <= support_min_b[i] + 1'b1;
                        if (projection_a[i] < tangent_min_on_min_b[i])
                            tangent_min_on_min_b[i] <= projection_a[i];
                        if (projection_a[i] > tangent_max_on_min_b[i])
                            tangent_max_on_min_b[i] <= projection_a[i];
                    end
                    if ((projection_b[i] + active_projection_tolerance[i]) >=
                        model_max_b[i]) begin
                        support_max_b[i] <= support_max_b[i] + 1'b1;
                        if (projection_a[i] < tangent_min_on_max_b[i])
                            tangent_min_on_max_b[i] <= projection_a[i];
                        if (projection_a[i] > tangent_max_on_max_b[i])
                            tangent_max_on_max_b[i] <= projection_a[i];
                    end
                end
            end
        end

        // Freeze frame-dependent thresholds before bbox_valid/bbox coordinates
        // are updated by the parent analyzer on the same frame_end edge.
        if (frame_end && (score_state == SCORE_IDLE)) begin
            score_model_box_matches <= active_model_box_matches;
            score_minimum_line_support <= active_minimum_line_support;
            family_score        <= {FAMILY_COUNT{1'b0}};
            family_candidate    <= {FAMILY_COUNT{1'b0}};
            score_accumulator   <= 1'b0;
            candidate_accumulator <= 1'b0;
            score_index         <= 5'd0;
            score_state         <= SCORE_LOAD;
            for (i = 0; i < FAMILY_COUNT; i = i + 1)
                score_projection_tolerance[i] <=
                    active_projection_tolerance[i];
        end

        case (score_state)
            SCORE_IDLE: begin
                // A frame_end event above starts the next blanking-time scan.
            end

            SCORE_LOAD: begin
                score_model_min_a <= model_min_a[score_index];
                score_model_max_a <= model_max_a[score_index];
                score_model_min_b <= model_min_b[score_index];
                score_model_max_b <= model_max_b[score_index];
                score_support_min_a <= support_min_a[score_index];
                score_support_max_a <= support_max_a[score_index];
                score_support_min_b <= support_min_b[score_index];
                score_support_max_b <= support_max_b[score_index];
                score_tangent_min_on_min_a <=
                    tangent_min_on_min_a[score_index];
                score_tangent_max_on_min_a <=
                    tangent_max_on_min_a[score_index];
                score_tangent_min_on_max_a <=
                    tangent_min_on_max_a[score_index];
                score_tangent_max_on_max_a <=
                    tangent_max_on_max_a[score_index];
                score_tangent_min_on_min_b <=
                    tangent_min_on_min_b[score_index];
                score_tangent_max_on_min_b <=
                    tangent_max_on_min_b[score_index];
                score_tangent_min_on_max_b <=
                    tangent_min_on_max_b[score_index];
                score_tangent_max_on_max_b <=
                    tangent_max_on_max_b[score_index];
                score_tolerance <= score_projection_tolerance[score_index];
                score_state <= SCORE_EVAL;
            end

            SCORE_EVAL: begin
                family_score[score_index] <= current_family_score;
                family_candidate[score_index] <= current_family_candidate;
                score_accumulator <=
                    score_accumulator || current_family_score;
                candidate_accumulator <=
                    candidate_accumulator || current_family_candidate;

                if (score_index == (FAMILY_COUNT - 1)) begin
                    rectangle_score <=
                        score_accumulator || current_family_score;
                    rectangle_candidate <=
                        candidate_accumulator || current_family_candidate;
                    fit_ready    <= score_model_box_matches;
                    result_valid <= 1'b1;
                    score_state  <= SCORE_IDLE;

                    // The just-scored support data refers to the old model.
                    // Install this frame's extrema only after scoring finishes.
                    model_valid <= bbox_valid &&
                                   (current_edge_count >= MIN_AREA);
                    if (bbox_valid &&
                        (current_edge_count >= MIN_AREA)) begin
                        model_bbox_x_min <= bbox_x_min;
                        model_bbox_x_max <= bbox_x_max;
                        model_bbox_y_min <= bbox_y_min;
                        model_bbox_y_max <= bbox_y_max;
                        for (i = 0; i < FAMILY_COUNT; i = i + 1) begin
                            model_min_a[i] <= current_min_a[i];
                            model_max_a[i] <= current_max_a[i];
                            model_min_b[i] <= current_min_b[i];
                            model_max_b[i] <= current_max_b[i];
                        end
                    end
                end else begin
                    score_index <= score_index + 1'b1;
                    score_state <= SCORE_LOAD;
                end
            end
            default: score_state <= SCORE_IDLE;
        endcase
        end
    end
end

endmodule
