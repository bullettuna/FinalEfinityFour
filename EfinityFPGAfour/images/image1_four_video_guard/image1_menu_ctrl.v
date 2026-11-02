`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"

// image1 menu controller.  Runs entirely in clk_sys, where the ADC, knob and
// keys already live.  It never touches video timing: it only emits absolute
// control writes, which uart_vision_ctrl applies to the same registers that
// the serial commands own.  That keeps one source of truth for every setting.
//
// Interaction
//   KEY1 long  : open / close the menu
//   KEY1 short : BROWSE -> EDIT for numeric items; toggle / next enum / action
//                EDIT   -> confirm and return to BROWSE
//   KEY2/KEY3  : BROWSE -> previous / next item
//                EDIT   -> value -1 / +1
//   Knob       : BROWSE -> scroll the list
//                EDIT   -> coarse value adjustment
module menu_ctrl #(
    parameter integer KNOB_SCROLL_STEP = 256,
    // The CH0 eight-sample average can still move by a few LSBs with the knob
    // untouched.  The original adc_threshold_ctrl used a deadband for exactly
    // this reason; the EDIT path must use one too, otherwise WB/Gamma values
    // appear to drift down on their own.
    parameter integer KNOB_DEADBAND    = 16
)(
    input [1:0] boot_selected,input [3:0] boot_status,
    input clk,
    input rst_n,

    input key1_short,
    input key1_long,
    input key_event,
    input [1:0] key_code,

    input [11:0] knob_value,
    input knob_sample,

    // Current effective values, all in clk_sys.
    input [1:0] cur_view,
    input cur_split, cur_shape, cur_freeze, cur_test, cur_median, cur_gamma,
    input [10:0] cur_high, cur_low,
    input [10:0] cur_wb_r, cur_wb_g, cur_wb_b,
    input [8:0]  cur_gamma_p,
    input [7:0]  cur_black,

    output menu_open,
    output reg write_valid,
    output reg [4:0] write_addr,
    output reg [11:0] write_value,

    output [`MENU_DISP_WIDTH-1:0] disp
);
localparam integer SCROLL_SHIFT = $clog2(KNOB_SCROLL_STEP);

reg [1:0] state;
reg [4:0] cursor;
reg [4:0] window_start;
reg [11:0] edit_value;
reg [11:0] knob_base;
reg [3:0]  edit_settle;

