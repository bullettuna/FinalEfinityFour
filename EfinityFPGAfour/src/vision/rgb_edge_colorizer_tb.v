`timescale 1ns/1ps

module rgb_edge_colorizer_tb;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg valid;
reg edge_value_in;
reg [23:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
wire out_valid;
wire [23:0] out_rgb;

rgb_edge_colorizer_kernel_3x3 dut (
    .clk(clk), .rst_n(rst_n), .overlay_enable(1'b1),
    .in_frame_vsync(1'b1), .in_frame_href(valid), .in_frame_hsync(1'b0),
    .p11(p11), .p12(p12), .p13(p13),
    .p21(p21), .p22(p22), .p23(p23),
    .p31(p31), .p32(p32), .p33(p33),
    .center_edge(edge_value_in),
    .out_frame_vsync(), .out_frame_href(out_valid), .out_frame_hsync(),
    .out_rgb(out_rgb)
);

task set_all;
    input [23:0] value;
    begin
        p11=value; p12=value; p13=value;
        p21=value; p22=value; p23=value;
        p31=value; p32=value; p33=value;
    end
endtask

task send_and_check;
    input edge_value;
    input [23:0] expected_rgb;
    integer cycle;
    reg found;
    begin
        @(negedge clk);
        edge_value_in = edge_value;
        valid = 1'b1;
        @(negedge clk);
        valid = 1'b0;
        edge_value_in = 1'b0;

        found = 1'b0;
        for (cycle = 0; cycle < 10; cycle = cycle + 1) begin
            @(posedge clk); #1;
            if (out_valid) begin
                found = 1'b1;
                if (out_rgb !== expected_rgb) begin
                    $display("FAIL RGB colorizer expected=%06x got=%06x",
                             expected_rgb, out_rgb);
                    $fatal(1);
                end
            end
        end
        if (!found) begin
            $display("FAIL RGB colorizer timed out");
            $fatal(1);
        end
    end
endtask

initial begin
    valid = 1'b0;
    edge_value_in = 1'b0;
    set_all(24'd0);
    repeat (4) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Non-edge pixels retain their aligned source colour.
    set_all(24'h204060);
    send_and_check(1'b0, 24'h204060);

    // Any near-black pixel in the 3x3 neighbourhood selects white.
    set_all(24'h204060);
    p11 = 24'h000000;
    send_and_check(1'b1, 24'hFFFFFF);

    // A summed RGB range above 300 selects yellow.
    set_all(24'h202020);
    p33 = 24'hF0F0F0;
    send_and_check(1'b1, 24'hFFFF00);

    // Otherwise the edge is the complement of the centre pixel.
    set_all(24'h204060);
    send_and_check(1'b1, 24'hDFBF9F);

    $display("RESULT: ALL RGB EDGE COLORIZER TESTS PASSED");
    $finish;
end

endmodule
