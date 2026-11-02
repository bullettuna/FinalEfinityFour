`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"

// Self-checking controller test.  The debounce/long-press timing is covered by
// key_press_debounce (and the real 20 ms/800 ms values are used in hardware);
// this test drives the short/long events directly and checks the menu state,
// navigation, absolute control writes and the EDIT +/-1 behaviour.
module menu_ctrl_tb;
reg clk = 0;
reg rst_n = 0;
always #5 clk = ~clk;

reg key1_short = 0, key1_long = 0;
reg key_event = 0;
reg [1:0] key_code = 0;
reg [11:0] knob_value = 12'd2048;
reg knob_sample = 0;

reg [1:0] cur_view = 2'd2;          // EDGE
reg cur_split = 0, cur_shape = 0, cur_freeze = 0, cur_test = 0;
reg cur_median = 1, cur_gamma = 1;
reg [10:0] cur_high = 11'd45, cur_low = 11'd22;
reg [10:0] cur_wb_r = 11'd335, cur_wb_g = 11'd248, cur_wb_b = 11'd280;
reg [8:0]  cur_gamma_p = 9'd42;
reg [7:0]  cur_black = 8'd96;

wire menu_open;
wire write_valid;
wire [4:0] write_addr;
wire [11:0] write_value;
wire [`MENU_DISP_WIDTH-1:0] disp;

menu_ctrl dut (
    .clk(clk), .rst_n(rst_n),
    .key1_short(key1_short), .key1_long(key1_long),
    .key_event(key_event), .key_code(key_code),
    .knob_value(knob_value), .knob_sample(knob_sample),
    .cur_view(cur_view), .cur_split(cur_split), .cur_shape(cur_shape),
    .cur_freeze(cur_freeze), .cur_test(cur_test), .cur_median(cur_median),
    .cur_gamma(cur_gamma), .cur_high(cur_high), .cur_low(cur_low),
    .cur_wb_r(cur_wb_r), .cur_wb_g(cur_wb_g), .cur_wb_b(cur_wb_b),
    .cur_gamma_p(cur_gamma_p), .cur_black(cur_black),
    .menu_open(menu_open),
    .write_valid(write_valid), .write_addr(write_addr), .write_value(write_value),
    .disp(disp)
);

// Sticky capture: write_valid is a single-cycle pulse, so the checker records
// the pulse on the following edge instead of trying to observe it live.
reg        wr_seen = 0;
reg [4:0]  wr_addr = 0;
reg [11:0] wr_val  = 0;
always @(posedge clk) begin
    if (write_valid) begin
        wr_seen <= 1'b1;
        wr_addr <= write_addr;
        wr_val  <= write_value;
    end
end

function [1:0] dstate;  dstate  = disp[`MD_STATE_OFF  +: 2]; endfunction
function [4:0] dcursor; dcursor = disp[`MD_CURSOR_OFF +: 5]; endfunction
function [4:0] dwindow; dwindow = disp[`MD_WINDOW_OFF +: 5]; endfunction
function [15:0] dhigh;  dhigh   = disp[`MD_HIGH_OFF   +: 16]; endfunction

task clear_write;
    begin
        @(posedge clk); #1;
        wr_seen = 1'b0;
    end
endtask

task expect_state;
    input [1:0] want;
    input [255:0] msg;
    begin
        #1;
        if (dstate !== want) $fatal(1, "FAIL %0s state=%0d want %0d", msg, dstate, want);
        $display("PASS %0s state=%0d", msg, dstate);
    end
endtask

