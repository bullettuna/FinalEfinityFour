`timescale 1ns/1ps
module person_canny_roi_view_tb #(parameter W=64,H=48,HT=80);
localparam DELAY=12*HT-31;
reg clk=0,rst_n=0,vs=0,hs=0,de=0,pixel=0;always #5 clk=~clk;
reg [2:0] view=6;reg source_valid=1,bv=1;
reg [11:0] xmin=W/8,xmax=W*7/8-1;reg [10:0] ymin=H/8,ymax=H*7/8-1;
reg [2:0] history[0:DELAY-1];integer ptr=0;
reg tv=0,th=0,te=0;
always @(posedge clk)begin
 if(!rst_n)begin ptr<=0;tv<=0;th<=0;te<=0;end
 else begin {tv,th,te}<=history[ptr];history[ptr]<={vs,hs,de};ptr<=ptr==DELAY-1?0:ptr+1;end
end
wire ov,oh,oe,active,aligned_edge,aligned_valid;wire [23:0] rgb;
person_canny_roi_view #(.WIDTH(W),.HEIGHT(H)) dut(
 .clk(clk),.rst_n(rst_n),.view_req(view),.source_valid(source_valid),.edge_vsync(vs),.edge_href(de),.edge_pixel(pixel),
 .target_vsync(tv),.target_hsync(th),.target_href(te),.bbox_valid(bv),.bbox_x_min(xmin),.bbox_x_max(xmax),.bbox_y_min(ymin),.bbox_y_max(ymax),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_rgb(rgb),.display_active(active),
 .aligned_edge(aligned_edge),.aligned_edge_valid(aligned_valid));
function automatic bit edge_at(input integer x,y,f);
 edge_at=((x*17+y*7+f*13)%11)<3;
endfunction
reg ov_d=0,oe_d=0;integer output_frame=0,x=0,y=-1,checked=0,complete=0;
reg [2:0] previous_target=0,sampled_target;
reg [23:0] expected;
integer bx0,bx1,by0,by1;
always @(posedge clk)begin
 sampled_target={tv,th,te};#1;
 if(rst_n)begin
  if({ov,oh,oe}!==previous_target)$fatal(1,"Canny ROI RGB/sync latency mismatch");
  if(ov&&!ov_d)begin output_frame++;y=-1;end
  if(oe)begin
   if(!oe_d)begin x=0;y++;end
   bx0=output_frame==1?W/8:W/4;bx1=output_frame==1?W*7/8-1:W*3/4-1;
   by0=output_frame==1?H/8:H/4;by1=output_frame==1?H*7/8-1:H*3/4-1;
   expected=0;
   if(x>=bx0&&x<=bx1&&y>=by0&&y<=by1)begin
    if(x==bx0||x==bx1||y==by0||y==by1)expected=24'h00ff00;
    else if(edge_at(x,y,output_frame))expected=24'hffffff;
   end
   if(rgb!==expected)$fatal(1,"Canny ROI coordinate/epoch/frame-box mismatch frame=%0d x=%0d y=%0d got=%h expected=%h row_ok=%b",output_frame,x,y,rgb,expected,dut.row_ok_q);
   if(aligned_valid!==1'b1||aligned_edge!==edge_at(x,y,output_frame))$fatal(1,"matcher edge sideband alignment mismatch x=%0d y=%0d",x,y);
   if(!active)$fatal(1,"U6 preview inactive");
   x++;checked++;
   if(x==W&&y==H-1)complete++;
  end
 end
 previous_target=sampled_target;ov_d=ov;oe_d=oe;
end
task tick;begin hs=ptr%HT>3;@(negedge clk);end endtask
task frame(input integer f);
 begin
 vs=0;de=0;repeat(5*HT)tick();vs=1;repeat(36*HT)tick();
 for(integer yy=0;yy<H;yy++)begin
  for(integer xx=0;xx<W;xx++)begin
   de=1;pixel=edge_at(xx,yy,f);
   if(f==1&&yy==H/2)begin xmin=W/4;xmax=W*3/4-1;ymin=H/4;ymax=H*3/4-1;end
   tick();
  end
  de=0;repeat(HT-W)tick();
 end
 repeat(4*HT)tick();vs=0;
 end
endtask
initial begin
 for(integer i=0;i<DELAY;i++)history[i]=0;
 repeat(4)tick();rst_n=1;frame(1);frame(2);repeat(DELAY+3*HT)tick();
 if(complete!=2||checked!=2*W*H)$fatal(1,"Canny ROI frame size/count mismatch");
 view=0;repeat(6)tick();if(active)$fatal(1,"U6 did not exit at blank");
 $display("PASS Canny ROI preview %0dx%0d: 16-line ring wraps, complete row/epoch tags, full edge pixels preserved inside ROI, green box, mid-frame bbox change deferred, matched RGB/sync and U6 exit",W,H);$finish;
end
initial begin #200000000;$fatal(1,"Canny ROI preview timeout");end
endmodule
