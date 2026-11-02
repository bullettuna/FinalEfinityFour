`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking testbench for the pipelined Sobel arithmetic and timing path.
// The line-window generator is already exercised by the working Bayer pipeline;
// this test isolates the new signed arithmetic, threshold and sync alignment.
//////////////////////////////////////////////////////////////////////////////////

module sobel_edge_tb;

reg clk;
reg rst_n;
reg in_frame_vsync;
reg in_frame_href;
reg in_frame_hsync;
reg [7:0] p11, p12, p13;
reg [7:0] p21, p22, p23;
reg [7:0] p31, p32, p33;
reg [10:0] edge_threshold;

wire out_frame_vsync;
wire out_frame_href;
wire out_frame_hsync;
wire [7:0] out_img_edge;

sobel_kernel_3x3 u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_frame_vsync  (in_frame_vsync),
    .in_frame_href   (in_frame_href),
    .in_frame_hsync  (in_frame_hsync),
    .p11             (p11),
    .p12             (p12),
    .p13             (p13),
    .p21             (p21),
    .p22             (p22),
    .p23             (p23),
    .p31             (p31),
    .p32             (p32),
    .p33             (p33),
    .edge_threshold  (edge_threshold),
    .out_frame_vsync (out_frame_vsync),
    .out_frame_href  (out_frame_href),
    .out_frame_hsync (out_frame_hsync),
    .out_img_edge    (out_img_edge)
);

always #5 clk = ~clk;

function [7:0] ref_edge;
    input [7:0] q11, q12, q13;
    input [7:0] q21, q22, q23;
    input [7:0] q31, q32, q33;
    input [10:0] threshold;
    integer gx;
    integer gy;
    integer magnitude;
    begin
        gx = (q13 + 2*q23 + q33) - (q11 + 2*q21 + q31);
        gy = (q11 + 2*q12 + q13) - (q31 + 2*q32 + q33);
        if (gx < 0) gx = -gx;
        if (gy < 0) gy = -gy;
        magnitude = gx + gy;
        ref_edge = (magnitude > threshold) ? 8'hFF : 8'h00;
    end
endfunction

reg [7:0] exp_edge_d0, exp_edge_d1, exp_edge_d2;
reg       exp_vs_d0, exp_vs_d1, exp_vs_d2;
reg       exp_href_d0, exp_href_d1, exp_href_d2;
reg       exp_hs_d0, exp_hs_d1, exp_hs_d2;
reg       exp_valid_d0, exp_valid_d1, exp_valid_d2;
integer   error_count;
integer   check_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        exp_edge_d0 <= 8'd0;
        exp_edge_d1 <= 8'd0;
        exp_edge_d2 <= 8'd0;
        exp_vs_d0 <= 1'b0;
        exp_vs_d1 <= 1'b0;
        exp_vs_d2 <= 1'b0;
        exp_href_d0 <= 1'b0;
        exp_href_d1 <= 1'b0;
        exp_href_d2 <= 1'b0;
        exp_hs_d0 <= 1'b0;
        exp_hs_d1 <= 1'b0;
        exp_hs_d2 <= 1'b0;
        exp_valid_d0 <= 1'b0;
        exp_valid_d1 <= 1'b0;
        exp_valid_d2 <= 1'b0;
    end else begin
        exp_edge_d0 <= in_frame_href ?
            ref_edge(p11,p12,p13,p21,p22,p23,p31,p32,p33,edge_threshold) : 8'd0;
        exp_edge_d1 <= exp_edge_d0;
        exp_edge_d2 <= exp_edge_d1;
        exp_vs_d0 <= in_frame_vsync;
        exp_vs_d1 <= exp_vs_d0;
        exp_vs_d2 <= exp_vs_d1;
        exp_href_d0 <= in_frame_href;
        exp_href_d1 <= exp_href_d0;
        exp_href_d2 <= exp_href_d1;
        exp_hs_d0 <= in_frame_hsync;
        exp_hs_d1 <= exp_hs_d0;
        exp_hs_d2 <= exp_hs_d1;
        exp_valid_d0 <= 1'b1;
        exp_valid_d1 <= exp_valid_d0;
        exp_valid_d2 <= exp_valid_d1;
    end

    #1;
    if (!rst_n) begin
        if ((out_img_edge !== 8'd0) || out_frame_vsync ||
            out_frame_href || out_frame_hsync) begin
            $display("FAIL reset output is not zero at time %0t", $time);
            error_count = error_count + 1;
        end
    end else if (exp_valid_d2) begin
        check_count = check_count + 1;
        if ((out_img_edge !== exp_edge_d2) ||
            (out_frame_vsync !== exp_vs_d2) ||
            (out_frame_href !== exp_href_d2) ||
            (out_frame_hsync !== exp_hs_d2)) begin
            $display("FAIL sample=%0d exp edge/sync=%02x/%b%b%b got=%02x/%b%b%b",
                     check_count, exp_edge_d2, exp_vs_d2, exp_href_d2, exp_hs_d2,
                     out_img_edge, out_frame_vsync, out_frame_href, out_frame_hsync);
            error_count = error_count + 1;
        end
    end
end

task drive_window;
    input [7:0] q11, q12, q13;
    input [7:0] q21, q22, q23;
    input [7:0] q31, q32, q33;
    input       qvs, qhref, qhs;
    input [10:0] threshold;
    begin
        @(negedge clk);
        p11=q11; p12=q12; p13=q13;
        p21=q21; p22=q22; p23=q23;
        p31=q31; p32=q32; p33=q33;
        in_frame_vsync=qvs;
        in_frame_href=qhref;
        in_frame_hsync=qhs;
        edge_threshold=threshold;
    end
endtask

integer i;
reg [31:0] lfsr;

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    in_frame_vsync = 1'b0;
    in_frame_href = 1'b0;
    in_frame_hsync = 1'b0;
    p11=0; p12=0; p13=0;
    p21=0; p22=0; p23=0;
    p31=0; p32=0; p33=0;
    edge_threshold = 11'd160;
    error_count = 0;
    check_count = 0;
    lfsr = 32'h51A7_2E9B;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    $display("Test 1: flat and canonical edges");
    drive_window(100,100,100, 100,100,100, 100,100,100, 1,1,0, 160);
    drive_window(0,0,255, 0,0,255, 0,0,255, 1,1,0, 160);
    drive_window(255,255,255, 0,0,0, 0,0,0, 1,1,0, 160);
    drive_window(0,0,10, 0,0,10, 0,0,10, 1,1,0, 160);

    $display("Test 2: threshold and blanking behavior");
    drive_window(0,0,255, 0,0,255, 0,0,255, 1,1,0, 11'd1020);
    drive_window(0,0,255, 0,0,255, 0,0,255, 1,1,0, 11'd1019);
    drive_window(0,0,255, 0,0,255, 0,0,255, 0,0,1, 11'd0);

    $display("Test 3: deterministic random windows and sync patterns");
    for (i = 0; i < 1024; i = i + 1) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        drive_window(lfsr[7:0], lfsr[15:8], lfsr[23:16],
                     lfsr[31:24], lfsr[11:4], lfsr[19:12],
                     lfsr[27:20], lfsr[9:2], lfsr[25:18],
                     lfsr[29], lfsr[28], lfsr[27], {3'd0,lfsr[7:0]});
    end

    // Flush the expected/DUT pipelines.
    repeat (4)
        drive_window(0,0,0, 0,0,0, 0,0,0, 0,0,0, 160);
    repeat (2) @(posedge clk);
    @(negedge clk);

    $display("----------------------------------------");
    $display("Checked samples: %0d", check_count);
    if (error_count == 0)
        $display("RESULT: ALL TESTS PASSED");
    else
        $display("RESULT: FAILED, errors=%0d", error_count);
    $display("----------------------------------------");
    $finish;
end

endmodule
