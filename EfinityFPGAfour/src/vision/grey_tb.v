`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking Verilog-2001 testbench for:
//   - grey: one RGB888 pixel per clock, timing/data/mode alignment, reset
//   - uart_vision_ctrl: ASCII mode/threshold/WB/Gamma/median decoding and replies
//
// Example:
//   iverilog -g2001 -s grey_tb -o grey_tb.vvp \
//       grey.v uart_vision_ctrl.v grey_tb.v
//   vvp grey_tb.vvp
//////////////////////////////////////////////////////////////////////////////////

module grey_tb;

reg         clk;
reg         rst_n;
reg         gray_en;
reg         per_frame_vsync;
reg         per_frame_href;
reg         per_frame_hsync;
reg  [7:0]  per_img_red;
reg  [7:0]  per_img_green;
reg  [7:0]  per_img_blue;

wire        post_frame_vsync;
wire        post_frame_href;
wire        post_frame_hsync;
wire [7:0]  post_img_gray;
wire [7:0]  post_img_red;
wire [7:0]  post_img_green;
wire [7:0]  post_img_blue;

grey u_grey (
    .clk             (clk),
    .rst_n           (rst_n),
    .gray_en         (gray_en),
    .per_frame_vsync (per_frame_vsync),
    .per_frame_href  (per_frame_href),
    .per_frame_hsync (per_frame_hsync),
    .per_img_red     (per_img_red),
    .per_img_green   (per_img_green),
    .per_img_blue    (per_img_blue),
    .post_frame_vsync(post_frame_vsync),
    .post_frame_href (post_frame_href),
    .post_frame_hsync(post_frame_hsync),
    .post_img_gray   (post_img_gray),
    .post_img_red    (post_img_red),
    .post_img_green  (post_img_green),
    .post_img_blue   (post_img_blue)
);

// UART command controller is tested at byte-interface level. The existing UART
// receiver/transmitter modules are responsible only for serial framing.
reg  [7:0] ctrl_rx_data;
reg        ctrl_rx_valid;
reg        ctrl_tx_done;
wire [7:0] ctrl_tx_data;
wire       ctrl_tx_start;
wire [1:0] ctrl_video_mode_req;
wire [10:0] ctrl_edge_threshold_req;
wire [10:0] ctrl_wb_red_gain_req;
wire [10:0] ctrl_wb_green_gain_req;
wire [10:0] ctrl_wb_blue_gain_req;
wire        ctrl_gamma_enable_req;
wire [8:0]  ctrl_gamma_strength_req;
wire        ctrl_median_enable_req;

uart_vision_ctrl #(
    .DEFAULT_VIDEO_MODE(2'd1),
    .DEFAULT_EDGE_THRESHOLD(11'd160)
) u_uart_vision_ctrl (
    .clk          (clk),
    .rst_n        (rst_n),
    .rx_data      (ctrl_rx_data),
    .rx_valid     (ctrl_rx_valid),
    .tx_done      (ctrl_tx_done),
    .tx_data      (ctrl_tx_data),
    .tx_start     (ctrl_tx_start),
    .video_mode_req(ctrl_video_mode_req),
    .edge_threshold_req(ctrl_edge_threshold_req),
    .wb_red_gain_req(ctrl_wb_red_gain_req),
    .wb_green_gain_req(ctrl_wb_green_gain_req),
    .wb_blue_gain_req(ctrl_wb_blue_gain_req),
    .gamma_enable_req(ctrl_gamma_enable_req),
    .gamma_strength_req(ctrl_gamma_strength_req),
    .median_enable_req(ctrl_median_enable_req)
);

always #5 clk = ~clk;

function [7:0] ref_gray;
    input [7:0] r;
    input [7:0] g;
    input [7:0] b;
    reg [17:0] accumulator;
    begin
        accumulator = r * 18'd54 +
                      g * 18'd183 +
                      b * 18'd19 +
                      18'd128;
        ref_gray = accumulator[15:8];
    end
endfunction

integer error_count;
integer check_count;

// Independent reference pipeline. A new expected sample is accepted on every
// rising edge, which proves full one-pixel-per-clock throughput.
reg [7:0] exp_red_d1;
reg [7:0] exp_green_d1;
reg [7:0] exp_blue_d1;
reg [7:0] exp_gray_d1;
reg [7:0] exp_red_d2;
reg [7:0] exp_green_d2;
reg [7:0] exp_blue_d2;
reg [7:0] exp_gray_d2;
reg       exp_vsync_d1;
reg       exp_href_d1;
reg       exp_hsync_d1;
reg       exp_vsync_d2;
reg       exp_href_d2;
reg       exp_hsync_d2;
reg       exp_valid_d1;
reg       exp_valid_d2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        exp_red_d1   <= 8'd0;
        exp_green_d1 <= 8'd0;
        exp_blue_d1  <= 8'd0;
        exp_gray_d1  <= 8'd0;
        exp_red_d2   <= 8'd0;
        exp_green_d2 <= 8'd0;
        exp_blue_d2  <= 8'd0;
        exp_gray_d2  <= 8'd0;
        exp_vsync_d1 <= 1'b0;
        exp_href_d1  <= 1'b0;
        exp_hsync_d1 <= 1'b0;
        exp_vsync_d2 <= 1'b0;
        exp_href_d2  <= 1'b0;
        exp_hsync_d2 <= 1'b0;
        exp_valid_d1 <= 1'b0;
        exp_valid_d2 <= 1'b0;
    end else begin
        if (gray_en) begin
            exp_red_d1   <= ref_gray(per_img_red, per_img_green, per_img_blue);
            exp_green_d1 <= ref_gray(per_img_red, per_img_green, per_img_blue);
            exp_blue_d1  <= ref_gray(per_img_red, per_img_green, per_img_blue);
        end else begin
            exp_red_d1   <= per_img_red;
            exp_green_d1 <= per_img_green;
            exp_blue_d1  <= per_img_blue;
        end

        exp_gray_d1 <= ref_gray(per_img_red, per_img_green, per_img_blue);

        exp_red_d2   <= exp_red_d1;
        exp_green_d2 <= exp_green_d1;
        exp_blue_d2  <= exp_blue_d1;
        exp_gray_d2  <= exp_gray_d1;
        exp_vsync_d1 <= per_frame_vsync;
        exp_href_d1  <= per_frame_href;
        exp_hsync_d1 <= per_frame_hsync;
        exp_vsync_d2 <= exp_vsync_d1;
        exp_href_d2  <= exp_href_d1;
        exp_hsync_d2 <= exp_hsync_d1;
        exp_valid_d1 <= 1'b1;
        exp_valid_d2 <= exp_valid_d1;
    end

    #1;
    if (!rst_n) begin
        if ((post_img_red !== 8'd0) ||
            (post_img_green !== 8'd0) ||
            (post_img_blue !== 8'd0) ||
            (post_img_gray !== 8'd0) ||
            (post_frame_vsync !== 1'b0) ||
            (post_frame_href !== 1'b0) ||
            (post_frame_hsync !== 1'b0)) begin
            $display("FAIL reset output is not zero at time %0t", $time);
            error_count = error_count + 1;
        end
    end else if (exp_valid_d2) begin
        check_count = check_count + 1;
        if ((post_img_red !== exp_red_d2) ||
            (post_img_green !== exp_green_d2) ||
            (post_img_blue !== exp_blue_d2) ||
            (post_img_gray !== exp_gray_d2) ||
            (post_frame_vsync !== exp_vsync_d2) ||
            (post_frame_href !== exp_href_d2) ||
            (post_frame_hsync !== exp_hsync_d2)) begin
            $display("FAIL sample=%0d time=%0t exp RGB/Y=%0d,%0d,%0d/%0d sync=%b%b%b got RGB/Y=%0d,%0d,%0d/%0d sync=%b%b%b",
                     check_count, $time,
                     exp_red_d2, exp_green_d2, exp_blue_d2, exp_gray_d2,
                     exp_vsync_d2, exp_href_d2, exp_hsync_d2,
                     post_img_red, post_img_green, post_img_blue, post_img_gray,
                     post_frame_vsync, post_frame_href, post_frame_hsync);
            error_count = error_count + 1;
        end
    end
end

task drive_sample;
    input [7:0] r;
    input [7:0] g;
    input [7:0] b;
    input       mode;
    input       vsync;
    input       href;
    input       hsync;
    begin
        @(negedge clk);
        per_img_red     = r;
        per_img_green   = g;
        per_img_blue    = b;
        gray_en         = mode;
        per_frame_vsync = vsync;
        per_frame_href  = href;
        per_frame_hsync = hsync;
    end
endtask

task check_gamma_strength;
    input [8:0] expected_strength;
    begin
        if (ctrl_gamma_strength_req !== expected_strength) begin
            $display("FAIL UART Gamma strength: expected %0d, got %0d",
                     expected_strength, ctrl_gamma_strength_req);
            error_count = error_count + 1;
        end
    end
endtask

task check_gamma_enable;
    input expected_enable;
    begin
        if (ctrl_gamma_enable_req !== expected_enable) begin
            $display("FAIL UART Gamma state: expected %b, got %b",
                     expected_enable, ctrl_gamma_enable_req);
            error_count = error_count + 1;
        end
    end
endtask

task check_median_enable;
    input expected_enable;
    begin
        if (ctrl_median_enable_req !== expected_enable) begin
            $display("FAIL UART median state: expected %b, got %b",
                     expected_enable, ctrl_median_enable_req);
            error_count = error_count + 1;
        end
    end
endtask

task check_wb_gains;
    input [10:0] expected_red;
    input [10:0] expected_green;
    input [10:0] expected_blue;
    begin
        if ((ctrl_wb_red_gain_req !== expected_red) ||
            (ctrl_wb_green_gain_req !== expected_green) ||
            (ctrl_wb_blue_gain_req !== expected_blue)) begin
            $display("FAIL UART WB gains: expected %0d/%0d/%0d, got %0d/%0d/%0d",
                     expected_red, expected_green, expected_blue,
                     ctrl_wb_red_gain_req, ctrl_wb_green_gain_req,
                     ctrl_wb_blue_gain_req);
            error_count = error_count + 1;
        end
    end
endtask

task send_uart_command;
    input [7:0] command;
    input [1:0] expected_mode;
    input [10:0] expected_threshold;
    input [7:0] expected_reply;
    input       expect_reply;
    begin
        @(negedge clk);
        ctrl_rx_data  = command;
        ctrl_rx_valid = 1'b1;
        @(posedge clk);
        #1;
        if ((ctrl_video_mode_req !== expected_mode) ||
            (ctrl_edge_threshold_req !== expected_threshold)) begin
            $display("FAIL UART command 0x%02x: expected mode/threshold %0d/%0d, got %0d/%0d",
                     command, expected_mode, expected_threshold,
                     ctrl_video_mode_req, ctrl_edge_threshold_req);
            error_count = error_count + 1;
        end
        if (expect_reply) begin
            if ((ctrl_tx_start !== 1'b1) || (ctrl_tx_data !== expected_reply)) begin
                $display("FAIL UART command 0x%02x: expected reply 0x%02x, start=1; got reply 0x%02x, start=%b",
                         command, expected_reply, ctrl_tx_data, ctrl_tx_start);
                error_count = error_count + 1;
            end
        end else if (ctrl_tx_start !== 1'b0) begin
            $display("FAIL UART CR/LF should not produce a response");
            error_count = error_count + 1;
        end

        @(negedge clk);
        ctrl_rx_valid = 1'b0;
        ctrl_tx_done  = expect_reply;
        @(posedge clk);
        @(negedge clk);
        ctrl_tx_done  = 1'b0;
    end
endtask

integer i;
reg [31:0] lfsr;

initial begin
    clk             = 1'b0;
    rst_n           = 1'b0;
    gray_en         = 1'b0;
    per_frame_vsync = 1'b0;
    per_frame_href  = 1'b0;
    per_frame_hsync = 1'b0;
    per_img_red     = 8'd0;
    per_img_green   = 8'd0;
    per_img_blue    = 8'd0;
    ctrl_rx_data    = 8'd0;
    ctrl_rx_valid   = 1'b0;
    ctrl_tx_done    = 1'b0;
    error_count     = 0;
    check_count     = 0;
    lfsr            = 32'h1ACE_B00C;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    $display("Test 1: UART mode commands");
    send_uart_command(8'h3F, 2'd1, 11'd160, 8'h31, 1'b1); // ? -> default gray
    send_uart_command(8'h43, 2'd0, 11'd160, 8'h30, 1'b1); // C -> color
    send_uart_command(8'h47, 2'd1, 11'd160, 8'h31, 1'b1); // G -> gray
    send_uart_command(8'h74, 2'd2, 11'd160, 8'h32, 1'b1); // t -> Sobel
    send_uart_command(8'h63, 2'd0, 11'd160, 8'h30, 1'b1); // c -> color
    send_uart_command(8'h45, 2'd2, 11'd160, 8'h32, 1'b1); // E -> Sobel
    send_uart_command(8'h2B, 2'd2, 11'd161, 8'h2B, 1'b1); // +1 threshold
    send_uart_command(8'h2D, 2'd2, 11'd160, 8'h2D, 1'b1); // - threshold

    // Decimal digits are accumulated and take effect only when Enter arrives.
    send_uart_command(8'h32, 2'd2, 11'd160, 8'h00, 1'b0); // '2'
    send_uart_command(8'h30, 2'd2, 11'd160, 8'h00, 1'b0); // '0'
    send_uart_command(8'h30, 2'd2, 11'd160, 8'h00, 1'b0); // '0'
    send_uart_command(8'h0D, 2'd2, 11'd200, 8'h4B, 1'b1); // Enter -> 200, reply K
    send_uart_command(8'h0A, 2'd2, 11'd200, 8'h00, 1'b0); // LF after CR ignored

    // An out-of-range decimal value saturates at the 11-bit Sobel maximum.
    send_uart_command(8'h39, 2'd2, 11'd200, 8'h00, 1'b0); // '9'
    send_uart_command(8'h39, 2'd2, 11'd200, 8'h00, 1'b0); // '9'
    send_uart_command(8'h39, 2'd2, 11'd200, 8'h00, 1'b0); // '9'
    send_uart_command(8'h39, 2'd2, 11'd200, 8'h00, 1'b0); // '9'
    send_uart_command(8'h0D, 2'd2, 11'd2047, 8'h4B, 1'b1);
    send_uart_command(8'h2B, 2'd2, 11'd2047, 8'h2B, 1'b1); // upper saturation
    send_uart_command(8'h2D, 2'd2, 11'd2046, 8'h2D, 1'b1);
    send_uart_command(8'h52, 2'd2, 11'd160, 8'h52, 1'b1); // R reset threshold

    $display("Test 2: UART manual white-balance commands");
    check_wb_gains(11'd256, 11'd256, 11'd256);
    send_uart_command(8'h57, 2'd2, 11'd160, 8'h00, 1'b0); // W prefix
    send_uart_command(8'h52, 2'd2, 11'd160, 8'h00, 1'b0); // red target
    send_uart_command(8'h33, 2'd2, 11'd160, 8'h00, 1'b0); // '3'
    send_uart_command(8'h38, 2'd2, 11'd160, 8'h00, 1'b0); // '8'
    send_uart_command(8'h34, 2'd2, 11'd160, 8'h00, 1'b0); // '4'
    send_uart_command(8'h0D, 2'd2, 11'd160, 8'h4B, 1'b1); // WR384
    check_wb_gains(11'd384, 11'd256, 11'd256);

    send_uart_command(8'h57, 2'd2, 11'd160, 8'h00, 1'b0); // W prefix
    send_uart_command(8'h42, 2'd2, 11'd160, 8'h00, 1'b0); // blue target
    send_uart_command(8'h32, 2'd2, 11'd160, 8'h00, 1'b0); // '2'
    send_uart_command(8'h32, 2'd2, 11'd160, 8'h00, 1'b0); // '2'
    send_uart_command(8'h34, 2'd2, 11'd160, 8'h00, 1'b0); // '4'
    send_uart_command(8'h0A, 2'd2, 11'd160, 8'h4B, 1'b1); // WB224
    check_wb_gains(11'd384, 11'd256, 11'd224);

    send_uart_command(8'h57, 2'd2, 11'd160, 8'h00, 1'b0); // W prefix
    send_uart_command(8'h44, 2'd2, 11'd160, 8'h57, 1'b1); // WD -> unity
    check_wb_gains(11'd256, 11'd256, 11'd256);

    $display("Test 3: UART Gamma toggle (default off)");
    check_gamma_enable(1'b0);
    check_gamma_strength(9'd64);
    send_uart_command(8'h59, 2'd2, 11'd160, 8'h31, 1'b1); // Y -> on, reply 1
    check_gamma_enable(1'b1);
    send_uart_command(8'h79, 2'd2, 11'd160, 8'h30, 1'b1); // y -> off, reply 0
    check_gamma_enable(1'b0);

    send_uart_command(8'h50, 2'd2, 11'd160, 8'h00, 1'b0); // P prefix
    send_uart_command(8'h39, 2'd2, 11'd160, 8'h00, 1'b0); // '9'
    send_uart_command(8'h36, 2'd2, 11'd160, 8'h00, 1'b0); // '6'
    send_uart_command(8'h0D, 2'd2, 11'd160, 8'h4B, 1'b1); // P96
    check_gamma_strength(9'd96);

    send_uart_command(8'h70, 2'd2, 11'd160, 8'h00, 1'b0); // p prefix
    send_uart_command(8'h39, 2'd2, 11'd160, 8'h00, 1'b0); // '9'
    send_uart_command(8'h39, 2'd2, 11'd160, 8'h00, 1'b0); // '9'
    send_uart_command(8'h39, 2'd2, 11'd160, 8'h00, 1'b0); // '9'
    send_uart_command(8'h0A, 2'd2, 11'd160, 8'h4B, 1'b1); // clamp to P256
    check_gamma_strength(9'd256);

    send_uart_command(8'h58, 2'd2, 11'd160, 8'h58, 1'b1); // default UART profile: gallery -> X
    send_uart_command(8'h0D, 2'd2, 11'd160, 8'h00, 1'b0); // CR ignored
    send_uart_command(8'h0A, 2'd2, 11'd160, 8'h00, 1'b0); // LF ignored

    $display("Test 4: UART median-filter toggle (default off)");
    check_median_enable(1'b0);
    send_uart_command(8'h4D, 2'd2, 11'd160, 8'h31, 1'b1); // M -> on
    check_median_enable(1'b1);
    send_uart_command(8'h6D, 2'd2, 11'd160, 8'h30, 1'b1); // m -> off
    check_median_enable(1'b0);

    $display("Test 5: solid colors and exact BT.709 rounding");
    drive_sample(8'd255, 8'd0,   8'd0,   1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd0,   8'd255, 8'd0,   1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd0,   8'd0,   8'd255, 1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd255, 8'd255, 8'd255, 1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd0,   8'd0,   8'd0,   1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd128, 8'd128, 8'd128, 1'b1, 1'b1, 1'b1, 1'b0);

    $display("Test 6: continuous full-range gradients");
    for (i = 0; i < 256; i = i + 1)
        drive_sample(i, i, i, 1'b1, 1'b1, 1'b1, 1'b0);

    for (i = 0; i < 256; i = i + 1)
        drive_sample(i, 255 - i, i * 5, 1'b1, 1'b1, 1'b1, 1'b0);

    $display("Test 7: line boundaries and timing-signal alignment");
    drive_sample(8'd0, 8'd0, 8'd0, 1'b1, 1'b0, 1'b0, 1'b0);
    drive_sample(8'd0, 8'd0, 8'd0, 1'b1, 1'b1, 1'b0, 1'b1);
    for (i = 0; i < 32; i = i + 1)
        drive_sample(i, 2 * i, 255 - i, 1'b1, 1'b1, 1'b1, 1'b0);
    drive_sample(8'd0, 8'd0, 8'd0, 1'b1, 1'b1, 1'b0, 1'b1);
    drive_sample(8'd0, 8'd0, 8'd0, 1'b1, 1'b1, 1'b0, 1'b0);

    $display("Test 8: per-pixel color/gray mode alignment");
    for (i = 0; i < 64; i = i + 1)
        drive_sample(i, 255 - i, 3 * i, i[0], 1'b1, 1'b1, 1'b0);

    $display("Test 9: deterministic pseudo-random stream");
    for (i = 0; i < 1024; i = i + 1) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        drive_sample(lfsr[7:0], lfsr[15:8], lfsr[23:16], lfsr[24],
                     lfsr[25], lfsr[26], lfsr[27]);
    end

    $display("Test 9: asynchronous reset during traffic");
    drive_sample(8'd201, 8'd37, 8'd99, 1'b1, 1'b1, 1'b1, 1'b0);
    @(negedge clk);
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Refill and flush the two-stage reference/DUT pipelines.
    drive_sample(8'd7, 8'd8, 8'd9, 1'b0, 1'b0, 1'b0, 1'b0);
    drive_sample(8'd10, 8'd11, 8'd12, 1'b1, 1'b0, 1'b0, 1'b0);
    drive_sample(8'd0, 8'd0, 8'd0, 1'b0, 1'b0, 1'b0, 1'b0);
    repeat (3) @(posedge clk);
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
