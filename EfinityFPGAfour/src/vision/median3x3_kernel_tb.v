`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking testbench for median3x3_kernel.
// Run with a Verilog-2001 simulator, for example:
//   iverilog -g2001 -s median3x3_kernel_tb -o median3x3_kernel_tb.vvp \
//       median3x3_sort3.v median3x3_kernel.v median3x3_kernel_tb.v
//   vvp median3x3_kernel_tb.vvp
//////////////////////////////////////////////////////////////////////////////////

module median3x3_kernel_tb;

reg clk;
reg rst_n;
reg in_frame_vsync;
reg in_frame_href;
reg in_frame_hsync;
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;

wire out_frame_vsync;
wire out_frame_href;
wire out_frame_hsync;
wire [7:0] out_img_median;

median3x3_kernel u_dut (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(in_frame_vsync),
    .in_frame_href(in_frame_href),
    .in_frame_hsync(in_frame_hsync),
    .p11(p11), .p12(p12), .p13(p13),
    .p21(p21), .p22(p22), .p23(p23),
    .p31(p31), .p32(p32), .p33(p33),
    .out_frame_vsync(out_frame_vsync),
    .out_frame_href(out_frame_href),
    .out_frame_hsync(out_frame_hsync),
    .out_img_median(out_img_median)
);

always #5 clk = ~clk;

function [7:0] reference_median9;
    input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
    reg [7:0] values [0:8];
    reg [7:0] temporary;
    integer i;
    integer j;
    begin
        values[0] = v0; values[1] = v1; values[2] = v2;
        values[3] = v3; values[4] = v4; values[5] = v5;
        values[6] = v6; values[7] = v7; values[8] = v8;
        for (i = 0; i < 8; i = i + 1) begin
            for (j = i + 1; j < 9; j = j + 1) begin
                if (values[i] > values[j]) begin
                    temporary = values[i];
                    values[i] = values[j];
                    values[j] = temporary;
                end
            end
        end
        reference_median9 = values[4];
    end
endfunction

reg [7:0] expected_pixel_d1, expected_pixel_d2, expected_pixel_d3;
reg expected_vsync_d1, expected_vsync_d2, expected_vsync_d3;
reg expected_href_d1, expected_href_d2, expected_href_d3;
reg expected_hsync_d1, expected_hsync_d2, expected_hsync_d3;
integer error_count;
integer check_count;
integer test_index;
reg [31:0] lfsr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        expected_pixel_d1 <= 8'd0;
        expected_pixel_d2 <= 8'd0;
        expected_pixel_d3 <= 8'd0;
        expected_vsync_d1 <= 1'b0;
        expected_vsync_d2 <= 1'b0;
        expected_vsync_d3 <= 1'b0;
        expected_href_d1  <= 1'b0;
        expected_href_d2  <= 1'b0;
        expected_href_d3  <= 1'b0;
        expected_hsync_d1 <= 1'b0;
        expected_hsync_d2 <= 1'b0;
        expected_hsync_d3 <= 1'b0;
    end else begin
        expected_pixel_d1 <= reference_median9(
            p11, p12, p13, p21, p22, p23, p31, p32, p33);
        expected_pixel_d2 <= expected_pixel_d1;
        expected_pixel_d3 <= expected_pixel_d2;
        expected_vsync_d1 <= in_frame_vsync;
        expected_vsync_d2 <= expected_vsync_d1;
        expected_vsync_d3 <= expected_vsync_d2;
        expected_href_d1  <= in_frame_href;
        expected_href_d2  <= expected_href_d1;
        expected_href_d3  <= expected_href_d2;
        expected_hsync_d1 <= in_frame_hsync;
        expected_hsync_d2 <= expected_hsync_d1;
        expected_hsync_d3 <= expected_hsync_d2;
    end

    #1;
    if (rst_n) begin
        check_count = check_count + 1;
        if ((out_frame_vsync !== expected_vsync_d3) ||
            (out_frame_href !== expected_href_d3) ||
            (out_frame_hsync !== expected_hsync_d3) ||
            (out_img_median !== (expected_href_d3 ? expected_pixel_d3 : 8'd0))) begin
            $display("FAIL check=%0d expected pixel/sync=%0d/%b%b%b got=%0d/%b%b%b",
                     check_count, expected_pixel_d3, expected_vsync_d3,
                     expected_href_d3, expected_hsync_d3, out_img_median,
                     out_frame_vsync, out_frame_href, out_frame_hsync);
            error_count = error_count + 1;
        end
    end
end

task drive_window;
    input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
    input href;
    begin
        @(negedge clk);
        p11 = v0; p12 = v1; p13 = v2;
        p21 = v3; p22 = v4; p23 = v5;
        p31 = v6; p32 = v7; p33 = v8;
        in_frame_vsync = test_index[0];
        in_frame_href  = href;
        in_frame_hsync = test_index[1];
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    in_frame_vsync = 1'b0;
    in_frame_href = 1'b0;
    in_frame_hsync = 1'b0;
    p11 = 0; p12 = 0; p13 = 0;
    p21 = 0; p22 = 0; p23 = 0;
    p31 = 0; p32 = 0; p33 = 0;
    error_count = 0;
    check_count = 0;
    test_index = 0;
    lfsr = 32'h41C6_4E6D;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    drive_window(9, 8, 7, 6, 5, 4, 3, 2, 1, 1'b1);
    test_index = test_index + 1;
    drive_window(0, 0, 0, 255, 255, 255, 10, 20, 30, 1'b1);
    test_index = test_index + 1;
    drive_window(17, 17, 17, 17, 17, 17, 17, 17, 17, 1'b1);
    test_index = test_index + 1;
    drive_window(0, 255, 0, 255, 128, 255, 0, 255, 0, 1'b1);
    test_index = test_index + 1;

    for (test_index = 0; test_index < 4096; test_index = test_index + 1) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        drive_window(lfsr[7:0], lfsr[15:8], lfsr[23:16], lfsr[31:24],
                     lfsr[11:4], lfsr[19:12], lfsr[27:20],
                     {lfsr[3:0], lfsr[31:28]}, {lfsr[5:0], lfsr[31:30]},
                     (test_index % 11) != 0);
    end

    repeat (8) drive_window(0, 0, 0, 0, 0, 0, 0, 0, 0, 1'b0);

    if (error_count == 0)
        $display("PASS median3x3_kernel: %0d checks", check_count);
    else
        $display("FAIL median3x3_kernel: %0d errors", error_count);
    $finish;
end

endmodule
