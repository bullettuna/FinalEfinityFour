`timescale 1ns/1ps
// The real LCD driver consumes FIFO data one clock ahead of active DE. The
// top-level background data AND its VALID must have the identical register.
module background_lcd_alignment_tb;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire request,vs,hs,de;wire [7:0] current_raw;
 reg [7:0] background_aligned;reg valid_aligned;
 integer px=0,py=0,cells=0,frames=0;reg vs_d=0;
 wire [7:0] background_fifo=40+px+py*4;
 wire [7:0] current_fifo=background_fifo+16;
 wire available=frames<2;
 lcd_driver #(.H_FRONT(4),.H_SYNC(2),.H_BACK(2),.H_DISP(16),.H_TOTAL(24),
  .V_FRONT(20),.V_SYNC(2),.V_BACK(2),.V_DISP(8),.V_TOTAL(32),.DATA_WIDTH(8)) lcd(
  .clk(clk),.rst_n(rst),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),.lcd_request(request),.lcd_rgb(current_raw),.lcd_data(current_fifo));
 always @(posedge clk)begin
  if(!rst)begin px<=0;py<=0;frames<=0;vs_d<=0;background_aligned<=0;valid_aligned<=0;end
  else begin
   vs_d<=vs;if(vs_d&&!vs)frames<=frames+1;
   background_aligned<=background_fifo;valid_aligned<=request&&available;
   if(!vs)begin px<=0;py<=0;end
   else if(request)begin if(px==15)begin px<=0;py<=py+1;end else px<=px+1;end
  end
 end
 wire cv,cm;wire [7:0] am,bm;wire [2:0] x;wire [9:0] y;
 background_bayer_average #(.WIDTH(16),.HEIGHT(8)) average(
  .clk(clk),.rst_n(rst),.vsync(vs),.href(de),.background_valid(1'b1),.sample_valid(valid_aligned),
  .current_raw(current_raw),.background_raw(background_aligned),.binary_mode(1'b0),.binary_pixel(1'b0),.threshold(8'd12),
  .cell_valid(cv),.cell_mask(cm),.current_mean(am),.background_mean(bm),.cell_x(x),.cell_y(y));
 always @(posedge clk)begin
  #1;
  if(cv)begin
   if(bm!=43+x*2+y*8||am!=bm+16||cm!==available)
    $fatal(1,"real LCD/FIFO offset or invalid-background leak: x=%d y=%d means=%d/%d mask=%b",x,y,am,bm,cm);
   cells=cells+1;
   if(cells==96)begin $display("PASS real LCD request/DE alignment + matching RAW means + missing background suppresses false foreground");$finish;end
  end
 end
 initial begin repeat(5)@(negedge clk);rst=1;end
 initial begin #100000;$fatal(1,"LCD alignment timeout");end
endmodule
