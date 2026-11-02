`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"

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
module image5_menu_render #(
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
    input [`M5_DISP_WIDTH-1:0] disp,
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

wire [1:0]  d_state  = disp[`M5D_STATE  +: 2];
wire [4:0]  d_cursor = disp[`M5D_CURSOR +: 5];
wire [4:0]  d_window = disp[`M5D_WINDOW +: 5];
wire [1:0]  d_view   = disp[`M5D_VIEW   +: 2];
wire [15:0] d_high   = disp[`M5D_HIGH   +: 16];
wire [15:0] d_low    = disp[`M5D_LOW    +: 16];
wire [15:0] d_wbr    = disp[`M5D_WBR    +: 16];
wire [15:0] d_wbg    = disp[`M5D_WBG    +: 16];
wire [15:0] d_wbb    = disp[`M5D_WBB    +: 16];
wire [11:0] d_gamma  = disp[`M5D_GAMMA  +: 12];

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

wire [6:0] flags=disp[`M5D_FLAGS+:7];
wire [2:0] usb_mode=disp[`M5D_USB_MODE+:3];
wire [1:0] usb_size=disp[`M5D_USB_SIZE+:2];
wire [15:0] adc0=disp[`M5D_ADC0+:16],adc1=disp[`M5D_ADC1+:16];
wire [4:0] rom_item=cell_row==10?(d_state==`M5_EDIT?26:24):cell_row==11?(d_state==`M5_EDIT?27:25):row_item;
wire [7:0] template_ch;
image5_menu_text_rom u_text_rom(.item(rom_item),.col(cell_col),.ch(template_ch));
wire [4:0] position=d_cursor+1'b1;
wire [7:0] pos_tens=position>=20?"2":position>=10?"1":" ";
wire [7:0] pos_ones="0"+(position>=20?position-20:position>=10?position-10:position);
function [7:0] enum_char;
 input [1:0] category;input [2:0] value;input [3:0] posn;
 reg [95:0] word;
 begin
  word="            ";
  case(category)
   0:case(value)0:word="COLOR       ";1:word="GRAY        ";default:word="EDGE        ";endcase
   1:case(value)0:word="STOP        ";1:word="COUNT       ";2:word="GRAY        ";3:word="EDGE1       ";default:word="EDGE8       ";endcase
   3:case(value)0:word="IMAGE7      ";1:word="IMAGE1      ";default:word="IMAGE5      ";endcase
   2:case(value)0:word="320X180     ";1:word="640X360     ";default:word="1920X1080   ";endcase
  endcase
  enum_char=posn<12?word[95-posn*8-:8]:8'h20;
 end
endfunction
function [7:0] boot_status_char;
 input [3:0] state_;input [2:0] index;reg [63:0] word_;
 begin
  case(state_)0:word_="READY   ";1:word_="WAIT    ";2:word_="LOAD    ";3:word_="ERROR   ";default:word_="HERE    ";endcase
  boot_status_char=word_[(7-index)*8+:8];
 end
endfunction
reg [15:0] number;
reg toggle_item,on_value,numeric_item;
always @*begin
 number=0;toggle_item=0;on_value=0;numeric_item=0;
 case(row_item)
  `M5_MEDIAN:begin toggle_item=1;on_value=flags[0];end
  `M5_CLEANUP:begin toggle_item=1;on_value=flags[1];end
  `M5_FREEZE:begin toggle_item=1;on_value=flags[2];end
  `M5_TEST:begin toggle_item=1;on_value=flags[3];end
  `M5_GAMMA:begin toggle_item=1;on_value=flags[4];end
  `M5_CANNY,`M5_CANNY_H:begin numeric_item=1;number=d_high;end
  `M5_CANNY_L:begin numeric_item=1;number=d_low;end
  `M5_WB_R:begin numeric_item=1;number=d_wbr;end
  `M5_WB_G:begin numeric_item=1;number=d_wbg;end
  `M5_WB_B:begin numeric_item=1;number=d_wbb;end
  `M5_GAMMA_P:begin numeric_item=1;number={4'd0,d_gamma};end
  default:begin end
 endcase
end
reg [7:0] ch0;
reg sel_row,edit_row;
reg [47:0] state_word;
always @*begin
 ch0=" ";sel_row=0;edit_row=0;
 state_word=d_state==`M5_EDIT?"EDIT  ":"BROWSE";
 if(in_region)begin
  if(cell_row==0)begin
   case(cell_col)
    0:ch0="I";1:ch0="M";2:ch0="A";3:ch0="G";4:ch0="E";5:ch0="5";
    7:ch0="M";8:ch0="E";9:ch0="N";10:ch0="U";
    19:ch0=flags[5]?"B":" ";20:ch0=flags[5]?"U":" ";21:ch0=flags[5]?"S":" ";22:ch0=flags[5]?"Y":" ";
    25:ch0=pos_tens;26:ch0=pos_ones;27:ch0="/";28:ch0="2";29:ch0="1";
    default:if(cell_col>=12&&cell_col<=17)ch0=state_word[47-(cell_col-12)*8-:8];
   endcase
  end else if(item_row)begin
   ch0=template_ch;sel_row=row_item==d_cursor;edit_row=sel_row&&d_state==`M5_EDIT;
   if(sel_row&&cell_col==0)ch0=">";
   if(row_item==`M5_ADC)begin
    if(cell_col>=7&&cell_col<=10)ch0=bcd4_digit(adc0,cell_col-7);
    if(cell_col>=19&&cell_col<=22)ch0=bcd4_digit(adc1,cell_col-19);
    if(cell_col==27)ch0=flags[6]?"1":"0";
   end else if(cell_col>=13&&cell_col<=23)begin
    if(row_item==`M5_VIEW)ch0=enum_char(0,{1'b0,d_view},cell_col-13);
    else if(row_item==`M5_USB_MODE)ch0=enum_char(1,usb_mode,cell_col-13);
    else if(row_item==`M5_USB_SIZE)ch0=enum_char(2,{1'b0,usb_size},cell_col-13);
    else if(row_item==`M5_BOOT)ch0=enum_char(3,{1'b0,disp[`M5D_BOOT+:2]},cell_col-13);
    else if(row_item==`M5_LOAD)ch0=cell_col<=20?boot_status_char(disp[`M5D_BOOT_STATUS+:4],cell_col-13):" ";
    else if(toggle_item)begin
     case(cell_col)13:ch0="O";14:ch0=on_value?"N":"F";15:ch0=on_value?" ":"F";default:ch0=" ";endcase
    end else if(numeric_item)begin
     if(cell_col<=16)ch0=bcd4_digit(number,cell_col-13);
     else if(row_item==`M5_CANNY)begin
      if(cell_col==17)ch0="/";
      else if(cell_col<=21)ch0=bcd4_digit(d_low,cell_col-18);
     end
    end
   end
   if(edit_row)begin if(cell_col==12)ch0="[";if(cell_col==24)ch0="]";end
  end else if(cell_row==9)ch0="-";
  else if(cell_row==10||cell_row==11)ch0=template_ch;
 end
end

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
        s0_region <= in_region && (d_state != `M5_CLOSED);
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
