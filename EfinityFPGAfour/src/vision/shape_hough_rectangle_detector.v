`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Resource-controlled multi-point rectangle detector (legacy/J=0 path).
//
// Edge pixels are projected on one perpendicular normal-vector pair per frame.
// Two small block-RAM histograms find the two strongest, well-separated lines
// for each normal.  FAMILY_START/FAMILY_STEP/FAMILY_COUNT let four independent
// lanes split the sixteen orientations without building a sixteen-way pixel
// clock combinational cone.
// The best family is validated on a final frame: all four lines need sufficient
// support and long tangential span.  The two normals are constructed as
// (a,b) and (-b,a), so their dot product is identically zero and opposite sides
// are parallel by construction.
//////////////////////////////////////////////////////////////////////////////////

module shape_hough_rectangle_detector
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter integer HIST_ADDR_BITS = 9,
    parameter integer HIST_COUNT_BITS = 16,
    parameter [3:0] BBOX_JITTER = 4'd6,
    parameter [3:0] PEAK_GUARD_BINS = 4'd12,
    parameter [2:0] LINE_TOLERANCE_BINS = 3'd1,
    parameter [7:0] MIN_PEAK_COUNT = 8'd8,
    parameter [3:0] FAMILY_START = 4'd0,
    parameter [3:0] FAMILY_STEP = 4'd1,
    parameter integer FAMILY_COUNT = 16
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

localparam integer HIST_DEPTH = (1 << HIST_ADDR_BITS);
localparam [HIST_COUNT_BITS-1:0] HIST_COUNT_MAX =
    {HIST_COUNT_BITS{1'b1}};

localparam [3:0] S_DISABLED = 4'd0;
localparam [3:0] S_CLEAR    = 4'd1;
localparam [3:0] S_WAIT     = 4'd2;
localparam [3:0] S_COLLECT  = 4'd3;
localparam [3:0] S_DRAIN    = 4'd4;
localparam [3:0] S_SCAN1    = 4'd5;
localparam [3:0] S_SCAN2    = 4'd6;
localparam [3:0] S_VALIDATE = 4'd7;

reg [3:0] state;
reg [3:0] active_family;
reg [4:0] family_index;
reg       validation_mode;
reg       sweep_valid;

reg [11:0] sweep_x_min;
reg [11:0] sweep_x_max;
reg [10:0] sweep_y_min;
reg [10:0] sweep_y_max;

wire [11:0] current_width  = bbox_x_max - bbox_x_min + 1'b1;
wire [11:0] current_height = {1'b0, bbox_y_max - bbox_y_min + 1'b1};
wire [11:0] current_min_dimension =
    (current_width <= current_height) ? current_width : current_height;
wire [11:0] proportional_jitter = {4'd0, current_min_dimension[11:4]};
wire [11:0] bbox_tolerance =
    (proportional_jitter > {8'd0, BBOX_JITTER}) ?
    proportional_jitter : {8'd0, BBOX_JITTER};

wire bbox_matches_sweep = sweep_valid && bbox_valid &&
    ({1'b0, sweep_x_min} <= ({1'b0, bbox_x_min} + bbox_tolerance)) &&
    ({1'b0, bbox_x_min} <= ({1'b0, sweep_x_min} + bbox_tolerance)) &&
    ({1'b0, sweep_x_max} <= ({1'b0, bbox_x_max} + bbox_tolerance)) &&
    ({1'b0, bbox_x_max} <= ({1'b0, sweep_x_max} + bbox_tolerance)) &&
    ({1'b0, sweep_y_min} <= ({1'b0, bbox_y_min} + bbox_tolerance)) &&
    ({1'b0, bbox_y_min} <= ({1'b0, sweep_y_min} + bbox_tolerance)) &&
    ({1'b0, sweep_y_max} <= ({1'b0, bbox_y_max} + bbox_tolerance)) &&
    ({1'b0, bbox_y_max} <= ({1'b0, sweep_y_max} + bbox_tolerance));

wire inside_sweep_box = sweep_valid &&
    (x_pos >= sweep_x_min) && (x_pos <= sweep_x_max) &&
    (y_pos >= sweep_y_min) && (y_pos <= sweep_y_max);

// The same sixteen direction families as the J=1 fitter, but evaluated one
// per frame.  Projection B uses a positive image-width offset for -b*x+a*y.
function [15:0] projection_a_value;
    input [3:0] family;
    input [15:0] x;
    input [15:0] y;
    begin
        case (family)
            4'd0:  projection_a_value = x;
            4'd1:  projection_a_value = (x << 3) + (x << 1) + y;
            4'd2:  projection_a_value = (x << 2) + x + y;
            4'd3:  projection_a_value = (x << 3) + (x << 1) + (y << 1) + y;
            4'd4:  projection_a_value = (x << 2) + x + (y << 1);
            4'd5:  projection_a_value = (x << 1) + y;
            4'd6:  projection_a_value = (x << 2) + x + (y << 1) + y;
            4'd7:  projection_a_value = (x << 2) + (y << 1) + y;
            4'd8:  projection_a_value = x + y;
            4'd9:  projection_a_value = (x << 1) + x + (y << 2);
            4'd10: projection_a_value = (x << 1) + x + (y << 2) + y;
            4'd11: projection_a_value = x + (y << 1);
            4'd12: projection_a_value = (x << 1) + (y << 2) + y;
            4'd13: projection_a_value = (x << 1) + x + (y << 3) + (y << 1);
            4'd14: projection_a_value = x + (y << 2) + y;
            default: projection_a_value = x + (y << 3) + (y << 1);
        endcase
    end
endfunction

function [15:0] projection_b_value;
    input [3:0] family;
    input [15:0] x;
    input [15:0] y;
    input [15:0] w;
    begin
        case (family)
            4'd0:  projection_b_value = y;
            4'd1:  projection_b_value = (y << 3) + (y << 1) + w - x;
            4'd2:  projection_b_value = (y << 2) + y + w - x;
            4'd3:  projection_b_value = (y << 3) + (y << 1) +
                                               (w << 1) + w - (x << 1) - x;
            4'd4:  projection_b_value = (y << 2) + y + (w << 1) - (x << 1);
            4'd5:  projection_b_value = (y << 1) + w - x;
            4'd6:  projection_b_value = (y << 2) + y + (w << 1) + w -
                                               (x << 1) - x;
            4'd7:  projection_b_value = (y << 2) + (w << 1) + w -
                                               (x << 1) - x;
            4'd8:  projection_b_value = y + w - x;
            4'd9:  projection_b_value = (y << 1) + y + (w << 2) - (x << 2);
            4'd10: projection_b_value = (y << 1) + y + (w << 2) + w -
                                               (x << 2) - x;
            4'd11: projection_b_value = y + (w << 1) - (x << 1);
            4'd12: projection_b_value = (y << 1) + (w << 2) + w -
                                               (x << 2) - x;
            4'd13: projection_b_value = (y << 1) + y + (w << 3) + (w << 1) -
                                               (x << 3) - (x << 1);
            4'd14: projection_b_value = y + (w << 2) + w - (x << 2) - x;
            default: projection_b_value = y + (w << 3) + (w << 1) -
                                               (x << 3) - (x << 1);
        endcase
    end
endfunction

function [3:0] projection_bin_shift;
    input [3:0] family;
    begin
        case (family)
            4'd0: projection_bin_shift = 4'd2;
            4'd1: projection_bin_shift = 4'd6;
            4'd2: projection_bin_shift = 4'd5;
            4'd3: projection_bin_shift = 4'd6;
            4'd4: projection_bin_shift = 4'd5;
            4'd5: projection_bin_shift = 4'd4;
            4'd6: projection_bin_shift = 4'd5;
            4'd7: projection_bin_shift = 4'd5;
            4'd8: projection_bin_shift = 4'd3;
            4'd9: projection_bin_shift = 4'd5;
            4'd10: projection_bin_shift = 4'd5;
            4'd11: projection_bin_shift = 4'd4;
            4'd12: projection_bin_shift = 4'd5;
            4'd13: projection_bin_shift = 4'd6;
            4'd14: projection_bin_shift = 4'd4;
            default: projection_bin_shift = 4'd5;
        endcase
    end
endfunction

reg [15:0] projection_a_reg;
reg [15:0] projection_b_reg;
reg [3:0]  projection_shift_reg;
reg        projection_valid_reg;
wire [15:0] shifted_a = projection_a_reg >> projection_shift_reg;
wire [15:0] shifted_b = projection_b_reg >> projection_shift_reg;
wire [HIST_ADDR_BITS-1:0] projection_bin_a =
    (|shifted_a[15:HIST_ADDR_BITS]) ? {HIST_ADDR_BITS{1'b1}} :
                                      shifted_a[HIST_ADDR_BITS-1:0];
wire [HIST_ADDR_BITS-1:0] projection_bin_b =
    (|shifted_b[15:HIST_ADDR_BITS]) ? {HIST_ADDR_BITS{1'b1}} :
                                      shifted_b[HIST_ADDR_BITS-1:0];

reg [HIST_ADDR_BITS:0] clear_addr;
reg [HIST_ADDR_BITS:0] scan_issue_addr;
reg [HIST_ADDR_BITS-1:0] scan_data_addr;
reg scan_data_valid;
reg [2:0] drain_count;

reg histogram_pending_valid;
reg [HIST_ADDR_BITS-1:0] histogram_pending_a;
reg [HIST_ADDR_BITS-1:0] histogram_pending_b;

wire scan_state = (state == S_SCAN1) || (state == S_SCAN2);
wire [HIST_ADDR_BITS-1:0] histogram_read_a = scan_state ?
    scan_issue_addr[HIST_ADDR_BITS-1:0] : projection_bin_a;
wire [HIST_ADDR_BITS-1:0] histogram_read_b = scan_state ?
    scan_issue_addr[HIST_ADDR_BITS-1:0] : projection_bin_b;

wire histogram_clear_write = (state == S_CLEAR) &&
                             (clear_addr < HIST_DEPTH);
wire histogram_collect_write = (state == S_COLLECT) &&
                               histogram_pending_valid;
wire histogram_write_enable = histogram_clear_write || histogram_collect_write;
wire [HIST_ADDR_BITS-1:0] histogram_write_a = histogram_clear_write ?
    clear_addr[HIST_ADDR_BITS-1:0] : histogram_pending_a;
wire [HIST_ADDR_BITS-1:0] histogram_write_b = histogram_clear_write ?
    clear_addr[HIST_ADDR_BITS-1:0] : histogram_pending_b;

wire [HIST_COUNT_BITS-1:0] histogram_q_a;
wire [HIST_COUNT_BITS-1:0] histogram_q_b;
wire [HIST_COUNT_BITS-1:0] histogram_increment_a =
    (histogram_q_a == HIST_COUNT_MAX) ? histogram_q_a : histogram_q_a + 1'b1;
wire [HIST_COUNT_BITS-1:0] histogram_increment_b =
    (histogram_q_b == HIST_COUNT_MAX) ? histogram_q_b : histogram_q_b + 1'b1;
wire [HIST_COUNT_BITS-1:0] histogram_write_data_a = histogram_clear_write ?
    {HIST_COUNT_BITS{1'b0}} : histogram_increment_a;
wire [HIST_COUNT_BITS-1:0] histogram_write_data_b = histogram_clear_write ?
    {HIST_COUNT_BITS{1'b0}} : histogram_increment_b;

shape_hough_histogram_ram #(
    .DATA_WIDTH(HIST_COUNT_BITS), .ADDR_WIDTH(HIST_ADDR_BITS)
) u_histogram_a (
    .clk(clk), .we(histogram_write_enable),
    .write_addr(histogram_write_a), .data(histogram_write_data_a),
    .read_addr(histogram_read_a), .q(histogram_q_a)
);

shape_hough_histogram_ram #(
    .DATA_WIDTH(HIST_COUNT_BITS), .ADDR_WIDTH(HIST_ADDR_BITS)
) u_histogram_b (
    .clk(clk), .we(histogram_write_enable),
    .write_addr(histogram_write_b), .data(histogram_write_data_b),
    .read_addr(histogram_read_b), .q(histogram_q_b)
);

reg [HIST_COUNT_BITS-1:0] peak1_count_a;
reg [HIST_COUNT_BITS-1:0] peak1_count_b;
reg [HIST_COUNT_BITS-1:0] peak2_count_a;
reg [HIST_COUNT_BITS-1:0] peak2_count_b;
reg [HIST_ADDR_BITS-1:0] peak1_bin_a;
reg [HIST_ADDR_BITS-1:0] peak1_bin_b;
reg [HIST_ADDR_BITS-1:0] peak2_bin_a;
reg [HIST_ADDR_BITS-1:0] peak2_bin_b;

wire [HIST_ADDR_BITS:0] scan_distance_a =
    (scan_data_addr >= peak1_bin_a) ?
    (scan_data_addr - peak1_bin_a) : (peak1_bin_a - scan_data_addr);
wire [HIST_ADDR_BITS:0] scan_distance_b =
    (scan_data_addr >= peak1_bin_b) ?
    (scan_data_addr - peak1_bin_b) : (peak1_bin_b - scan_data_addr);

wire [HIST_ADDR_BITS:0] peak_separation_a =
    (peak1_bin_a >= peak2_bin_a) ?
    (peak1_bin_a - peak2_bin_a) : (peak2_bin_a - peak1_bin_a);
wire [HIST_ADDR_BITS:0] peak_separation_b =
    (peak1_bin_b >= peak2_bin_b) ?
    (peak1_bin_b - peak2_bin_b) : (peak2_bin_b - peak1_bin_b);
wire current_peaks_separated =
    (peak_separation_a > PEAK_GUARD_BINS) &&
    (peak_separation_b > PEAK_GUARD_BINS);

wire [HIST_COUNT_BITS-1:0] current_min_ab =
    (peak1_count_a <= peak2_count_a) ? peak1_count_a : peak2_count_a;
wire [HIST_COUNT_BITS-1:0] current_min_cd =
    (peak1_count_b <= peak2_count_b) ? peak1_count_b : peak2_count_b;
wire [HIST_COUNT_BITS-1:0] current_family_quality =
    (current_min_ab <= current_min_cd) ? current_min_ab : current_min_cd;
wire current_family_valid = current_peaks_separated &&
    (current_family_quality >= MIN_PEAK_COUNT);

reg best_valid;
reg [HIST_COUNT_BITS-1:0] best_quality;
reg [3:0] best_family;
reg [HIST_ADDR_BITS-1:0] best_a0;
reg [HIST_ADDR_BITS-1:0] best_a1;
reg [HIST_ADDR_BITS-1:0] best_b0;
reg [HIST_ADDR_BITS-1:0] best_b1;

reg [HIST_ADDR_BITS-1:0] selected_a0;
reg [HIST_ADDR_BITS-1:0] selected_a1;
reg [HIST_ADDR_BITS-1:0] selected_b0;
reg [HIST_ADDR_BITS-1:0] selected_b1;

wire current_is_new_best = current_family_valid &&
    (!best_valid || (current_family_quality > best_quality));

reg [21:0] validate_count_a0;
reg [21:0] validate_count_a1;
reg [21:0] validate_count_b0;
reg [21:0] validate_count_b1;
reg [HIST_ADDR_BITS-1:0] validate_tmin_a0;
reg [HIST_ADDR_BITS-1:0] validate_tmax_a0;
reg [HIST_ADDR_BITS-1:0] validate_tmin_a1;
reg [HIST_ADDR_BITS-1:0] validate_tmax_a1;
reg [HIST_ADDR_BITS-1:0] validate_tmin_b0;
reg [HIST_ADDR_BITS-1:0] validate_tmax_b0;
reg [HIST_ADDR_BITS-1:0] validate_tmin_b1;
reg [HIST_ADDR_BITS-1:0] validate_tmax_b1;

function within_line_tolerance;
    input [HIST_ADDR_BITS-1:0] value;
    input [HIST_ADDR_BITS-1:0] target;
    reg [HIST_ADDR_BITS:0] difference;
    begin
        difference = (value >= target) ? (value - target) : (target - value);
        within_line_tolerance = difference <= LINE_TOLERANCE_BINS;
    end
endfunction

wire validation_hit_a0 = within_line_tolerance(projection_bin_a, selected_a0);
wire validation_hit_a1 = within_line_tolerance(projection_bin_a, selected_a1);
wire validation_hit_b0 = within_line_tolerance(projection_bin_b, selected_b0);
wire validation_hit_b1 = within_line_tolerance(projection_bin_b, selected_b1);

wire [11:0] sweep_width = sweep_x_max - sweep_x_min + 1'b1;
wire [11:0] sweep_height = {1'b0, sweep_y_max - sweep_y_min + 1'b1};
wire [11:0] sweep_min_dimension =
    (sweep_width <= sweep_height) ? sweep_width : sweep_height;
wire [11:0] support_half = {1'b0, sweep_min_dimension[11:1]};
wire [11:0] support_three_eighths =
    {2'b00, sweep_min_dimension[11:2]} +
    {3'b000, sweep_min_dimension[11:3]};
wire [11:0] support_quarter = {2'b00, sweep_min_dimension[11:2]};
wire [11:0] support_eighth = {3'b000, sweep_min_dimension[11:3]};
wire [11:0] selected_support =
    (line_support_level == 2'd0) ? support_half :
    (line_support_level == 2'd1) ? support_three_eighths :
    (line_support_level == 2'd2) ? support_quarter : support_eighth;
wire [21:0] minimum_line_support =
    (selected_support < 12'd8) ? 22'd8 : {10'd0, selected_support};

wire [HIST_ADDR_BITS:0] selected_separation_a =
    (selected_a0 >= selected_a1) ?
    (selected_a0 - selected_a1) : (selected_a1 - selected_a0);
wire [HIST_ADDR_BITS:0] selected_separation_b =
    (selected_b0 >= selected_b1) ?
    (selected_b0 - selected_b1) : (selected_b1 - selected_b0);
wire [HIST_ADDR_BITS:0] required_a_tangent_span =
    selected_separation_b - (selected_separation_b >> 2);
wire [HIST_ADDR_BITS:0] required_b_tangent_span =
    selected_separation_a - (selected_separation_a >> 2);
wire [HIST_ADDR_BITS:0] span_a0 = validate_tmax_a0 - validate_tmin_a0;
wire [HIST_ADDR_BITS:0] span_a1 = validate_tmax_a1 - validate_tmin_a1;
wire [HIST_ADDR_BITS:0] span_b0 = validate_tmax_b0 - validate_tmin_b0;
wire [HIST_ADDR_BITS:0] span_b1 = validate_tmax_b1 - validate_tmin_b1;

wire [HIST_ADDR_BITS-1:0] selected_min_a =
    (selected_a0 <= selected_a1) ? selected_a0 : selected_a1;
wire [HIST_ADDR_BITS-1:0] selected_max_a =
    (selected_a0 >= selected_a1) ? selected_a0 : selected_a1;
wire [HIST_ADDR_BITS-1:0] selected_min_b =
    (selected_b0 <= selected_b1) ? selected_b0 : selected_b1;
wire [HIST_ADDR_BITS-1:0] selected_max_b =
    (selected_b0 >= selected_b1) ? selected_b0 : selected_b1;
wire [HIST_ADDR_BITS:0] corner_tolerance =
    {1'b0, LINE_TOLERANCE_BINS} + 2'd2;

// A long arc can satisfy a loose span test. A true four-line contour also
// reaches both intersections with the perpendicular pair. Requiring three
// closed sides tolerates one broken Canny corner while rejecting circle arcs.
wire side_a0_closed =
    ({1'b0, validate_tmin_a0} <=
        ({1'b0, selected_min_b} + corner_tolerance)) &&
    (({1'b0, validate_tmax_a0} + corner_tolerance) >=
        {1'b0, selected_max_b});
wire side_a1_closed =
    ({1'b0, validate_tmin_a1} <=
        ({1'b0, selected_min_b} + corner_tolerance)) &&
    (({1'b0, validate_tmax_a1} + corner_tolerance) >=
        {1'b0, selected_max_b});
wire side_b0_closed =
    ({1'b0, validate_tmin_b0} <=
        ({1'b0, selected_min_a} + corner_tolerance)) &&
    (({1'b0, validate_tmax_b0} + corner_tolerance) >=
        {1'b0, selected_max_a});
wire side_b1_closed =
    ({1'b0, validate_tmin_b1} <=
        ({1'b0, selected_min_a} + corner_tolerance)) &&
    (({1'b0, validate_tmax_b1} + corner_tolerance) >=
        {1'b0, selected_max_a});

wire side_a0_ok = (validate_count_a0 >= minimum_line_support) &&
                  (span_a0 >= required_a_tangent_span);
wire side_a1_ok = (validate_count_a1 >= minimum_line_support) &&
                  (span_a1 >= required_a_tangent_span);
wire side_b0_ok = (validate_count_b0 >= minimum_line_support) &&
                  (span_b0 >= required_b_tangent_span);
wire side_b1_ok = (validate_count_b1 >= minimum_line_support) &&
                  (span_b1 >= required_b_tangent_span);
wire [2:0] validated_side_count = {2'd0, side_a0_ok} +
                                         {2'd0, side_a1_ok} +
                                         {2'd0, side_b0_ok} +
                                         {2'd0, side_b1_ok};
wire [2:0] closed_side_count = {2'd0, side_a0_closed} +
                                      {2'd0, side_a1_closed} +
                                      {2'd0, side_b0_closed} +
                                      {2'd0, side_b1_closed};
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                 <= S_DISABLED;
        active_family         <= FAMILY_START;
        family_index          <= 5'd0;
        validation_mode       <= 1'b0;
        sweep_valid           <= 1'b0;
        sweep_x_min           <= 12'd0;
        sweep_x_max           <= 12'd0;
        sweep_y_min           <= 11'd0;
        sweep_y_max           <= 11'd0;
        projection_a_reg      <= 16'd0;
        projection_b_reg      <= 16'd0;
        projection_shift_reg  <= 4'd0;
        projection_valid_reg  <= 1'b0;
        clear_addr            <= 0;
        scan_issue_addr       <= 0;
        scan_data_addr        <= 0;
        scan_data_valid       <= 1'b0;
        drain_count           <= 3'd0;
        histogram_pending_valid <= 1'b0;
        histogram_pending_a   <= 0;
        histogram_pending_b   <= 0;
        peak1_count_a         <= 0;
        peak1_count_b         <= 0;
        peak2_count_a         <= 0;
        peak2_count_b         <= 0;
        peak1_bin_a           <= 0;
        peak1_bin_b           <= 0;
        peak2_bin_a           <= 0;
        peak2_bin_b           <= 0;
        best_valid            <= 1'b0;
        best_quality          <= 0;
        best_family           <= 4'd0;
        best_a0               <= 0;
        best_a1               <= 0;
        best_b0               <= 0;
        best_b1               <= 0;
        selected_a0           <= 0;
        selected_a1           <= 0;
        selected_b0           <= 0;
        selected_b1           <= 0;
        validate_count_a0     <= 0;
        validate_count_a1     <= 0;
        validate_count_b0     <= 0;
        validate_count_b1     <= 0;
        validate_tmin_a0      <= {HIST_ADDR_BITS{1'b1}};
        validate_tmax_a0      <= 0;
        validate_tmin_a1      <= {HIST_ADDR_BITS{1'b1}};
        validate_tmax_a1      <= 0;
        validate_tmin_b0      <= {HIST_ADDR_BITS{1'b1}};
        validate_tmax_b0      <= 0;
        validate_tmin_b1      <= {HIST_ADDR_BITS{1'b1}};
        validate_tmax_b1      <= 0;
        rectangle_score       <= 1'b0;
        rectangle_candidate   <= 1'b0;
        fit_ready             <= 1'b0;
        result_valid          <= 1'b0;
    end else begin
        result_valid <= 1'b0;

        // One pipeline stage isolates the projection add/shift network from
        // the RAM address and validation comparators.
        projection_valid_reg <= 1'b0;
        if (((state == S_COLLECT) || (state == S_VALIDATE)) &&
            pixel_valid && edge_pixel && inside_sweep_box &&
            ((state == S_VALIDATE) || (x_pos[0] == active_family[0]))) begin
            projection_a_reg <= projection_a_value(
                active_family, {4'd0, x_pos}, {5'd0, y_pos});
            projection_b_reg <= projection_b_value(
                active_family, {4'd0, x_pos}, {5'd0, y_pos},
                {2'd0, IMG_HDISP});
            projection_shift_reg <= projection_bin_shift(active_family);
            projection_valid_reg <= 1'b1;
        end

        histogram_pending_valid <=
            (state == S_COLLECT) && projection_valid_reg;
        if ((state == S_COLLECT) && projection_valid_reg) begin
            histogram_pending_a <= projection_bin_a;
            histogram_pending_b <= projection_bin_b;
        end

        if (!processing_enable) begin
            state                   <= S_DISABLED;
            sweep_valid             <= 1'b0;
            validation_mode         <= 1'b0;
            histogram_pending_valid <= 1'b0;
            projection_valid_reg    <= 1'b0;
            rectangle_score         <= 1'b0;
            rectangle_candidate     <= 1'b0;
            fit_ready               <= 1'b0;
        end else begin
            case (state)
                S_DISABLED: begin
                    clear_addr      <= 0;
                    active_family   <= FAMILY_START;
                    family_index    <= 5'd0;
                    validation_mode <= 1'b0;
                    sweep_valid     <= 1'b0;
                    best_valid      <= 1'b0;
                    best_quality    <= 0;
                    fit_ready       <= 1'b0;
                    state           <= S_CLEAR;
                end

                S_CLEAR: begin
                    histogram_pending_valid <= 1'b0;
                    if (clear_addr == HIST_DEPTH - 1) begin
                        clear_addr <= 0;
                        state      <= S_WAIT;
                    end else begin
                        clear_addr <= clear_addr + 1'b1;
                    end
                end

                S_WAIT: begin
                    histogram_pending_valid <= 1'b0;
                    if (frame_start && bbox_valid) begin
                        if (!bbox_matches_sweep) begin
                            sweep_valid     <= 1'b1;
                            sweep_x_min     <= bbox_x_min;
                            sweep_x_max     <= bbox_x_max;
                            sweep_y_min     <= bbox_y_min;
                            sweep_y_max     <= bbox_y_max;
                            active_family   <= FAMILY_START;
                            family_index    <= 5'd0;
                            validation_mode <= 1'b0;
                            best_valid      <= 1'b0;
                            best_quality    <= 0;
                            fit_ready       <= 1'b0;
                            state           <= S_COLLECT;
                        end else if (validation_mode) begin
                            validate_count_a0 <= 0;
                            validate_count_a1 <= 0;
                            validate_count_b0 <= 0;
                            validate_count_b1 <= 0;
                            validate_tmin_a0 <= {HIST_ADDR_BITS{1'b1}};
                            validate_tmax_a0 <= 0;
                            validate_tmin_a1 <= {HIST_ADDR_BITS{1'b1}};
                            validate_tmax_a1 <= 0;
                            validate_tmin_b0 <= {HIST_ADDR_BITS{1'b1}};
                            validate_tmax_b0 <= 0;
                            validate_tmin_b1 <= {HIST_ADDR_BITS{1'b1}};
                            validate_tmax_b1 <= 0;
                            state <= S_VALIDATE;
                        end else begin
                            state <= S_COLLECT;
                        end
                    end
                end

                S_COLLECT: begin
                    if (frame_end) begin
                        drain_count <= 3'd3;
                        state       <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    if (drain_count == 0) begin
                        scan_issue_addr <= 0;
                        scan_data_valid <= 1'b0;
                        peak1_count_a   <= 0;
                        peak1_count_b   <= 0;
                        peak1_bin_a     <= 0;
                        peak1_bin_b     <= 0;
                        state           <= S_SCAN1;
                    end else begin
                        drain_count <= drain_count - 1'b1;
                    end
                end

                S_SCAN1: begin
                    if (scan_data_valid) begin
                        if (histogram_q_a > peak1_count_a) begin
                            peak1_count_a <= histogram_q_a;
                            peak1_bin_a   <= scan_data_addr;
                        end
                        if (histogram_q_b > peak1_count_b) begin
                            peak1_count_b <= histogram_q_b;
                            peak1_bin_b   <= scan_data_addr;
                        end
                    end
                    if (scan_issue_addr < HIST_DEPTH) begin
                        scan_data_addr  <= scan_issue_addr[HIST_ADDR_BITS-1:0];
                        scan_data_valid <= 1'b1;
                        scan_issue_addr <= scan_issue_addr + 1'b1;
                    end else begin
                        scan_data_valid <= 1'b0;
                        if (!scan_data_valid) begin
                            scan_issue_addr <= 0;
                            peak2_count_a   <= 0;
                            peak2_count_b   <= 0;
                            peak2_bin_a     <= 0;
                            peak2_bin_b     <= 0;
                            state           <= S_SCAN2;
                        end
                    end
                end

                S_SCAN2: begin
                    if (scan_data_valid) begin
                        if ((scan_distance_a > PEAK_GUARD_BINS) &&
                            (histogram_q_a > peak2_count_a)) begin
                            peak2_count_a <= histogram_q_a;
                            peak2_bin_a   <= scan_data_addr;
                        end
                        if ((scan_distance_b > PEAK_GUARD_BINS) &&
                            (histogram_q_b > peak2_count_b)) begin
                            peak2_count_b <= histogram_q_b;
                            peak2_bin_b   <= scan_data_addr;
                        end
                    end
                    if (scan_issue_addr < HIST_DEPTH) begin
                        scan_data_addr  <= scan_issue_addr[HIST_ADDR_BITS-1:0];
                        scan_data_valid <= 1'b1;
                        scan_issue_addr <= scan_issue_addr + 1'b1;
                    end else begin
                        scan_data_valid <= 1'b0;
                        if (!scan_data_valid) begin
                            if (current_is_new_best) begin
                                best_valid   <= 1'b1;
                                best_quality <= current_family_quality;
                                best_family  <= active_family;
                                best_a0      <= peak1_bin_a;
                                best_a1      <= peak2_bin_a;
                                best_b0      <= peak1_bin_b;
                                best_b1      <= peak2_bin_b;
                            end

                            if (family_index == (FAMILY_COUNT - 1)) begin
                                if (current_is_new_best || best_valid) begin
                                    validation_mode <= 1'b1;
                                    if (current_is_new_best) begin
                                        active_family <= active_family;
                                        selected_a0 <= peak1_bin_a;
                                        selected_a1 <= peak2_bin_a;
                                        selected_b0 <= peak1_bin_b;
                                        selected_b1 <= peak2_bin_b;
                                    end else begin
                                        active_family <= best_family;
                                        selected_a0 <= best_a0;
                                        selected_a1 <= best_a1;
                                        selected_b0 <= best_b0;
                                        selected_b1 <= best_b1;
                                    end
                                    clear_addr <= 0;
                                    state <= S_CLEAR;
                                end else begin
                                    rectangle_score     <= 1'b0;
                                    rectangle_candidate <= 1'b0;
                                    fit_ready           <= 1'b1;
                                    result_valid        <= 1'b1;
                                    validation_mode     <= 1'b0;
                                    sweep_valid         <= 1'b0;
                                    clear_addr          <= 0;
                                    state               <= S_CLEAR;
                                end
                            end else begin
                                active_family <= active_family + FAMILY_STEP;
                                family_index  <= family_index + 1'b1;
                                clear_addr    <= 0;
                                state         <= S_CLEAR;
                            end
                        end
                    end
                end

                S_VALIDATE: begin
                    if (projection_valid_reg) begin
                        if (validation_hit_a0) begin
                            validate_count_a0 <= validate_count_a0 + 1'b1;
                            if (projection_bin_b < validate_tmin_a0)
                                validate_tmin_a0 <= projection_bin_b;
                            if (projection_bin_b > validate_tmax_a0)
                                validate_tmax_a0 <= projection_bin_b;
                        end
                        if (validation_hit_a1) begin
                            validate_count_a1 <= validate_count_a1 + 1'b1;
                            if (projection_bin_b < validate_tmin_a1)
                                validate_tmin_a1 <= projection_bin_b;
                            if (projection_bin_b > validate_tmax_a1)
                                validate_tmax_a1 <= projection_bin_b;
                        end
                        if (validation_hit_b0) begin
                            validate_count_b0 <= validate_count_b0 + 1'b1;
                            if (projection_bin_a < validate_tmin_b0)
                                validate_tmin_b0 <= projection_bin_a;
                            if (projection_bin_a > validate_tmax_b0)
                                validate_tmax_b0 <= projection_bin_a;
                        end
                        if (validation_hit_b1) begin
                            validate_count_b1 <= validate_count_b1 + 1'b1;
                            if (projection_bin_a < validate_tmin_b1)
                                validate_tmin_b1 <= projection_bin_a;
                            if (projection_bin_a > validate_tmax_b1)
                                validate_tmax_b1 <= projection_bin_a;
                        end
                    end
                    if (frame_end) begin
                        rectangle_score <= (validated_side_count >= 3'd3) &&
                                           (closed_side_count >= 3'd3);
                        rectangle_candidate <=
                            (validated_side_count >= 3'd2) &&
                            (closed_side_count >= 3'd2);
                        fit_ready       <= 1'b1;
                        result_valid    <= 1'b1;
                        validation_mode <= 1'b0;
                        sweep_valid     <= 1'b0;
                        active_family   <= FAMILY_START;
                        family_index    <= 5'd0;
                        best_valid      <= 1'b0;
                        best_quality    <= 0;
                        clear_addr      <= 0;
                        state           <= S_CLEAR;
                    end
                end

                default: state <= S_DISABLED;
            endcase
        end
    end
end

endmodule


//////////////////////////////////////////////////////////////////////////////////
// Four-lane wrapper.  Lane N evaluates families N, N+4, N+8 and N+12, so the
// sixteen-family search completes in four image frames.  Each lane keeps its
// own two histogram RAMs; only the small final result OR/reduction is shared.
//////////////////////////////////////////////////////////////////////////////////
module shape_hough_rectangle_parallel4
#(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter [21:0] MIN_AREA  = 22'd64,
    parameter integer HIST_ADDR_BITS = 9,
    parameter integer HIST_COUNT_BITS = 16,
    parameter [3:0] BBOX_JITTER = 4'd6,
    parameter [3:0] PEAK_GUARD_BINS = 4'd12,
    parameter [2:0] LINE_TOLERANCE_BINS = 3'd1,
    parameter [7:0] MIN_PEAK_COUNT = 8'd8
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

wire lane_enable = processing_enable && bbox_valid;
wire lane0_score, lane1_score, lane2_score, lane3_score;
wire lane0_candidate, lane1_candidate, lane2_candidate, lane3_candidate;
wire lane0_ready, lane1_ready, lane2_ready, lane3_ready;
wire lane0_valid, lane1_valid, lane2_valid, lane3_valid;
reg [3:0] completed_mask;
reg score_accumulator;
reg candidate_accumulator;
// A lane with no viable family can finish one frame before a lane that needs
// validation.  Hold each completed lane in reset until all four results have
// arrived so the next group always starts from the same video frame.
wire lane0_enable = lane_enable && !completed_mask[0];
wire lane1_enable = lane_enable && !completed_mask[1];
wire lane2_enable = lane_enable && !completed_mask[2];
wire lane3_enable = lane_enable && !completed_mask[3];

shape_hough_rectangle_detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA),
    .HIST_ADDR_BITS(HIST_ADDR_BITS), .HIST_COUNT_BITS(HIST_COUNT_BITS),
    .BBOX_JITTER(BBOX_JITTER), .PEAK_GUARD_BINS(PEAK_GUARD_BINS),
    .LINE_TOLERANCE_BINS(LINE_TOLERANCE_BINS),
    .MIN_PEAK_COUNT(MIN_PEAK_COUNT),
    .FAMILY_START(4'd0), .FAMILY_STEP(4'd4), .FAMILY_COUNT(4)
) u_lane0 (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(lane0_enable), .line_support_level(line_support_level),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel), .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid), .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(lane0_score), .rectangle_candidate(lane0_candidate),
    .fit_ready(lane0_ready), .result_valid(lane0_valid)
);

shape_hough_rectangle_detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA),
    .HIST_ADDR_BITS(HIST_ADDR_BITS), .HIST_COUNT_BITS(HIST_COUNT_BITS),
    .BBOX_JITTER(BBOX_JITTER), .PEAK_GUARD_BINS(PEAK_GUARD_BINS),
    .LINE_TOLERANCE_BINS(LINE_TOLERANCE_BINS),
    .MIN_PEAK_COUNT(MIN_PEAK_COUNT),
    .FAMILY_START(4'd1), .FAMILY_STEP(4'd4), .FAMILY_COUNT(4)
) u_lane1 (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(lane1_enable), .line_support_level(line_support_level),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel), .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid), .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(lane1_score), .rectangle_candidate(lane1_candidate),
    .fit_ready(lane1_ready), .result_valid(lane1_valid)
);

shape_hough_rectangle_detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA),
    .HIST_ADDR_BITS(HIST_ADDR_BITS), .HIST_COUNT_BITS(HIST_COUNT_BITS),
    .BBOX_JITTER(BBOX_JITTER), .PEAK_GUARD_BINS(PEAK_GUARD_BINS),
    .LINE_TOLERANCE_BINS(LINE_TOLERANCE_BINS),
    .MIN_PEAK_COUNT(MIN_PEAK_COUNT),
    .FAMILY_START(4'd2), .FAMILY_STEP(4'd4), .FAMILY_COUNT(4)
) u_lane2 (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(lane2_enable), .line_support_level(line_support_level),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel), .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid), .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(lane2_score), .rectangle_candidate(lane2_candidate),
    .fit_ready(lane2_ready), .result_valid(lane2_valid)
);

shape_hough_rectangle_detector #(
    .IMG_HDISP(IMG_HDISP), .IMG_VDISP(IMG_VDISP), .MIN_AREA(MIN_AREA),
    .HIST_ADDR_BITS(HIST_ADDR_BITS), .HIST_COUNT_BITS(HIST_COUNT_BITS),
    .BBOX_JITTER(BBOX_JITTER), .PEAK_GUARD_BINS(PEAK_GUARD_BINS),
    .LINE_TOLERANCE_BINS(LINE_TOLERANCE_BINS),
    .MIN_PEAK_COUNT(MIN_PEAK_COUNT),
    .FAMILY_START(4'd3), .FAMILY_STEP(4'd4), .FAMILY_COUNT(4)
) u_lane3 (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(lane3_enable), .line_support_level(line_support_level),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel), .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid), .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(lane3_score), .rectangle_candidate(lane3_candidate),
    .fit_ready(lane3_ready), .result_valid(lane3_valid)
);

wire [3:0] lane_valid_bus =
    {lane3_valid, lane2_valid, lane1_valid, lane0_valid};
wire [3:0] completed_next = completed_mask | lane_valid_bus;
wire score_next = score_accumulator |
                  (lane0_valid && lane0_score) |
                  (lane1_valid && lane1_score) |
                  (lane2_valid && lane2_score) |
                  (lane3_valid && lane3_score);
wire candidate_next = candidate_accumulator |
                      (lane0_valid && lane0_candidate) |
                      (lane1_valid && lane1_candidate) |
                      (lane2_valid && lane2_candidate) |
                      (lane3_valid && lane3_candidate);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        completed_mask        <= 4'd0;
        score_accumulator     <= 1'b0;
        candidate_accumulator <= 1'b0;
        rectangle_score       <= 1'b0;
        rectangle_candidate   <= 1'b0;
        fit_ready             <= 1'b0;
        result_valid          <= 1'b0;
    end else begin
        result_valid <= 1'b0;
        if (!lane_enable) begin
            completed_mask        <= 4'd0;
            score_accumulator     <= 1'b0;
            candidate_accumulator <= 1'b0;
            rectangle_score       <= 1'b0;
            rectangle_candidate   <= 1'b0;
            fit_ready             <= 1'b0;
        end else if (|lane_valid_bus) begin
            if (&completed_next) begin
                completed_mask        <= 4'd0;
                score_accumulator     <= 1'b0;
                candidate_accumulator <= 1'b0;
                rectangle_score       <= score_next;
                rectangle_candidate   <= candidate_next;
                fit_ready             <= lane0_ready || lane1_ready ||
                                         lane2_ready || lane3_ready;
                result_valid          <= 1'b1;
            end else begin
                completed_mask        <= completed_next;
                score_accumulator     <= score_next;
                candidate_accumulator <= candidate_next;
            end
        end
    end
end

endmodule


module shape_hough_histogram_ram #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 8
) (
    input                       clk,
    input                       we,
    input      [ADDR_WIDTH-1:0] write_addr,
    input      [DATA_WIDTH-1:0] data,
    input      [ADDR_WIDTH-1:0] read_addr,
    output reg [DATA_WIDTH-1:0] q
);

(* ram_style = "block", syn_ramstyle = "block_ram" *)
reg [DATA_WIDTH-1:0] ram [0:(1 << ADDR_WIDTH)-1];

always @(posedge clk) begin
    if (we)
        ram[write_addr] <= data;
    q <= ram[read_addr];
end

endmodule
