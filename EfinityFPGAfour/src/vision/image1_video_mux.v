`timescale 1ns/1ps
// Fixed display phase for every mode. Latencies from the grey output are:
// color=0, median=7, Canny/split=27, overlay=35, shape+Chinese text=39.
// Delay shorter branches to 39 clocks; selection changes RGB only, never
// HDMI sync phase. A final register slice isolates the TMDS input cone.
module image1_video_mux #(parameter [2:0] DEFAULT_SOURCE=3'd2)(
    input clk,input rst_n,input [2:0] source_req,
    input [5:0] in_vsync,input [5:0] in_hsync,input [5:0] in_href,
    input [143:0] in_rgb,
    output reg out_vsync,output reg out_hsync,output reg out_href,
    output reg [23:0] out_rgb,
    output reg [2:0] source_active
);
reg [2:0] safe_blank;
wire [5:0] aligned_vs,aligned_hs,aligned_de;
wire [143:0] aligned_rgb;
genvar lane;
generate for(lane=0;lane<6;lane=lane+1)begin : g_align
    localparam DELAY=(lane==0)?39:(lane==1)?32:(lane==2 || lane==4)?12:(lane==3)?4:0;
    image1_video_delay #(.CLOCKS(DELAY)) u_delay (
        .clk(clk),.rst_n(rst_n),.in_vsync(in_vsync[lane]),
        .in_hsync(in_hsync[lane]),.in_href(in_href[lane]),.in_rgb(in_rgb[lane*24+:24]),
        .out_vsync(aligned_vs[lane]),.out_hsync(aligned_hs[lane]),
        .out_href(aligned_de[lane]),.out_rgb(aligned_rgb[lane*24+:24])
    );
end endgenerate
wire common_blank=!(|aligned_vs) && !(|aligned_de) && (&aligned_hs);
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        source_active<=DEFAULT_SOURCE;safe_blank<=0;
        out_vsync<=0;out_hsync<=0;out_href<=0;out_rgb<=0;
    end else begin
        safe_blank<={safe_blank[1:0],common_blank};
        if(common_blank && (&safe_blank) && source_req<6)
            source_active<=source_req;
        out_vsync<=aligned_vs[5];out_hsync<=aligned_hs[5];
        out_href<=aligned_de[5];
        out_rgb<=aligned_de[5] ? aligned_rgb[source_active*24+:24] : 24'd0;
    end
end
endmodule

module image1_video_delay #(parameter CLOCKS=1)(
    input clk,input rst_n,input in_vsync,input in_hsync,input in_href,input [23:0] in_rgb,
    output out_vsync,output out_hsync,output out_href,output [23:0] out_rgb
);
generate if(CLOCKS==0)begin : g_direct
    assign {out_vsync,out_hsync,out_href,out_rgb}={in_vsync,in_hsync,in_href,in_rgb};
end else begin : g_delay
    reg [CLOCKS-1:0] vs,hs,de;
    reg [23:0] rgb[0:CLOCKS-1];
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin vs<=0;hs<=0;de<=0;end
        else begin
            vs<=(vs<<1)|in_vsync;hs<=(hs<<1)|in_hsync;de<=(de<<1)|in_href;
        end
    end
    // Pixel storage needs no reset: reset-cleared DE masks its contents until
    // the pipeline is full. This permits shift-register rather than line RAM.
    always @(posedge clk)begin
        rgb[0]<=in_rgb;
        for(i=1;i<CLOCKS;i=i+1)rgb[i]<=rgb[i-1];
    end
    assign out_vsync=vs[CLOCKS-1];assign out_hsync=hs[CLOCKS-1];
    assign out_href=de[CLOCKS-1];assign out_rgb=rgb[CLOCKS-1];
end endgenerate
endmodule
