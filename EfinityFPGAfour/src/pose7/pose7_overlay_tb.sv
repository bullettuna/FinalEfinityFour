`timescale 1ns/1ps
module pose7_overlay_tb;
 reg sclk=0,pclk=0,rst_n=0;
 always #5 sclk=~sclk;always #3 pclk=~pclk;
 reg publish=0,valid=1;reg [527:0] points=0;
 reg iv=0,ih=0,ide=0;reg [23:0] rgb=24'h123456;
 wire ov,oh,ode;wire [23:0] orgb;
 pose7_hdmi_overlay #(.RESULT_TIMEOUT(200000)) dut(sclk,rst_n,pclk,rst_n,publish,points,valid,4'd3,8'd0,iv,ih,ide,rgb,ov,oh,ode,orgb);
 integer hits[0:10];integer colored=0;
 task publish_points(input integer shift,input bit good);
  begin
   @(negedge sclk);
   for(integer i=0;i<11;i=i+1)begin
    points[i*48+:16]=(20+i*12+shift)*4/3;
    points[i*48+16+:16]=(30+(i%3)*20)*4/3;
    points[i*48+32+:16]=50000;
   end
   valid=good;publish=1;@(negedge sclk);publish=0;
   repeat(20)@(negedge pclk);
  end
 endtask
 task tick(input bit v,input bit h,input bit de);
  begin
   @(negedge pclk);iv=v;ih=h;ide=de;
   #1;
   if(de)for(integer i=0;i<11;i=i+1)if(dut.point_hit[i])hits[i]=hits[i]+1;
   @(posedge pclk);#1;
   if({ov,oh,ode}!=={v,h,de})$fatal(1,"HDMI timing mismatch");
   if(de&&orgb!=rgb)colored=colored+1;
  end
 endtask
 task frame;
  begin
   tick(1,0,0);tick(0,0,0);repeat(8)tick(0,0,0);
   for(integer y=0;y<96;y=y+1)begin
    for(integer x=0;x<192;x=x+1)tick(1,1,1);
    repeat(4)tick(1,0,0);
   end
  end
 endtask
 integer previous_x;
 initial begin
  for(integer i=0;i<11;i=i+1)hits[i]=0;
  #31;rst_n=1;publish_points(0,1);frame();
  for(integer i=0;i<11;i=i+1)begin
   if(hits[i]==0||!dut.point_ok[i])$fatal(1,"Missing point %0d",i);
   if(dut.x[i]!=(20+i*12))$fatal(1,"Point scaling %0d",i);
  end
  if(dut.line_ok!==12'hfff||colored<100)$fatal(1,"Missing skeleton edges");
  previous_x=dut.x[10];publish_points(12,1);
  if(dut.x[10]!=previous_x)$fatal(1,"Result tore during active frame");
  frame();if(dut.x[0]!=32||dut.x[10]!=152)$fatal(1,"New complete result not applied");
  publish_points(0,0);frame();if(dut.frame_valid)$fatal(1,"Invalid result visible");
  publish_points(0,1);frame();repeat(200010)@(negedge pclk);
  if(dut.point_hit!=0||dut.line_hit!=0)$fatal(1,"Stale result visible");
  @(negedge sclk);publish=1;valid=1;@(negedge sclk);valid=0;
  repeat(20)@(negedge pclk);frame();
  if(dut.frame_valid||dut.point_hit!=0||dut.line_hit!=0)$fatal(1,"OFF invalidation lost behind occupied mailbox");
  @(negedge sclk);publish=0;
  $display("PASS HDMI eleven-point overlay: all points/12 edges, anatomical topology, frame-atomic CDC, aligned video, OFF and stale suppression");$finish;
 end
 initial begin #4000000;$fatal(1,"Overlay timeout");end
endmodule
