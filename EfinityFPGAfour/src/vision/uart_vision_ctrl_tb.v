`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking UART command regression for frame freeze and command isolation.
//////////////////////////////////////////////////////////////////////////////////

module uart_vision_ctrl_tb;

reg clk;
reg rst_n;
reg [7:0] rx_data;
reg rx_valid;
reg tx_done;

wire [7:0] tx_data;
wire tx_start;
wire [1:0] video_mode_req;
wire [10:0] edge_threshold_req;
wire [10:0] canny_low_threshold_req;
wire [10:0] wb_red_gain_req;
wire [10:0] wb_green_gain_req;
wire [10:0] wb_blue_gain_req;
wire gamma_enable_req;
wire [8:0] gamma_strength_req;
wire median_enable_req;
wire freeze_req;
wire gray_canny_enable_req;
wire color_canny_enable_req;
wire shape_enable_req;
wire rect_line_fit_enable_req;
wire [1:0] line_support_level_req;
wire [7:0] black_threshold_req;
wire status_query_req;
wire photo_capture_req, sd_info_query_req, photo_gallery_toggle_req;
wire photo_gallery_prev_req, photo_gallery_next_req;
reg [4:0] expected_photo_requests;

uart_vision_ctrl #(
    .DEFAULT_VIDEO_MODE(2'd1),
    .DEFAULT_EDGE_THRESHOLD(11'd160),
    .DEFAULT_CANNY_LOW_THRESHOLD(11'd80),
    .DEFAULT_WB_RED_GAIN(11'd256),
    .DEFAULT_WB_GREEN_GAIN(11'd256),
    .DEFAULT_WB_BLUE_GAIN(11'd256),
    .DEFAULT_GAMMA_ENABLE(1'b0),
    .DEFAULT_GAMMA_STRENGTH(9'd64),
    .DEFAULT_MEDIAN_ENABLE(1'b0),
    .DEFAULT_GRAY_CANNY_ENABLE(1'b0),
    .DEFAULT_COLOR_CANNY_ENABLE(1'b0),
    .DEFAULT_SHAPE_ENABLE(1'b0),
    .DEFAULT_BLACK_THRESHOLD(8'd96)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .tx_done(tx_done),
    .tx_data(tx_data),
    .tx_start(tx_start),
    .video_mode_req(video_mode_req),
    .edge_threshold_req(edge_threshold_req),
    .canny_low_threshold_req(canny_low_threshold_req),
    .wb_red_gain_req(wb_red_gain_req),
    .wb_green_gain_req(wb_green_gain_req),
    .wb_blue_gain_req(wb_blue_gain_req),
    .gamma_enable_req(gamma_enable_req),
    .gamma_strength_req(gamma_strength_req),
    .median_enable_req(median_enable_req),
    .freeze_req(freeze_req),
    .photo_capture_req(photo_capture_req),
    .sd_info_query_req(sd_info_query_req),
    .photo_gallery_toggle_req(photo_gallery_toggle_req),
    .photo_gallery_prev_req(photo_gallery_prev_req),
    .photo_gallery_next_req(photo_gallery_next_req),
    .gray_canny_enable_req(gray_canny_enable_req),
    .color_canny_enable_req(color_canny_enable_req),
    .shape_enable_req(shape_enable_req),
    .rect_line_fit_enable_req(rect_line_fit_enable_req),
    .line_support_level_req(line_support_level_req),
    .black_threshold_req(black_threshold_req),
    .status_query_req(status_query_req)
);

always #5 clk = ~clk;

task send_and_check;
    input [7:0] value;
    input expect_response;
    input [7:0] expected_response;
    begin
        @(negedge clk);
        rx_data = value;
        rx_valid = 1'b1;
        @(posedge clk);
        #1;
        if ({photo_capture_req, sd_info_query_req, photo_gallery_toggle_req,
             photo_gallery_prev_req, photo_gallery_next_req} !== expected_photo_requests)
            $fatal(1,"Unexpected photo/SD/gallery request for byte %02x", value);
        if (expect_response) begin
            if ((tx_start !== 1'b1) || (tx_data !== expected_response)) begin
                $display("FAIL command 0x%02x expected response 0x%02x, got start=%b data=0x%02x",
                         value, expected_response, tx_start, tx_data);
                $fatal(1,"UART regression assertion failed");
            end
        end else if (tx_start !== 1'b0) begin
            $display("FAIL command 0x%02x unexpectedly produced response 0x%02x", value, tx_data);
            $fatal(1,"UART regression assertion failed");
        end

        @(negedge clk);
        rx_valid = 1'b0;
        tx_done = expect_response;
        @(posedge clk);
        #1;
        @(negedge clk);
        tx_done = 1'b0;
    end
endtask

task check_thresholds;
    input [10:0] expected_high;
    input [10:0] expected_low;
    begin
        if ((edge_threshold_req !== expected_high) ||
            (canny_low_threshold_req !== expected_low)) begin
            $display("FAIL thresholds expected high=%0d low=%0d, got high=%0d low=%0d",
                     expected_high, expected_low,
                     edge_threshold_req, canny_low_threshold_req);
            $fatal(1,"UART regression assertion failed");
        end
    end
endtask

task check_state;
    input expected_freeze;
    input expected_median;
    input [1:0] expected_mode;
    input expected_gray_canny;
    input expected_color_canny;
    begin
        if ((freeze_req !== expected_freeze) ||
            (median_enable_req !== expected_median) ||
            (video_mode_req !== expected_mode) ||
            (gray_canny_enable_req !== expected_gray_canny) ||
            (color_canny_enable_req !== expected_color_canny)) begin
            $display("FAIL state expected freeze=%b median=%b mode=%0d gray_canny=%b color_canny=%b, got freeze=%b median=%b mode=%0d gray_canny=%b color_canny=%b",
                     expected_freeze, expected_median, expected_mode,
                     expected_gray_canny, expected_color_canny,
                     freeze_req, median_enable_req, video_mode_req,
                     gray_canny_enable_req, color_canny_enable_req);
            $fatal(1,"UART regression assertion failed");
        end
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    rx_data = 8'h00;
    rx_valid = 1'b0;
    tx_done = 1'b0;
    expected_photo_requests = 5'b00000;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_state(1'b0, 1'b0, 2'd1, 1'b0, 1'b0);
    check_thresholds(11'd160, 11'd80);
    // Retired words/coordinates are rejected once and cannot leak letters
    // into algorithm controls or the 'i' SD-initialization command.
    send_and_check("g",0,0); send_and_check("a",0,0);
    send_and_check("m",0,0); send_and_check("e",1,"!");
    send_and_check(8'h0d,0,0); send_and_check(8'h0a,0,0);
    send_and_check("v",0,0); send_and_check("i",0,0);
    send_and_check("d",0,0); send_and_check("e",0,0);
    send_and_check("o",1,"!");
    send_and_check("@",0,0); send_and_check("1",0,0);
    send_and_check("2",0,0); send_and_check("3",0,0);
    send_and_check(",",0,0); send_and_check("4",0,0);
    send_and_check("5",0,0); send_and_check(8'h0d,1,"!");
    send_and_check(8'h0a,0,0);
    check_state(0,0,2'd1,0,0);
    check_thresholds(11'd160,11'd80);
    if (shape_enable_req) $fatal(1,"Retired video word changed shape mode");
    // The active one-byte photo commands still generate exactly one pulse.
    expected_photo_requests=5'b01000; send_and_check("i",0,0);
    expected_photo_requests=5'b10000; send_and_check("b",0,0);
    expected_photo_requests=5'b00100; send_and_check("x",1,"X");
    expected_photo_requests=5'b00010; send_and_check("<",1,"<");
    expected_photo_requests=5'b00001; send_and_check(">",1,">");
    expected_photo_requests=5'b00000;
    send_and_check("U",1'b1,"!");send_and_check("u",1'b1,"!");
    send_and_check("N",1'b0,0);send_and_check("3",1'b0,0);send_and_check("2",1'b0,0);
    send_and_check(8'h0d,1'b1,"!");send_and_check(8'h0a,1'b0,0);
    check_thresholds(11'd160,11'd80);
    send_and_check("n",1'b0,0);send_and_check(8'h0d,1'b1,"!");
    check_thresholds(11'd160,11'd80);
    if (shape_enable_req || !rect_line_fit_enable_req ||
        (line_support_level_req != 2'd0) ||
        (black_threshold_req != 8'd96)) begin
        $display("FAIL shape defaults enable=%b line_fit=%b support=%0d threshold=%0d",
                 shape_enable_req, rect_line_fit_enable_req,
                 line_support_level_req,
                 black_threshold_req);
        $fatal(1,"UART regression assertion failed");
    end

    // Line fitting is the reset default. J switches only the rectangle
    // classifier and replies with its new mode.
    send_and_check("J", 1'b1, "0");
    if (rect_line_fit_enable_req) begin
        $display("FAIL J did not select legacy rectangle detection");
        $fatal(1,"UART regression assertion failed");
    end
    send_and_check("j", 1'b1, "1");
    if (!rect_line_fit_enable_req) begin
        $display("FAIL j did not restore line-fit rectangle detection");
        $fatal(1,"UART regression assertion failed");
    end

    // K selects the line-support fraction. Values above three clamp to the
    // most permissive 1/8 setting.
    send_and_check("K", 1'b0, 8'h00);
    send_and_check("2", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    if (line_support_level_req != 2'd2) begin
        $display("FAIL K2 expected 1/4 support level, got %0d",
                 line_support_level_req);
        $fatal(1,"UART regression assertion failed");
    end
    send_and_check("k", 1'b0, 8'h00);
    send_and_check("9", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    if (line_support_level_req != 2'd3) begin
        $display("FAIL K9 expected clamped 1/8 support level, got %0d",
                 line_support_level_req);
        $fatal(1,"UART regression assertion failed");
    end

    // H and L select independent decimal targets. Low is clamped to high,
    // and lowering high also preserves the invariant low <= high.
    send_and_check("H", 1'b0, 8'h00);
    send_and_check("1", 1'b0, 8'h00);
    send_and_check("2", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    check_thresholds(11'd120, 11'd80);

    send_and_check("L", 1'b0, 8'h00);
    send_and_check("4", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    check_thresholds(11'd120, 11'd40);

    send_and_check("L", 1'b0, 8'h00);
    send_and_check("2", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    check_thresholds(11'd120, 11'd120);

    send_and_check("H", 1'b0, 8'h00);
    send_and_check("9", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    check_thresholds(11'd90, 11'd90);

    send_and_check("R", 1'b1, "R");
    check_thresholds(11'd160, 11'd80);

    // A and V independently toggle the gray and color edge algorithms.
    send_and_check("A", 1'b1, "C");
    check_state(1'b0, 1'b0, 2'd1, 1'b1, 1'b0);
    send_and_check("V", 1'b1, "C");
    check_state(1'b0, 1'b0, 2'd1, 1'b1, 1'b1);
    send_and_check("a", 1'b1, "S");
    check_state(1'b0, 1'b0, 2'd1, 1'b0, 1'b1);
    // Lowercase v is reserved for the "video" word parser in this project.
    send_and_check("V", 1'b1, "S");
    check_state(1'b0, 1'b0, 2'd1, 1'b0, 1'b0);

    // Freeze uses the previously unused bare F/f command and replies 1/0.
    send_and_check("F", 1'b1, "1");
    check_state(1'b1, 1'b0, 2'd1, 1'b0, 1'b0);
    send_and_check("f", 1'b1, "0");
    check_state(1'b0, 1'b0, 2'd1, 1'b0, 1'b0);

    // Shape detection is an independent display override. Bare B selects its
    // 8-bit threshold, while WB still selects blue gain after a W prefix.
    send_and_check("D", 1'b1, "1");
    if (!shape_enable_req) begin
        $display("FAIL shape detection did not enable");
        $fatal(1,"UART regression assertion failed");
    end
    send_and_check("B", 1'b1, "B");
    send_and_check("1", 1'b0, 8'h00);
    send_and_check("2", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    if (black_threshold_req != 8'd120) begin
        $display("FAIL black threshold expected 120, got %0d", black_threshold_req);
        $fatal(1,"UART regression assertion failed");
    end
    send_and_check("d", 1'b1, "0");
    if (shape_enable_req) begin
        $display("FAIL shape detection did not disable");
        $fatal(1,"UART regression assertion failed");
    end

    // Q is consumed by the multi-byte status reporter, not the one-byte reply
    // path. The request pulse lasts exactly one clock.
    @(negedge clk);
    rx_data = "Q";
    rx_valid = 1'b1;
    @(posedge clk);
    #1;
    if ((status_query_req !== 1'b1) || (tx_start !== 1'b0)) begin
        $display("FAIL Q expected query pulse without single-byte reply");
        $fatal(1,"UART regression assertion failed");
    end
    @(negedge clk);
    rx_valid = 1'b0;
    @(posedge clk);
    #1;
    if (status_query_req !== 1'b0) begin
        $display("FAIL Q query pulse lasted more than one clock");
        $fatal(1,"UART regression assertion failed");
    end

    // Existing median and mode commands remain independent of freeze.
    send_and_check("M", 1'b1, "1");
    check_state(1'b0, 1'b1, 2'd1, 1'b0, 1'b0);
    send_and_check("C", 1'b1, "0");
    check_state(1'b0, 1'b1, 2'd0, 1'b0, 1'b0);
    send_and_check("F", 1'b1, "1");
    check_state(1'b1, 1'b1, 2'd0, 1'b0, 1'b0);

    // WB uses B only after the W prefix; bare F does not collide with it.
    send_and_check("W", 1'b0, 8'h00);
    send_and_check("B", 1'b0, 8'h00);
    send_and_check("3", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check("0", 1'b0, 8'h00);
    send_and_check(8'h0D, 1'b1, "K");
    if (wb_blue_gain_req !== 11'd300) begin
        $display("FAIL WB command expected blue gain 300, got %0d", wb_blue_gain_req);
        $fatal(1,"UART regression assertion failed");
    end
    check_state(1'b1, 1'b1, 2'd0, 1'b0, 1'b0);

    send_and_check("F", 1'b1, "0");
    check_state(1'b0, 1'b1, 2'd0, 1'b0, 1'b0);

    $display("PASS UART/photo/gallery commands + retired game/U/N rejection without side effects");
    $finish;
end

endmodule
