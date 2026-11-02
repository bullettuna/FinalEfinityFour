`timescale 1ns/1ps

// End-to-end check for the four-bin tangent estimator carried through close.
module binary_direction_tb;

localparam [13:0] WIDTH  = 14'd32;
localparam [13:0] HEIGHT = 14'd24;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_vsync = 1'b0;
reg in_href = 1'b0;
reg in_hsync = 1'b0;
reg in_edge = 1'b0;
always #5 clk = ~clk;

wire out_vsync;
wire out_href;
wire out_hsync;
wire out_mask;
wire out_edge;
wire [1:0] out_direction;
wire [7:0] out_red, out_green, out_blue;

binary_close3x3 #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_close (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(in_vsync), .per_frame_href(in_href),
    .per_frame_hsync(in_hsync), .per_img_mask(in_edge),
    .per_img_edge(in_edge), .per_img_direction(2'd0),
    .per_img_red(8'd0), .per_img_green(8'd0), .per_img_blue(8'd0),
    .post_frame_vsync(out_vsync), .post_frame_href(out_href),
    .post_frame_hsync(out_hsync), .post_img_mask(out_mask),
    .post_img_edge(out_edge), .post_img_direction(out_direction),
    .post_img_red(out_red), .post_img_green(out_green),
    .post_img_blue(out_blue)
);

integer direction_0;
integer direction_1;
integer direction_2;
integer direction_3;
integer errors = 0;
integer row;
integer col;

always @(posedge clk) begin
    if (!rst_n || !out_vsync) begin
        direction_0 = 0;
        direction_1 = 0;
        direction_2 = 0;
        direction_3 = 0;
    end else if (out_href && out_edge) begin
        case (out_direction)
            2'd0: direction_0 = direction_0 + 1;
            2'd1: direction_1 = direction_1 + 1;
            2'd2: direction_2 = direction_2 + 1;
            default: direction_3 = direction_3 + 1;
        endcase
    end
end

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

function diamond_pixel;
    input integer pixel_row;
    input integer pixel_col;
    integer distance;
    begin
        distance = ((pixel_row >= 12) ? pixel_row - 12 : 12 - pixel_row) +
                   ((pixel_col >= 16) ? pixel_col - 16 : 16 - pixel_col);
        diamond_pixel = (distance == 10);
    end
endfunction

task send_frame;
    input integer shape_select;
    begin
        in_vsync = 1'b1;
        repeat (2) @(negedge clk);
        for (row = 0; row < HEIGHT; row = row + 1) begin
            in_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                case (shape_select)
                    1: in_edge = circle_pixel(row, col);
                    2: in_edge = diamond_pixel(row, col);
                    default: in_edge = rectangle_pixel(row, col);
                endcase
                @(negedge clk);
            end
            in_href = 1'b0;
            in_edge = 1'b0;
            in_hsync = 1'b1;
            repeat (12) @(negedge clk);
            in_hsync = 1'b0;
        end
        in_vsync = 1'b0;
        if (!out_vsync)
            @(posedge out_vsync);
        @(negedge out_vsync);
        @(negedge clk);
    end
endtask

task check_two_dominant;
    input [127:0] shape_name;
    integer hi01, lo01, hi23, lo23, top1, top2a, top2b, top2, total;
    begin
        hi01 = (direction_0 >= direction_1) ? direction_0 : direction_1;
        lo01 = (direction_0 >= direction_1) ? direction_1 : direction_0;
        hi23 = (direction_2 >= direction_3) ? direction_2 : direction_3;
        lo23 = (direction_2 >= direction_3) ? direction_3 : direction_2;
        top1 = (hi01 >= hi23) ? hi01 : hi23;
        top2a = (hi01 >= hi23) ? hi23 : hi01;
        top2b = (lo01 >= lo23) ? lo01 : lo23;
        top2 = (top2a >= top2b) ? top2a : top2b;
        total = direction_0 + direction_1 + direction_2 + direction_3;
        if ((total == 0) || ((top1 + top2) * 32 < total * 31)) begin
            errors = errors + 1;
            $display("FAIL %0s directions=%0d/%0d/%0d/%0d",
                     shape_name, direction_0, direction_1,
                     direction_2, direction_3);
        end
    end
endtask

task check_circle_distribution;
    integer hi01, lo01, hi23, lo23, top1, top2a, top2b, top2, total;
    begin
        hi01 = (direction_0 >= direction_1) ? direction_0 : direction_1;
        lo01 = (direction_0 >= direction_1) ? direction_1 : direction_0;
        hi23 = (direction_2 >= direction_3) ? direction_2 : direction_3;
        lo23 = (direction_2 >= direction_3) ? direction_3 : direction_2;
        top1 = (hi01 >= hi23) ? hi01 : hi23;
        top2a = (hi01 >= hi23) ? hi23 : hi01;
        top2b = (lo01 >= lo23) ? lo01 : lo23;
        top2 = (top2a >= top2b) ? top2a : top2b;
        total = direction_0 + direction_1 + direction_2 + direction_3;
        if ((total == 0) || ((top1 + top2) * 32 >= total * 31) ||
            (direction_0 * 64 < total) || (direction_1 * 64 < total) ||
            (direction_2 * 64 < total) || (direction_3 * 64 < total)) begin
            errors = errors + 1;
            $display("FAIL circle directions=%0d/%0d/%0d/%0d",
                     direction_0, direction_1, direction_2, direction_3);
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    send_frame(0);
    check_two_dominant("axis rectangle");
    repeat (20) @(negedge clk);

    send_frame(1);
    check_circle_distribution();
    repeat (20) @(negedge clk);

    send_frame(2);
    check_two_dominant("rotated rectangle");

    if (errors == 0)
        $display("PASS binary tangent direction distributions");
    else
        $display("FAIL direction regression errors=%0d", errors);
    $finish;
end

endmodule
