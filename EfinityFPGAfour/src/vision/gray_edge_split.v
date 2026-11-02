`timescale 1ns/1ps
// Wipe comparison, not two scaled copies. Gray and edge MUST describe the
// same pixel and share the same Canny-delayed timing. No line/frame RAM.
module gray_edge_split #(
    parameter [13:0] IMG_HDISP = 14'd1920
)(
    input clk, input rst_n, input split_req,
    input in_vsync, input in_hsync, input in_href,
    input [7:0] aligned_gray, input [7:0] aligned_edge,
    output out_vsync, output out_hsync, output out_href,
    output [23:0] out_rgb, output reg split_active
);
reg [13:0] pixel_x;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pixel_x <= 14'd0;
        split_active <= 1'b0;
    end else begin
        if (!in_vsync || !in_href)
            pixel_x <= 14'd0;
        else
            pixel_x <= pixel_x + 1'b1;
        // Existing video uses active-low VSYNC. Apply the synchronized request
        // in this stream's vertical blank, never halfway through a picture.
        if (!in_vsync && !in_href)
            split_active <= split_req;
    end
end
wire [7:0] pixel = pixel_x < IMG_HDISP/2 ? aligned_gray : aligned_edge;
assign out_vsync = in_vsync;
assign out_hsync = in_hsync;
assign out_href = in_href;
assign out_rgb = in_href ? {pixel, pixel, pixel} : 24'd0;
endmodule
