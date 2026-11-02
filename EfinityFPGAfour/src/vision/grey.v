`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// RGB888 to grayscale processor
//
// Fixed-point BT.709 luminance approximation:
//   Y = (54 * R + 183 * G + 19 * B + 128) >> 8
//
// The coefficient sum is 256, so the rounded result is naturally limited to
// 0..255. The RGB data, video timing signals, and mode bit all pass through
// the same two-register pipeline. Consequently, gray_en may change on any
// input pixel without mixing the mode belonging to that pixel with another
// pixel's data. A system-level controller should still update gray_en during
// vertical blanking when whole-frame mode changes are desired.
//////////////////////////////////////////////////////////////////////////////////

module grey
(
    input               clk,
    input               rst_n,

    // Synchronous mode associated with the current input pixel.
    // 1: grayscale, 0: registered color bypass.
    input               gray_en,

    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,

    output              post_frame_vsync,
    output              post_frame_href,
    output              post_frame_hsync,
    // Always-valid grayscale sample aligned with the post-frame timing.  This
    // remains grayscale even when the RGB outputs are in color-bypass mode so
    // downstream vision algorithms do not need to repeat the conversion.
    output      [7:0]   post_img_gray,
    output      [7:0]   post_img_red,
    output      [7:0]   post_img_green,
    output      [7:0]   post_img_blue
);

// Stage 1: registered constant multipliers.
reg [15:0] r_prod;
reg [15:0] g_prod;
reg [15:0] b_prod;

// Explicitly widen the adder tree. Its mathematical maximum is 65408 after
// rounding, but the extra bit prevents accidental expression-width truncation
// if this code is maintained or compiled by a different Verilog front end.
wire [16:0] weighted_sum;
wire [16:0] rounded_sum;

assign weighted_sum = {1'b0, r_prod} +
                      {1'b0, g_prod} +
                      {1'b0, b_prod};
assign rounded_sum  = weighted_sum + 17'd128;

// Stage 2 grayscale result.
reg [7:0] gray_data_d2;

// Registered color bypass and per-pixel mode, matched to the grayscale path.
reg [7:0] red_d1;
reg [7:0] green_d1;
reg [7:0] blue_d1;
reg [7:0] red_d2;
reg [7:0] green_d2;
reg [7:0] blue_d2;
reg       gray_en_d1;
reg       gray_en_d2;

// Video timing pipeline, matched to both data paths.
reg [1:0] vsync_d;
reg [1:0] href_d;
reg [1:0] hsync_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_prod       <= 16'd0;
        g_prod       <= 16'd0;
        b_prod       <= 16'd0;
        gray_data_d2 <= 8'd0;

        red_d1       <= 8'd0;
        green_d1     <= 8'd0;
        blue_d1      <= 8'd0;
        red_d2       <= 8'd0;
        green_d2     <= 8'd0;
        blue_d2      <= 8'd0;
        gray_en_d1   <= 1'b0;
        gray_en_d2   <= 1'b0;

        vsync_d      <= 2'b00;
        href_d       <= 2'b00;
        hsync_d      <= 2'b00;
    end else begin
        // Pipeline stage 1.
        r_prod      <= per_img_red   * 16'd54;
        g_prod      <= per_img_green * 16'd183;
        b_prod      <= per_img_blue  * 16'd19;
        red_d1      <= per_img_red;
        green_d1    <= per_img_green;
        blue_d1     <= per_img_blue;
        gray_en_d1  <= gray_en;

        // Pipeline stage 2. rounded_sum is formed from the previous stage-1
        // products because all sequential assignments are non-blocking.
        gray_data_d2 <= rounded_sum[15:8];
        red_d2      <= red_d1;
        green_d2    <= green_d1;
        blue_d2     <= blue_d1;
        gray_en_d2  <= gray_en_d1;

        vsync_d     <= {vsync_d[0], per_frame_vsync};
        href_d      <= {href_d[0],  per_frame_href};
        hsync_d     <= {hsync_d[0], per_frame_hsync};
    end
end

assign post_frame_vsync = vsync_d[1];
assign post_frame_href  = href_d[1];
assign post_frame_hsync = hsync_d[1];

assign post_img_gray = gray_data_d2;
assign post_img_red   = gray_en_d2 ? gray_data_d2 : red_d2;
assign post_img_green = gray_en_d2 ? gray_data_d2 : green_d2;
assign post_img_blue  = gray_en_d2 ? gray_data_d2 : blue_d2;

endmodule
