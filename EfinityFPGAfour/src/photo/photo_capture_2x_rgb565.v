`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// One-shot 1920x1080 RGB -> 960x540 RGB565 photo sampler.
//
// `capture_toggle` is produced in a slower control clock domain and must be
// synchronized into `clk` by the caller.  A changed value arms the next whole
// input frame; the module never begins in the middle of a frame.  The output
// emits one RGB565 sample at the top-left of each 2x2 input cell.  This has no
// line RAM and deliberately keeps the photo path small; the following DDR
// writer is responsible for accepting exactly one sample every four pixels.
//
// The physical SD card cannot absorb a 960x540 BMP while this stream is being
// created.  Therefore `pixel_valid` is intended for a DDR staging writer, not
// for a direct SD writer.
//////////////////////////////////////////////////////////////////////////////////
module photo_capture_2x_rgb565 #(
    parameter [11:0] IN_WIDTH  = 12'd1920,
    parameter [10:0] IN_HEIGHT = 11'd1080
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        capture_toggle,

    input  wire        in_vsync,
    input  wire        in_href,
    input  wire [7:0]  in_red,
    input  wire [7:0]  in_green,
    input  wire [7:0]  in_blue,

    output reg         capture_active,
    output reg         capture_done_toggle,
    output reg         pixel_valid,
    output reg [9:0]   pixel_x,
    output reg [8:0]   pixel_y,
    output reg [15:0]  pixel_rgb565
);

    reg        vsync_d;
    reg        href_d;
    reg        capture_toggle_seen;
    reg [11:0] source_x;
    reg [10:0] source_y;

    wire frame_start = in_vsync && !vsync_d;
    wire line_start  = in_href && !href_d;
    wire capture_request_pending = (capture_toggle != capture_toggle_seen);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d             <= 1'b0;
            href_d              <= 1'b0;
            capture_toggle_seen <= 1'b0;
            capture_active      <= 1'b0;
            capture_done_toggle <= 1'b0;
            pixel_valid         <= 1'b0;
            pixel_x             <= 10'd0;
            pixel_y             <= 9'd0;
            pixel_rgb565        <= 16'd0;
            source_x            <= 12'd0;
            source_y            <= 11'd0;
        end else begin
            vsync_d     <= in_vsync;
            href_d      <= in_href;
            pixel_valid <= 1'b0;

            // A photo always starts at the beginning of a complete frame.
            // If a former photo was active, this same edge is its completion
            // boundary.  A new b command may be queued simultaneously.
            if (frame_start) begin
                source_x <= 12'd0;
                source_y <= 11'd0;
                if (capture_active) begin
                    capture_active      <= 1'b0;
                    capture_done_toggle <= ~capture_done_toggle;
                end
                if (capture_request_pending) begin
                    capture_toggle_seen <= capture_toggle;
                    capture_active      <= 1'b1;
                end
            end else if (in_href) begin
                if (source_x < IN_WIDTH) begin
                    source_x <= source_x + 1'b1;
                end

                // Select the first pixel in every 2x2 source cell.  The
                // source counters contain the present pixel coordinate before
                // their non-blocking update, which is exactly what is needed.
                if (capture_active && source_x < IN_WIDTH &&
                    source_y < IN_HEIGHT && !source_x[0] && !source_y[0]) begin
                    pixel_valid  <= 1'b1;
                    pixel_x      <= source_x[11:1];
                    pixel_y      <= source_y[10:1];
                    pixel_rgb565 <= {in_red[7:3], in_green[7:2], in_blue[7:3]};
                end
            end else begin
                // Reset X during blanking, advance Y after a complete line.
                // The first active pixel therefore uses X=0 exactly once.
                source_x <= 12'd0;
                if (href_d && source_y < IN_HEIGHT)
                    source_y <= source_y + 1'b1;
            end
        end
    end

endmodule
