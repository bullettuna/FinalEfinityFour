`timescale 1ns/1ps
module person_pose_pipeline_tb #(parameter SHADOW_SCENE=0,WHITE_SCENE=0);
localparam W=256,H=256,HT=320;
reg clk=0,rst_n=0,vs=0,de=0,edge_pixel=1,config_changed=0,white_req=WHITE_SCENE;
reg raw_ready=!WHITE_SCENE,raw_fault=WHITE_SCENE;
always #5 clk=~clk;
reg [7:0] raw=40;reg [1:0] vectors[0:4096*23-1];
wire tick,error,ov,oe;wire [2:0] pose;wire [9:0] score;
wire [23:0] rgb;
integer recognized=0,rejected=0,unknown_ticks=0,unknown_before=0,dx=0,dy=-1,checked=0;reg de_d=0;
person_roi_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.POSE_MATCH(1),.RAW_REFINE(WHITE_SCENE),.LIGHTING_AVAILABLE(1),.WHITE_AVAILABLE(WHITE_SCENE)) dut(
 .clk(clk),.rst_n(rst_n),.background_valid(raw_ready),.sample_valid(de&&raw_ready),.stream_fault(raw_fault),
 .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.current_raw(raw),.background_raw(SHADOW_SCENE?8'd200:8'd40),
 .threshold_req(8'd24),.noise_req(2'd0),.view_req(3'd1),.edge_source_req(1'b0),
 .lighting_req(1'b1),
 .white_req(white_req),
 .edge_vsync(1'b0),.edge_hsync(1'b0),.edge_href(1'b0),.edge_foreground(1'b0),.edge_pixel(1'b0),.edge_reference_valid(1'b0),.edge_stream_fault(1'b0),
 .canny_vsync(vs),.canny_href(de),.canny_pixel(edge_pixel),.pose_config_changed(config_changed),
 .pose_tick(tick),.pose_id(pose),.pose_similarity(score),.processing_error(error),
 .out_vsync(ov),.out_href(oe),.out_rgb(rgb));
always @(posedge clk)begin
 #1;
 if(tick)begin
  if(pose==0)unknown_ticks++;
  if(edge_pixel&&pose==4)recognized++;
  if(!edge_pixel&&pose==0&&score>=550)rejected++;
 end
 if(rst_n&&error)$fatal(1,"end-to-end pipeline error");
 if(!ov)dy=-1;
 if(oe)begin
  if(!de_d)begin dx=0;dy++;end
  if(!WHITE_SCENE||dut.valid_source)begin
   if(rgb!==(vectors[3*4096+(dy/4)*64+dx/4][0]?24'hffffff:24'd0))$fatal(1,"U1 display moved after adding matcher x=%0d y=%0d rgb=%h",dx,dy,rgb);
   checked++;
  end else if(rgb!==24'd0)$fatal(1,"white mode displayed foreground before its frame reference was ready");
  dx++;
 end
 de_d=oe;
end
task frame;
 bit body,cast_shadow;
 begin
 @(negedge clk);vs=0;de=0;repeat(5*HT)@(negedge clk);vs=1;repeat(36*HT)@(negedge clk);
 for(integer y=0;y<H;y++)begin
  for(integer x=0;x<W;x++)begin
   body=vectors[3*4096+(y/4)*64+x/4][0];
   cast_shadow=x/4>=8&&vectors[3*4096+(y/4)*64+x/4-8][0];
   de=1;raw=SHADOW_SCENE?(body?60:cast_shadow?150:200):(body?200:40);@(negedge clk);
  end
  de=0;repeat(HT-W)@(negedge clk);
 end
 repeat(4*HT)@(negedge clk);
 end
endtask
initial begin
 $readmemh("vectors.mem",vectors);
 repeat(5)@(negedge clk);rst_n=1;
 repeat(WHITE_SCENE?7:6)frame();
 if(recognized<1||checked<5*W*H)$fatal(1,"RAW/line-ring/matcher chain did not recognize pose 4");
 edge_pixel=0;config_changed=1;@(negedge clk);config_changed=0;
 repeat(6)frame();
 if(rejected<1)$fatal(1,"end-to-end missing Canny not rejected");
 if(WHITE_SCENE)begin
  white_req=0;repeat(2)frame();
  if(dut.white_active||dut.candidate_valid||pose!=0)$fatal(1,"leaving white mode retained stale recognition without RAW background");
  white_req=1;edge_pixel=1;recognized=0;repeat(6)frame();
  if(recognized<1)$fatal(1,"white mode did not reacquire after switching");
  unknown_before=unknown_ticks;raw_ready=1;raw_fault=0;white_req=0;repeat(2)frame();
  if(unknown_ticks<=unknown_before)$fatal(1,"switch to an already ready RAW model did not invalidate UART pose confirmation");
 end
 $display("PASS end-to-end RAW difference/morphology/Canny line alignment/snapshot/pose, pixel-exact U1, config invalidation, adjacent-shadow=%0d white-no-background=%0d",SHADOW_SCENE,WHITE_SCENE);$finish;
end
initial begin #40000000;$fatal(1,"pose pipeline timeout");end
endmodule
