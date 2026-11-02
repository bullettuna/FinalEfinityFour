`timescale 1ns/1ps
// Preserve the pre-Gaussian luminance without changing the legacy Canny RTL.
// Each center-only window matches the corresponding Canny spatial delay;
// its unused neighbours/second historical row can be removed by synthesis.
module gray_canny_alignment #(
    parameter [13:0] IMG_HDISP=14'd1920,
    parameter [13:0] IMG_VDISP=14'd1080
)(
    input clk, input rst_n,
    input in_vsync, input in_hsync, input in_href,
    input [7:0] in_gray,
    output out_vsync, output out_hsync, output out_href,
    output [7:0] out_gray
);
wire [4:0] vs,hs,de;
wire [7:0] gray0,gray1,gray2,gray3,gray4;
assign vs[0]=in_vsync;assign hs[0]=in_hsync;assign de[0]=in_href;
assign gray0=in_gray;
gray_center_delay #(.IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.PIPE_STAGES(2)) gaussian_delay (
    .clk(clk),.rst_n(rst_n),.in_vsync(vs[0]),.in_hsync(hs[0]),.in_href(de[0]),.in_gray(gray0),
    .out_vsync(vs[1]),.out_hsync(hs[1]),.out_href(de[1]),.out_gray(gray1));
gray_center_delay #(.IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.PIPE_STAGES(3)) gradient_delay (
    .clk(clk),.rst_n(rst_n),.in_vsync(vs[1]),.in_hsync(hs[1]),.in_href(de[1]),.in_gray(gray1),
    .out_vsync(vs[2]),.out_hsync(hs[2]),.out_href(de[2]),.out_gray(gray2));
gray_center_delay #(.IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.PIPE_STAGES(1)) nms_delay (
    .clk(clk),.rst_n(rst_n),.in_vsync(vs[2]),.in_hsync(hs[2]),.in_href(de[2]),.in_gray(gray2),
    .out_vsync(vs[3]),.out_hsync(hs[3]),.out_href(de[3]),.out_gray(gray3));
// Double threshold has one clock but no spatial window.
reg threshold_vsync,threshold_hsync,threshold_href;
reg [7:0] threshold_gray;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        threshold_vsync<=0;threshold_hsync<=0;threshold_href<=0;threshold_gray<=0;
    end else begin
        threshold_vsync<=vs[3];threshold_hsync<=hs[3];threshold_href<=de[3];
        threshold_gray<=de[3] ? gray3 : 8'd0;
    end
end
gray_center_delay #(.IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.PIPE_STAGES(1)) hysteresis_delay (
    .clk(clk),.rst_n(rst_n),.in_vsync(threshold_vsync),.in_hsync(threshold_hsync),.in_href(threshold_href),.in_gray(threshold_gray),
    .out_vsync(vs[4]),.out_hsync(hs[4]),.out_href(de[4]),.out_gray(gray4));
assign out_vsync=vs[4];assign out_hsync=hs[4];assign out_href=de[4];assign out_gray=gray4;
endmodule

module gray_center_delay #(
    parameter [13:0] IMG_HDISP=14'd1920,
    parameter [13:0] IMG_VDISP=14'd1080,
    parameter PIPE_STAGES=1
)(
    input clk,input rst_n,
    input in_vsync,input in_hsync,input in_href,input [7:0] in_gray,
    output out_vsync,output out_hsync,output out_href,output [7:0] out_gray
);
wire vs,hs,de;
wire [7:0] center;
VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.DATA_WIDTH(8)) window (
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(in_vsync),.per_frame_hsync(in_hsync),
    .per_frame_href(in_href),.per_img_Y(in_gray),
    .matrix_frame_vsync(vs),.matrix_frame_hsync(hs),.matrix_frame_href(de),.matrix_p22(center));
reg [PIPE_STAGES-1:0] vs_pipe,hs_pipe,de_pipe;
reg [7:0] gray_pipe[0:PIPE_STAGES-1];
integer i;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        vs_pipe<=0;hs_pipe<=0;de_pipe<=0;
        for(i=0;i<PIPE_STAGES;i=i+1)gray_pipe[i]<=0;
    end else begin
        vs_pipe[0]<=vs;hs_pipe[0]<=hs;de_pipe[0]<=de;gray_pipe[0]<=center;
        for(i=1;i<PIPE_STAGES;i=i+1)begin
            vs_pipe[i]<=vs_pipe[i-1];hs_pipe[i]<=hs_pipe[i-1];de_pipe[i]<=de_pipe[i-1];
            gray_pipe[i]<=gray_pipe[i-1];
        end
    end
end
assign out_vsync=vs_pipe[PIPE_STAGES-1];assign out_hsync=hs_pipe[PIPE_STAGES-1];
assign out_href=de_pipe[PIPE_STAGES-1];
assign out_gray=out_href ? gray_pipe[PIPE_STAGES-1] : 8'd0;
endmodule
