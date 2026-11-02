`timescale 1ns/1ps
module person_snapshot_1080p_tb #(parameter REFINE=0);
reg clk=0,rst_n=0,vs=0,hs=0,de=0,mask=0;
always #5 clk=~clk;
wire ov,oh,oe,om,oc,bv,busy,err;wire [31:0] completed;
wire [11:0] xmin,xmax;wire [10:0] ymin,ymax;
person_snapshot_selector #(.REFINE(REFINE)) dut(.clk(clk),.rst_n(rst_n),.source_valid(1'b1),.invalidate(1'b0),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_mask(mask),.in_weak_mask(mask),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_mask(om),.out_contour(oc),
 .bbox_valid(bv),.bbox_x_min(xmin),.bbox_x_max(xmax),.bbox_y_min(ymin),.bbox_y_max(ymax),
 .busy(busy),.processing_error(err),.completed_snapshots(completed));
integer frame=0,x=0,y=0,cycles=0,processing_start=0,max_cycles=0,valid_frames=0;
bit want_mask,want_contour,previous_valid=0;
always @(posedge clk)begin
 if(rst_n)begin
  cycles++;
  if(dut.state==2&&dut.cursor==0)processing_start=cycles;
  if(dut.state==20&&cycles-processing_start>max_cycles)max_cycles=cycles-processing_start;
 end
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(frame=0;frame<10;frame++)begin
  vs=0;de=0;repeat(5*2200)@(negedge clk);vs=1;repeat(36*2200)@(negedge clk);
  for(y=0;y<1080;y++)begin
   for(x=0;x<1920;x++)begin
    de=1;mask=frame<4&&((x>=600&&x<1200&&y>=200&&y<1000)||(x>=1800&&x<1812&&y>=80&&y<92));
    @(posedge clk);#1;
    if(oe!==1||err)$fatal(1,"HDMI stream stalled or analysis failed frame=%0d x=%0d y=%0d",frame,x,y);
    want_mask=bv&&x>=600&&x<1200&&y>=200&&y<1000;
    want_contour=want_mask&&(x<604||x>=1196||y<204||y>=996);
    if(om!==want_mask||oc!==want_contour)$fatal(1,"1080p snapshot/contour mismatch frame=%0d x=%0d y=%0d got=%b/%b expected=%b/%b",frame,x,y,om,oc,want_mask,want_contour);
    if(x==0&&y==0)begin
     if(bv)valid_frames++;
     previous_valid=bv;
    end else if(bv!=previous_valid)$fatal(1,"ROI changed inside an active frame");
    @(negedge clk);
   end
   de=0;repeat(280)@(negedge clk);
  end
  repeat(4*2200)@(negedge clk);
 end
 if(bv||valid_frames==0||completed<2)$fatal(1,"1080p detection/loss not completed valid=%b frames=%0d completed=%0d state=%0d count=%0d maxcycles=%0d",bv,valid_frames,completed,dut.state,dut.component_area,max_cycles);
 $display("PASS 1920x1080 ten exact frames: selected silhouette/contour, distractor rejection, no stalled/torn frame and loss; max analysis=%0d pixel clocks (%0.3f ms at 148.81 MHz), published snapshots=%0d",max_cycles,max_cycles/148810.0,completed);
 $finish;
end
initial begin #300000000;$fatal(1,"1080p snapshot timeout");end
endmodule
