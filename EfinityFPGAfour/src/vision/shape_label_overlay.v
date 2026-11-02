`timescale 1ns/1ps

// Five Chinese characters, 16x16 pixels each at 2x scale. Three pipeline
// stages separate placement, font lookup and pixel selection at 148.5 MHz.
// The video and all three timing signals travel through the same stages.
module shape_label_overlay #(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080
)(
    input clk, input rst_n,
    input per_frame_vsync, input per_frame_href, input per_frame_hsync,
    input [7:0] per_img_red, input [7:0] per_img_green, input [7:0] per_img_blue,
    input bbox_valid, input [11:0] bbox_x_min, input [10:0] bbox_y_min,
    input [1:0] shape_type,
    input bbox2_valid, input [11:0] bbox2_x_min, input [10:0] bbox2_y_min,
    input [1:0] shape2_type,
    output reg post_frame_vsync, output reg post_frame_href,
    output reg post_frame_hsync,
    output reg [7:0] post_img_red, output reg [7:0] post_img_green,
    output reg [7:0] post_img_blue
);

localparam [1:0] SHAPE_RECTANGLE = 2'd1, SHAPE_CIRCLE = 2'd2;
localparam LABEL_WIDTH = 168, LABEL_HEIGHT = 40;
localparam LABEL_FITS = (IMG_HDISP >= LABEL_WIDTH) && (IMG_VDISP >= LABEL_HEIGHT);
localparam [11:0] LAST_X = LABEL_FITS ? IMG_HDISP - LABEL_WIDTH : 0;
localparam [10:0] LAST_Y = LABEL_FITS ? IMG_VDISP - LABEL_HEIGHT : 0;

reg href_d;
reg [11:0] x_pos;
reg [10:0] y_pos;
wire [11:0] label_x1 = (bbox_x_min > LAST_X) ? LAST_X : bbox_x_min;
wire [11:0] label_x2 = (bbox2_x_min > LAST_X) ? LAST_X : bbox2_x_min;
// Prefer above the box with a four-pixel gap. Near the top, place the label
// just inside the upper edge; clamp both axes to the active image.
wire [11:0] preferred_y1 = (bbox_y_min >= 44) ?
                                       {1'b0,bbox_y_min} - 12'd44 :
                                       {1'b0,bbox_y_min} + 12'd4;
wire [11:0] preferred_y2 = (bbox2_y_min >= 44) ?
                                       {1'b0,bbox2_y_min} - 12'd44 :
                                       {1'b0,bbox2_y_min} + 12'd4;
wire [10:0] label_y1 = (preferred_y1 > {1'b0,LAST_Y}) ? LAST_Y : preferred_y1[10:0];
wire [10:0] label_y2 = (preferred_y2 > {1'b0,LAST_Y}) ? LAST_Y : preferred_y2[10:0];
wire [11:0] dx1 = x_pos - label_x1;
wire [11:0] dx2 = x_pos - label_x2;
wire [10:0] dy1 = y_pos - label_y1;
wire [10:0] dy2 = y_pos - label_y2;
wire [11:0] text_x1 = dx1 - 12'd4, text_x2 = dx2 - 12'd4;
wire [10:0] text_y1 = dy1 - 11'd4, text_y2 = dy2 - 11'd4;
wire region1 = LABEL_FITS && per_frame_href && bbox_valid &&
               ((shape_type == SHAPE_RECTANGLE) || (shape_type == SHAPE_CIRCLE)) &&
               (x_pos >= label_x1) && (dx1 < LABEL_WIDTH) &&
               (y_pos >= label_y1) && (dy1 < LABEL_HEIGHT);
wire region2 = LABEL_FITS && per_frame_href && bbox2_valid &&
               ((shape2_type == SHAPE_RECTANGLE) || (shape2_type == SHAPE_CIRCLE)) &&
               (x_pos >= label_x2) && (dx2 < LABEL_WIDTH) &&
               (y_pos >= label_y2) && (dy2 < LABEL_HEIGHT);

// Font glyph IDs: 0=检, 1=测, 2=到, 3=圆, 4=形, 5=矩.
function [2:0] glyph_for_character;
    input [2:0] character_index;
    input [1:0] object_type;
    begin
        case (character_index)
            3'd0: glyph_for_character = 3'd0;
            3'd1: glyph_for_character = 3'd1;
            3'd2: glyph_for_character = 3'd2;
            3'd3: glyph_for_character = (object_type == SHAPE_CIRCLE) ? 3'd3 : 3'd5;
            3'd4: glyph_for_character = 3'd4;
            default: glyph_for_character = 3'd7;
        endcase
    end
endfunction

reg [2:0] glyph1_s1, glyph2_s1;
reg [3:0] row1_s1, row2_s1, col1_s1, col2_s1;
reg region1_s1, region2_s1, text1_s1, text2_s1, circle1_s1, circle2_s1;
wire [15:0] font1, font2;
shape_chinese_font u_font1(.glyph(glyph1_s1), .row(row1_s1), .pixels(font1));
shape_chinese_font u_font2(.glyph(glyph2_s1), .row(row2_s1), .pixels(font2));
reg [15:0] font1_s2, font2_s2;
reg [3:0] col1_s2, col2_s2;
reg region1_s2, region2_s2, text1_s2, text2_s2, circle1_s2, circle2_s2;
reg [23:0] rgb_s1, rgb_s2;
reg [2:0] timing_s1, timing_s2;
wire ink1 = text1_s2 && font1_s2[4'd15-col1_s2];
wire ink2 = text2_s2 && font2_s2[4'd15-col2_s2];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        href_d <= 1'b0;
        x_pos <= 12'd0;
        y_pos <= 11'd0;
        glyph1_s1 <= 3'd7; glyph2_s1 <= 3'd7;
        row1_s1 <= 0; row2_s1 <= 0; col1_s1 <= 0; col2_s1 <= 0;
        region1_s1 <= 0; region2_s1 <= 0; text1_s1 <= 0; text2_s1 <= 0;
        circle1_s1 <= 0; circle2_s1 <= 0;
        font1_s2 <= 0; font2_s2 <= 0; col1_s2 <= 0; col2_s2 <= 0;
        region1_s2 <= 0; region2_s2 <= 0; text1_s2 <= 0; text2_s2 <= 0;
        circle1_s2 <= 0; circle2_s2 <= 0;
        rgb_s1 <= 0; rgb_s2 <= 0; timing_s1 <= 0; timing_s2 <= 0;
        post_frame_vsync <= 0; post_frame_href <= 0; post_frame_hsync <= 0;
        post_img_red <= 0; post_img_green <= 0; post_img_blue <= 0;
    end else begin
        href_d <= per_frame_href;
        if (!per_frame_vsync) begin
            x_pos <= 0; y_pos <= 0;
        end else if (per_frame_href) begin
            x_pos <= x_pos + 1'b1;
        end else if (href_d) begin
            x_pos <= 0; y_pos <= y_pos + 1'b1;
        end

        rgb_s1 <= {per_img_red,per_img_green,per_img_blue};
        timing_s1 <= {per_frame_vsync,per_frame_href,per_frame_hsync};
        region1_s1 <= region1; region2_s1 <= region2;
        text1_s1 <= region1 && (dx1 >= 4) && (dx1 < 164) && (dy1 >= 4) && (dy1 < 36);
        text2_s1 <= region2 && (dx2 >= 4) && (dx2 < 164) && (dy2 >= 4) && (dy2 < 36);
        glyph1_s1 <= glyph_for_character(text_x1[7:5], shape_type);
        glyph2_s1 <= glyph_for_character(text_x2[7:5], shape2_type);
        row1_s1 <= text_y1[4:1]; row2_s1 <= text_y2[4:1];
        col1_s1 <= text_x1[4:1]; col2_s1 <= text_x2[4:1];
        circle1_s1 <= (shape_type == SHAPE_CIRCLE);
        circle2_s1 <= (shape2_type == SHAPE_CIRCLE);

        rgb_s2 <= rgb_s1; timing_s2 <= timing_s1;
        region1_s2 <= region1_s1; region2_s2 <= region2_s1;
        text1_s2 <= text1_s1; text2_s2 <= text2_s1;
        font1_s2 <= font1; font2_s2 <= font2;
        col1_s2 <= col1_s1; col2_s2 <= col2_s1;
        circle1_s2 <= circle1_s1; circle2_s2 <= circle2_s1;

        {post_frame_vsync,post_frame_href,post_frame_hsync} <= timing_s2;
        if (!timing_s2[1]) begin
            {post_img_red,post_img_green,post_img_blue} <= 24'd0;
        end else if (region1_s2) begin
            {post_img_red,post_img_green,post_img_blue} <= ink1 ?
                           (circle1_s2 ? 24'h00bfff : 24'h00ff00) : 24'h202020;
        end else if (region2_s2) begin
            {post_img_red,post_img_green,post_img_blue} <= ink2 ?
                           (circle2_s2 ? 24'h00bfff : 24'h00ff00) : 24'h202020;
        end else begin
            {post_img_red,post_img_green,post_img_blue} <= rgb_s2;
        end
    end
end
endmodule
