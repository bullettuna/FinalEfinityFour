`timescale 1ns/1ps
module photo_gallery_display_tb #(parameter DWIDTH=8,DHEIGHT=4);
 localparam SOURCE_BYTES=DWIDTH*DHEIGHT/2;
 reg clk=0,rst=0,en=0,vs=0,de=0,sreset=0,supply=1;
 always #5 clk=~clk;
 integer byte_index=0,frame_no=0;
 wire ready,err,ode;wire [7:0] r,g,b;
 function [15:0] pixel(input integer n);
  begin case(n%8)
   0:pixel=16'hf800;1:pixel=16'h07e0;2:pixel=16'h001f;3:pixel=16'h630c;
   4:pixel=16'hffff;5:pixel=16'h0000;6:pixel=16'hf81f;7:pixel=16'h07ff;
  endcase if(DWIDTH>8 && (n/(DWIDTH/2))%2)pixel=pixel^16'h0841;end
 endfunction
 wire [15:0] offered=pixel(byte_index/2) ^ (frame_no==1?16'hffff:16'h0000);
 photo_display_stream #(.DISPLAY_WIDTH(DWIDTH),.DISPLAY_HEIGHT(DHEIGHT)) dut(
  .clk(clk),.rst_n(rst),.gallery_enable(en),.photo_stream_reset(sreset),
  .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.photo_byte_valid(supply&&byte_index<SOURCE_BYTES),
  .photo_byte(byte_index%2?offered[15:8]:offered[7:0]),.photo_byte_ready(ready),
  .out_href(ode),.out_red(r),.out_green(g),.out_blue(b),.frame_error(err));
 always @(posedge clk)begin
  if(sreset||!rst)byte_index<=0;
  else if(ready&&supply&&byte_index<SOURCE_BYTES)byte_index<=byte_index+1;
 end
 task frame;
  reg [15:0] want;
  begin
   @(negedge clk);vs=1;sreset=1;
   repeat(3)@(negedge clk);sreset=0;
   repeat(3)@(negedge clk);vs=0;
   repeat(12)@(negedge clk);
   for(integer y=0;y<DHEIGHT;y=y+1)begin
    for(integer x=0;x<DWIDTH;x=x+1)begin
     de=1;@(posedge clk);#1;want=pixel((y/2)*(DWIDTH/2)+x/2) ^ (frame_no==1?16'hffff:16'h0000);
     if(!ode||{r,g,b}!={want[15:11],3'b0,want[10:5],2'b0,want[4:0],3'b0})
      $fatal(1,"2x/RGB565 mismatch x=%d y=%d got=%h want=%h",x,y,{r,g,b},want);
     if(err)$fatal(1,"unexpected underflow");@(negedge clk);
    end
    de=0;repeat(8)@(negedge clk);
   end
   if(byte_index!=SOURCE_BYTES)$fatal(1,"source byte count wrong");
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;en=1;frame();frame_no=1;frame();
  supply=0;vs=1;sreset=1;repeat(3)@(negedge clk);sreset=0;vs=0;
  repeat(8)@(negedge clk);de=1;repeat(4)@(negedge clk);
  if(!err||{r,g,b}!=0)$fatal(1,"underflow did not suppress corrupt frame");
  de=0;supply=1;frame_no=0;frame();
  $display("PASS gallery little-endian RGB565, exact 2x rows/columns, frame reset and underflow recovery");$finish;
 end
 initial begin #100000000;$fatal(1,"display timeout");end
endmodule
