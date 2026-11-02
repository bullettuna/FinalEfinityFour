`timescale 1ns/1ps

module shape_stage1_tb;

localparam [13:0] WIDTH  = 14'd32;
localparam [13:0] HEIGHT = 14'd24;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

// Threshold unit check.
reg threshold_vsync = 1'b0;
reg threshold_href = 1'b0;
reg threshold_hsync = 1'b0;
reg [7:0] gray = 8'd0;
wire threshold_out_vsync;
wire threshold_out_href;
wire threshold_out_hsync;
wire threshold_mask;

black_threshold u_threshold (
    .clk(clk), .rst_n(rst_n), .black_threshold_level(8'd96),
    .per_frame_vsync(threshold_vsync),
    .per_frame_href(threshold_href),
    .per_frame_hsync(threshold_hsync),
    .per_img_gray(gray),
    .post_frame_vsync(threshold_out_vsync),
    .post_frame_href(threshold_out_href),
    .post_frame_hsync(threshold_out_hsync),
    .post_img_mask(threshold_mask)
);

// Analyzer check is driven directly with already-clean binary shapes.
reg frame_vsync = 1'b0;
reg frame_href = 1'b0;
reg frame_mask = 1'b0;
reg frame_edge = 1'b0;
reg [1:0] frame_direction = 2'd0;
reg rect_line_fit_enable = 1'b0;
wire bbox_valid;
wire [11:0] bbox_x_min, bbox_x_max;
wire [10:0] bbox_y_min, bbox_y_max;
wire [21:0] object_area;
wire [1:0] shape_type;

shape_frame_analyzer #(
    .IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT), .MIN_AREA(22'd8),
    .BORDER_MARGIN_X(12'd1), .BORDER_MARGIN_Y(11'd1),
    .MIN_BOX_WIDTH(12'd8), .MIN_BOX_HEIGHT(11'd8),
    .ROI_X_MIN(12'd5), .ROI_X_MAX(12'd27),
    .ROI_Y_MIN(11'd1), .ROI_Y_MAX(11'd22), .ROI_MARGIN(4'd0),
    // The synthetic image is only 32x24, so one-pixel fitting tolerance is
    // equivalent to several pixels on the live Full-HD target.
    .LINE_FIT_MIN_TOLERANCE(5'd1)
) u_analyzer (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(frame_vsync),
    .per_frame_href(frame_href),
    .per_img_mask(frame_mask),
    .per_img_edge(frame_edge),
    .per_img_direction(frame_direction),
    .processing_enable(1'b1),
    .rect_line_fit_enable(rect_line_fit_enable),
    .line_support_level(2'd0),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .object_area(object_area), .shape_type(shape_type)
);

integer row;
integer col;
integer errors = 0;
integer circle_dx2;
integer circle_dy2;

function rectangle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        rectangle_pixel =
            (((pixel_row == 2) || (pixel_row == 21)) &&
             (pixel_col >= 6) && (pixel_col <= 25)) ||
            (((pixel_col == 6) || (pixel_col == 25)) &&
             (pixel_row >= 2) && (pixel_row <= 21));
    end
endfunction

function circle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        circle_pixel =
            (((pixel_row == 2) || (pixel_row == 21)) &&
             (pixel_col >= 14) && (pixel_col <= 17)) ||
            (((pixel_row == 3) || (pixel_row == 20)) &&
             (pixel_col >= 11) && (pixel_col <= 20)) ||
            (((pixel_row == 4) || (pixel_row == 19)) &&
             (pixel_col >= 9) && (pixel_col <= 22)) ||
            (((pixel_col == 8) || (pixel_col == 23)) &&
             ((pixel_row == 5) || (pixel_row == 18))) ||
            (((pixel_col == 7) || (pixel_col == 24)) &&
             (pixel_row >= 6) && (pixel_row <= 17)) ||
            (((pixel_col == 6) || (pixel_col == 25)) &&
             (pixel_row >= 9) && (pixel_row <= 14));
    end
endfunction

function noisy_rectangle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        // The isolated points are deliberately outside the rectangle. The old
        // full-frame bounding box would expand to include them; CCL must not.
        noisy_rectangle_pixel = rectangle_pixel(pixel_row, pixel_col) ||
                                ((pixel_row == 10) && (pixel_col == 2)) ||
                                ((pixel_row == 12) && (pixel_col == 29));
    end
endfunction

function filled_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        filled_pixel = (pixel_row >= 2) && (pixel_row <= 21) &&
                       (pixel_col >= 6) && (pixel_col <= 25);
    end
endfunction

function border_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        border_pixel = (((pixel_row == 2) || (pixel_row == 21)) &&
                        (pixel_col >= 0) && (pixel_col <= 31)) ||
                       (((pixel_col == 0) || (pixel_col == 31)) &&
                        (pixel_row >= 2) && (pixel_row <= 21));
    end
endfunction

function diamond_pixel;
    input integer pixel_row;
    input integer pixel_col;
    integer manhattan_distance;
    begin
        manhattan_distance = ((pixel_row >= 12) ? pixel_row - 12 : 12 - pixel_row) +
                             ((pixel_col >= 16) ? pixel_col - 16 : 16 - pixel_col);
        diamond_pixel = (manhattan_distance >= 8) &&
                        (manhattan_distance <= 10);
    end
endfunction

// A real thick black ring generates two disconnected Canny contours.  The
// analyzer must fit the longer outer contour while tolerating the inner one
// that also lies inside the selected bounding box.
function inner_circle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        inner_circle_pixel =
            (((pixel_row == 6) || (pixel_row == 17)) &&
             (pixel_col >= 14) && (pixel_col <= 17)) ||
            (((pixel_row == 7) || (pixel_row == 16)) &&
             (pixel_col >= 12) && (pixel_col <= 19)) ||
            (((pixel_col == 11) || (pixel_col == 20)) &&
             ((pixel_row == 8) || (pixel_row == 15))) ||
            (((pixel_col == 10) || (pixel_col == 21)) &&
             (pixel_row >= 9) && (pixel_row <= 14));
    end
endfunction

function thick_circle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        thick_circle_pixel = circle_pixel(pixel_row, pixel_col) ||
                             inner_circle_pixel(pixel_row, pixel_col);
    end
endfunction

// A 26.6-degree rectangle whose normal is (2,1).  This angle sat almost
// exactly between two samples in the old eight-family line fitter; the new
// sixteen-family fitter contains a matching orientation.
function rotated_27_pixel;
    input integer pixel_row;
    input integer pixel_col;
    integer dx;
    integer dy;
    integer normal_position;
    integer tangent_position;
    integer abs_normal;
    integer abs_tangent;
    begin
        dx = pixel_col - 16;
        dy = pixel_row - 12;
        normal_position  = (dx * 2) + dy;
        tangent_position = (dy * 2) - dx;
        abs_normal  = (normal_position < 0) ?
                      -normal_position : normal_position;
        abs_tangent = (tangent_position < 0) ?
                      -tangent_position : tangent_position;
        rotated_27_pixel =
            (((abs_normal >= 11) && (abs_normal <= 13)) &&
             (abs_tangent <= 8)) ||
            (((abs_tangent >= 7) && (abs_tangent <= 9)) &&
             (abs_normal <= 12));
    end
endfunction

function outside_roi_pixel;
    input integer pixel_row;
    input integer pixel_col;
    begin
        outside_roi_pixel =
            (((pixel_row == 5) || (pixel_row == 15)) &&
             (pixel_col >= 1) && (pixel_col <= 9)) ||
            (((pixel_col == 1) || (pixel_col == 9)) &&
             (pixel_row >= 5) && (pixel_row <= 15));
    end
endfunction

task send_shape_frame;
    input integer shape_select;
    begin
        frame_vsync = 1'b1;
        repeat (2) @(negedge clk);
        for (row = 0; row < HEIGHT; row = row + 1) begin
            frame_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                case (shape_select)
                    1: frame_mask = circle_pixel(row, col);
                    2: frame_mask = filled_pixel(row, col);
                    3: frame_mask = border_pixel(row, col);
                    4: frame_mask = noisy_rectangle_pixel(row, col);
                    5: frame_mask = diamond_pixel(row, col);
                    6: frame_mask = outside_roi_pixel(row, col);
                    7: frame_mask = rotated_27_pixel(row, col);
                    8: frame_mask = thick_circle_pixel(row, col);
                    default: frame_mask = rectangle_pixel(row, col);
                endcase
                frame_edge = frame_mask && (shape_select != 2);
                if ((shape_select == 1) || (shape_select == 8)) begin
                    circle_dx2 = ((2 * col) >= 31) ?
                                 ((2 * col) - 31) : (31 - (2 * col));
                    circle_dy2 = ((2 * row) >= 23) ?
                                 ((2 * row) - 23) : (23 - (2 * row));
                    if (circle_dy2 > (circle_dx2 * 2))
                        frame_direction = 2'd0;
                    else if (circle_dx2 > (circle_dy2 * 2))
                        frame_direction = 2'd2;
                    else if ((row < 12) == (col < 16))
                        frame_direction = 2'd1;
                    else
                        frame_direction = 2'd3;
                end else if (shape_select == 5) begin
                    frame_direction = ((row < 12) == (col < 16)) ?
                                      2'd1 : 2'd3;
                end else if ((row == 2) || (row == 21)) begin
                    frame_direction = 2'd0;
                end else begin
                    frame_direction = 2'd2;
                end
                @(negedge clk);
            end
            frame_href = 1'b0;
            frame_mask = 1'b0;
            frame_edge = 1'b0;
            repeat (3) @(negedge clk);
        end
        frame_vsync = 1'b0;
        // Leave enough synthetic vertical blanking for the shared sixteen-
        // direction line-score engine (LOAD+EVAL per family plus publish).
        repeat (40) @(negedge clk);
    end
endtask

task check_diamond_box;
    begin
        if (!bbox_valid || (bbox_x_min != 12'd6) ||
            (bbox_x_max != 12'd26) || (bbox_y_min != 11'd2) ||
            (bbox_y_max != 11'd22)) begin
            errors = errors + 1;
            $display("FAIL diamond bbox valid=%0d x=%0d..%0d y=%0d..%0d",
                     bbox_valid, bbox_x_min, bbox_x_max,
                     bbox_y_min, bbox_y_max);
        end
    end
endtask

task check_box;
    begin
        if (!bbox_valid || (bbox_x_min != 12'd6) ||
            (bbox_x_max != 12'd25) || (bbox_y_min != 11'd2) ||
            (bbox_y_max != 11'd21)) begin
            errors = errors + 1;
            $display("FAIL bbox valid=%0d x=%0d..%0d y=%0d..%0d",
                     bbox_valid, bbox_x_min, bbox_x_max,
                     bbox_y_min, bbox_y_max);
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Dark and threshold-equal pixels are foreground; a brighter pixel is not.
    threshold_vsync = 1'b1;
    threshold_href = 1'b1;
    gray = 8'd40;
    @(negedge clk);
    if (!threshold_out_vsync || !threshold_out_href || !threshold_mask) begin
        errors = errors + 1;
        $display("FAIL dark threshold sample");
    end
    gray = 8'd96;
    @(negedge clk);
    if (!threshold_mask) begin
        errors = errors + 1;
        $display("FAIL threshold-equal sample");
    end
    gray = 8'd97;
    @(negedge clk);
    if (threshold_mask) begin
        errors = errors + 1;
        $display("FAIL bright threshold sample");
    end
    threshold_href = 1'b0;
    threshold_vsync = 1'b0;

    // Frame 1 establishes the box; frame 2 classifies its corners.
    send_shape_frame(0);
    check_box();
    if (shape_type != 2'd0) begin
        errors = errors + 1;
        $display("FAIL first-frame type=%0d expected unknown", shape_type);
    end

    send_shape_frame(0);
    check_box();
    if (shape_type != 2'd1) begin
        errors = errors + 1;
        $display("FAIL rectangle type=%0d", shape_type);
    end

    // Type-to-type changes require two agreeing frames so a single noisy frame
    // cannot flip the on-screen result.
    send_shape_frame(1);
    send_shape_frame(1);
    check_box();
    if (shape_type != 2'd2) begin
        errors = errors + 1;
        $display("FAIL circle type=%0d dirs=%0d/%0d/%0d/%0d rect_dir=%0d balance=%0d radial=%0d/%0d sectors=%0d",
                 shape_type, u_analyzer.direction_0_hits,
                 u_analyzer.direction_1_hits, u_analyzer.direction_2_hits,
                 u_analyzer.direction_3_hits,
                 u_analyzer.rectangle_direction_score,
                 u_analyzer.circle_direction_balance,
                 u_analyzer.circle_radial_hits,
                 u_analyzer.circle_edge_hits,
                 u_analyzer.circle_sector_count);
    end
    if (!u_analyzer.circle_radial_consistency ||
        !u_analyzer.circle_sector_coverage) begin
        errors = errors + 1;
        $display("FAIL circle fit radial=%0d/%0d sectors=%0d",
                 u_analyzer.circle_radial_hits,
                 u_analyzer.circle_edge_hits,
                 u_analyzer.circle_sector_count);
    end

    // A thick black outline creates separate outer and inner Canny contours.
    // The outer-radius vote must keep this practical target classified as a
    // circle instead of treating the inner contour as radial noise.
    send_shape_frame(8);
    send_shape_frame(8);
    send_shape_frame(8);
    send_shape_frame(8);
    check_box();
    if ((shape_type != 2'd2) ||
        !u_analyzer.circle_radial_consistency ||
        !u_analyzer.circle_sector_coverage) begin
        errors = errors + 1;
        $display("FAIL thick circle type=%0d raw=%0d pending=%0d/%0d radial=%0d/%0d sectors=%0d dirs=%0d/%0d/%0d/%0d rect=%0d corners=%0d circle=%0d side=%0d square=%0d balance=%0d",
                 shape_type, u_analyzer.raw_shape_type,
                 u_analyzer.pending_shape_type,
                 u_analyzer.pending_shape_count,
                 u_analyzer.circle_radial_hits,
                 u_analyzer.circle_edge_hits,
                 u_analyzer.circle_sector_count,
                 u_analyzer.direction_0_hits,
                 u_analyzer.direction_1_hits,
                 u_analyzer.direction_2_hits,
                 u_analyzer.direction_3_hits,
                 u_analyzer.rectangle_direction_score,
                 u_analyzer.rectangle_corner_score,
                 u_analyzer.selected_circle_score,
                 u_analyzer.side_coverage_ok,
                 u_analyzer.near_square,
                 u_analyzer.circle_direction_balance);
    end

    // A solid black patch has the same bounding box, but is not a line-drawn
    // rectangle or circle and must remain unknown.
    // UNKNOWN is published only after three consecutive rejected frames.
    send_shape_frame(2);
    send_shape_frame(2);
    send_shape_frame(2);
    check_box();
    if (shape_type != 2'd0) begin
        errors = errors + 1;
        $display("FAIL filled patch type=%0d expected unknown", shape_type);
    end

    // Foreground touching the image border is background/clutter, not a target.
    send_shape_frame(3);
    if (bbox_valid || (shape_type != 2'd0)) begin
        errors = errors + 1;
        $display("FAIL border clutter valid=%0d type=%0d expected rejected",
                 bbox_valid, shape_type);
    end

    // A valid-looking object outside the configured ROI must never become a
    // candidate even though it is clear of the physical image border.
    send_shape_frame(6);
    if (bbox_valid || (shape_type != 2'd0)) begin
        errors = errors + 1;
        $display("FAIL outside-ROI object valid=%0d type=%0d expected rejected",
                 bbox_valid, shape_type);
    end

    // Disconnected black specks must not enlarge or invalidate the main box.
    send_shape_frame(4);
    check_box();
    send_shape_frame(4);
    check_box();
    if (shape_type != 2'd1) begin
        errors = errors + 1;
        $display("FAIL noisy rectangle type=%0d", shape_type);
    end

    // A 45-degree rectangle has few hits in the axis-aligned corner zones.
    // Direction concentration must still classify it as a rectangle rather
    // than falling through to the near-square circle rule.
    send_shape_frame(5);
    check_diamond_box();
    if (u_analyzer.circle_radial_consistency) begin
        errors = errors + 1;
        $display("FAIL rotated rectangle passed circle radius fit radial=%0d/%0d sectors=%0d",
                 u_analyzer.circle_radial_hits,
                 u_analyzer.circle_edge_hits,
                 u_analyzer.circle_sector_count);
    end

    send_shape_frame(5);
    check_diamond_box();
    send_shape_frame(5);
    check_diamond_box();
    send_shape_frame(5);
    check_diamond_box();
    if (shape_type != 2'd1) begin
        errors = errors + 1;
        $display("FAIL rotated rectangle type=%0d dirs=%0d/%0d/%0d/%0d rect_dir=%0d side=%0d density=%0d",
                 shape_type, u_analyzer.direction_0_hits,
                 u_analyzer.direction_1_hits, u_analyzer.direction_2_hits,
                 u_analyzer.direction_3_hits,
                 u_analyzer.rectangle_direction_score,
                 u_analyzer.side_coverage_ok,
                 u_analyzer.outline_density_ok);
    end

    // The independently selectable line-fit path first stabilizes the box,
    // then captures four line positions, then measures support on the next
    // frame.  This added latency is hidden by the existing stable-frame UART
    // reporter during live operation.
    rect_line_fit_enable = 1'b1;
    send_shape_frame(5);
    check_diamond_box();
    send_shape_frame(5);
    check_diamond_box();
    send_shape_frame(5);
    check_diamond_box();
    if (shape_type != 2'd1) begin
        errors = errors + 1;
        $display("FAIL line-fit rotated rectangle type=%0d score=%0d",
                 shape_type, u_analyzer.rectangle_line_fit_score);
    end

    // Exercise an orientation that the previous eight-family detector did not
    // sample directly.
    send_shape_frame(7);
    send_shape_frame(7);
    send_shape_frame(7);
    if (shape_type != 2'd1) begin
        errors = errors + 1;
        $display("FAIL line-fit 27-degree rectangle type=%0d score=%0d candidate=%0d families=%04x",
                 shape_type, u_analyzer.rectangle_line_fit_score,
                 u_analyzer.rectangle_line_fit_candidate,
                 u_analyzer.u_shape_line_fit_detector.family_score);
    end

    send_shape_frame(1);
    send_shape_frame(1);
    send_shape_frame(1);
    send_shape_frame(1);
    if (shape_type != 2'd2) begin
        errors = errors + 1;
        $display("FAIL line-fit circle rejection type=%0d line_score=%0d families=%04x",
                 shape_type, u_analyzer.rectangle_line_fit_score,
                 u_analyzer.u_shape_line_fit_detector.family_score);
        $display("family0 support=%0d/%0d/%0d/%0d minimum=%0d tolerance=%0d",
                 u_analyzer.u_shape_line_fit_detector.support_min_a[0],
                 u_analyzer.u_shape_line_fit_detector.support_max_a[0],
                 u_analyzer.u_shape_line_fit_detector.support_min_b[0],
                 u_analyzer.u_shape_line_fit_detector.support_max_b[0],
                 u_analyzer.u_shape_line_fit_detector.minimum_line_support,
                 u_analyzer.u_shape_line_fit_detector.base_tolerance);
    end

    if (errors == 0)
        $display("PASS stage-one threshold, bbox and shape classifier");
    else
        $display("FAIL stage-one regression errors=%0d", errors);
    $finish;
end

endmodule
