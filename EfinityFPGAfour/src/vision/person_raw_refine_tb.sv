`timescale 1ns/1ps
module person_raw_refine_tb;
localparam W=32,H=24,FW=W*4,FH=H*4;
reg clk=0,rst_n=0,vs=0,de=0,strong_pixel=0,weak_pixel=0;always #5 clk=~clk;
wire ov,oe,mask,contour,valid,busy,error,fallback;wire [11:0] xmin,xmax;
person_snapshot_selector #(.WIDTH(W),.HEIGHT(H),.MIN_AREA(8),.MIN_WIDTH(2),.MIN_HEIGHT(2),
 .FRAGMENT_AREA(2),.PAD(1),.QUEUE_BITS(9),.REFINE(1),.GROW_PAD(8),.GROW_FACTOR(2),.GROW_EXTRA(0),.MAX_HOLE(4)) dut(
 .clk(clk),.rst_n(rst_n),.source_valid(1'b1),.invalidate(1'b0),.in_vsync(vs),.in_hsync(1'b0),.in_href(de),
 .in_mask(strong_pixel),.in_weak_mask(weak_pixel),.out_vsync(ov),.out_href(oe),.out_mask(mask),.out_contour(contour),
 .bbox_valid(valid),.bbox_x_min(xmin),.bbox_x_max(xmax),.busy(busy),.processing_error(error),.refine_fallback(fallback));
function automatic bit solid(input integer x,y,m);
 if(m==3)solid=x>=6&&x<=25&&y>=2&&y<=21&&!(x>=10&&x<=20&&y>=7&&y<=17);
 else solid=m!=0&&x>=10&&x<=17&&y>=6&&y<=19&&!(x>=13&&x<=14&&y>=10&&y<=11)&&!(x>=15&&y>=15&&y<=16);
endfunction
function automatic bit weak_area(input integer x,y,m);
 if(m==0)weak_area=x>=8&&x<=20&&y>=5&&y<=19;
 else if(m==2)weak_area=1;
 else weak_area=solid(x,y,m)||(m==1&&((x>=18&&x<=23&&y>=8&&y<=9)||(x>=24&&x<=25&&y>=18&&y<=19)));
endfunction
function automatic bit expected(input integer x,y,m);
 if(x<0||x>=W||y<0||y>=H)expected=0;
 else expected=solid(x,y,m)||((m==1||m==2)&&x>=13&&x<=14&&y>=10&&y<=11)||(m==1&&x>=18&&x<=23&&y>=8&&y<=9);
endfunction
function automatic bit border(input integer x,y,m);
 bit interior;
 begin interior=1;for(integer a=-1;a<=1;a++)for(integer b=-1;b<=1;b++)interior&=expected(x+a,y+b,m);border=expected(x,y,m)&&!interior;end
endfunction
task frame(input integer m,input bit check);
 begin
 @(negedge clk);vs=0;de=0;repeat(8)@(negedge clk);vs=1;repeat(8)@(negedge clk);
 for(integer y=0;y<FH;y++)begin
  for(integer x=0;x<FW;x++)begin
   @(negedge clk);de=1;strong_pixel=solid(x/4,y/4,m);weak_pixel=weak_area(x/4,y/4,m);
   @(posedge clk);#1;
   if(check&&(mask!==expected(x/4,y/4,m)||contour!==border(x/4,y/4,m)))
    $fatal(1,"RAW refinement mode=%0d x=%0d y=%0d mask=%b/%b contour=%b/%b state=%0d",m,x,y,mask,expected(x/4,y/4,m),contour,border(x/4,y/4,m),dut.state);
  end
  @(negedge clk);de=0;repeat(8)@(negedge clk);
 end
 @(negedge clk);vs=0;de=0;
 end
endtask
task run(input integer m);
 integer timeout;
 begin
 rst_n=0;vs=0;de=0;repeat(4)@(negedge clk);rst_n=1;
 frame(m,0);timeout=0;while(!dut.pending&&timeout<200000)begin @(negedge clk);timeout++;end
 if(!dut.pending||error)$fatal(1,"RAW refinement incomplete mode=%0d state=%0d error=%b",m,dut.state,error);
 if(fallback!==(m==2))$fatal(1,"growth rollback mismatch mode=%0d fallback=%b",m,fallback);
 frame(m,1);
 if(valid!==(m!=0))$fatal(1,"weak_pixel-only background became target");
 if(m==1&&xmax!=99)$fatal(1,"recovered arm did not expand bbox: xmax=%0d",xmax);
 $display("REFINE mode=%0d passed fallback=%b bbox=%0d..%0d",m,fallback,xmin,xmax);
 end
endtask
initial begin run(1);run(2);run(3);run(0);$display("PASS RAW refinement: connected weak_pixel arm recovered, detached weak_pixel background rejected, small enclosed hole filled, open notch and large hole preserved, excessive growth rolls back to strong_pixel result, weak_pixel-only frame rejected");$finish;end
initial begin #15000000;$fatal(1,"RAW refinement timeout");end
endmodule
