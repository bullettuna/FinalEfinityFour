`timescale 1ns/1ps
module person_roi_pipeline_tb #(parameter REFINE=0);
localparam W=64,H=48,HT=80,DELAY=12*HT+3;
reg clk=0,rst=0,vs=0,hs=0,de=0,available=1,fault=0;
reg [7:0] current=40,background=40,threshold=24;
reg [1:0] noise=2;reg [2:0] view=1;
wire ov,oh,oe,active,valid,busy,error;wire [23:0] rgb;
always #5 clk=~clk;
person_roi_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.RAW_REFINE(REFINE)) dut(
 .clk(clk),.rst_n(rst),.background_valid(available),.sample_valid(de&&available),.stream_fault(fault),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.current_raw(current),.background_raw(background),
 .threshold_req(threshold),.noise_req(noise),.view_req(view),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_rgb(rgb),.display_active(active),
 .candidate_valid(valid),.analysis_busy(busy),.processing_error(error));
reg [2:0] history[0:DELAY+1];
integer cycles=0,xout=0,yout=-1,checked=0,mode=1;
reg de_old=0;bit person;
always @(posedge clk)begin
 history[cycles%(DELAY+2)]={vs,hs,de};#1;
 if(rst&&cycles>DELAY+2&&{ov,oh,oe}!==history[(cycles-DELAY)%(DELAY+2)])
  $fatal(1,"person display sync changed cycle=%0d got=%b want=%b",cycles,{ov,oh,oe},history[(cycles-DELAY)%(DELAY+2)]);
 if(!ov)yout=-1;
 if(oe)begin
  if(!de_old)begin xout=0;yout++;end
  if(xout>=W||yout>=H)$fatal(1,"person display frame geometry");
  person=xout>=16&&xout<40&&yout>=8&&yout<40;
  if(mode==1&&rgb!== (person?24'hffffff:24'd0))$fatal(1,"raw mask display x=%0d y=%0d got=%h",xout,yout,rgb);
  if(mode==3&&valid&&rgb!== (person?24'hffffff:24'd0))$fatal(1,"selected mask display x=%0d y=%0d got=%h",xout,yout,rgb);
  xout++;checked++;
 end
 de_old=oe;cycles++;
 if(error)$fatal(1,"pipeline processing error");
end
task tick;begin hs=cycles%HT>=4;@(negedge clk);end endtask
task frame;
 begin
  vs=0;de=0;repeat(5*HT)tick();vs=1;repeat(36*HT)tick();
  for(integer y=0;y<H;y++)begin
   for(integer x=0;x<W;x++)begin de=1;current=(x>=16&&x<40&&y>=8&&y<40)?120:40;tick();end
   de=0;repeat(HT-W)tick();
  end
  repeat(4*HT)tick();
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 frame();frame();frame();
 // Change diagnostic view at blank; subsequent snapshots retain exact RGB.
 view=3;mode=0;frame();mode=3;frame();frame();
 if(!valid||!active||checked<5*W*H)$fatal(1,"pipeline did not produce candidate or complete frames");
 @(negedge clk);available=0;repeat(5)tick();if(valid)$fatal(1,"background invalidation retained ROI");
 $display("PASS person pipeline: real RAW mean/morphology/snapshot/display integration, pixel-perfect raw and selected mask, matched RGB/sync and invalid background");$finish;
end
initial begin #2000000;$fatal(1,"person pipeline timeout");end
endmodule