task expect_cursor;
    input [4:0] want;
    input [255:0] msg;
    begin
        #1;
        if (dcursor !== want) $fatal(1, "FAIL %0s cursor=%0d want %0d", msg, dcursor, want);
        if (dwindow > 5'd11) $fatal(1, "FAIL %0s window=%0d out of range", msg, dwindow);
        $display("PASS %0s cursor=%0d window=%0d", msg, dcursor, dwindow);
    end
endtask

task expect_write;
    input [4:0] want_addr;
    input [11:0] want_value;
    input [255:0] msg;
    integer waits;
    begin
        waits = 0;
        while (!wr_seen && waits < 8) begin
            @(posedge clk); #1;
            waits = waits + 1;
        end
        if (!wr_seen) $fatal(1, "FAIL %0s: no write pulse", msg);
        if ((wr_addr !== want_addr) || (wr_val !== want_value))
            $fatal(1, "FAIL %0s write addr=%0d value=%0d want %0d/%0d",
                   msg, wr_addr, wr_val, want_addr, want_value);
        $display("PASS %0s write %0d=%0d", msg, wr_addr, wr_val);
    end
endtask

task expect_no_write;
    input [255:0] msg;
    integer i;
    begin
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk); #1;
            if (wr_seen) $fatal(1, "FAIL %0s unexpected write addr=%0d value=%0d",
                                msg, wr_addr, wr_val);
        end
    end
endtask

task do_long;
    begin
        @(posedge clk); #1; key1_long = 1;
        @(posedge clk); #1; key1_long = 0;
        @(posedge clk); #1;
    end
endtask

task do_short;
    begin
        @(posedge clk); #1; key1_short = 1;
        @(posedge clk); #1; key1_short = 0;
        @(posedge clk); #1;
    end
endtask

task do_key;
    input [1:0] code;
    begin
        @(posedge clk); #1; key_event = 1; key_code = code;
        @(posedge clk); #1; key_event = 0; key_code = 0;
        @(posedge clk); #1;
    end
endtask

task do_knob;
    input [11:0] value;
    begin
        @(posedge clk); #1; knob_value = value; knob_sample = 1;
        @(posedge clk); #1; knob_sample = 0;
        @(posedge clk); #1;
    end
endtask

