`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking arithmetic and timing testbench for rgb_white_balance.
//////////////////////////////////////////////////////////////////////////////////

module rgb_white_balance_tb;

reg clk;
reg rst_n;
reg per_frame_vsync;
reg per_frame_href;
reg per_frame_hsync;
reg [7:0] per_img_red;
reg [7:0] per_img_green;
reg [7:0] per_img_blue;
reg [10:0] red_gain;
reg [10:0] green_gain;
reg [10:0] blue_gain;

wire post_frame_vsync;
wire post_frame_href;
wire post_frame_hsync;
wire [7:0] post_img_red;
wire [7:0] post_img_green;
wire [7:0] post_img_blue;

rgb_white_balance dut (
    .clk(clk),
    .rst_n(rst_n),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href(per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_red(per_img_red),
    .per_img_green(per_img_green),
    .per_img_blue(per_img_blue),
    .red_gain(red_gain),
    .green_gain(green_gain),
    .blue_gain(blue_gain),
    .post_frame_vsync(post_frame_vsync),
    .post_frame_href(post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_red(post_img_red),
    .post_img_green(post_img_green),
    .post_img_blue(post_img_blue)
);

always #5 clk = ~clk;

function [7:0] reference_gain;
    input [7:0] pixel;
    input [10:0] gain;
    reg [18:0] scaled;
    begin
        scaled = pixel * gain + 19'd128;
        if (scaled[18:8] > 11'd255)
            reference_gain = 8'hFF;
        else
            reference_gain = scaled[15:8];
    end
endfunction

reg [7:0] expected_red_d1;
reg [7:0] expected_green_d1;
reg [7:0] expected_blue_d1;
reg [7:0] expected_red_d2;
reg [7:0] expected_green_d2;
reg [7:0] expected_blue_d2;
reg expected_vsync_d1;
reg expected_href_d1;
reg expected_hsync_d1;
reg expected_vsync_d2;
reg expected_href_d2;
reg expected_hsync_d2;
reg expected_valid_d1;
reg expected_valid_d2;
integer error_count;
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        expected_red_d1   <= 8'd0;
        expected_green_d1 <= 8'd0;
        expected_blue_d1  <= 8'd0;
        expected_red_d2   <= 8'd0;
        expected_green_d2 <= 8'd0;
        expected_blue_d2  <= 8'd0;
        expected_vsync_d1 <= 1'b0;
        expected_href_d1  <= 1'b0;
        expected_hsync_d1 <= 1'b0;
        expected_vsync_d2 <= 1'b0;
        expected_href_d2  <= 1'b0;
        expected_hsync_d2 <= 1'b0;
        expected_valid_d1 <= 1'b0;
        expected_valid_d2 <= 1'b0;
    end else begin
        expected_red_d1   <= reference_gain(per_img_red, red_gain);
        expected_green_d1 <= reference_gain(per_img_green, green_gain);
        expected_blue_d1  <= reference_gain(per_img_blue, blue_gain);
        expected_vsync_d1 <= per_frame_vsync;
        expected_href_d1  <= per_frame_href;
        expected_hsync_d1 <= per_frame_hsync;
        expected_valid_d1 <= 1'b1;

        expected_red_d2   <= expected_red_d1;
        expected_green_d2 <= expected_green_d1;
        expected_blue_d2  <= expected_blue_d1;
        expected_vsync_d2 <= expected_vsync_d1;
        expected_href_d2  <= expected_href_d1;
        expected_hsync_d2 <= expected_hsync_d1;
        expected_valid_d2 <= expected_valid_d1;
    end

    #1;
    if (rst_n && expected_valid_d2) begin
        if ((post_img_red !== expected_red_d2) ||
            (post_img_green !== expected_green_d2) ||
            (post_img_blue !== expected_blue_d2) ||
            (post_frame_vsync !== expected_vsync_d2) ||
            (post_frame_href !== expected_href_d2) ||
            (post_frame_hsync !== expected_hsync_d2)) begin
            $display("FAIL expected RGB=%0d/%0d/%0d sync=%b%b%b, got RGB=%0d/%0d/%0d sync=%b%b%b",
                     expected_red_d2, expected_green_d2, expected_blue_d2,
                     expected_vsync_d2, expected_href_d2, expected_hsync_d2,
                     post_img_red, post_img_green, post_img_blue,
                     post_frame_vsync, post_frame_href, post_frame_hsync);
            error_count = error_count + 1;
        end
    end
end

task drive_pixel;
    input [7:0] r;
    input [7:0] g;
    input [7:0] b;
    input [10:0] rg;
    input [10:0] gg;
    input [10:0] bg;
    begin
        @(negedge clk);
        per_img_red = r;
        per_img_green = g;
        per_img_blue = b;
        red_gain = rg;
        green_gain = gg;
        blue_gain = bg;
        per_frame_vsync = 1'b1;
        per_frame_href = 1'b1;
        per_frame_hsync = 1'b0;
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    per_frame_vsync = 1'b0;
    per_frame_href = 1'b0;
    per_frame_hsync = 1'b0;
    per_img_red = 8'd0;
    per_img_green = 8'd0;
    per_img_blue = 8'd0;
    red_gain = 11'd256;
    green_gain = 11'd256;
    blue_gain = 11'd256;
    error_count = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    drive_pixel(8'd0, 8'd0, 8'd0, 11'd256, 11'd256, 11'd256);
    drive_pixel(8'd255, 8'd128, 8'd1, 11'd256, 11'd256, 11'd256);
    drive_pixel(8'd100, 8'd100, 8'd100, 11'd384, 11'd256, 11'd224);
    drive_pixel(8'd200, 8'd200, 8'd200, 11'd512, 11'd512, 11'd512);

    for (i = 0; i < 256; i = i + 1)
        drive_pixel(i[7:0], (255-i), (i*3), 11'd384, 11'd256, 11'd224);

    repeat (4) @(posedge clk);
    if (error_count == 0)
        $display("RESULT: ALL WHITE-BALANCE TESTS PASSED");
    else
        $display("RESULT: FAILED, errors=%0d", error_count);
    $finish;
end

endmodule