assign menu_open = (state != `MENU_STATE_CLOSED);

// 0 = numeric, 1 = toggle, 2 = enum, 3 = action.
function [1:0] item_type;
    input [4:0] idx;
    begin
        case (idx)
            `MENU_ITEM_BOOT, `MENU_ITEM_VIEW:      item_type = 2'd2;
            `MENU_ITEM_SPLIT,
            `MENU_ITEM_SHAPE,
            `MENU_ITEM_FREEZE,
            `MENU_ITEM_TEST,
            `MENU_ITEM_MEDIAN,
            `MENU_ITEM_GAMMA:     item_type = 2'd1;
            `MENU_ITEM_CANNY_RST,
            `MENU_ITEM_LOAD, `MENU_ITEM_WB_RST:    item_type = 2'd3;
            default:              item_type = 2'd0;
        endcase
    end
endfunction

function [2:0] item_shift;
    input [4:0] idx;
    begin
        case (idx)
            `MENU_ITEM_GAMMA_P,
            `MENU_ITEM_BLACK: item_shift = 3'd4;
            default:          item_shift = 3'd2;
        endcase
    end
endfunction

function [11:0] item_max;
    input [4:0] idx;
    input [10:0] high;
    begin
        case (idx)
            `MENU_ITEM_CANNY,
            `MENU_ITEM_CANNY_H,
            `MENU_ITEM_WB_R,
            `MENU_ITEM_WB_G,
            `MENU_ITEM_WB_B:  item_max = 12'd2047;
            `MENU_ITEM_CANNY_L: item_max = {1'b0, high};
            `MENU_ITEM_GAMMA_P: item_max = 12'd256;
            `MENU_ITEM_BLACK:   item_max = 12'd255;
            default:            item_max = 12'd2047;
        endcase
    end
endfunction

function [4:0] cursor_forward;
    input [4:0] c;
    input [4:0] n;
    reg [5:0] t;
    begin
        t = {1'b0, c} + {1'b0, n};
        if (t >= `MENU_ITEM_COUNT)
            t = t - `MENU_ITEM_COUNT;
        cursor_forward = t[4:0];
    end
endfunction

function [4:0] cursor_backward;
    input [4:0] c;
    input [4:0] n;
    reg [5:0] t;
    begin
        if ({1'b0, c} >= {1'b0, n})
            t = {1'b0, c} - {1'b0, n};
        else
            t = {1'b0, c} + `MENU_ITEM_COUNT - {1'b0, n};
        cursor_backward = t[4:0];
    end
endfunction

// Value currently under the cursor, used when EDIT begins.
reg [11:0] current_item_value;
always @* begin
    case (cursor)
        `MENU_ITEM_CANNY, `MENU_ITEM_CANNY_H: current_item_value = {1'b0, cur_high};
        `MENU_ITEM_CANNY_L:                   current_item_value = {1'b0, cur_low};
        `MENU_ITEM_WB_R:                      current_item_value = {1'b0, cur_wb_r};
        `MENU_ITEM_WB_G:                      current_item_value = {1'b0, cur_wb_g};
        `MENU_ITEM_WB_B:                      current_item_value = {1'b0, cur_wb_b};
        `MENU_ITEM_GAMMA_P:                   current_item_value = {3'd0, cur_gamma_p};
        `MENU_ITEM_BLACK:                     current_item_value = {4'd0, cur_black};
        default:                              current_item_value = 12'd0;
    endcase
end

wire signed [12:0] knob_delta = $signed({1'b0, knob_value}) - $signed({1'b0, knob_base});
wire signed [12:0] knob_magnitude = (knob_delta >= 0) ? knob_delta : -knob_delta;
wire signed [12:0] knob_step_magnitude = knob_magnitude >>> item_shift(cursor);
wire signed [12:0] knob_edit_step = (knob_delta >= 0) ? knob_step_magnitude : -knob_step_magnitude;
// Keep the scroll direction signed.  Computing two unsigned differences would
// underflow when the knob moves backwards and would look like a large forward
// step.
wire signed [12:0] scroll_fwd = (knob_delta > 0) ? knob_delta : 13'sd0;
wire signed [12:0] scroll_rev = (knob_delta < 0) ? -knob_delta : 13'sd0;
wire [4:0] scroll_steps_fwd = scroll_fwd >> SCROLL_SHIFT;
wire [4:0] scroll_steps_rev = scroll_rev >> SCROLL_SHIFT;

task issue_write;
    input [4:0] addr;
    input [11:0] value;
    begin
        write_valid <= 1'b1;
        write_addr  <= addr;
        write_value <= value;
    end
endtask

task toggle_write;
    input [4:0] idx;
    begin
        case (idx)
            `MENU_ITEM_SPLIT:  issue_write(idx, {11'd0, ~cur_split});
            `MENU_ITEM_SHAPE:  issue_write(idx, {11'd0, ~cur_shape});
            `MENU_ITEM_FREEZE: issue_write(idx, {11'd0, ~cur_freeze});
            `MENU_ITEM_TEST:   issue_write(idx, {11'd0, ~cur_test});
            `MENU_ITEM_MEDIAN: issue_write(idx, {11'd0, ~cur_median});
            `MENU_ITEM_GAMMA:  issue_write(idx, {11'd0, ~cur_gamma});
            default: ;
        endcase
    end
endtask

// Clamp a signed candidate into the numeric item's range.
reg [11:0] max_value;
reg signed [13:0] edit_sum;
reg [11:0] edit_candidate;
always @* begin
    max_value = item_max(cursor, cur_high);
    edit_sum = $signed({2'b0, edit_value}) + knob_edit_step;
    if (edit_sum < 0)
        edit_candidate = 12'd0;
    else if (edit_sum > $signed({2'b0, max_value}))
        edit_candidate = max_value;
    else
        edit_candidate = edit_sum[11:0];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= `MENU_STATE_CLOSED;
        cursor       <= 5'd0;
        window_start <= 5'd0;
        edit_value   <= 12'd0;
        knob_base    <= 12'd0;
        edit_settle  <= 4'd0;
        write_valid  <= 1'b0;
        write_addr   <= 5'd0;
        write_value  <= 12'd0;
    end else begin
        write_valid <= 1'b0;

        if (key1_long) begin
            if (state == `MENU_STATE_CLOSED) begin
                state       <= `MENU_STATE_BROWSE;
                knob_base   <= knob_value;
                edit_settle <= 4'd0;
            end else begin
                state       <= `MENU_STATE_CLOSED;
                knob_base   <= knob_value;
                edit_settle <= 4'd0;
            end
        end else if (key1_short) begin
            if (state == `MENU_STATE_BROWSE) begin
                case (item_type(cursor))
                    2'd0: begin
                        state       <= `MENU_STATE_EDIT;
                        edit_value  <= current_item_value;
                        knob_base   <= knob_value;
                        // Ignore the first eight averaged samples: the ADC
                        // average is still settling when the key is released.
                        edit_settle <= 4'd8;
                    end
                    2'd1: toggle_write(cursor);
                    2'd2: if(cursor==`MENU_ITEM_BOOT) issue_write(cursor,{10'd0,boot_selected+2'd1});
                    else issue_write(`MENU_ITEM_VIEW,
                                      {10'd0, (cur_view == 2'd3) ? 2'd0 : cur_view + 2'd1});
                    default: issue_write(cursor, 12'd0);
                endcase
            end else if (state == `MENU_STATE_EDIT) begin
                state       <= `MENU_STATE_BROWSE;
                knob_base   <= knob_value;
                edit_settle <= 4'd0;
            end
        end else if (key_event) begin
            if (state == `MENU_STATE_BROWSE) begin
                if (key_code == 2'd1) begin
                    cursor <= cursor_backward(cursor, 5'd1);
                end else if (key_code == 2'd2) begin
                    cursor <= cursor_forward(cursor, 5'd1);
                end
            end else if (state == `MENU_STATE_EDIT) begin
                // KEY2 is the "up" key: in EDIT it raises by one minimum step.
                if (key_code == 2'd1) begin
                    if (edit_value < max_value)
                        edit_value <= edit_value + 1'b1;
                    issue_write(cursor, (edit_value < max_value) ? edit_value + 1'b1 : max_value);
                end else if (key_code == 2'd2) begin
                    if (edit_value != 12'd0)
                        edit_value <= edit_value - 1'b1;
                    issue_write(cursor, (edit_value != 12'd0) ? edit_value - 1'b1 : 12'd0);
                end
            end
        end else if (knob_sample) begin
            if (state == `MENU_STATE_BROWSE) begin
                if (scroll_fwd >= KNOB_SCROLL_STEP) begin
                    cursor    <= cursor_forward(cursor, scroll_steps_fwd);
                    knob_base <= knob_base + (scroll_steps_fwd << SCROLL_SHIFT);
                end else if (scroll_rev >= KNOB_SCROLL_STEP) begin
                    cursor    <= cursor_backward(cursor, scroll_steps_rev);
                    knob_base <= knob_base - (scroll_steps_rev << SCROLL_SHIFT);
                end
            end else if (state == `MENU_STATE_EDIT) begin
                if (edit_settle != 0) begin
                    // Let the eight-sample ADC average settle before edits.
                    edit_settle <= edit_settle - 1'b1;
                    knob_base   <= knob_value;
                end else if (((knob_delta >= KNOB_DEADBAND) ||
                              (knob_delta <= -KNOB_DEADBAND)) &&
                             (knob_edit_step != 0)) begin
                    edit_value <= edit_candidate;
                    knob_base  <= knob_value;
                    issue_write(cursor, edit_candidate);
                end
            end else begin
                knob_base <= knob_value;
            end
        end

        // Keep the visible window on the cursor.  Window 0..9 leaves all eight
        // rows inside the 17-item list.
        if (state != `MENU_STATE_CLOSED) begin
            if (cursor < window_start)
                window_start <= cursor;
            else if (cursor >= window_start + `MENU_VISIBLE_ROWS)
                window_start <= cursor - (`MENU_VISIBLE_ROWS - 1);
        end
    end
end

// ---------------------------------------------------------------------------
// Display record.  Numeric fields use the live edit value while EDIT is active
// so the screen responds before the control write has propagated.
// ---------------------------------------------------------------------------
wire [11:0] disp_high_val =
    ((state == `MENU_STATE_EDIT) &&
     ((cursor == `MENU_ITEM_CANNY) || (cursor == `MENU_ITEM_CANNY_H))) ?
    edit_value : {1'b0, cur_high};
wire [11:0] disp_low_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_CANNY)) ?
    {1'b0, edit_value[11:1]} :
    (((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_CANNY_L)) ?
     edit_value : {1'b0, cur_low});
wire [11:0] disp_wbr_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_WB_R)) ? edit_value : {1'b0, cur_wb_r};
wire [11:0] disp_wbg_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_WB_G)) ? edit_value : {1'b0, cur_wb_g};
wire [11:0] disp_wbb_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_WB_B)) ? edit_value : {1'b0, cur_wb_b};
wire [11:0] disp_gamma_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_GAMMA_P)) ?
    {3'd0, edit_value[8:0]} : {3'd0, cur_gamma_p};
wire [11:0] disp_black_val =
    ((state == `MENU_STATE_EDIT) && (cursor == `MENU_ITEM_BLACK)) ?
    {4'd0, edit_value[7:0]} : {4'd0, cur_black};

function [15:0] bcd4;
    input [11:0] v;
    reg [3:0] d3, d2, d1, d0;
    begin
        d3 = v / 1000;
        d2 = (v / 100) % 10;
        d1 = (v / 10) % 10;
        d0 = v % 10;
        bcd4 = {d3, d2, d1, d0};
    end
endfunction

function [11:0] bcd3;
    input [11:0] v;
    reg [3:0] d2, d1, d0;
    begin
        d2 = (v / 100) % 10;
        d1 = (v / 10) % 10;
        d0 = v % 10;
        bcd3 = {d2, d1, d0};
    end
endfunction

reg [`MENU_DISP_WIDTH-1:0] disp_r;
always @* begin
    disp_r = {`MENU_DISP_WIDTH{1'b0}};
    disp_r[`MD_BOOT_OFF+:2]=boot_selected;
    disp_r[`MD_BOOT_STATUS_OFF+:4]=boot_status;
    disp_r[`MD_STATE_OFF  +: 2]  = state;
    disp_r[`MD_CURSOR_OFF +: 5]  = cursor;
    disp_r[`MD_WINDOW_OFF +: 5]  = window_start;
    disp_r[`MD_VIEW_OFF   +: 2]  = cur_view;
    disp_r[`MD_FLAGS_OFF  +: 6]  = {cur_gamma, cur_median, cur_test,
                                    cur_freeze, cur_shape, cur_split};
    disp_r[`MD_HIGH_OFF   +: 16] = bcd4(disp_high_val);
    disp_r[`MD_LOW_OFF    +: 16] = bcd4(disp_low_val);
    disp_r[`MD_WBR_OFF    +: 16] = bcd4(disp_wbr_val);
    disp_r[`MD_WBG_OFF    +: 16] = bcd4(disp_wbg_val);
    disp_r[`MD_WBB_OFF    +: 16] = bcd4(disp_wbb_val);
    disp_r[`MD_GAMMA_OFF  +: 12] = bcd3(disp_gamma_val);
    disp_r[`MD_BLACK_OFF  +: 12] = bcd3(disp_black_val);
end

assign disp = disp_r;

endmodule
