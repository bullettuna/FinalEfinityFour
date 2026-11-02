`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking fixed-point tests for the Canny arithmetic stages.  Window
// generation is covered separately by VIP_Matrix_Generate_3X3_8Bit_tb.v.
//////////////////////////////////////////////////////////////////////////////////

module canny_kernel_tb;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg frame_valid;
reg [7:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
reg color_gradient_test;
reg [31:0] color_p11, color_p12, color_p13;
reg [31:0] color_p21, color_p22, color_p23;
reg [31:0] color_p31, color_p32, color_p33;
wire [10:0] gradient_magnitude;
wire [1:0] gradient_direction;
wire gradient_valid;

wire [31:0] gradient_p11 = color_gradient_test ? color_p11 : {p11, 24'd0};
wire [31:0] gradient_p12 = color_gradient_test ? color_p12 : {p12, 24'd0};
wire [31:0] gradient_p13 = color_gradient_test ? color_p13 : {p13, 24'd0};
wire [31:0] gradient_p21 = color_gradient_test ? color_p21 : {p21, 24'd0};
wire [31:0] gradient_p22 = color_gradient_test ? color_p22 : {p22, 24'd0};
wire [31:0] gradient_p23 = color_gradient_test ? color_p23 : {p23, 24'd0};
wire [31:0] gradient_p31 = color_gradient_test ? color_p31 : {p31, 24'd0};
wire [31:0] gradient_p32 = color_gradient_test ? color_p32 : {p32, 24'd0};
wire [31:0] gradient_p33 = color_gradient_test ? color_p33 : {p33, 24'd0};

canny_gradient_kernel_3x3 u_gradient (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(1'b1), .in_frame_href(frame_valid),
    .in_frame_hsync(1'b0),
    .p11(gradient_p11), .p12(gradient_p12), .p13(gradient_p13),
    .p21(gradient_p21), .p22(gradient_p22), .p23(gradient_p23),
    .p31(gradient_p31), .p32(gradient_p32), .p33(gradient_p33),
    .out_frame_vsync(), .out_frame_href(gradient_valid),
    .out_frame_hsync(), .out_magnitude(gradient_magnitude),
    .out_direction(gradient_direction), .out_rgb()
);

reg nms_valid;
reg [10:0] m11, m12, m13, m21, m22, m23, m31, m32, m33;
reg [1:0] nms_direction;
wire [10:0] nms_magnitude;
wire nms_out_valid;

canny_nms_kernel_3x3 u_nms (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(1'b1), .in_frame_href(nms_valid),
    .in_frame_hsync(1'b0),
    .m11(m11), .m12(m12), .m13(m13),
    .m21(m21), .m22(m22), .m23(m23),
    .m31(m31), .m32(m32), .m33(m33),
    .center_direction(nms_direction), .center_rgb(24'hABCDEF),
    .out_frame_vsync(), .out_frame_href(nms_out_valid),
    .out_frame_hsync(), .out_magnitude(nms_magnitude), .out_rgb()
);

reg threshold_valid;
reg [10:0] threshold_magnitude;
wire [1:0] edge_class;
wire threshold_out_valid;

canny_double_threshold u_threshold (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(1'b1), .per_frame_href(threshold_valid),
    .per_frame_hsync(1'b0), .per_magnitude(threshold_magnitude),
    .low_threshold(11'd50), .high_threshold(11'd100),
    .per_img_red(8'h11), .per_img_green(8'h22), .per_img_blue(8'h33),
    .post_frame_vsync(), .post_frame_href(threshold_out_valid),
    .post_frame_hsync(), .post_edge_class(edge_class),
    .post_img_red(), .post_img_green(), .post_img_blue()
);

reg hysteresis_valid;
reg [1:0] c11, c12, c13, c21, c22, c23, c31, c32, c33;
wire [7:0] hysteresis_edge;
wire hysteresis_out_valid;

canny_hysteresis_kernel_3x3 u_hysteresis (
    .clk(clk), .rst_n(rst_n),
    .in_frame_vsync(1'b1), .in_frame_href(hysteresis_valid),
    .in_frame_hsync(1'b0),
    .c11(c11), .c12(c12), .c13(c13),
    .c21(c21), .c22(c22), .c23(c23),
    .c31(c31), .c32(c32), .c33(c33),
    .center_rgb(24'h654321),
    .out_frame_vsync(), .out_frame_href(hysteresis_out_valid),
    .out_frame_hsync(), .out_img_edge(hysteresis_edge), .out_rgb()
);

task clear_gradient_window;
    begin
        p11=0; p12=0; p13=0; p21=0; p22=0;
        p23=0; p31=0; p32=0; p33=0;
    end
endtask

task clear_colour_gradient_window;
    begin
        color_p11=0; color_p12=0; color_p13=0;
        color_p21=0; color_p22=0; color_p23=0;
        color_p31=0; color_p32=0; color_p33=0;
    end
endtask

task check_gradient;
    input [10:0] expected_magnitude;
    input [1:0] expected_direction;
    begin
        frame_valid = 1'b1;
        @(posedge clk); #1;
        frame_valid = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;   // third stage of the colour-gradient pipeline
        if (!gradient_valid || gradient_magnitude !== expected_magnitude ||
            gradient_direction !== expected_direction) begin
            $display("FAIL gradient expected mag=%0d dir=%0d got valid=%b mag=%0d dir=%0d",
                     expected_magnitude, expected_direction, gradient_valid,
                     gradient_magnitude, gradient_direction);
            $fatal(1);
        end
    end
endtask

task check_nms;
    input [10:0] expected_magnitude;
    begin
        nms_valid = 1'b1;
        @(posedge clk); #1;
        nms_valid = 1'b0;
        if (!nms_out_valid || nms_magnitude !== expected_magnitude) begin
            $display("FAIL NMS expected=%0d got valid=%b magnitude=%0d",
                     expected_magnitude, nms_out_valid, nms_magnitude);
            $fatal(1);
        end
    end
endtask

task check_threshold;
    input [10:0] magnitude;
    input [1:0] expected_class;
    begin
        threshold_magnitude = magnitude;
        threshold_valid = 1'b1;
        @(posedge clk); #1;
        threshold_valid = 1'b0;
        if (!threshold_out_valid || edge_class !== expected_class) begin
            $display("FAIL threshold magnitude=%0d expected=%0d got valid=%b class=%0d",
                     magnitude, expected_class, threshold_out_valid, edge_class);
            $fatal(1);
        end
    end
endtask

task clear_classes;
    begin
        c11=0; c12=0; c13=0; c21=0; c22=0;
        c23=0; c31=0; c32=0; c33=0;
    end
endtask

task check_hysteresis;
    input [7:0] expected_edge;
    begin
        hysteresis_valid = 1'b1;
        @(posedge clk); #1;
        hysteresis_valid = 1'b0;
        if (!hysteresis_out_valid || hysteresis_edge !== expected_edge) begin
            $display("FAIL hysteresis expected=%02x got valid=%b edge=%02x",
                     expected_edge, hysteresis_out_valid, hysteresis_edge);
            $fatal(1);
        end
    end
endtask

initial begin
    frame_valid = 0; nms_valid = 0; threshold_valid = 0; hysteresis_valid = 0;
    color_gradient_test = 0;
    clear_gradient_window();
    clear_colour_gradient_window();
    m11=0; m12=0; m13=0; m21=0; m22=0; m23=0; m31=0; m32=0; m33=0;
    nms_direction=0; threshold_magnitude=0; clear_classes();

    repeat (4) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    // Vertical intensity edge: gradient normal is horizontal.
    clear_gradient_window();
    p13=255; p23=255; p33=255;
    check_gradient(11'd1020, 2'b00);

    // Horizontal intensity edge: gradient normal is vertical.
    clear_gradient_window();
    p11=255; p12=255; p13=255;
    check_gradient(11'd1020, 2'b10);

    // Two diagonal gradient signs exercise both diagonal bins.
    clear_gradient_window();
    p12=255; p13=255; p23=255;
    check_gradient(11'd1530, 2'b01);

    clear_gradient_window();
    p23=255; p32=255; p33=255;
    check_gradient(11'd1530, 2'b11);

    // Red and green sides have equal gray samples here (the low byte is zero),
    // so the former grayscale gradient would be zero. The RGB gradient must
    // retain the red-channel boundary.
    clear_colour_gradient_window();
    color_gradient_test = 1'b1;
    color_p11=32'hFF000000; color_p21=32'hFF000000; color_p31=32'hFF000000;
    color_p13=32'h00820000; color_p23=32'h00820000; color_p33=32'h00820000;
    check_gradient(11'd1020, 2'b00);
    color_gradient_test = 1'b0;

    // Horizontal NMS retains a local maximum and suppresses a weaker centre.
    m21=80; m22=100; m23=90; nms_direction=2'b00;
    check_nms(11'd100);
    m23=120;
    check_nms(11'd0);

    check_threshold(11'd0,   2'b00);
    check_threshold(11'd20,  2'b00);
    check_threshold(11'd80,  2'b01);
    check_threshold(11'd120, 2'b10);

    clear_classes(); c22=2'b10;
    check_hysteresis(8'hFF);
    clear_classes(); c22=2'b01; c13=2'b10;
    check_hysteresis(8'hFF);
    clear_classes(); c22=2'b01;
    check_hysteresis(8'h00);
    clear_classes(); c22=2'b00; c13=2'b10;
    check_hysteresis(8'h00);

    $display("RESULT: ALL CANNY KERNEL TESTS PASSED");
    $finish;
end

endmodule
