`timescale 1ns/1ps

// Regression for the intermediate-angle dead zone seen with a thin live edge.
// It drives the line fitter directly with one-pixel rectangular contours at
// 30, 35, 40, 45, 50, 55, 60, 70, 80 and 90 degrees.
module shape_line_fit_angle_tb;

localparam [13:0] WIDTH  = 14'd128;
localparam [13:0] HEIGHT = 14'd96;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg frame_start = 1'b0;
reg frame_end = 1'b0;
reg pixel_valid = 1'b0;
reg edge_pixel = 1'b0;
reg [11:0] x_pos = 12'd0;
reg [10:0] y_pos = 11'd0;
reg [1:0] line_support_level = 2'd0;
reg bbox_valid = 1'b1;
reg [11:0] bbox_x_min = 12'd0;
reg [11:0] bbox_x_max = 12'd0;
reg [10:0] bbox_y_min = 11'd0;
reg [10:0] bbox_y_max = 11'd0;
wire rectangle_score;
wire rectangle_candidate;
wire fit_ready;
wire result_valid;

shape_line_fit_detector #(
    .IMG_HDISP(WIDTH),
    .IMG_VDISP(HEIGHT),
    .MIN_AREA(22'd64),
    .MIN_LINE_TOLERANCE(5'd4),
    .BBOX_JITTER(4'd4)
) u_detector (
    .clk(clk), .rst_n(rst_n),
    .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(1'b1),
    .line_support_level(line_support_level),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel),
    .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(rectangle_score),
    .rectangle_candidate(rectangle_candidate),
    .fit_ready(fit_ready), .result_valid(result_valid)
);

integer angle_cos;
integer angle_sin;
integer row;
integer col;
integer errors = 0;

// Coefficients are cos/sin scaled by 100.  The physical half sizes are
// approximately 20 and 35 pixels; BORDER=100 creates a one-pixel contour.
function angle_rectangle_pixel;
    input integer pixel_row;
    input integer pixel_col;
    integer dx;
    integer dy;
    integer normal_position;
    integer tangent_position;
    integer abs_normal;
    integer abs_tangent;
    begin
        dx = pixel_col - 64;
        dy = pixel_row - 48;
        normal_position = (dx * angle_cos) + (dy * angle_sin);
        tangent_position = (dy * angle_cos) - (dx * angle_sin);
        abs_normal = (normal_position < 0) ?
                     -normal_position : normal_position;
        abs_tangent = (tangent_position < 0) ?
                      -tangent_position : tangent_position;
        angle_rectangle_pixel =
            (((abs_normal >= 1900) && (abs_normal <= 2100)) &&
             (abs_tangent <= 3500)) ||
            (((abs_tangent >= 3400) && (abs_tangent <= 3600)) &&
             (abs_normal <= 2000));
    end
endfunction

task configure_angle;
    input integer cos_value;
    input integer sin_value;
    begin
        angle_cos = cos_value;
        angle_sin = sin_value;
        bbox_x_min = WIDTH - 1'b1;
        bbox_x_max = 12'd0;
        bbox_y_min = HEIGHT - 1'b1;
        bbox_y_max = 11'd0;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            for (col = 0; col < WIDTH; col = col + 1) begin
                if (angle_rectangle_pixel(row, col)) begin
                    if (col < bbox_x_min)
                        bbox_x_min = col;
                    if (col > bbox_x_max)
                        bbox_x_max = col;
                    if (row < bbox_y_min)
                        bbox_y_min = row;
                    if (row > bbox_y_max)
                        bbox_y_max = row;
                end
            end
        end
    end
endtask

task check_support_control;
    integer dimension;
    integer expected;
    integer level;
    begin
        configure_angle(71, 71);
        dimension = (bbox_x_max - bbox_x_min + 1 <=
                     bbox_y_max - bbox_y_min + 1) ?
                    (bbox_x_max - bbox_x_min + 1) :
                    (bbox_y_max - bbox_y_min + 1);
        for (level = 0; level < 4; level = level + 1) begin
            line_support_level = level[1:0];
            #1;
            case (level)
                0: expected = dimension >> 1;
                1: expected = (dimension >> 2) + (dimension >> 3);
                2: expected = dimension >> 2;
                default: expected = dimension >> 3;
            endcase
            if (expected < 8)
                expected = 8;
            if (u_detector.minimum_line_support !== expected) begin
                errors = errors + 1;
                $display("FAIL support level=%0d expected=%0d got=%0d",
                         level, expected,
                         u_detector.minimum_line_support);
            end
        end
        line_support_level = 2'd0;
    end
endtask

task send_frame;
    begin
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            pixel_valid = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                x_pos = col;
                y_pos = row;
                edge_pixel = angle_rectangle_pixel(row, col);
                @(negedge clk);
            end
        end
        pixel_valid = 1'b0;
        edge_pixel = 1'b0;
        repeat (4) @(negedge clk);
        frame_end = 1'b1;
        @(negedge clk);
        frame_end = 1'b0;
        repeat (40) @(negedge clk);
    end
endtask

task check_angle;
    input integer angle_degrees;
    input integer cos_value;
    input integer sin_value;
    begin
        configure_angle(cos_value, sin_value);
        // First frame installs the projection model; second frame scores it.
        send_frame;
        send_frame;
        if (!fit_ready || !rectangle_score) begin
            errors = errors + 1;
            $display("FAIL line fit angle=%0d ready=%0d score=%0d candidate=%0d families=%04x bbox=%0d,%0d,%0d,%0d",
                     angle_degrees, fit_ready, rectangle_score,
                     rectangle_candidate, u_detector.family_score,
                     bbox_x_min, bbox_x_max, bbox_y_min, bbox_y_max);
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    check_support_control;
    check_angle(30, 87, 50);
    check_angle(35, 82, 57);
    check_angle(40, 77, 64);
    check_angle(45, 71, 71);
    check_angle(50, 64, 77);
    check_angle(55, 57, 82);
    check_angle(60, 50, 87);
    check_angle(70, 34, 94);
    check_angle(80, 17, 98);
    check_angle(90,  0, 100);

    if (errors == 0)
        $display("PASS line-fit 30-to-90-degree angle regression");
    else
        $display("FAIL line-fit angle regression errors=%0d", errors);
    $finish;
end

endmodule
