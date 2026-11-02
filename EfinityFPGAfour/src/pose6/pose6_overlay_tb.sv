`timescale 1ns/1ps
module pose6_overlay_tb;
 reg sclk=0,pclk=0,rst_n=0;
 always #5 sclk=~sclk;always #3 pclk=~pclk;
 reg publish=0,valid=1;reg [191:0] points=0;
 reg iv=0,ih=0,ide=0;reg [23:0] rgb=24'h123456;
 wire ov,oh,ode;wire [23:0] orgb;
 pose6_hdmi_overlay #(.RESULT_TIMEOUT(100000)) dut(sclk,rst_n,pclk,rst_n,publish,points,valid,4'd3,8'd0,iv,ih,ide,rgb,ov,oh,ode,orgb);
 integer count0=0,count1=0,count2=0,count3=0,lines=0;
 reg first_frame=1;
 task publish_points(input integer shift,input bit good);
  begin
   @(negedge sclk);
   points[0+:48]={16'd40000,16'd40,16'(40+shift)};
   points[48+:48]={16'd40000,16'd40,16'(80+shift)};
   points[96+:48]={16'd40000,16'd80,16'(20+shift)};
   points[144+:48]={16'd40000,16'd80,16'(100+shift)};
   valid=good;publish=1;@(negedge sclk);publish=0;
   repeat(20)@(negedge pclk);
  end
 endtask
 task tick(input bit v,input bit h,input bit de,input [23:0] color);
  begin
   @(negedge pclk);iv=v;ih=h;ide=de;rgb=color;
   @(posedge pclk);#1;
   if({ov,oh,ode}!=={v,h,de})$fatal(1,"HDMI sync/DE not aligned with RGB");
   if(de)case(orgb)
    24'h49ddff:count0=count0+1;
    24'hffcc55:count1=count1+1;
    24'h59ff99:count2=count2+1;
    24'hff7799:count3=count3+1;
   endcase
  end
 endtask
 task frame;
  begin
   tick(1,0,0,0);tick(0,0,0,0);repeat(8)tick(0,0,0,0);
   for(integer y=0;y<96;y=y+1)begin
    for(integer x=0;x<128;x=x+1)begin
     tick(1,1,1,24'h123456);
     if(first_frame&&x==45&&y==30&&orgb!==24'hdddddd)$fatal(1,"Shoulder segment rasterization");
     if(x==110&&y==90&&orgb!==24'h123456)$fatal(1,"Uncovered video pixel changed");
    end
    repeat(4)tick(1,0,0,0);
   end
  end
 endtask
 initial begin
  #31;rst_n=1;
  publish_points(0,1);frame();
  first_frame=0;
  if(count0==0||count1==0||count2==0||count3==0)$fatal(1,"Four point colors missing %0d %0d %0d %0d",count0,count1,count2,count3);
  if(dut.x[0]!=30||dut.y[0]!=30||dut.x[3]!=75||dut.y[3]!=60)$fatal(1,"Q14.2 -> 1080p coordinate mapping");
  // A new result arriving inside the active frame cannot tear the quartet.
  publish_points(40,1);
  if(dut.x[0]!=30||dut.x[3]!=75)$fatal(1,"Points changed before frame boundary");
  frame();if(dut.x[0]!=60||dut.x[1]!=90||dut.x[2]!=45||dut.x[3]!=105)$fatal(1,"New frame did not apply complete latest quartet");
  publish_points(0,0);frame();
  if(dut.frame_valid)$fatal(1,"Invalid point result remained visible");
  publish_points(0,1);frame();
  repeat(100010)@(negedge pclk);
  if(dut.age<100000||dut.point_hit!=0||dut.line_hit!=0)$fatal(1,"Stale results not hidden");
  // Model OFF repeatedly publishes invalidation: it must survive a busy
  // mailbox occupied by the immediately preceding valid result.
  @(negedge sclk);publish=1;valid=1;
  @(negedge sclk);valid=0;
  repeat(20)@(negedge pclk);
  frame();
  if(dut.frame_valid||dut.point_hit!=0||dut.line_hit!=0)$fatal(1,"Model OFF clear lost behind occupied mailbox");
  @(negedge sclk);publish=0;
  $display("PASS HDMI model OFF invalidation survives occupied CDC mailbox and leaves video timing intact");
  $display("PASS HDMI overlay: async immutable quartet, frame-boundary updates, Q14.2 scaling, four colors, aligned RGB/sync, invalid/stale suppression");$finish;
 end
 initial begin #2000000;$fatal(1,"overlay timeout");end
endmodule
