`timescale 1ns/1ps

// Self-checking regression for border padding, exact line width and frame
// isolation. A pixel is encoded as {row[3:0], column[3:0]}.
module VIP_Matrix_Generate_3X3_8Bit_tb;

localparam [13:0] WIDTH  = 14'd8;
localparam [13:0] HEIGHT = 14'd6;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg per_frame_vsync = 1'b0;
reg per_frame_href = 1'b0;
reg per_frame_hsync = 1'b0;
reg [7:0] per_img_Y = 8'd0;

wire matrix_frame_vsync;
wire matrix_frame_href;
wire matrix_frame_hsync;
wire [7:0] p11, p12, p13;
wire [7:0] p21, p22, p23;
wire [7:0] p31, p32, p33;

VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(WIDTH),
    .IMG_VDISP(HEIGHT)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .per_frame_vsync(per_frame_vsync),
    .per_frame_href(per_frame_href),
    .per_frame_hsync(per_frame_hsync),
    .per_img_Y(per_img_Y),
    .matrix_frame_vsync(matrix_frame_vsync),
    .matrix_frame_href(matrix_frame_href),
    .matrix_frame_hsync(matrix_frame_hsync),
    .matrix_p11(p11), .matrix_p12(p12), .matrix_p13(p13),
    .matrix_p21(p21), .matrix_p22(p22), .matrix_p23(p23),
    .matrix_p31(p31), .matrix_p32(p32), .matrix_p33(p33)
);

always #5 clk = ~clk;

integer row;
integer col;
integer frame;
integer errors = 0;
integer checked_pixels = 0;
integer checked_lines = 0;
integer output_row = 0;
integer output_col = 0;
reg output_href_d = 1'b0;

function [7:0] pixel_at;
    input integer pixel_row;
    input integer pixel_col;
    begin
        pixel_at = {pixel_row[3:0], pixel_col[3:0]};
    end
endfunction

integer top_row;
integer middle_row;
integer left_col;
integer right_col;

always @(posedge clk) begin
    #1;
    if (!rst_n || !matrix_frame_vsync) begin
        output_row = 0;
        output_col = 0;
        output_href_d = 1'b0;
    end else begin
        if (matrix_frame_href) begin
            top_row    = (output_row < 2) ? 0 : output_row - 2;
            middle_row = (output_row == 0) ? 0 : output_row - 1;
            left_col   = (output_col == 0) ? 0 : output_col - 1;
            right_col  = (output_col == WIDTH - 1) ? WIDTH - 1 : output_col + 1;

            if ((p11 !== pixel_at(top_row, left_col)) ||
                (p12 !== pixel_at(top_row, output_col)) ||
                (p13 !== pixel_at(top_row, right_col)) ||
                (p21 !== pixel_at(middle_row, left_col)) ||
                (p22 !== pixel_at(middle_row, output_col)) ||
                (p23 !== pixel_at(middle_row, right_col)) ||
                (p31 !== pixel_at(output_row, left_col)) ||
                (p32 !== pixel_at(output_row, output_col)) ||
                (p33 !== pixel_at(output_row, right_col))) begin
                errors = errors + 1;
                $display("FAIL row=%0d col=%0d matrix=%02x %02x %02x / %02x %02x %02x / %02x %02x %02x",
                         output_row, output_col, p11, p12, p13, p21, p22,
                         p23, p31, p32, p33);
            end
            checked_pixels = checked_pixels + 1;
            output_col = output_col + 1;
        end

        if (output_href_d && !matrix_frame_href) begin
            if (output_col != WIDTH) begin
                errors = errors + 1;
                $display("FAIL row=%0d width=%0d expected=%0d", output_row,
                         output_col, WIDTH);
            end
            checked_lines = checked_lines + 1;
            output_col = 0;
            output_row = output_row + 1;
        end
        output_href_d = matrix_frame_href;
    end
end

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    for (frame = 0; frame < 2; frame = frame + 1) begin
        per_frame_vsync = 1'b1;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            per_frame_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                per_img_Y = {row[3:0], col[3:0]};
                @(negedge clk);
            end
            per_frame_href = 1'b0;
            per_frame_hsync = 1'b1;
            repeat (4) @(negedge clk);
            per_frame_hsync = 1'b0;
        end
        per_frame_vsync = 1'b0;
        repeat (8) @(negedge clk);
    end

    repeat (8) @(posedge clk);
    if ((errors == 0) &&
        (checked_pixels == 2 * WIDTH * HEIGHT) &&
        (checked_lines == 2 * HEIGHT))
        $display("PASS matrix3x3: pixels=%0d lines=%0d", checked_pixels, checked_lines);
    else
        $display("FAIL matrix3x3: errors=%0d pixels=%0d lines=%0d",
                 errors, checked_pixels, checked_lines);
    $finish;
end

endmodule
