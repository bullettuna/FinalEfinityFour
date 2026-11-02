`timescale 1ns/1ps

module shape_hough_rectangle_tb;

localparam integer W = 320;
localparam integer H = 240;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg frame_start = 1'b0;
reg frame_end = 1'b0;
reg processing_enable = 1'b0;
reg pixel_valid = 1'b0;
reg edge_pixel = 1'b0;
reg [11:0] x_pos = 12'd0;
reg [10:0] y_pos = 11'd0;
reg bbox_valid = 1'b1;
reg [11:0] bbox_x_min = 12'd96;
reg [11:0] bbox_x_max = 12'd224;
reg [10:0] bbox_y_min = 11'd56;
reg [10:0] bbox_y_max = 11'd184;

wire rectangle_score;
wire rectangle_candidate;
wire fit_ready;
wire result_valid;

shape_hough_rectangle_parallel4 #(
    .IMG_HDISP(W),
    .IMG_VDISP(H),
    .MIN_AREA(22'd16)
) dut (
    .clk(clk), .rst_n(rst_n),
    .frame_start(frame_start), .frame_end(frame_end),
    .processing_enable(processing_enable),
    .line_support_level(2'd0),
    .pixel_valid(pixel_valid), .edge_pixel(edge_pixel),
    .x_pos(x_pos), .y_pos(y_pos),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .rectangle_score(rectangle_score),
    .rectangle_candidate(rectangle_candidate),
    .fit_ready(fit_ready), .result_valid(result_valid)
);

always #5 clk = ~clk;

integer result_seen = 0;
integer expect_rectangle = 1;
integer test_circle = 0;
integer frame_index;
always @(posedge clk) begin
    if (result_valid) begin
        result_seen = 1;
        $display("RESULT frame=%0d shape=%0d candidate=%0d ready=%0d",
                 frame_index, rectangle_score, rectangle_candidate, fit_ready);
        if (expect_rectangle && !rectangle_score) begin
            $display("FAIL: 45-degree rectangle was not accepted");
            $finish;
        end
        if (!expect_rectangle && rectangle_score) begin
            $display("FAIL: circle was incorrectly accepted as a rectangle");
            $finish;
        end
    end
end

function integer abs_i;
    input integer value;
    begin
        abs_i = (value < 0) ? -value : value;
    end
endfunction

function circle_edge;
    input integer px;
    input integer py;
    integer dx;
    integer dy;
    integer radius_squared;
    begin
        dx = px - 160;
        dy = py - 120;
        radius_squared = dx * dx + dy * dy;
        circle_edge = (radius_squared >= 2401) &&
                      (radius_squared <= 2601);
    end
endfunction

function rectangle_edge_45;
    input integer px;
    input integer py;
    integer pa;
    integer pb;
    begin
        // Family 8: A=x+y and B=-x+y+W. Four complete lines are formed from
        // many pixels, not from four isolated corner samples.
        pa = px + py - 280;
        pb = py + W - px - 280;
        rectangle_edge_45 =
            (((abs_i(abs_i(pa) - 70) <= 1) && (abs_i(pb) <= 45)) ||
             ((abs_i(abs_i(pb) - 45) <= 1) && (abs_i(pa) <= 70)));
    end
endfunction

task send_rectangle_frame;
    integer x;
    integer y;
    begin
        while (((!dut.completed_mask[0]) &&
                (dut.u_lane0.state != 4'd2)) ||
               ((!dut.completed_mask[1]) &&
                (dut.u_lane1.state != 4'd2)) ||
               ((!dut.completed_mask[2]) &&
                (dut.u_lane2.state != 4'd2)) ||
               ((!dut.completed_mask[3]) &&
                (dut.u_lane3.state != 4'd2)))
            @(posedge clk);
        frame_start = 1'b1;
        @(posedge clk);
        frame_start = 1'b0;
        for (y = bbox_y_min; y <= bbox_y_max; y = y + 1) begin
            for (x = bbox_x_min; x <= bbox_x_max; x = x + 1) begin
                x_pos = x;
                y_pos = y;
                edge_pixel = test_circle ? circle_edge(x, y) :
                                           rectangle_edge_45(x, y);
                pixel_valid = 1'b1;
                @(posedge clk);
            end
        end
        pixel_valid = 1'b0;
        edge_pixel = 1'b0;
        frame_end = 1'b1;
        @(posedge clk);
        frame_end = 1'b0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    processing_enable = 1'b1;

    for (frame_index = 0; frame_index < 9 && !result_seen;
         frame_index = frame_index + 1)
        send_rectangle_frame();

    repeat (1000) @(posedge clk);
    if (!result_seen) begin
        $display("FAIL: rectangle test produced no result");
        $finish;
    end
    if (frame_index > 7) begin
        $display("FAIL: parallel rectangle result exceeded latency budget");
        $finish;
    end
    $display("PASS: four-lane Hough detector accepted a 45-degree rectangle");

    // Run a second sweep without resetting.  This catches lane drift when a
    // no-candidate lane finishes one frame before a lane that validates.
    result_seen = 0;
    for (frame_index = 0; frame_index < 9 && !result_seen;
         frame_index = frame_index + 1)
        send_rectangle_frame();
    repeat (1000) @(posedge clk);
    if (!result_seen || (frame_index > 7)) begin
        $display("FAIL: repeated parallel sweep lost lane synchronization");
        $finish;
    end
    $display("PASS: repeated four-lane sweep remained synchronized");

    processing_enable = 1'b0;
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    bbox_x_min = 12'd108;
    bbox_x_max = 12'd212;
    bbox_y_min = 11'd68;
    bbox_y_max = 11'd172;
    result_seen = 0;
    expect_rectangle = 0;
    test_circle = 1;
    rst_n = 1'b1;
    processing_enable = 1'b1;

    for (frame_index = 0; frame_index < 9 && !result_seen;
         frame_index = frame_index + 1)
        send_rectangle_frame();

    repeat (1000) @(posedge clk);
    if (!result_seen) begin
        $display("FAIL: circle rejection test produced no result");
        $finish;
    end
    if (frame_index > 7) begin
        $display("FAIL: parallel circle rejection exceeded latency budget");
        $finish;
    end
    $display("PASS: four-lane Hough detector rejected a circle");
    $finish;
end

endmodule
