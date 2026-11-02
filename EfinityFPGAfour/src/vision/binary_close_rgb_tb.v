`timescale 1ns/1ps

// Verifies that the RGB sideband follows the exact center pixel through both
// 3x3 stages of the close operation.
module binary_close_rgb_tb;

localparam [13:0] WIDTH  = 14'd8;
localparam [13:0] HEIGHT = 14'd6;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_vsync = 1'b0;
reg in_href = 1'b0;
reg in_hsync = 1'b0;
reg in_mask = 1'b0;
reg [7:0] in_red = 8'd0;
reg [7:0] in_green = 8'd0;
reg [7:0] in_blue = 8'd0;
always #5 clk = ~clk;

wire out_vsync;
wire out_href;
wire out_hsync;
wire out_mask;
wire out_edge;
wire [1:0] out_direction;
wire [7:0] out_red;
wire [7:0] out_green;
wire [7:0] out_blue;

binary_close3x3 #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_close (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(in_vsync),
    .per_frame_href(in_href),
    .per_frame_hsync(in_hsync),
    .per_img_mask(in_mask),
    .per_img_edge(in_mask),
    .per_img_direction(2'd0),
    .per_img_red(in_red),
    .per_img_green(in_green),
    .per_img_blue(in_blue),
    .post_frame_vsync(out_vsync),
    .post_frame_href(out_href),
    .post_frame_hsync(out_hsync),
    .post_img_mask(out_mask),
    .post_img_edge(out_edge),
    .post_img_direction(out_direction),
    .post_img_red(out_red),
    .post_img_green(out_green),
    .post_img_blue(out_blue)
);

integer row;
integer col;
integer out_row = 0;
integer out_col = 0;
integer checked_pixels = 0;
integer checked_lines = 0;
integer errors = 0;
reg out_href_d = 1'b0;
reg [7:0] expected_red;
reg [7:0] expected_green;
reg [7:0] expected_blue;
reg expected_edge;

always @(posedge clk) begin
    #1;
    if (!rst_n || !out_vsync) begin
        out_row = 0;
        out_col = 0;
        out_href_d = 1'b0;
    end else begin
        if (out_href) begin
            expected_red = (out_row < 2) ? 8'd0 : out_row - 2;
            expected_green = out_col;
            expected_blue = expected_red ^ expected_green;
            expected_edge = (out_row == 5) &&
                            (out_col >= 2) && (out_col <= 5);
            if ((out_edge !== expected_edge) || (out_red !== expected_red) ||
                (out_green !== expected_green) ||
                (out_blue !== expected_blue)) begin
                errors = errors + 1;
                $display("FAIL close RGB row=%0d col=%0d mask=%0d rgb=%02x%02x%02x expected=%02x%02x%02x",
                         out_row, out_col, out_mask,
                         out_red, out_green, out_blue,
                         expected_red, expected_green, expected_blue);
            end
            if (expected_edge && (out_direction !== 2'd0)) begin
                errors = errors + 1;
                $display("FAIL horizontal direction row=%0d col=%0d dir=%0d",
                         out_row, out_col, out_direction);
            end
            checked_pixels = checked_pixels + 1;
            out_col = out_col + 1;
        end
        if (out_href_d && !out_href) begin
            if (out_col != WIDTH) begin
                errors = errors + 1;
                $display("FAIL close line width=%0d expected=%0d", out_col, WIDTH);
            end
            checked_lines = checked_lines + 1;
            out_col = 0;
            out_row = out_row + 1;
        end
        out_href_d = out_href;
    end
end

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    in_vsync = 1'b1;

    for (row = 0; row < HEIGHT; row = row + 1) begin
        in_href = 1'b1;
        for (col = 0; col < WIDTH; col = col + 1) begin
            in_mask = (row == 3) && (col >= 2) && (col <= 5);
            in_red = row;
            in_green = col;
            in_blue = row ^ col;
            @(negedge clk);
        end
        in_href = 1'b0;
        in_hsync = 1'b1;
        repeat (24) @(negedge clk);
        in_hsync = 1'b0;
    end

    in_vsync = 1'b0;
    repeat (40) @(posedge clk);
    if ((errors == 0) && (checked_pixels == WIDTH * HEIGHT) &&
        (checked_lines == HEIGHT))
        $display("PASS close RGB alignment: pixels=%0d lines=%0d",
                 checked_pixels, checked_lines);
    else
        $display("FAIL close RGB alignment: errors=%0d pixels=%0d lines=%0d",
                 errors, checked_pixels, checked_lines);
    $finish;
end

endmodule
