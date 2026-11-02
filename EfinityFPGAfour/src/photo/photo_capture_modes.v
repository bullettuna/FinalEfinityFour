`timescale 1ns/1ps
// A complete-frame sampler. C retains the legacy top-left RGB565 sampling.
// G/E average all four exact 8-bit luminance samples BEFORE edge extraction.
// Their temporary DDR format is {8'b0,Y}, converted to BMP only after processing.
module photo_capture_modes #(parameter IN_WIDTH=1920,IN_HEIGHT=1080)(
 input clk,input rst_n,input capture_toggle,input [1:0] mode_req,
 input in_vsync,in_href,input [7:0] red,green,blue,
 output reg capture_active,output reg capture_done_toggle,
 output reg pixel_valid,output reg [15:0] pixel_rgb565
);
 wire v,h;wire [7:0] gray,r,g,b;
 grey u_gray(.clk(clk),.rst_n(rst_n),.gray_en(1'b0),
  .per_frame_vsync(in_vsync),.per_frame_href(in_href),.per_frame_hsync(1'b0),
  .per_img_red(red),.per_img_green(green),.per_img_blue(blue),
  .post_frame_vsync(v),.post_frame_href(h),.post_frame_hsync(),
  .post_img_gray(gray),.post_img_red(r),.post_img_green(g),.post_img_blue(b));
 (* async_reg="true" *) reg [1:0] mode_meta,mode_sync;
 reg vd,hd,seen;reg [1:0] mode;
 reg [11:0] x;reg [10:0] y;
 reg [7:0] left;reg [8:0] top_pair;
 (* ram_style="block" *) reg [8:0] row_pairs[0:IN_WIDTH/2-1];
 wire [8:0] pair_sum={1'b0,left}+{1'b0,gray};
 wire [10:0] sum4={2'b0,top_pair}+{2'b0,pair_sum}+11'd2;
 // Synchronous read has a full input pixel period before the odd-X consumer.
 always @(posedge clk)begin
  if(h&&!x[0])top_pair<=row_pairs[x[11:1]];
  if(h&&x[0]&&!y[0])row_pairs[x[11:1]]<=pair_sum;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mode_meta<=0;mode_sync<=0;vd<=0;hd<=0;seen<=0;mode<=0;
   x<=0;y<=0;left<=0;capture_active<=0;capture_done_toggle<=0;pixel_valid<=0;pixel_rgb565<=0;end
  else begin
   mode_meta<=mode_req;mode_sync<=mode_meta;vd<=v;hd<=h;pixel_valid<=0;
   if(v&&!vd)begin
    x<=0;y<=0;
    if(capture_active)begin capture_active<=0;capture_done_toggle<=~capture_done_toggle;end
    if(capture_toggle!=seen)begin seen<=capture_toggle;capture_active<=1;mode<=mode_sync;end
   end else if(h)begin
    x<=x+1'b1;left<=gray;
    if(capture_active&&x<IN_WIDTH&&y<IN_HEIGHT)begin
     if(mode==0&&!x[0]&&!y[0])begin pixel_valid<=1;pixel_rgb565<={r[7:3],g[7:2],b[7:3]};end
     if(mode!=0&&x[0]&&y[0])begin pixel_valid<=1;pixel_rgb565<={8'd0,sum4[9:2]};end
    end
   end else begin x<=0;if(hd)y<=y+1'b1;end
  end
 end
endmodule
