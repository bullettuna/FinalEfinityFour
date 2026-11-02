`timescale 1ns/1ps

// End-to-end timing regression for the implemented overlay path. It verifies
// that the median/Sobel timing and the delayed RGB timing remain cycle-exact,
// and that two cascaded 3x3 stages preserve frame width and frame isolation.
module vision_overlay_pipeline_tb;

localparam [13:0] WIDTH  = 14'd8;
localparam [13:0] HEIGHT = 14'd6;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_vsync = 1'b0;
reg in_href = 1'b0;
reg in_hsync = 1'b0;
reg [7:0] in_pixel = 8'd0;
reg [10:0] threshold = 11'd2047;

wire median_vsync, median_href, median_hsync;
wire [7:0] median_pixel;
wire median_rgb_vsync, median_rgb_href, median_rgb_hsync;
wire [7:0] median_r, median_g, median_b;
wire edge_vsync, edge_href, edge_hsync;
wire [7:0] edge_pixel;
wire edge_rgb_vsync, edge_rgb_href, edge_rgb_hsync;
wire [7:0] edge_r, edge_g, edge_b;
wire out_vsync, out_href, out_hsync;
wire [7:0] out_r, out_g, out_b;

always #5 clk = ~clk;

median3x3_filter #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_median (
    .clk(clk), .rst_n(rst_n), .median_enable(1'b1),
    .per_frame_vsync(in_vsync), .per_frame_href(in_href),
    .per_frame_hsync(in_hsync), .per_img_gray(in_pixel),
    .post_frame_vsync(median_vsync), .post_frame_href(median_href),
    .post_frame_hsync(median_hsync), .post_img_gray(median_pixel)
);

rgb_window_delay #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_median_rgb (
    .clk(clk), .rst_n(rst_n), .delay_enable(1'b1),
    .per_frame_vsync(in_vsync), .per_frame_href(in_href),
    .per_frame_hsync(in_hsync), .per_img_red(in_pixel),
    .per_img_green(in_pixel), .per_img_blue(in_pixel),
    .post_frame_vsync(median_rgb_vsync), .post_frame_href(median_rgb_href),
    .post_frame_hsync(median_rgb_hsync), .post_img_red(median_r),
    .post_img_green(median_g), .post_img_blue(median_b)
);

sobel_edge #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_sobel (
    .clk(clk), .rst_n(rst_n), .per_frame_vsync(median_vsync),
    .per_frame_href(median_href), .per_frame_hsync(median_hsync),
    .per_img_gray(median_pixel), .edge_threshold(threshold),
    .post_frame_vsync(edge_vsync), .post_frame_href(edge_href),
    .post_frame_hsync(edge_hsync), .post_img_edge(edge_pixel)
);

rgb_window_delay #(.IMG_HDISP(WIDTH), .IMG_VDISP(HEIGHT)) u_sobel_rgb (
    .clk(clk), .rst_n(rst_n), .delay_enable(1'b1),
    .per_frame_vsync(median_rgb_vsync), .per_frame_href(median_rgb_href),
    .per_frame_hsync(median_rgb_hsync), .per_img_red(median_r),
    .per_img_green(median_g), .per_img_blue(median_b),
    .post_frame_vsync(edge_rgb_vsync), .post_frame_href(edge_rgb_href),
    .post_frame_hsync(edge_rgb_hsync), .post_img_red(edge_r),
    .post_img_green(edge_g), .post_img_blue(edge_b)
);

color_edge_overlay u_overlay (
    .overlay_enable(1'b1), .per_frame_vsync(edge_rgb_vsync),
    .per_frame_href(edge_rgb_href), .per_frame_hsync(edge_rgb_hsync),
    .per_img_red(edge_r), .per_img_green(edge_g), .per_img_blue(edge_b),
    .per_img_edge(edge_pixel), .edge_color_red(8'hff),
    .edge_color_green(8'h00), .edge_color_blue(8'h00),
    .post_frame_vsync(out_vsync), .post_frame_href(out_href),
    .post_frame_hsync(out_hsync), .post_img_red(out_r),
    .post_img_green(out_g), .post_img_blue(out_b)
);

integer row;
integer col;
integer frame;
integer out_row = 0;
integer out_col = 0;
integer checked_pixels = 0;
integer checked_lines = 0;
integer errors = 0;
reg out_href_d = 1'b0;
reg [7:0] expected_pixel;

function [7:0] pixel_at;
    input integer pixel_row;
    input integer pixel_col;
    begin
        pixel_at = {pixel_row[3:0], pixel_col[3:0]};
    end
endfunction

always @(posedge clk) begin
    #1;
    if (rst_n) begin
        if ((median_vsync !== median_rgb_vsync) ||
            (median_href !== median_rgb_href) ||
            (median_hsync !== median_rgb_hsync)) begin
            errors = errors + 1;
            $display("FAIL median RGB timing mismatch at %0t", $time);
        end
        if ((edge_vsync !== edge_rgb_vsync) ||
            (edge_href !== edge_rgb_href) ||
            (edge_hsync !== edge_rgb_hsync)) begin
            errors = errors + 1;
            $display("FAIL Sobel RGB timing mismatch at %0t", $time);
        end
    end

    if (!rst_n || !out_vsync) begin
        out_row = 0;
        out_col = 0;
        out_href_d = 1'b0;
    end else begin
        if (out_href) begin
            expected_pixel = pixel_at((out_row < 2) ? 0 : out_row - 2, out_col);
            if ((edge_pixel !== 8'h00) ||
                (out_r !== expected_pixel) ||
                (out_g !== expected_pixel) ||
                (out_b !== expected_pixel)) begin
                errors = errors + 1;
                $display("FAIL overlay row=%0d col=%0d edge=%02x rgb=%02x%02x%02x expected=%02x",
                         out_row, out_col, edge_pixel, out_r, out_g, out_b,
                         expected_pixel);
            end
            checked_pixels = checked_pixels + 1;
            out_col = out_col + 1;
        end
        if (out_href_d && !out_href) begin
            if (out_col != WIDTH) begin
                errors = errors + 1;
                $display("FAIL overlay row=%0d width=%0d expected=%0d",
                         out_row, out_col, WIDTH);
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

    for (frame = 0; frame < 2; frame = frame + 1) begin
        in_vsync = 1'b1;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            in_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                in_pixel = pixel_at(row, col);
                @(negedge clk);
            end
            in_href = 1'b0;
            in_hsync = 1'b1;
            repeat (24) @(negedge clk);
            in_hsync = 1'b0;
        end
        in_vsync = 1'b0;
        repeat (40) @(negedge clk);
    end

    repeat (40) @(posedge clk);
    if ((errors == 0) &&
        (checked_pixels == 2 * WIDTH * HEIGHT) &&
        (checked_lines == 2 * HEIGHT))
        $display("PASS overlay pipeline: pixels=%0d lines=%0d", checked_pixels, checked_lines);
    else
        $display("FAIL overlay pipeline: errors=%0d pixels=%0d lines=%0d",
                 errors, checked_pixels, checked_lines);
    $finish;
end

endmodule
