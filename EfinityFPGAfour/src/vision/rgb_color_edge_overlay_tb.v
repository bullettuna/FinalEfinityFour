`timescale 1ns/1ps
// Self-checking regression for the RGB-aware color-edge overlay.
module rgb_color_edge_overlay_tb;

localparam [13:0] WIDTH  = 14'd12;
localparam [13:0] HEIGHT = 14'd8;
localparam integer HBLANK = 16;
localparam integer VBLANK = 32;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg in_vsync = 1'b0;
reg in_href = 1'b0;
reg in_hsync = 1'b0;
reg [7:0] in_r = 8'd0;
reg [7:0] in_g = 8'd0;
reg [7:0] in_b = 8'd0;
reg [10:0] threshold = 11'd45;
reg [1:0] pattern = 2'd0;
reg check_en = 1'b0;

wire out_vsync;
wire out_href;
wire out_hsync;
wire [7:0] out_r;
wire [7:0] out_g;
wire [7:0] out_b;

always #5 clk = ~clk;

rgb_color_edge_overlay #(
    .IMG_HDISP(WIDTH),
    .IMG_VDISP(HEIGHT),
    .STRONG_DIFF(10'd300),
    .BLACK_TH(8'd20)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .overlay_enable(1'b1),
    .per_frame_vsync(in_vsync),
    .per_frame_href(in_href),
    .per_frame_hsync(in_hsync),
    .per_img_red(in_r),
    .per_img_green(in_g),
    .per_img_blue(in_b),
    .edge_threshold(threshold),
    .post_frame_vsync(out_vsync),
    .post_frame_href(out_href),
    .post_frame_hsync(out_hsync),
    .post_img_red(out_r),
    .post_img_green(out_g),
    .post_img_blue(out_b)
);

integer errors = 0;
integer samples = 0;
integer yellow_hits = 0;
integer white_hits = 0;
integer complement_hits = 0;
reg [23:0] out_rgb;

always @(posedge clk) begin
    #1;
    if (rst_n && check_en) begin
        out_rgb = {out_r, out_g, out_b};
        if (!out_href) begin
            if (out_rgb !== 24'h000000) begin
                errors = errors + 1;
                $display("FAIL blanking RGB=%06h at %0t", out_rgb, $time);
            end
        end else begin
            samples = samples + 1;
            case (pattern)
                2'd0: begin
                    case (out_rgb)
                        24'hFF0000, 24'h0000FF, 24'h000000: ;
                        24'hFFFF00: yellow_hits = yellow_hits + 1;
                        24'hFFFFFF: white_hits = white_hits + 1;
                        default: begin
                            errors = errors + 1;
                            $display("FAIL bar RGB=%06h at %0t", out_rgb, $time);
                        end
                    endcase
                end

                2'd1: begin
                    case (out_rgb)
                        24'h643232, 24'h963232: ;
                        24'h9BCDCD, 24'h69CDCD: complement_hits = complement_hits + 1;
                        24'h000000, 24'hFFFFFF: ;
                        default: begin
                            errors = errors + 1;
                            $display("FAIL complement RGB=%06h at %0t", out_rgb, $time);
                        end
                    endcase
                end

                default: begin
                    if (out_rgb !== 24'h506070) begin
                        errors = errors + 1;
                        $display("FAIL flat passthrough RGB=%06h at %0t", out_rgb, $time);
                    end
                end
            endcase
        end
    end
end

task drive_pixel;
    input integer pixel_x;
    begin
        case (pattern)
            // red | blue | red | black: red/blue must produce yellow, and
            // red/black must produce white under the migrated color policy.
            2'd0: begin
                if (pixel_x < 3 || (pixel_x >= 6 && pixel_x < 9)) begin
                    in_r = 8'hFF; in_g = 8'h00; in_b = 8'h00;
                end else if (pixel_x < 6) begin
                    in_r = 8'h00; in_g = 8'h00; in_b = 8'hFF;
                end else begin
                    in_r = 8'h00; in_g = 8'h00; in_b = 8'h00;
                end
            end

            // Moderate red-only transition: spread is below STRONG_DIFF, so
            // the edge must use the complement of the center pixel.
            2'd1: begin
                if (pixel_x < 6) begin
                    in_r = 8'd100; in_g = 8'd50; in_b = 8'd50;
                end else begin
                    in_r = 8'd150; in_g = 8'd50; in_b = 8'd50;
                end
            end

            default: begin
                in_r = 8'h50; in_g = 8'h60; in_b = 8'h70;
            end
        endcase
    end
endtask

integer row;
integer col;
task send_frame;
    begin
        in_vsync = 1'b1;
        for (row = 0; row < HEIGHT; row = row + 1) begin
            in_href = 1'b1;
            for (col = 0; col < WIDTH; col = col + 1) begin
                drive_pixel(col);
                @(negedge clk);
            end
            in_href = 1'b0;
            in_hsync = 1'b1;
            in_r = 8'd0; in_g = 8'd0; in_b = 8'd0;
            repeat (HBLANK) @(negedge clk);
            in_hsync = 1'b0;
        end
        in_vsync = 1'b0;
        repeat (VBLANK) @(negedge clk);
    end
endtask

initial begin
    repeat (5) @(negedge clk);
    rst_n = 1'b1;

    pattern = 2'd0;
    threshold = 11'd45;
    send_frame;
    send_frame;
    check_en = 1'b1;
    send_frame;
    send_frame;
    check_en = 1'b0;

    pattern = 2'd1;
    threshold = 11'd45;
    send_frame;
    send_frame;
    check_en = 1'b1;
    send_frame;
    send_frame;
    check_en = 1'b0;

    pattern = 2'd2;
    threshold = 11'd2047;
    send_frame;
    send_frame;
    check_en = 1'b1;
    send_frame;
    send_frame;
    check_en = 1'b0;

    repeat (64) @(posedge clk);
    if ((errors == 0) && (samples > 0) &&
        (yellow_hits > 0) && (white_hits > 0) &&
        (complement_hits > 0)) begin
        $display("PASS RGB color overlay: samples=%0d yellow=%0d white=%0d complement=%0d",
                 samples, yellow_hits, white_hits, complement_hits);
    end else begin
        $display("FAIL RGB color overlay: errors=%0d samples=%0d yellow=%0d white=%0d complement=%0d",
                 errors, samples, yellow_hits, white_hits, complement_hits);
    end
    $finish;
end

initial begin
    #2000000;
    $display("FAIL RGB color overlay timeout");
    $finish;
end

endmodule
