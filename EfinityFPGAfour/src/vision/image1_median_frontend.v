`timescale 1ns/1ps

// Shared window for exact luminance/RGB medians. M switches pixels only;
// VS/HS/DE always have seven clocks of latency, including raw bypass.
module image1_median_frontend #(
    parameter [13:0] IMG_HDISP = 14'd1920,
    parameter [13:0] IMG_VDISP = 14'd1080,
    parameter DEFAULT_MEDIAN_ENABLE = 1'b1
)(
    input clk, input rst_n, input median_enable_req,
    input per_frame_vsync, input per_frame_href, input per_frame_hsync,
    input [7:0] per_img_gray,
    input [7:0] per_img_red, input [7:0] per_img_green, input [7:0] per_img_blue,
    output reg post_frame_vsync, output reg post_frame_href, output reg post_frame_hsync,
    output reg [7:0] post_img_gray,
    output reg [7:0] post_img_red, output reg [7:0] post_img_green, output reg [7:0] post_img_blue,
    output reg [7:0] post_original_gray,
    output reg median_active
);
wire matrix_vs,matrix_de,matrix_hs;
wire [31:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
VIP_Matrix_Generate_3X3_8Bit #(
    .IMG_HDISP(IMG_HDISP),.IMG_VDISP(IMG_VDISP),.DATA_WIDTH(32)
) u_shared_window (
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(per_frame_vsync),
    .per_frame_href(per_frame_href),.per_frame_hsync(per_frame_hsync),
    .per_img_Y({per_img_gray,per_img_red,per_img_green,per_img_blue}),
    .matrix_frame_vsync(matrix_vs),.matrix_frame_href(matrix_de),.matrix_frame_hsync(matrix_hs),
    .matrix_p11(p11),.matrix_p12(p12),.matrix_p13(p13),
    .matrix_p21(p21),.matrix_p22(p22),.matrix_p23(p23),
    .matrix_p31(p31),.matrix_p32(p32),.matrix_p33(p33)
);
wire [31:0] filtered;
genvar channel;
generate for(channel=0;channel<4;channel=channel+1)begin : g_channel
    median3x3_kernel u_median (
        .clk(clk),.rst_n(rst_n),.in_frame_vsync(matrix_vs),
        .in_frame_href(matrix_de),.in_frame_hsync(matrix_hs),
        .p11(p11[channel*8+:8]),.p12(p12[channel*8+:8]),.p13(p13[channel*8+:8]),
        .p21(p21[channel*8+:8]),.p22(p22[channel*8+:8]),.p23(p23[channel*8+:8]),
        .p31(p31[channel*8+:8]),.p32(p32[channel*8+:8]),.p33(p33[channel*8+:8]),
        .out_img_median(filtered[channel*8+:8]),
        .out_frame_vsync(),.out_frame_href(),.out_frame_hsync()
    );
end endgenerate
// Window=3 clocks; kernel=3 clocks. Raw bypass keeps its original spatial
// coordinates at the same clock latency. Share p22 for the original split
// sample instead of allocating another pair of line buffers.
reg [2:0] vs_d,de_d,hs_d;
reg [7:0] original_center[0:2];
reg [31:0] raw_pixels[0:5];
integer i;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        median_active<=DEFAULT_MEDIAN_ENABLE;
        vs_d<=0;de_d<=0;hs_d<=0;
        for(i=0;i<3;i=i+1)original_center[i]<=0;
        for(i=0;i<6;i=i+1)raw_pixels[i]<=0;
        post_frame_vsync<=0;post_frame_href<=0;post_frame_hsync<=0;
        post_img_gray<=0;post_img_red<=0;post_img_green<=0;post_img_blue<=0;
        post_original_gray<=0;
    end else begin
        vs_d<={vs_d[1:0],matrix_vs};de_d<={de_d[1:0],matrix_de};hs_d<={hs_d[1:0],matrix_hs};
        original_center[0]<=p22[31:24];
        for(i=1;i<3;i=i+1)original_center[i]<=original_center[i-1];
        raw_pixels[0]<={per_img_gray,per_img_red,per_img_green,per_img_blue};
        for(i=1;i<6;i=i+1)raw_pixels[i]<=raw_pixels[i-1];
        if(!per_frame_vsync && !vs_d[2] && !post_frame_vsync &&
           !per_frame_href && !de_d[2] && !post_frame_href)
            median_active<=median_enable_req;
        post_frame_vsync<=vs_d[2];post_frame_href<=de_d[2];post_frame_hsync<=hs_d[2];
        {post_img_gray,post_img_red,post_img_green,post_img_blue}<=
            de_d[2] ? (median_active ? filtered : raw_pixels[5]) : 32'd0;
        post_original_gray<=de_d[2] ?
            (median_active ? original_center[2] : raw_pixels[5][31:24]) : 8'd0;
    end
end
endmodule
