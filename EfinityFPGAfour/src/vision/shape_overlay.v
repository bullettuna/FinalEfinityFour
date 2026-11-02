`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Registered RGB renderer with a colored edge and three-pixel result box.
// Edge=red, rectangle=green, circle=cyan-blue, unknown/learning frame=yellow.
//////////////////////////////////////////////////////////////////////////////////

module shape_overlay
#(
    parameter [11:0] ROI_X_MIN = 12'd320,
    parameter [11:0] ROI_X_MAX = 12'd1599,
    parameter [10:0] ROI_Y_MIN = 11'd180,
    parameter [10:0] ROI_Y_MAX = 11'd899
)
(
    input               clk,
    input               rst_n,
    input               per_frame_vsync,
    input               per_frame_href,
    input               per_frame_hsync,
    input               per_img_mask,
    input       [7:0]   per_img_red,
    input       [7:0]   per_img_green,
    input       [7:0]   per_img_blue,
    input               bbox_valid,
    input       [11:0]  bbox_x_min,
    input       [11:0]  bbox_x_max,
    input       [10:0]  bbox_y_min,
    input       [10:0]  bbox_y_max,
    input       [1:0]   shape_type,
    input               bbox2_valid,
    input       [11:0]  bbox2_x_min,
    input       [11:0]  bbox2_x_max,
    input       [10:0]  bbox2_y_min,
    input       [10:0]  bbox2_y_max,
    input       [1:0]   shape2_type,
    output reg          post_frame_vsync,
    output reg          post_frame_href,
    output reg          post_frame_hsync,
    output reg  [7:0]   post_img_red,
    output reg  [7:0]   post_img_green,
    output reg  [7:0]   post_img_blue
);

localparam [1:0] SHAPE_RECTANGLE = 2'd1;
localparam [1:0] SHAPE_CIRCLE    = 2'd2;

reg href_d;
reg [11:0] x_pos;
reg [10:0] y_pos;

wire inside_x = (x_pos >= bbox_x_min) && (x_pos <= bbox_x_max);
wire inside_y = (y_pos >= bbox_y_min) && (y_pos <= bbox_y_max);
wire on_left  = (x_pos >= bbox_x_min) &&
                (x_pos <= bbox_x_min + 12'd2);
wire on_right = (x_pos <= bbox_x_max) &&
                (x_pos + 12'd2 >= bbox_x_max);
wire on_top   = (y_pos >= bbox_y_min) &&
                (y_pos <= bbox_y_min + 11'd2);
wire on_bottom = (y_pos <= bbox_y_max) &&
                 (y_pos + 11'd2 >= bbox_y_max);
wire draw_box = bbox_valid &&
                ((inside_y && (on_left || on_right)) ||
                 (inside_x && (on_top || on_bottom)));
wire inside2_x = (x_pos >= bbox2_x_min) && (x_pos <= bbox2_x_max);
wire inside2_y = (y_pos >= bbox2_y_min) && (y_pos <= bbox2_y_max);
wire on2_left  = (x_pos >= bbox2_x_min) && (x_pos <= bbox2_x_min + 12'd2);
wire on2_right = (x_pos <= bbox2_x_max) && (x_pos + 12'd2 >= bbox2_x_max);
wire on2_top   = (y_pos >= bbox2_y_min) && (y_pos <= bbox2_y_min + 11'd2);
wire on2_bottom = (y_pos <= bbox2_y_max) && (y_pos + 11'd2 >= bbox2_y_max);
wire draw_box2 = bbox2_valid &&
                 ((inside2_y && (on2_left || on2_right)) ||
                  (inside2_x && (on2_top || on2_bottom)));
wire inside_roi_x = (x_pos >= ROI_X_MIN) && (x_pos <= ROI_X_MAX);
wire inside_roi_y = (y_pos >= ROI_Y_MIN) && (y_pos <= ROI_Y_MAX);
wire on_roi_left  = (x_pos >= ROI_X_MIN) &&
                    (x_pos <= ROI_X_MIN + 12'd1);
wire on_roi_right = (x_pos <= ROI_X_MAX) &&
                    (x_pos + 12'd1 >= ROI_X_MAX);
wire on_roi_top   = (y_pos >= ROI_Y_MIN) &&
                    (y_pos <= ROI_Y_MIN + 11'd1);
wire on_roi_bottom = (y_pos <= ROI_Y_MAX) &&
                     (y_pos + 11'd1 >= ROI_Y_MAX);
wire draw_roi = (inside_roi_y && (on_roi_left || on_roi_right)) ||
                (inside_roi_x && (on_roi_top || on_roi_bottom));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        href_d            <= 1'b0;
        x_pos             <= 12'd0;
        y_pos             <= 11'd0;
        post_frame_vsync  <= 1'b0;
        post_frame_href   <= 1'b0;
        post_frame_hsync  <= 1'b0;
        post_img_red      <= 8'd0;
        post_img_green    <= 8'd0;
        post_img_blue     <= 8'd0;
    end else begin
        href_d            <= per_frame_href;
        post_frame_vsync  <= per_frame_vsync;
        post_frame_href   <= per_frame_href;
        post_frame_hsync  <= per_frame_hsync;

        if (!per_frame_vsync) begin
            x_pos <= 12'd0;
            y_pos <= 11'd0;
        end else if (per_frame_href) begin
            x_pos <= x_pos + 1'b1;
        end else if (href_d) begin
            x_pos <= 12'd0;
            y_pos <= y_pos + 1'b1;
        end

        if (!per_frame_href) begin
            post_img_red   <= 8'd0;
            post_img_green <= 8'd0;
            post_img_blue  <= 8'd0;
        end else if (draw_box || draw_box2) begin
            if (draw_box) begin
                if (shape_type == SHAPE_RECTANGLE) begin
                    post_img_red   <= 8'h00;
                    post_img_green <= 8'hff;
                    post_img_blue  <= 8'h00;
                end else if (shape_type == SHAPE_CIRCLE) begin
                    post_img_red   <= 8'h00;
                    post_img_green <= 8'hbf;
                    post_img_blue  <= 8'hff;
                end else begin
                    post_img_red   <= 8'hff;
                    post_img_green <= 8'hff;
                    post_img_blue  <= 8'h00;
                end
            end else if (shape2_type == SHAPE_RECTANGLE) begin
                post_img_red   <= 8'h00;
                post_img_green <= 8'hff;
                post_img_blue  <= 8'h00;
            end else if (shape2_type == SHAPE_CIRCLE) begin
                post_img_red   <= 8'h00;
                post_img_green <= 8'hbf;
                post_img_blue  <= 8'hff;
            end else begin
                post_img_red   <= 8'hff;
                post_img_green <= 8'hff;
                post_img_blue  <= 8'h00;
            end
        end else if (draw_roi) begin
            post_img_red   <= 8'hff;
            post_img_green <= 8'h00;
            post_img_blue  <= 8'hff;
        end else if (per_img_mask) begin
            post_img_red   <= 8'hff;
            post_img_green <= 8'h00;
            post_img_blue  <= 8'h00;
        end else begin
            post_img_red   <= per_img_red;
            post_img_green <= per_img_green;
            post_img_blue  <= per_img_blue;
        end
    end
end

endmodule
