`timescale 1ns/1ps
// Image1's exact median kernel, with a center-tap bypass of identical latency.
// M changes pixel values, never the video delay or the window's coordinates.
module image5_gray_median #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,input rst_n,input enable_req,input in_vsync,in_hsync,in_href,input [7:0] in_gray,
 output out_vsync,out_hsync,out_href,output [7:0] out_gray
);
 wire mv,mh,me;wire [7:0] a,b,c,d,e,f,g,h,i;
 reg active;reg [2:0] enable_pipe;reg [7:0] center0,center1,center2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=1;enable_pipe<=7;center0<=0;center1<=0;center2<=0;end
  else begin
   if(!in_vsync)active<=enable_req;
   enable_pipe<={enable_pipe[1:0],active};center0<=e;center1<=center0;center2<=center1;
  end
 end
 VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) u_window(
  .clk(clk),.rst_n(rst_n),.per_frame_vsync(in_vsync),.per_frame_hsync(in_hsync),.per_frame_href(in_href),.per_img_Y(in_gray),
  .matrix_frame_vsync(mv),.matrix_frame_hsync(mh),.matrix_frame_href(me),
  .matrix_p11(a),.matrix_p12(b),.matrix_p13(c),.matrix_p21(d),.matrix_p22(e),.matrix_p23(f),.matrix_p31(g),.matrix_p32(h),.matrix_p33(i));
 wire [7:0] median;
 median3x3_kernel u_kernel(.clk(clk),.rst_n(rst_n),.in_frame_vsync(mv),.in_frame_hsync(mh),.in_frame_href(me),
  .p11(a),.p12(b),.p13(c),.p21(d),.p22(e),.p23(f),.p31(g),.p32(h),.p33(i),
  .out_frame_vsync(out_vsync),.out_frame_hsync(out_hsync),.out_frame_href(out_href),.out_img_median(median));
 assign out_gray=!out_href?8'd0:enable_pipe[2]?median:center2;
endmodule

// Remove pixels with fewer than two 8-neighbours. Unlike binary erosion this
// preserves a one-pixel-wide continuous line; it does not invent or thicken it.
module image5_edge_prune #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,input rst_n,input enable_req,input in_vsync,in_hsync,in_href,input in_edge,
 output reg out_vsync,out_hsync,out_href,output reg out_edge
);
 wire mv,mh,me;wire a,b,c,d,e,f,g,h,i;
 reg active;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)active<=1;else if(!in_vsync)active<=enable_req;
 end
 VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT),.DATA_WIDTH(1)) u_window(
  .clk(clk),.rst_n(rst_n),.per_frame_vsync(in_vsync),.per_frame_hsync(in_hsync),.per_frame_href(in_href),.per_img_Y(in_edge),
  .matrix_frame_vsync(mv),.matrix_frame_hsync(mh),.matrix_frame_href(me),
  .matrix_p11(a),.matrix_p12(b),.matrix_p13(c),.matrix_p21(d),.matrix_p22(e),.matrix_p23(f),.matrix_p31(g),.matrix_p32(h),.matrix_p33(i));
 wire [3:0] neighbours={3'd0,a}+b+c+d+f+g+h+i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin out_vsync<=0;out_hsync<=0;out_href<=0;out_edge<=0;end
  else begin out_vsync<=mv;out_hsync<=mh;out_href<=me;out_edge<=me&&e&&(!active||neighbours>=2);end
 end
endmodule

module image5_canny_pipeline #(parameter WIDTH=1920,HEIGHT=1080,TOP_GUARD=12)(
 input clk,input rst_n,input in_vsync,in_hsync,in_href,input [7:0] in_gray,
 input median_req,input cleanup_req,input [10:0] high_threshold,low_threshold,
 output gray_vsync,gray_hsync,gray_href,output [7:0] gray_pixel,
 output out_vsync,out_hsync,out_href,output [7:0] out_edge
);
 image5_gray_median #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_gray_median(
  .clk(clk),.rst_n(rst_n),.enable_req(median_req),.in_vsync(in_vsync),.in_hsync(in_hsync),.in_href(in_href),.in_gray(in_gray),
  .out_vsync(gray_vsync),.out_hsync(gray_hsync),.out_href(gray_href),.out_gray(gray_pixel));
 wire cv,ch,ce;wire [7:0] edge_pixel;
 // image1's gradient selects the strongest RGB channel (gray is a sideband).
 // Replicate filtered gray on all three channels for true grayscale Canny.
 // Identical channels can share logic/RAM after synthesis; never tie them off.
 canny_edge #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) u_canny(
  .clk(clk),.rst_n(rst_n),.per_frame_vsync(gray_vsync),.per_frame_hsync(gray_hsync),.per_frame_href(gray_href),
  .per_img_gray(gray_pixel),.per_img_red(gray_pixel),.per_img_green(gray_pixel),.per_img_blue(gray_pixel),
  .high_threshold(high_threshold),.low_threshold(low_threshold),.post_frame_vsync(cv),.post_frame_hsync(ch),.post_frame_href(ce),
  .post_img_edge(edge_pixel),.post_img_red(),.post_img_green(),.post_img_blue());
 (* async_reg="true" *)reg clean_meta,clean_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin clean_meta<=1;clean_sync<=1;end
  else begin clean_meta<=cleanup_req;clean_sync<=clean_meta;end
 end
 wire v0,h0,e0,p0,v1,h1,e1,p1;
 image5_edge_prune #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_prune0(
  .clk(clk),.rst_n(rst_n),.enable_req(clean_sync),.in_vsync(cv),.in_hsync(ch),.in_href(ce),.in_edge(edge_pixel!=0),
  .out_vsync(v0),.out_hsync(h0),.out_href(e0),.out_edge(p0));
 image5_edge_prune #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_prune1(
  .clk(clk),.rst_n(rst_n),.enable_req(clean_sync),.in_vsync(v0),.in_hsync(h0),.in_href(e0),.in_edge(p0),
  .out_vsync(v1),.out_hsync(h1),.out_href(e1),.out_edge(p1));
 reg href_d;reg [11:0] x;reg [10:0] y;
 wire [11:0] px=e1&&!href_d?0:x;
 wire [10:0] py=e1&&!href_d?y+1'b1:y;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin href_d<=0;x<=0;y<=11'h7ff;end
  else begin
   href_d<=e1;
   if(!v1)begin x<=0;y<=11'h7ff;end
   else if(e1)begin x<=px+1'b1;y<=py;end
  end
 end
 assign out_vsync=v1;assign out_hsync=h1;assign out_href=e1;
 // Suppress only startup/border artifacts; preserve every output pixel/line.
 assign out_edge=e1&&p1&&py>=TOP_GUARD&&py<HEIGHT-2&&px>=2&&px<WIDTH-2?8'hff:8'h00;
endmodule
