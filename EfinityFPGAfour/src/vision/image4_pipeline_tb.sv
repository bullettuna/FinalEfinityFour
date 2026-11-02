`timescale 1ns/1ps
// End-to-end test uses RAW samples (including gray cast shadow) and no DDR
// background, Canny edge stream or pose ROM. The torso touches frame bottom.
module image4_pipeline_tb;
localparam W=256,H=256,HT=320;
reg clk=0,rst_n=0,vs=0,de=0;reg [7:0] raw=200;reg [2:0] view=1;
always #5 clk=~clk;
wire mv,mh,me,selected,white,ready,candidate,error;wire [23:0] rgb;
wire [2:0] active_view;wire tick,valid,conv;wire [7:0] iterations;
wire [15:0] pixels,ends,branches,pruned;
image4_person_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.RAW_REFINE(1),.POSE_MATCH(0),.LIGHTING_AVAILABLE(1),.WHITE_AVAILABLE(1)) segmentation(
 .clk(clk),.rst_n(rst_n),.background_valid(1'b0),.sample_valid(1'b0),.stream_fault(1'b1),
 .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.current_raw(raw),.background_raw(8'd0),
 .threshold_req(8'd24),.noise_req(2'd2),.view_req(view),.lighting_req(1'b1),.white_req(1'b1),
 .white_active(white),.white_ready(ready),.edge_source_req(1'b0),.edge_vsync(1'b0),.edge_hsync(1'b0),.edge_href(1'b0),
 .edge_foreground(1'b0),.edge_pixel(1'b0),.edge_reference_valid(1'b0),.edge_stream_fault(1'b0),
 .canny_vsync(1'b0),.canny_href(1'b0),.canny_pixel(1'b0),.pose_config_changed(1'b0),
 .out_vsync(mv),.out_hsync(mh),.out_href(me),.out_rgb(rgb),.selected_pixel(selected),.active_view(active_view),
 .candidate_valid(candidate),.processing_error(error));
skeleton_video_pipeline #(.WIDTH(W),.HEIGHT(H),.STEP_LOG2(3),.MAX_ITER(32)) skeleton(
 .clk(clk),.rst_n(rst_n),.source_valid(candidate&&ready&&!error),.selected_pixel(selected),
 .in_vsync(mv),.in_hsync(mh),.in_href(me),.reference_rgb(rgb),.view(active_view),
 .sample_tick(tick),.sample_valid(valid),.sample_converged(conv),.sample_iterations(iterations),
 .sample_pixels(pixels),.sample_endpoints(ends),.sample_branches(branches),.sample_pruned(pruned));
integer completed=0,seen_body=0,seen_shadow=0,dx=0,dy=-1,baseline_pixels=0;reg de_old=0;
always @(posedge clk)begin
 #1;
 if(rst_n&&error)$fatal(1,"white/selector processing error");
 if(tick&&valid)begin
  completed++;
  if(!conv||pixels<10||ends<2)$fatal(1,"silhouette did not produce a converged branching skeleton");
  if(view==1)baseline_pixels=pixels;
  else if(baseline_pixels!=0&&pixels!=baseline_pixels)$fatal(1,"view selection changed captured skeleton");
 end
 if(!mv)dy=-1;
 if(me)begin
  if(!de_old)begin dx=0;dy++;end
  if(candidate)begin
   if(dx==128&&dy==176&&selected)seen_body++;
   if(dx==208&&dy==176&&selected)seen_shadow++;
  end
  dx++;
 end
 de_old=me;
end
task frame;
 bit body,shadow;
 begin
  vs=0;de=0;repeat(5*HT)@(negedge clk);vs=1;repeat(36*HT)@(negedge clk);
  for(integer y=0;y<H;y++)begin
   for(integer x=0;x<W;x++)begin
    body=(x>=48&&x<208&&y>=56&&y<96)||(x>=96&&x<160&&y>=80);
    shadow=x>=160&&x<232&&y>=96;
    raw=body?60:shadow?150:200;de=1;@(negedge clk);
   end
   de=0;repeat(HT-W)@(negedge clk);
  end
  repeat(4*HT)@(negedge clk);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 for(integer n=0;n<80&&completed<2;n++)frame();
 if(completed<2||seen_body<1||seen_shadow!=0||!white||!ready)$fatal(1,"white segmentation/skeleton chain failed done=%0d body=%0d shadow=%0d",completed,seen_body,seen_shadow);
 completed=0;view=4;
 for(integer n=0;n<80&&completed<2;n++)frame();
 if(completed<2)$fatal(1,"view 4 stopped analysis");
 $display("PASS image4 RAW white/shadow -> refined selected silhouette -> skeleton, truncated torso and view-independent capture");$finish;
end
initial begin #100000000;$fatal(1,"integration timeout");end
endmodule