// The controller ignores the first eight averaged samples after entering
// EDIT.  Keep the knob still while those samples drain.
task drain_settle;
    integer n;
    begin
        for (n = 0; n < 10; n = n + 1)
            do_knob(12'd2048);
    end
endtask

integer i;
initial begin
    if ($test$plusargs("dump")) begin
        $dumpfile("menu_ctrl.vcd");
        $dumpvars(0, menu_ctrl_tb);
    end
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    if (menu_open !== 1'b0) $fatal(1, "FAIL reset leaves menu open");
    expect_state(`MENU_STATE_CLOSED, "reset");

    // Long press opens; KEY2/KEY3 navigate with wrap.
    do_long;
    if (menu_open !== 1'b1) $fatal(1, "FAIL long press did not open menu");
    expect_state(`MENU_STATE_BROWSE, "long press open");
    expect_cursor(5'd0, "initial cursor");

    do_key(2'd2); expect_cursor(5'd1, "KEY3 down");
    do_key(2'd1); expect_cursor(5'd0, "KEY2 up");
    do_key(2'd1); expect_cursor(19-1, "KEY2 wraps to last item");
    do_key(2'd2); expect_cursor(5'd0, "KEY3 wraps to first item");

    // VIEW is an enum: a short press writes the next absolute mode.
    clear_write;
    do_short;
    expect_write(`MENU_ITEM_VIEW, 12'd3, "VIEW advances EDGE->EDGE-RGB");
    expect_state(`MENU_STATE_BROWSE, "VIEW stays in BROWSE");
    cur_view = 2'd3;

    // Move to CANNY H (item 6) and edit by one minimum step with KEY2/KEY3.
    for (i = 0; i < 6; i = i + 1) do_key(2'd2);
    expect_cursor(5'd6, "cursor on CANNY H");
    do_short;
    expect_state(`MENU_STATE_EDIT, "short press enters EDIT");
    if (dhigh !== 16'h0045) $fatal(1, "FAIL initial edit value %h", dhigh);
    drain_settle;

    clear_write;
    do_key(2'd1);
    expect_write(`MENU_ITEM_CANNY_H, 12'd46, "KEY2 +1");
    if (dhigh !== 16'h0046) $fatal(1, "FAIL display did not follow +1: %h", dhigh);
    cur_high = 11'd46;

    clear_write;
    do_key(2'd2);
    expect_write(`MENU_ITEM_CANNY_H, 12'd45, "KEY3 -1");
    cur_high = 11'd45;

    // Knob coarse edit: +16 raw counts = +4 at shift 2, then -16 = -4.
    clear_write;
    do_knob(12'd2064);
    expect_write(`MENU_ITEM_CANNY_H, 12'd49, "knob +16");
    cur_high = 11'd49;

    clear_write;
    do_knob(12'd2048);
    expect_write(`MENU_ITEM_CANNY_H, 12'd45, "knob -16");
    cur_high = 11'd45;

    do_short;
    expect_state(`MENU_STATE_BROWSE, "second short press confirms");

    // Back to SPLIT (item 1): a toggle writes the opposite absolute state.
    for (i = 0; i < 5; i = i + 1) do_key(2'd1);
    expect_cursor(5'd1, "cursor on SPLIT");
    clear_write;
    do_short;
    expect_write(`MENU_ITEM_SPLIT, 12'd1, "SPLIT turns on");
    expect_state(`MENU_STATE_BROWSE, "toggle stays in BROWSE");
    cur_split = 1;

    // Action item: CANNY RST executes immediately.
    for (i = 0; i < 7; i = i + 1) do_key(2'd2);
    expect_cursor(5'd8, "cursor on CANNY RST");
    clear_write;
    do_short;
    expect_write(`MENU_ITEM_CANNY_RST, 12'd0, "CANNY RST executes");

    // Knob scroll in BROWSE: one 256-count step moves one item in each direction.
    do_knob(12'd2304);
    expect_cursor(5'd9, "knob scrolls down one item");
    do_knob(12'd2048);
    expect_cursor(5'd8, "knob scrolls back up one item");

    // Closing stops all menu input.
    do_long;
    expect_state(`MENU_STATE_CLOSED, "long press closes");
    if (menu_open !== 1'b0) $fatal(1, "FAIL menu_open still high");
    clear_write;
    do_key(2'd2);
    do_short;
    expect_no_write("closed input is ignored");

    // Reopen and check the edit value uses the current effective value.
    // The cursor is still on CANNY RST (8) after the reverse scroll.
    do_long;
    expect_state(`MENU_STATE_BROWSE, "reopen");
    do_key(2'd1);
    do_key(2'd1);
    expect_cursor(5'd6, "cursor back on CANNY H");
    do_short;
    expect_state(`MENU_STATE_EDIT, "re-enter EDIT");
    if (dhigh !== 16'h0045) $fatal(1, "FAIL re-enter value %h", dhigh);

    // WB regression: small ADC dither around the rest position must not change
    // the value.  This reproduces the reported "automatic decrement" failure.
    do_short;
    expect_state(`MENU_STATE_BROWSE, "leave CANNY H");
    for (i = 0; i < 4; i = i + 1) do_key(2'd2);
    expect_cursor(5'd10, "cursor on WB R");
    do_short;
    expect_state(`MENU_STATE_EDIT, "WB R enters EDIT");
    drain_settle;

    clear_write;
    do_knob(12'd2044);
    expect_no_write("WB dither -4 ignored");
    clear_write;
    do_knob(12'd2052);
    expect_no_write("WB dither +4 ignored");

    clear_write;
    do_knob(12'd2064);
    expect_write(`MENU_ITEM_WB_R, 12'd339, "WB knob +16 -> +4");
    clear_write;
    do_knob(12'd2048);
    expect_write(`MENU_ITEM_WB_R, 12'd335, "WB knob -16 -> -4");

    $display("PASS menu_ctrl: navigation, wrap, window, absolute writes, EDIT +/-1, knob deadband, WB dither immunity");
    $finish;
end

initial begin
    #5_000_000;
    $fatal(1, "FAIL timeout");
end
endmodule
