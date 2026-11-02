`timescale 1ns/1ps
// Independent 1080p timing and a fixed four-colour picture. No camera/DDR input
// is used by the generator. Normal video passes through without added latency.
module video_diagnostic_mux #(
    parameter H_SYNC=44, H_BACK=148, H_DISP=1920, H_TOTAL=2200,
    parameter V_SYNC=5, V_BACK=36, V_DISP=1080, V_TOTAL=1125
)(
    input clk, input rst_n, input diagnostic_req,
    input live_vsync, input live_hsync, input live_href,
    input [23:0] live_rgb,
    output out_vsync, output out_hsync, output out_href,
    output [23:0] out_rgb, output reg diagnostic_active
);
localparam H_START=H_SYNC+H_BACK, V_START=V_SYNC+V_BACK;
reg [13:0] hcnt;
reg [11:0] vcnt;
reg test_vsync, test_hsync, test_href;
reg [23:0] test_rgb;
wire active_pixel = hcnt>=H_START && hcnt<H_START+H_DISP &&
                    vcnt>=V_START && vcnt<V_START+V_DISP;
wire [13:0] x=hcnt-H_START;
wire [11:0] y=vcnt-V_START;
wire border = x<4 || x>=H_DISP-4 || y<4 || y>=V_DISP-4;
wire crosshair = (x>=H_DISP/2-2 && x<H_DISP/2+2) ||
                 (y>=V_DISP/2-2 && y<V_DISP/2+2);
wire [23:0] quadrant = y<V_DISP/2 ?
    (x<H_DISP/2 ? 24'hff0000 : 24'h00ff00) :
    (x<H_DISP/2 ? 24'h0000ff : 24'hffff00);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        hcnt<=0; vcnt<=0;
        test_vsync<=0; test_hsync<=0; test_href<=0; test_rgb<=0;
    end else begin
        hcnt<=hcnt==H_TOTAL-1 ? 14'd0 : hcnt+1'b1;
        if(hcnt==H_TOTAL-1) begin
            vcnt<=vcnt==V_TOTAL-1 ? 12'd0 : vcnt+1'b1;
            // Match the existing lcd_driver's line-boundary VSYNC behavior.
            test_vsync<=vcnt>=V_SYNC;
        end
        test_hsync<=hcnt>=H_SYNC;
        test_href<=active_pixel;
        test_rgb<=active_pixel ? ((border||crosshair)?24'hffffff:quadrant) : 24'd0;
    end
end
(* async_reg="true" *) reg req_meta, req_sync;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin req_meta<=0;req_sync<=0;diagnostic_active<=0;end
    else begin
        req_meta<=diagnostic_req; req_sync<=req_meta;
        // Both independent and live streams must be in vertical blanking.
        // No mode change can cut an active line or produce a partial DE pulse.
        if(hcnt==0 && vcnt==2 && !test_vsync && !test_href &&
           !live_vsync && !live_href)
            diagnostic_active<=req_sync;
    end
end
assign out_vsync=diagnostic_active?test_vsync:live_vsync;
assign out_hsync=diagnostic_active?test_hsync:live_hsync;
assign out_href=diagnostic_active?test_href:live_href;
assign out_rgb=diagnostic_active?test_rgb:live_rgb;
endmodule
