`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Exact, three-stage-pipelined median of a 3x3 window.
//
// Reduction used here:
//   1. Sort each row into low/middle/high.
//   2. Keep max(row lows), median(row middles), min(row highs).
//   3. The median of those three candidates is the median of all nine pixels.
//
// One window is accepted and one result is produced on every clock.  Each
// arithmetic stage carries the video timing signals beside its pixel data.
//////////////////////////////////////////////////////////////////////////////////

module median3x3_kernel
(
    input               clk,
    input               rst_n,

    input               in_frame_vsync,
    input               in_frame_href,
    input               in_frame_hsync,
    input       [7:0]   p11, p12, p13,
    input       [7:0]   p21, p22, p23,
    input       [7:0]   p31, p32, p33,

    output reg          out_frame_vsync,
    output reg          out_frame_href,
    output reg          out_frame_hsync,
    output reg  [7:0]   out_img_median
);

// Stage 1: sort the three rows in parallel.
wire [7:0] row1_min_w, row1_mid_w, row1_max_w;
wire [7:0] row2_min_w, row2_mid_w, row2_max_w;
wire [7:0] row3_min_w, row3_mid_w, row3_max_w;

median3x3_sort3 u_sort_row1 (
    .value_a(p11), .value_b(p12), .value_c(p13),
    .value_min(row1_min_w), .value_mid(row1_mid_w), .value_max(row1_max_w)
);

median3x3_sort3 u_sort_row2 (
    .value_a(p21), .value_b(p22), .value_c(p23),
    .value_min(row2_min_w), .value_mid(row2_mid_w), .value_max(row2_max_w)
);

median3x3_sort3 u_sort_row3 (
    .value_a(p31), .value_b(p32), .value_c(p33),
    .value_min(row3_min_w), .value_mid(row3_mid_w), .value_max(row3_max_w)
);

reg [7:0] row1_min_s1, row1_mid_s1, row1_max_s1;
reg [7:0] row2_min_s1, row2_mid_s1, row2_max_s1;
reg [7:0] row3_min_s1, row3_mid_s1, row3_max_s1;
reg       vsync_s1, href_s1, hsync_s1;

// Stage 2: reduce nine values to the three candidates that can contain the
// global median.  Only the selected output of each sorter is registered.
wire [7:0] lows_min_unused, lows_mid_unused, max_of_lows_w;
wire [7:0] mids_min_unused, median_of_mids_w, mids_max_unused;
wire [7:0] min_of_highs_w, highs_mid_unused, highs_max_unused;

median3x3_sort3 u_sort_row_lows (
    .value_a(row1_min_s1), .value_b(row2_min_s1), .value_c(row3_min_s1),
    .value_min(lows_min_unused), .value_mid(lows_mid_unused),
    .value_max(max_of_lows_w)
);

median3x3_sort3 u_sort_row_middles (
    .value_a(row1_mid_s1), .value_b(row2_mid_s1), .value_c(row3_mid_s1),
    .value_min(mids_min_unused), .value_mid(median_of_mids_w),
    .value_max(mids_max_unused)
);

median3x3_sort3 u_sort_row_highs (
    .value_a(row1_max_s1), .value_b(row2_max_s1), .value_c(row3_max_s1),
    .value_min(min_of_highs_w), .value_mid(highs_mid_unused),
    .value_max(highs_max_unused)
);

reg [7:0] max_of_lows_s2;
reg [7:0] median_of_mids_s2;
reg [7:0] min_of_highs_s2;
reg       vsync_s2, href_s2, hsync_s2;

// Stage 3: choose the middle candidate.
wire [7:0] candidate_min_unused;
wire [7:0] final_median_w;
wire [7:0] candidate_max_unused;

median3x3_sort3 u_sort_candidates (
    .value_a(max_of_lows_s2),
    .value_b(median_of_mids_s2),
    .value_c(min_of_highs_s2),
    .value_min(candidate_min_unused),
    .value_mid(final_median_w),
    .value_max(candidate_max_unused)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        row1_min_s1      <= 8'd0;
        row1_mid_s1      <= 8'd0;
        row1_max_s1      <= 8'd0;
        row2_min_s1      <= 8'd0;
        row2_mid_s1      <= 8'd0;
        row2_max_s1      <= 8'd0;
        row3_min_s1      <= 8'd0;
        row3_mid_s1      <= 8'd0;
        row3_max_s1      <= 8'd0;
        vsync_s1         <= 1'b0;
        href_s1          <= 1'b0;
        hsync_s1         <= 1'b0;

        max_of_lows_s2   <= 8'd0;
        median_of_mids_s2 <= 8'd0;
        min_of_highs_s2  <= 8'd0;
        vsync_s2         <= 1'b0;
        href_s2          <= 1'b0;
        hsync_s2         <= 1'b0;

        out_frame_vsync  <= 1'b0;
        out_frame_href   <= 1'b0;
        out_frame_hsync  <= 1'b0;
        out_img_median   <= 8'd0;
    end else begin
        row1_min_s1 <= row1_min_w;
        row1_mid_s1 <= row1_mid_w;
        row1_max_s1 <= row1_max_w;
        row2_min_s1 <= row2_min_w;
        row2_mid_s1 <= row2_mid_w;
        row2_max_s1 <= row2_max_w;
        row3_min_s1 <= row3_min_w;
        row3_mid_s1 <= row3_mid_w;
        row3_max_s1 <= row3_max_w;
        vsync_s1    <= in_frame_vsync;
        href_s1     <= in_frame_href;
        hsync_s1    <= in_frame_hsync;

        max_of_lows_s2    <= max_of_lows_w;
        median_of_mids_s2 <= median_of_mids_w;
        min_of_highs_s2   <= min_of_highs_w;
        vsync_s2          <= vsync_s1;
        href_s2           <= href_s1;
        hsync_s2          <= hsync_s1;

        out_frame_vsync <= vsync_s2;
        out_frame_href  <= href_s2;
        out_frame_hsync <= hsync_s2;
        if (href_s2)
            out_img_median <= final_median_w;
        else
            out_img_median <= 8'd0;
    end
end

endmodule
