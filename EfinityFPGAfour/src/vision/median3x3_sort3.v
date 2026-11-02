`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Combinational sorting network for three unsigned 8-bit samples.
//
// The three compare-and-swap steps form a fixed network, so synthesis produces
// deterministic comparison logic rather than a data-dependent loop.
//////////////////////////////////////////////////////////////////////////////////

module median3x3_sort3
(
    input       [7:0] value_a,
    input       [7:0] value_b,
    input       [7:0] value_c,
    output reg  [7:0] value_min,
    output reg  [7:0] value_mid,
    output reg  [7:0] value_max
);

reg [7:0] work_a;
reg [7:0] work_b;
reg [7:0] work_c;
reg [7:0] swap_value;

always @(*) begin
    work_a = value_a;
    work_b = value_b;
    work_c = value_c;
    swap_value = 8'd0;

    if (work_a > work_b) begin
        swap_value = work_a;
        work_a      = work_b;
        work_b      = swap_value;
    end

    if (work_b > work_c) begin
        swap_value = work_b;
        work_b      = work_c;
        work_c      = swap_value;
    end

    if (work_a > work_b) begin
        swap_value = work_a;
        work_a      = work_b;
        work_b      = swap_value;
    end

    value_min = work_a;
    value_mid = work_b;
    value_max = work_c;
end

endmodule
