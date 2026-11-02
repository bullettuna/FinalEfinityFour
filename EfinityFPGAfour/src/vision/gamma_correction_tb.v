`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking bypass, LUT-value and timing testbench for gamma_correction.
//////////////////////////////////////////////////////////////////////////////////

module gamma_correction_tb;

reg clk;
reg rst_n;
reg gamma_enable;
reg [8:0] gamma_strength;
reg per_frame_vsync;
reg per_frame_href;
reg per_frame_hsync;
reg [7:0] per_img_red;
reg [7:0] per_img_green;
reg [7:0] per_img_blue;

wire post_frame_vsync;
wire post_frame_href;
wire post_frame_hsync;
wire [7:0] post_img_red;
wire [7:0] post_img_green;
wire [7:0] post_img_blue;

gamma_correction dut (
    .clk(clk),
    .rst_n(rst_n),
    .gamma_enable(gamma_enable),
    .gamma_strength(gamma_strength),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href(per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_red(per_img_red),
    .per_img_green(per_img_green),
    .per_img_blue(per_img_blue),
    .post_frame_vsync(post_frame_vsync),
    .post_frame_href(post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_red(post_img_red),
    .post_img_green(post_img_green),
    .post_img_blue(post_img_blue)
);

always #5 clk = ~clk;

task drive_and_check;
    input enable;
    input [8:0] strength;
    input [7:0] r;
    input [7:0] g;
    input [7:0] b;
    input [7:0] expected_r;
    input [7:0] expected_g;
    input [7:0] expected_b;
    begin
        @(negedge clk);
        gamma_enable = enable;
        gamma_strength = strength;
        per_img_red = r;
        per_img_green = g;
        per_img_blue = b;
        per_frame_vsync = 1'b1;
        per_frame_href = 1'b1;
        per_frame_hsync = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if ((post_img_red !== expected_r) ||
            (post_img_green !== expected_g) ||
            (post_img_blue !== expected_b) ||
            (post_frame_vsync !== 1'b1) ||
            (post_frame_href !== 1'b1) ||
            (post_frame_hsync !== 1'b0)) begin
            $display("FAIL enable=%b strength=%0d input=%0d/%0d/%0d expected=%0d/%0d/%0d got=%0d/%0d/%0d",
                     enable, strength, r, g, b, expected_r, expected_g, expected_b,
                     post_img_red, post_img_green, post_img_blue);
            $finish;
        end
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    gamma_enable = 1'b0;
    gamma_strength = 9'd0;
    per_frame_vsync = 1'b0;
    per_frame_href = 1'b0;
    per_frame_hsync = 1'b0;
    per_img_red = 8'd0;
    per_img_green = 8'd0;
    per_img_blue = 8'd0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    drive_and_check(1'b0, 9'd256, 8'd16, 8'd64, 8'd128, 8'd16, 8'd64, 8'd128);
    drive_and_check(1'b1, 9'd0,   8'd16, 8'd64, 8'd128, 8'd16, 8'd64, 8'd128);
    drive_and_check(1'b1, 9'd64,  8'd16, 8'd64, 8'd128, 8'd30, 8'd82, 8'd143);
    drive_and_check(1'b1, 9'd128, 8'd1,  8'd4,  8'd192, 8'd11, 8'd22, 8'd208);
    drive_and_check(1'b1, 9'd256, 8'd16, 8'd64, 8'd128, 8'd72, 8'd136, 8'd186);

    $display("RESULT: ALL GAMMA TESTS PASSED");
    $finish;
end

endmodule
