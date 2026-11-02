`timescale 1ns/1ps

module shape_overlay_tb;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg frame_vsync = 1'b0;
reg frame_href = 1'b0;
reg frame_hsync = 1'b0;
reg edge_mask = 1'b0;
reg [7:0] image_red = 8'd0;
reg [7:0] image_green = 8'd0;
reg [7:0] image_blue = 8'd0;
reg bbox_valid = 1'b0;
reg [11:0] bbox_x_min = 12'd0;
reg [11:0] bbox_x_max = 12'd0;
reg [10:0] bbox_y_min = 11'd0;
reg [10:0] bbox_y_max = 11'd0;
reg [1:0] shape_type = 2'd0;

wire out_vsync;
wire out_href;
wire out_hsync;
wire [7:0] out_red;
wire [7:0] out_green;
wire [7:0] out_blue;

shape_overlay #(
    .ROI_X_MIN(12'd8), .ROI_X_MAX(12'd15),
    .ROI_Y_MIN(11'd0), .ROI_Y_MAX(11'd4)
) u_shape_overlay (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(frame_vsync),
    .per_frame_href(frame_href),
    .per_frame_hsync(frame_hsync),
    .per_img_mask(edge_mask),
    .per_img_red(image_red),
    .per_img_green(image_green),
    .per_img_blue(image_blue),
    .bbox_valid(bbox_valid),
    .bbox_x_min(bbox_x_min), .bbox_x_max(bbox_x_max),
    .bbox_y_min(bbox_y_min), .bbox_y_max(bbox_y_max),
    .shape_type(shape_type),
    .post_frame_vsync(out_vsync),
    .post_frame_href(out_href),
    .post_frame_hsync(out_hsync),
    .post_img_red(out_red),
    .post_img_green(out_green),
    .post_img_blue(out_blue)
);

integer errors = 0;

task check_rgb;
    input [7:0] expected_red;
    input [7:0] expected_green;
    input [7:0] expected_blue;
    input [127:0] check_name;
    begin
        @(negedge clk);
        if (!out_vsync || !out_href ||
            (out_red != expected_red) ||
            (out_green != expected_green) ||
            (out_blue != expected_blue)) begin
            errors = errors + 1;
            $display("FAIL %0s got=%02x%02x%02x timing=%0d/%0d",
                     check_name, out_red, out_green, out_blue,
                     out_vsync, out_href);
        end
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    frame_vsync = 1'b1;
    frame_href = 1'b1;

    image_red = 8'h12;
    image_green = 8'h34;
    image_blue = 8'h56;
    check_rgb(8'h12, 8'h34, 8'h56, "background passthrough");

    edge_mask = 1'b1;
    check_rgb(8'hff, 8'h00, 8'h00, "red edge");

    edge_mask = 1'b0;
    bbox_valid = 1'b1;
    bbox_x_min = 12'd0;
    bbox_x_max = 12'd20;
    bbox_y_min = 11'd0;
    bbox_y_max = 11'd20;

    shape_type = 2'd1;
    check_rgb(8'h00, 8'hff, 8'h00, "rectangle box");

    shape_type = 2'd2;
    check_rgb(8'h00, 8'hbf, 8'hff, "circle box");

    shape_type = 2'd0;
    check_rgb(8'hff, 8'hff, 8'h00, "unknown box");

    bbox_valid = 1'b0;
    check_rgb(8'h12, 8'h34, 8'h56, "background before ROI");
    check_rgb(8'h12, 8'h34, 8'h56, "background before ROI");
    check_rgb(8'h12, 8'h34, 8'h56, "background before ROI");
    check_rgb(8'hff, 8'h00, 8'hff, "magenta ROI border");

    frame_href = 1'b0;
    @(negedge clk);
    if ((out_red != 8'd0) || (out_green != 8'd0) ||
        (out_blue != 8'd0)) begin
        errors = errors + 1;
        $display("FAIL blanking got=%02x%02x%02x",
                 out_red, out_green, out_blue);
    end

    if (errors == 0)
        $display("PASS aligned background, edge and shape colors");
    else
        $display("FAIL overlay regression errors=%0d", errors);
    $finish;
end

endmodule
