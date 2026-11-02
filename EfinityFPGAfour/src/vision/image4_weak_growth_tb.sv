`timescale 1ns/1ps
// A/B test of N24 -> N60: a colored difference-55 patch touches a strong
// silhouette. N60 removes the patch from U2; only old weak growth restores it.
module image4_weak_growth_tb;
localparam W=256,H=256,HT=320;
reg clk=0,rst_n=0,vs=0,de=0;reg [7:0] raw=200,threshold=24;
always #5 clk=~clk;
wire [1:0] mv,me,candidate,error,selected;
wire [23:0] rgb[0:1];
wire [1:0] ready;
for(genvar g=0;g<2;g++)begin:ab
 image4_person_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.RAW_REFINE(1),.POSE_MATCH(0),
  .LIGHTING_AVAILABLE(1),.WHITE_AVAILABLE(1),.WEAK_GROWTH(g)) dut(
  .clk(clk),.rst_n(rst_n),.background_valid(1'b0),.sample_valid(1'b0),.stream_fault(1'b1),
  .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.current_raw(raw),.background_raw(8'd0),
  .threshold_req(threshold),.noise_req(2'd2),.view_req(3'd2),.lighting_req(1'b1),.white_req(1'b1),.white_ready(ready[g]),
  .edge_source_req(1'b0),.edge_vsync(1'b0),.edge_hsync(1'b0),.edge_href(1'b0),
  .edge_foreground(1'b0),.edge_pixel(1'b0),.edge_reference_valid(1'b0),.edge_stream_fault(1'b0),
  .canny_vsync(1'b0),.canny_href(1'b0),.canny_pixel(1'b0),.pose_config_changed(1'b0),
  .out_vsync(mv[g]),.out_href(me[g]),.out_rgb(rgb[g]),.selected_pixel(selected[g]),.candidate_valid(candidate[g]),.processing_error(error[g]));
end
integer dx=0,dy=-1,phase=0,checked24=0,checked60=0;reg de_old=0,verify=0;
integer initial_done0=0,initial_done1=0;
always @(posedge clk)begin
 #1;
 if(rst_n&&(error!=0||mv[0]!==mv[1]||me[0]!==me[1]))$fatal(1,"A/B segmentation timing/error");
 if(!mv[0])dy=-1;
 if(me[0])begin
  if(!de_old)begin dx=0;dy++;end
  if(verify&&dx==176&&dy==176)begin
   if(candidate!=3||ready!=3)$fatal(1,"A/B foreground not ready");
   if(phase==0)begin
    if(rgb[0]!==24'hffffff||rgb[1]!==24'hffffff||selected!==2'b11)$fatal(1,"N24 did not include difference-55 patch");
    checked24++;
   end else begin
    if(rgb[0]!==0||rgb[1]!==0)$fatal(1,"N60 U2 still included difference-55 patch");
    if(selected!==2'b10)$fatal(1,"N60 A/B patch: no-weak=%b weak=%b",selected[0],selected[1]);
    checked60++;
   end
  end
  if(verify&&dx==128&&dy==176&&selected!==2'b11)$fatal(1,"disabling weak growth removed strong torso");
  dx++;
 end
 de_old=me[0];
end
task frame;
 bit body,patch;
 begin
  vs=0;de=0;repeat(5*HT)@(negedge clk);vs=1;repeat(36*HT)@(negedge clk);
  for(integer y=0;y<H;y++)begin
   for(integer x=0;x<W;x++)begin
    body=(x>=48&&x<208&&y>=56&&y<96)||(x>=96&&x<160&&y>=80);
    patch=x>=160&&x<192&&y>=112&&y<224;
    raw=body?60:patch&&x%2==0&&y%2==0?145:200;
    de=1;@(negedge clk);
   end
   de=0;repeat(HT-W)@(negedge clk);
  end
  repeat(4*HT)@(negedge clk);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 for(integer n=0;n<40&&(ab[0].dut.u_person_snapshot_selector.completed_snapshots<2||ab[1].dut.u_person_snapshot_selector.completed_snapshots<2);n++)frame();
 verify=1;repeat(2)frame();verify=0;
 initial_done0=ab[0].dut.u_person_snapshot_selector.completed_snapshots;
 initial_done1=ab[1].dut.u_person_snapshot_selector.completed_snapshots;
 threshold=60;phase=1;
 for(integer n=0;n<40&&(ab[0].dut.u_person_snapshot_selector.completed_snapshots<initial_done0+2||ab[1].dut.u_person_snapshot_selector.completed_snapshots<initial_done1+2);n++)frame();
 verify=1;repeat(3)frame();
 if(checked24<1||checked60<1)$fatal(1,"A/B coverage incomplete");
 $display("PASS N24->N60 A/B: both U2 reject difference-55 patch at N60; old weak U3 restores it, new strong-only U3 excludes it; strong torso and video timing retained");$finish;
end
initial begin #100000000;$fatal(1,"A/B threshold timeout");end
endmodule
