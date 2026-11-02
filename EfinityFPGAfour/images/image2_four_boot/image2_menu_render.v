`timescale 1ns/1ps
`include "images/image2_four_boot/image2_menu_defs.vh"

// Text-only overlay in the top-left corner of the live 1080p picture.
//
// VS/HS/DE and RGB all pass through exactly three register stages, so the
// HDMI waveform keeps its original line width, frame period and polarity.
// Only pixels inside the menu rectangle are substituted; everywhere else the
// output is the input delayed by three clocks.  When the menu is closed the
// same three-stage path is a pure delay.
//
// Geometry: 30 columns x 12 rows, 18 x 24 pixels per cell.  The 5x7 glyph is
// enlarged 3x (15 x 21 pixels), leaving a 3-pixel margin on the right/bottom.
module image2_menu_render #(
    parameter H_DISP = 1920,
    parameter V_DISP = 1080,
    parameter MENU_X = 8,
    parameter MENU_Y = 8,
    parameter CELL_W = 18,
    parameter CELL_H = 24,
    parameter COLS   = 30,
    parameter ROWS   = 12
)(
    input clk,
    input rst_n,
    input in_vsync,
    input in_hsync,
    input in_href,
    input [23:0] in_rgb,
    input [`MENU_DISP_WIDTH-1:0] disp,
    output reg out_vsync,
    output reg out_hsync,
    output reg out_href,
    output reg [23:0] out_rgb
);
localparam [23:0] TEXT_COLOR   = 24'hFFFFFF;
localparam [23:0] SELECT_COLOR = 24'hFFFF00;
localparam [23:0] EDIT_COLOR   = 24'h00FFFF;
localparam [23:0] BACKDROP     = 24'h101020;
localparam [11:0] MENU_W = COLS * CELL_W;
localparam [11:0] MENU_H = ROWS * CELL_H;

wire [1:0]  d_state  = disp[`MD_STATE_OFF  +: 2];
wire [4:0]  d_cursor = disp[`MD_CURSOR_OFF +: 5];
wire [4:0]  d_window = disp[`MD_WINDOW_OFF +: 5];
wire [1:0]  d_view   = disp[`MD_VIEW_OFF   +: 2];
wire [15:0] d_high   = disp[`MD_HIGH_OFF   +: 16];
wire [15:0] d_low    = disp[`MD_LOW_OFF    +: 16];
wire [15:0] d_wbr    = disp[`MD_WBR_OFF    +: 16];
wire [15:0] d_wbg    = disp[`MD_WBG_OFF    +: 16];
wire [15:0] d_wbb    = disp[`MD_WBB_OFF    +: 16];
wire [11:0] d_gamma  = disp[`MD_GAMMA_OFF  +: 12];
wire [11:0] d_black  = disp[`MD_BLACK_OFF  +: 12];

// ---------------------------------------------------------------------------
// Pixel coordinates of the incoming stream, in the active video area.
// ---------------------------------------------------------------------------
reg [11:0] x_cnt, y_cnt;
reg href_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_cnt  <= 12'd0;
        y_cnt  <= 12'd0;
        href_d <= 1'b0;
    end else begin
        href_d <= in_href;
        if (!in_vsync)
            y_cnt <= 12'd0;
        else if (!in_href && href_d)
            y_cnt <= y_cnt + 1'b1;
        if (!in_href)
            x_cnt <= 12'd0;
        else
            x_cnt <= x_cnt + 1'b1;
    end
end

// Cell counters avoid a divide by 18/24 in the 148.5 MHz pixel path.  The
// counters hold the coordinate of the current pixel; they advance for the
// next pixel and reset during blanking.
reg [4:0] col_in_cell;   // 0..17
reg [4:0] cell_col;      // 0..29
reg [4:0] line_in_cell;  // 0..23
reg [3:0] cell_row;      // 0..11
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_in_cell  <= 5'd0;
        cell_col     <= 5'd0;
        line_in_cell <= 5'd0;
        cell_row     <= 4'd0;
    end else begin
        if (!in_href) begin
            col_in_cell <= 5'd0;
            cell_col    <= 5'd0;
        end else if (x_cnt >= MENU_X) begin
            if (col_in_cell == CELL_W-1) begin
                col_in_cell <= 5'd0;
                if (cell_col < COLS-1)
                    cell_col <= cell_col + 1'b1;
            end else begin
                col_in_cell <= col_in_cell + 1'b1;
            end
        end

        if (!in_vsync) begin
            line_in_cell <= 5'd0;
            cell_row     <= 4'd0;
        end else if (!in_href && href_d && (y_cnt >= MENU_Y)) begin
            if (line_in_cell == CELL_H-1) begin
                line_in_cell <= 5'd0;
                if (cell_row < ROWS-1)
                    cell_row <= cell_row + 1'b1;
            end else begin
                line_in_cell <= line_in_cell + 1'b1;
            end
        end
    end
end

wire in_region = in_href &&
                 (x_cnt >= MENU_X) && (x_cnt < MENU_X + MENU_W) &&
                 (y_cnt >= MENU_Y) && (y_cnt < MENU_Y + MENU_H);

wire item_row = (cell_row >= 4'd1) && (cell_row <= 4'd8);
wire [4:0] row_item = d_window + {1'b0, cell_row} - 5'd1;

// Footer rows reuse items 17..20 of the same character ROM.
wire [4:0] rom_item =
    (cell_row == 4'd10) ? ((d_state == `MENU_STATE_EDIT) ? 5'd21 : 5'd19) :
    (cell_row == 4'd11) ? ((d_state == `MENU_STATE_EDIT) ? 5'd22 : 5'd20) :
    row_item;
wire [7:0] template_ch;
image2_menu_rom u_text_rom (
    .item(rom_item),
    .col(cell_col),
    .ch(template_ch)
);

// ---------------------------------------------------------------------------
// Small character helpers
// ---------------------------------------------------------------------------
wire [4:0] pos = d_cursor + 5'd1;
wire [7:0] pos_tens = pos>=30 ? "3" : pos>=20 ? "2" : pos>=10 ? "1" : " ";
wire [7:0] pos_ones = "0"+(pos>=30 ? pos-30 : pos>=20 ? pos-20 : pos>=10 ? pos-10 : pos);

// 5x7 glyph enlarged 3x: 0..14 -> columns 0..4, 15..17 -> blank.
function [2:0] scale3;
    input [4:0] v;
    begin
        case (v)
            5'd0, 5'd1, 5'd2:       scale3 = 3'd0;
            5'd3, 5'd4, 5'd5:       scale3 = 3'd1;
            5'd6, 5'd7, 5'd8:       scale3 = 3'd2;
            5'd9, 5'd10, 5'd11:     scale3 = 3'd3;
            5'd12, 5'd13, 5'd14:    scale3 = 3'd4;
            5'd15, 5'd16, 5'd17:    scale3 = 3'd5;
            5'd18, 5'd19, 5'd20:    scale3 = 3'd6;
            default:                scale3 = 3'd7;
        endcase
    end
endfunction

function [7:0] bcd4_digit;
    input [15:0] bcd;
    input [1:0] posn;   // 0 = thousands ... 3 = ones
    reg [3:0] d3, d2, d1, d0;
    begin
        d3 = bcd[15:12];
        d2 = bcd[11:8];
        d1 = bcd[7:4];
        d0 = bcd[3:0];
        case (posn)
            2'd0: bcd4_digit = (d3 == 0) ? 8'h20 : (8'h30 + d3);
            2'd1: bcd4_digit = ((d3 == 0) && (d2 == 0)) ? 8'h20 : (8'h30 + d2);
            2'd2: bcd4_digit = ((d3 == 0) && (d2 == 0) && (d1 == 0)) ?
                               8'h20 : (8'h30 + d1);
            default: bcd4_digit = 8'h30 + d0;
        endcase
    end
endfunction

function [7:0] bcd3_digit;
    input [11:0] bcd;
    input [1:0] posn;   // 0 = hundreds, 1 = tens, 2 = ones
    reg [3:0] d2, d1, d0;
    begin
        d2 = bcd[11:8];
        d1 = bcd[7:4];
        d0 = bcd[3:0];
        case (posn)
            2'd0: bcd3_digit = (d2 == 0) ? 8'h20 : (8'h30 + d2);
            2'd1: bcd3_digit = ((d2 == 0) && (d1 == 0)) ? 8'h20 : (8'h30 + d1);
            default: bcd3_digit = 8'h30 + d0;
        endcase
    end
endfunction

function [7:0] view_char;
    input [1:0] v;
    input [2:0] idx;
    begin
        view_char = 8'h20;
        case (v)
            2'd0: case (idx)
                3'd0: view_char = "C";
                3'd1: view_char = "O";
                3'd2: view_char = "L";
                3'd3: view_char = "O";
                3'd4: view_char = "R";
                default: view_char = " ";
            endcase
            2'd1: case (idx)
                3'd0: view_char = "G";
                3'd1: view_char = "R";
                3'd2: view_char = "A";
                3'd3: view_char = "Y";
                default: view_char = " ";
            endcase
            2'd2: case (idx)
                3'd0: view_char = "E";
                3'd1: view_char = "D";
                3'd2: view_char = "G";
                3'd3: view_char = "E";
                default: view_char = " ";
            endcase
            default: case (idx)
                3'd0: view_char = "E";
                3'd1: view_char = "D";
                3'd2: view_char = "G";
                3'd3: view_char = "E";
                3'd4: view_char = "-";
                3'd5: view_char = "R";
                3'd6: view_char = "G";
                default: view_char = "B";
            endcase
        endcase
    end
endfunction

function [7:0] boot_char;
 input [1:0] slot;input [2:0] index;reg [47:0] word_;
 begin
  case(slot)0:word_="IMAGE7";1:word_="IMAGE1";2:word_="IMAGE5";default:word_="IMAGE2";endcase
  boot_char=word_[(5-index)*8+:8];
 end
endfunction
function [7:0] boot_status_char;
 input [3:0] state_;input [2:0] index;reg [63:0] word_;
 begin
  case(state_)0:word_="READY   ";1:word_="WAIT    ";2:word_="LOAD    ";3:word_="ERROR   ";default:word_="HERE    ";endcase
  boot_status_char=word_[(7-index)*8+:8];
 end
endfunction

function [7:0] hex_char;input [3:0] n;begin hex_char=n<10?"0"+n:"A"+n-10;end endfunction
function [7:0] sd_char;input [1:0] v;input [2:0] idx;reg [63:0] word_;begin
case(v)0:word_="UNCHECK ";1:word_="WAIT    ";2:word_="PASS    ";3:word_="FAIL    ";endcase
sd_char=word_[(7-idx)*8+:8];end endfunction
function [7:0] delete_char;input armed;input [3:0] idx;reg [95:0] word_;begin
word_=armed?"PRESS AGAIN ":"PRESS K1    ";delete_char=word_[(11-idx)*8+:8];end endfunction
function [7:0] status_char;input [3:0] ev;input busy;input [7:0] code;input [3:0] stage;input [2:0] photo;input [4:0] idx;reg [239:0] word_;begin
case(ev)
0:word_="DDR READY                     ";
1:word_="OK                            ";
2:word_="CAPTURE ERROR                 ";
3:word_="SAVE ERROR                    ";
4:word_="BUSY / REJECTED               ";
5:word_="SD PASS                       ";
6:word_="SD FAIL                       ";
7:word_="DDR ERROR                     ";
8:word_="SAVE TIMEOUT                  ";
9:word_="FAULT / RETRY                 ";
10:word_="BMP READY                     ";
11:word_="BMP ERROR                     ";
12:word_="LIVE                          ";
13:word_="DISPLAY ERROR                 ";
14:case(code)
0:word_="CONFIRM DELETE                ";
1:word_="DELETED                       ";
2:word_="DELETE FAIL                   ";
3:word_="ALBUM EMPTY                   ";
default:word_="DELETE CANCELED               ";endcase
15:word_=code==0?"PROCESSING                    ":"PROCESS ERROR                 ";
endcase
if(photo==3&&(stage==9||stage==10||ev==2||ev==3||ev==7||ev==8||ev==9||ev==15))word_="ERROR                         ";
else if(busy||photo==1)word_="WAIT                          ";
status_char=word_[(29-idx)*8+:8];end endfunction
function [7:0] photo_char;input [2:0] status_;input [2:0] idx;reg [55:0] word_;begin
 case(status_)0:word_="READY  ";1:word_="WAIT   ";2:word_="OK     ";3:word_="ERROR  ";default:word_="BUSY   ";endcase
 photo_char=word_[(6-idx)*8+:8];end endfunction
function [7:0] footer_char;input [4:0] idx;reg [239:0] word_;begin
word_="K2/3 NAV K1 OK HOLD EXITS  E  ";footer_char=word_[(29-idx)*8+:8];end endfunction

function is_toggle_item;
    input [4:0] idx;
    begin
        case (idx)
            `MENU_ITEM_FREEZE,
            `MENU_ITEM_TEST,
            `MENU_ITEM_MEDIAN,
            `MENU_ITEM_GAMMA: is_toggle_item = 1'b1;
            default:          is_toggle_item = 1'b0;
        endcase
    end
endfunction

function is_numeric_item;
    input [4:0] idx;
    begin
        case (idx)
            `MENU_ITEM_MINIMUM,
            `MENU_ITEM_CANNY,
            `MENU_ITEM_CANNY_H,
            `MENU_ITEM_CANNY_L,
            `MENU_ITEM_WB_R,
            `MENU_ITEM_WB_G,
            `MENU_ITEM_WB_B,
            `MENU_ITEM_GAMMA_P,
            `MENU_ITEM_CLEANUP: is_numeric_item = 1'b1;
            default:          is_numeric_item = 1'b0;
        endcase
    end
endfunction

function is_on;
    input [4:0] idx;
    input [5:0] flags;
    begin
        case (idx)
            `MENU_ITEM_SPLIT:  is_on = flags[`MD_FLAG_SPLIT];
            `MENU_ITEM_SHAPE:  is_on = flags[`MD_FLAG_SHAPE];
            `MENU_ITEM_FREEZE: is_on = flags[`MD_FLAG_FREEZE];
            `MENU_ITEM_TEST:   is_on = flags[`MD_FLAG_TEST];
            `MENU_ITEM_MEDIAN: is_on = flags[`MD_FLAG_MEDIAN];
            default:           is_on = flags[`MD_FLAG_GAMMA];
        endcase
    end
endfunction

// ---------------------------------------------------------------------------
// Stage 0: pick the character for this pixel.
// ---------------------------------------------------------------------------
reg [7:0] ch0;
reg sel_row, edit_row;
always @* begin
    ch0      = 8'h20;
    sel_row  = 1'b0;
    edit_row = 1'b0;

    if (in_region) begin
        if (cell_row == 4'd0) begin
            case (cell_col)
                5'd0: ch0="I";
                5'd1: ch0="M";
                5'd2: ch0="A";
                5'd3: ch0="G";
                5'd4: ch0="E";
                5'd5: ch0="2";
                5'd6: ch0=" ";
                5'd7: ch0="M";
                5'd8: ch0="E";
                5'd9: ch0="N";
                5'd10: ch0="U";
                5'd20: ch0 = "I";
                5'd21: ch0 = "T";
                5'd22: ch0 = "E";
                5'd23: ch0 = "M";
                5'd25: ch0 = pos_tens;
                5'd26: ch0 = pos_ones;
                5'd27: ch0 = "/";
                5'd28: ch0 = "2";
                5'd29: ch0 = "4";
                default: ch0 = " ";
            endcase
        end else if (item_row) begin
            ch0      = template_ch;
            sel_row  = (row_item == d_cursor);
            edit_row = sel_row && (d_state == `MENU_STATE_EDIT);
            if (sel_row && (cell_col == 5'd0))
                ch0 = ">";

            if(row_item==`MENU_ITEM_BOOT)begin
                if(cell_col>=12&&cell_col<=17)ch0=boot_char(disp[`MD_BOOT_OFF+:2],cell_col-12);
            end else if(row_item==`MENU_ITEM_LOAD)begin
                if(cell_col>=12&&cell_col<=19)ch0=boot_status_char(disp[`MD_BOOT_STATUS_OFF+:4],cell_col-12);
            end else if (row_item == `MENU_ITEM_VIEW) begin
                if ((cell_col >= 5'd10) && (cell_col <= 5'd17))
                    ch0 = view_char(d_view, cell_col - 5'd10);
            end else if (is_toggle_item(row_item)) begin
                if ((cell_col >= 5'd10) && (cell_col <= 5'd12)) begin
                    if (cell_col == 5'd10)
                        ch0 = "O";
                    else if (cell_col == 5'd11)
                        ch0 = is_on(row_item, disp[`MD_FLAGS_OFF +: 6]) ? "N" : "F";
                    else
                        ch0 = is_on(row_item, disp[`MD_FLAGS_OFF +: 6]) ? " " : "F";
                end
            end else if (is_numeric_item(row_item)) begin
                case (row_item)
                    `MENU_ITEM_CANNY: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_high, cell_col - 5'd10);
                        else if (cell_col == 5'd14)
                            ch0 = "/";
                        else if ((cell_col >= 5'd15) && (cell_col <= 5'd18))
                            ch0 = bcd4_digit(d_low, cell_col - 5'd15);
                    end
                    `MENU_ITEM_MINIMUM:begin
                     if(cell_col>=10&&cell_col<=13)ch0=bcd4_digit(disp[`MD_MINIMUM_OFF+:16],cell_col-10);
                    end
                    `MENU_ITEM_CANNY_H: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_high, cell_col - 5'd10);
                    end
                    `MENU_ITEM_CANNY_L: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_low, cell_col - 5'd10);
                    end
                    `MENU_ITEM_WB_R: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_wbr, cell_col - 5'd10);
                    end
                    `MENU_ITEM_WB_G: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_wbg, cell_col - 5'd10);
                    end
                    `MENU_ITEM_WB_B: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd13))
                            ch0 = bcd4_digit(d_wbb, cell_col - 5'd10);
                    end
                    `MENU_ITEM_GAMMA_P: begin
                        if ((cell_col >= 5'd10) && (cell_col <= 5'd12))
                            ch0 = bcd3_digit(d_gamma, cell_col - 5'd10);
                    end
                    `MENU_ITEM_CLEANUP:begin if(cell_col==10)ch0="0"+disp[`MD_CLEANUP_OFF+:4];end
                    default: ;
                endcase
            end

            if(row_item==`MENU_ITEM_CAPTURE && cell_col>=12&&cell_col<=18)
             ch0=photo_char(disp[`MD_PHOTO_STATUS_OFF+:3],cell_col-12);
            if(row_item==`MENU_ITEM_SD && cell_col>=10&&cell_col<=17)
             ch0=sd_char(disp[`MD_SD_OFF+:2],cell_col-10);
            if(row_item==`MENU_ITEM_SD && disp[`MD_SD_OFF+:2]==3)case(cell_col)
             18:ch0="C";19:ch0="M";20:ch0="D";
             21:ch0=hex_char({2'd0,disp[`MD_SD_COMMAND_OFF+4+:2]});
             22:ch0=hex_char(disp[`MD_SD_COMMAND_OFF+:4]);
             24:ch0="R";25:ch0=hex_char(disp[`MD_SD_REASON_OFF+:4]);default:;
            endcase
            if(row_item==`MENU_ITEM_GALLERY && cell_col>=10&&cell_col<=12)
             ch0=cell_col==10?"O":cell_col==11?(disp[`MD_GALLERY_OFF]?"N":"F"):(disp[`MD_GALLERY_OFF]?" ":"F");
            if(row_item==`MENU_ITEM_DELETE && cell_col>=12&&cell_col<=23)
             ch0=delete_char(disp[`MD_DELETE_OFF],cell_col-12);

            if (edit_row) begin
                case (row_item)
                    `MENU_ITEM_CANNY: begin
                        if (cell_col == 5'd9)  ch0 = "[";
                        if (cell_col == 5'd19) ch0 = "]";
                    end
                    `MENU_ITEM_CANNY_H,
                    `MENU_ITEM_CANNY_L,
                    `MENU_ITEM_WB_R,
                    `MENU_ITEM_WB_G,
                    `MENU_ITEM_MINIMUM, `MENU_ITEM_WB_B: begin
                        if (cell_col == 5'd9)  ch0 = "[";
                        if (cell_col == 5'd14) ch0 = "]";
                    end
                    `MENU_ITEM_GAMMA_P,
                    `MENU_ITEM_CLEANUP: begin
                        if (cell_col == 5'd9)  ch0 = "[";
                        if (cell_col == 5'd13) ch0 = "]";
                    end
                    default: ;
                endcase
            end
        end else if (cell_row == 4'd9) begin
            // Low 16 bits in hex: camera frames / good / rejected / underflow.
            ch0 = " ";
            case(cell_col)
             0:ch0="C";6:ch0="G";12:ch0="B";18:ch0="U";default:;
            endcase
            if(cell_col>=1&&cell_col<=4)ch0=hex_char(disp[`MD_HEALTH_OFF+(4-cell_col)*4+:4]);
            if(cell_col>=7&&cell_col<=10)ch0=hex_char(disp[`MD_HEALTH_OFF+16+(10-cell_col)*4+:4]);
            if(cell_col>=13&&cell_col<=16)ch0=hex_char(disp[`MD_HEALTH_OFF+32+(16-cell_col)*4+:4]);
            if(cell_col>=19&&cell_col<=22)ch0=hex_char(disp[`MD_HEALTH_OFF+48+(22-cell_col)*4+:4]);
        end else if(cell_row==10)begin
            ch0=status_char(disp[`MD_EVENT_OFF+:4],disp[`MD_BUSY_OFF],disp[`MD_ERROR_OFF+:8],disp[`MD_STAGE_OFF+:4],disp[`MD_PHOTO_STATUS_OFF+:3],cell_col);
            if(cell_col>=22&&cell_col<=28)ch0="0"+((disp[`MD_FILE_OFF+:28]>>((28-cell_col)*4))&4'hf);
        end else if(cell_row==11)begin
            ch0=footer_char(cell_col);
            if(cell_col==25)ch0=hex_char(disp[`MD_STAGE_OFF+:4]);
            if(cell_col==28)ch0=hex_char(disp[`MD_ERROR_OFF+4+:4]);
            if(cell_col==29)ch0=hex_char(disp[`MD_ERROR_OFF+:4]);
        end
    end
end

// ---------------------------------------------------------------------------
// Three registered stages.  ch0 -> font row -> pixel selection.
// ---------------------------------------------------------------------------
reg s0_region, s0_sel, s0_edit;
reg [7:0] s0_ch;
reg [4:0] s0_gx, s0_gy;
reg s0_vs, s0_hs, s0_de;
reg [23:0] s0_rgb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_region <= 1'b0;
        s0_sel    <= 1'b0;
        s0_edit   <= 1'b0;
        s0_ch     <= 8'h20;
        s0_gx     <= 5'd0;
        s0_gy     <= 5'd0;
        s0_vs     <= 1'b0;
        s0_hs     <= 1'b0;
        s0_de     <= 1'b0;
        s0_rgb    <= 24'd0;
    end else begin
        s0_region <= in_region && (d_state != `MENU_STATE_CLOSED);
        s0_sel    <= sel_row;
        s0_edit   <= edit_row;
        s0_ch     <= ch0;
        s0_gx     <= col_in_cell;
        s0_gy     <= line_in_cell;
        s0_vs     <= in_vsync;
        s0_hs     <= in_hsync;
        s0_de     <= in_href;
        s0_rgb    <= in_rgb;
    end
end

wire [5:0] glyph = ((s0_ch >= 8'h20) && (s0_ch <= 8'h5F)) ?
                   (s0_ch - 8'h20) : 6'd0;
wire [2:0] font_row = scale3(s0_gy);
wire [2:0] font_col = scale3(s0_gx);
wire [7:0] font_bits;
menu_font_8x8 u_font (
    .glyph(glyph),
    .row(font_row),
    .pixels(font_bits)
);
wire ink = font_bits[3'd7 - font_col];

reg s1_region, s1_sel, s1_edit, s1_ink;
reg s1_vs, s1_hs, s1_de;
reg [23:0] s1_rgb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_region <= 1'b0;
        s1_sel    <= 1'b0;
        s1_edit   <= 1'b0;
        s1_ink    <= 1'b0;
        s1_vs     <= 1'b0;
        s1_hs     <= 1'b0;
        s1_de     <= 1'b0;
        s1_rgb    <= 24'd0;
    end else begin
        s1_region <= s0_region;
        s1_sel    <= s0_sel;
        s1_edit   <= s0_edit;
        s1_ink    <= ink;
        s1_vs     <= s0_vs;
        s1_hs     <= s0_hs;
        s1_de     <= s0_de;
        s1_rgb    <= s0_rgb;
    end
end

wire [23:0] ink_color = s1_edit ? EDIT_COLOR :
                        (s1_sel ? SELECT_COLOR : TEXT_COLOR);
wire [23:0] menu_rgb = s1_ink ? ink_color : BACKDROP;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_vsync <= 1'b0;
        out_hsync <= 1'b0;
        out_href  <= 1'b0;
        out_rgb   <= 24'd0;
    end else begin
        out_vsync <= s1_vs;
        out_hsync <= s1_hs;
        out_href  <= s1_de;
        out_rgb   <= s1_region ? menu_rgb : s1_rgb;
    end
end

endmodule
