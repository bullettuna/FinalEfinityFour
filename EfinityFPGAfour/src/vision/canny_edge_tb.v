`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// End-to-end stream regression: a flat frame must remain edge-free and a
// vertical step frame must produce a non-empty Canny edge map.  It also checks
// that every output line retains the configured active width.
//////////////////////////////////////////////////////////////////////////////////

module canny_edge_tb;

localparam integer WIDTH  = 12;
localparam integer HEIGHT = 10;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_vsync = 1'b0;
reg in_href = 1'b0;
reg in_hsync = 1'b0;
reg [7:0] in_gray = 8'd0;

wire out_vsync;
wire out_href;
wire out_hsync;
wire [7:0] out_edge;

canny_edge #(
    .IMG_HDISP(WIDTH),
    .IMG_VDISP(HEIGHT)
) dut (
    .clk(clk), .rst_n(rst_n),
    .per_frame_vsync(in_vsync),
    .per_frame_href(in_href),
    .per_frame_hsync(in_hsync),
    .per_img_gray(in_gray),
    .per_img_red(in_gray), .per_img_green(in_gray), .per_img_blue(in_gray),
    .low_threshold(11'd40), .high_threshold(11'd80),
    .post_frame_vsync(out_vsync),
    .post_frame_href(out_href),
    .post_frame_hsync(out_hsync),
    .post_img_edge(out_edge),
    .post_img_red(), .post_img_green(), .post_img_blue()
);

always #5 clk = ~clk;

integer row;
integer col;
integer output_frame;
integer output_pixels;
integer output_edges;
integer output_col;
integer errors;
reg out_vsync_d;
reg out_href_d;

task send_frame;
    input step_pattern;
    begin
        @(negedge clk);
        in_vsync = 1'b1;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            in_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                in_gray = step_pattern ? ((col < WIDTH/2) ? 8'd0 : 8'd255) : 8'd64;
                @(negedge clk);
            end
            in_href = 1'b0;
            in_hsync = 1'b1;
            in_gray = 8'd0;
            repeat (12) @(negedge clk);
            in_hsync = 1'b0;
        end
        in_vsync = 1'b0;
        repeat (48) @(negedge clk);
    end
endtask

always @(posedge clk) begin
    if (!rst_n) begin
        output_frame  = 0;
        output_pixels = 0;
        output_edges  = 0;
        output_col    = 0;
        errors        = 0;
        out_vsync_d   = 1'b0;
        out_href_d    = 1'b0;
    end else begin
        if (!out_vsync_d && out_vsync) begin
            output_frame  = output_frame + 1;
            output_pixels = 0;
            output_edges  = 0;
            output_col    = 0;
        end

        if (out_href) begin
            output_pixels = output_pixels + 1;
            output_col = output_col + 1;
            if (out_edge != 8'd0)
                output_edges = output_edges + 1;
        end

        if (out_href_d && !out_href) begin
            if (output_col != WIDTH) begin
                errors = errors + 1;
                $display("FAIL Canny frame=%0d output line width=%0d expected=%0d",
                         output_frame, output_col, WIDTH);
            end
            output_col = 0;
        end

        if (out_vsync_d && !out_vsync) begin
            if (output_pixels != WIDTH * HEIGHT) begin
                errors = errors + 1;
                $display("FAIL Canny frame=%0d pixels=%0d expected=%0d",
                         output_frame, output_pixels, WIDTH * HEIGHT);
            end
            if ((output_frame == 1) && (output_edges != 0)) begin
                errors = errors + 1;
                $display("FAIL flat Canny frame produced %0d edge pixels", output_edges);
            end
            if ((output_frame == 2) && (output_edges == 0)) begin
                errors = errors + 1;
                $display("FAIL vertical-step Canny frame produced no edge pixels");
            end
        end

        out_vsync_d = out_vsync;
        out_href_d  = out_href;
    end
end

initial begin
    repeat (5) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;

    send_frame(1'b0);
    send_frame(1'b1);
    repeat (64) @(posedge clk);

    if ((errors == 0) && (output_frame == 2))
        $display("RESULT: ALL CANNY STREAM TESTS PASSED");
    else begin
        $display("FAIL Canny stream errors=%0d frames=%0d", errors, output_frame);
        $fatal(1);
    end
    $finish;
end

wire unused_out_hsync = out_hsync;

endmodule
