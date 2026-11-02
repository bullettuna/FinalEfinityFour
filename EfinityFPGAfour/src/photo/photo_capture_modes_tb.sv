`timescale 1ns/1ps
module photo_capture_modes_tb #(parameter WIDTH=64,HEIGHT=40);
 reg clk=0,rst_n=0,toggle=0,vs=0,de=0;reg [1:0] mode=0;
 reg [7:0] r=0,g=0,b=0;wire active,finished,valid;wire [15:0] pixel;
 always #3.36 clk=~clk;
 photo_capture_modes #(.IN_WIDTH(WIDTH),.IN_HEIGHT(HEIGHT)) dut(
  .clk(clk),.rst_n(rst_n),.capture_toggle(toggle),.mode_req(mode),.in_vsync(vs),.in_href(de),
  .red(r),.green(g),.blue(b),.capture_active(active),.capture_done_toggle(finished),.pixel_valid(valid),.pixel_rgb565(pixel));
 integer count=0,expected_mode=0,source_frame=0;reg checking=0;
 function [7:0] red(input integer x,y,f);red=(13*x+7*y+17*f)%256;endfunction
 function [7:0] green(input integer x,y,f);green=(3*x+11*y+23*f)%256;endfunction
 function [7:0] blue(input integer x,y,f);blue=(19*x+5*y+31*f)%256;endfunction
 function integer gray(input integer x,y,f);gray=(54*red(x,y,f)+183*green(x,y,f)+19*blue(x,y,f)+128)/256;endfunction
 integer xx,yy,avg;reg [15:0] wanted;reg [7:0] er,eg,eb;
 always @(negedge clk)if(checking&&valid)begin
  xx=(count%(WIDTH/2))*2;yy=(count/(WIDTH/2))*2;
  er=red(xx,yy,source_frame);eg=green(xx,yy,source_frame);eb=blue(xx,yy,source_frame);
  avg=(gray(xx,yy,source_frame)+gray(xx+1,yy,source_frame)+gray(xx,yy+1,source_frame)+gray(xx+1,yy+1,source_frame)+2)/4;
  wanted=expected_mode==0?{er[7:3],eg[7:2],eb[7:3]}:avg;
  if(pixel!==wanted)$fatal(1,"capture mode=%0d x=%0d y=%0d got=%h expected=%h",expected_mode,xx,yy,pixel,wanted);
  count=count+1;
 end
 task frame(input integer f,input integer change_mode);
  @(negedge clk);vs=1;
  repeat(12)@(negedge clk);
  for(integer y=0;y<HEIGHT;y=y+1)begin
   for(integer x=0;x<WIDTH;x=x+1)begin
    de=1;r=red(x,y,f);g=green(x,y,f);b=blue(x,y,f);
    if(change_mode&&y==HEIGHT/2&&x==0)mode=0;
    @(negedge clk);
   end
   de=0;repeat(12)@(negedge clk);
  end
  vs=0;repeat(20)@(negedge clk);
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
  for(integer m=0;m<3;m=m+1)begin
   mode=m;expected_mode=m;source_frame=m;count=0;checking=1;
   repeat(6)@(negedge clk);toggle=!toggle;frame(m,m!=0);
   if(count!=WIDTH*HEIGHT/4)$fatal(1,"capture pixel count %d",count);
   checking=0;frame(7,0);
   if(active)$fatal(1,"one-shot capture did not finish");
   $display("PASS image2 %0dx%0d mode %0d complete-frame sampling and exact 2x2 grayscale mean (%0d pixels)",WIDTH,HEIGHT,m,count);
  end
  $finish;
 end
 initial begin #1000000000;$fatal(1,"sampler watchdog");end
endmodule
