`timescale 1ns/1ps
// Independent display scoreboard under moving inputs, view changes and aborts.
module skeleton_video_motion_tb;
localparam W=64,H=64,SIZE=1024;
reg clk=0,rst_n=0,source=0,vs=0,hs=0,de=0,pixel=0;
reg [23:0] rgb=0;reg [2:0] view=5;
integer input_case=3,input_x=0,input_y=0,frame_number=0;
wire ov,oh,oe,active,tick,valid,conv,busy,body_valid;wire [1:0] arms;wire [23:0] out;
wire [7:0] iterations;wire [15:0] pixels,ends,branches,pruned;
reg [1:0] body_vectors[0:8191];reg [2:0] body_stats[0:7];
reg [1:0] vectors[0:8191];reg [79:0] stats[0:7];
skeleton_video_pipeline #(.WIDTH(W),.HEIGHT(H),.STEP_LOG2(1),.MAX_ITER(32)) dut(
 .clk(clk),.rst_n(rst_n),.source_valid(source),.selected_pixel(pixel),.in_vsync(vs),.in_hsync(hs),.in_href(de),.reference_rgb(rgb),.view(view),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_rgb(out),.display_active(active),
 .sample_tick(tick),.sample_valid(valid),.sample_converged(conv),.sample_iterations(iterations),
 .sample_pixels(pixels),.sample_endpoints(ends),.sample_branches(branches),.sample_pruned(pruned),.busy(busy),.sample_body_valid(body_valid),.sample_arm_flags(arms));
always #5 clk=~clk;
integer captured_case=0,front_case=0,published=0,checked=0,views_seen=0,loss_ticks=0;
integer model_view=0,dump_state=0,dump_file;
reg model_valid=0,old_bank=0;
reg expected_v=0,expected_h=0,expected_de=0,previous_front_valid=0;
reg [23:0] expected_rgb=0,next_rgb;
integer previous_x=0,previous_y=0,previous_view=0,ref_addr;
always @(posedge clk)begin
 if(!rst_n)begin
  model_valid=0;model_view=0;expected_v=0;expected_h=0;expected_de=0;expected_rgb=0;
 end else begin
  next_rgb=0;
  if(de)begin
   ref_addr=front_case*SIZE+(input_y/2)*32+input_x/2;
   case(model_view)
    1,2:next_rgb=rgb;
    3:next_rgb=model_valid&&source&&vectors[ref_addr][0]?24'hffffff:0;
    4:next_rgb=model_valid&&source&&vectors[ref_addr][1]?24'hffffff:0;
    5:next_rgb=!(model_valid&&source)?0:vectors[ref_addr][1]?24'hff2020:vectors[ref_addr][0]?24'h505050:0;
    6:next_rgb=!(model_valid&&source)?0:!body_stats[front_case][0]?(vectors[ref_addr][0]?24'h505050:0):
      body_vectors[ref_addr]==1?24'h20ff20:body_vectors[ref_addr]==2?24'h20ffff:body_vectors[ref_addr]==3?24'hff20ff:vectors[ref_addr][0]?24'h505050:0;
   endcase
  end
  // A single snapshot is selected when the full input frame starts.
  if(source&&dut.state==0&&dut.first)captured_case=input_case;
  if(!source)model_valid=0;
  else if(dut.state==7&&!vs)begin front_case=captured_case;model_valid=1;end
  if(!vs)model_view=view;
  #1;
  if({ov,oh,oe}!=={expected_v,expected_h,expected_de})$fatal(1,"VS/HS/DE latency mismatch");
  if(expected_de&&out!==expected_rgb)$fatal(1,"moving view %0d pixel %0d/%0d got=%h expected=%h",previous_view,previous_x,previous_y,out,expected_rgb);
  if(expected_de)begin
   checked++;views_seen=views_seen|(1<<previous_view);
   if(dump_state==0&&previous_view==5&&previous_front_valid&&previous_x==0&&previous_y==0)dump_state=1;
   if(dump_state==1)begin
    $fdisplay(dump_file,"%06x",out);
    if(previous_x==W-1&&previous_y==H-1)dump_state=2;
   end
  end
  if(dut.front_bank!=old_bank&&vs)$fatal(1,"moving frame swapped while active");
  old_bank=dut.front_bank;
  if(tick)begin
   if(valid)begin
    published++;
    if({arms,body_valid}!==body_stats[front_case])$fatal(1,"body metadata not frame atomic");
    if({pruned,branches,ends,pixels,conv,iterations}!==stats[front_case][72:0])$fatal(1,"moving snapshot statistics mismatch");
   end else loss_ticks++;
  end
  expected_v=vs;expected_h=hs;expected_de=de;expected_rgb=next_rgb;
  previous_x=input_x;previous_y=input_y;previous_view=dut.view_d;previous_front_valid=model_valid&&source;
 end
end
task frame;
 begin
  input_case=published%2?2:3;
  vs=0;de=0;hs=0;repeat(12)@(negedge clk);
  vs=1;repeat(5)@(negedge clk);
  for(integer y=0;y<H;y++)begin
   input_y=y;
   for(integer x=0;x<W;x++)begin
    input_x=x;de=1;hs=1;pixel=vectors[input_case*SIZE+(y/2)*32+x/2][0];rgb=pixel?24'hffffff:0;
    if(x==21&&y==20)view=1+frame_number%6;
    @(negedge clk);
   end
   de=0;hs=0;repeat(16)@(negedge clk);
  end
  vs=0;de=0;repeat(12)@(negedge clk);frame_number++;
 end
endtask
task abort_at(input integer target_state);
 bit aborted;
 begin
  aborted=0;
  fork
   begin wait(dut.state==target_state);@(negedge clk);source=0;repeat(4)@(negedge clk);aborted=1;end
   begin while(!aborted)frame();end
  join
  if(valid||dut.front_valid||busy)$fatal(1,"abort at state %0d retained result/job",target_state);
  source=1;
 end
endtask
initial begin
 $readmemh("body_video.mem",body_vectors);$readmemh("body_video_stats.mem",body_stats);
 $readmemh("vectors.mem",vectors);$readmemh("vectors_stats.mem",stats);
 dump_file=$fopen("motion_overlay.hex","w");
 repeat(5)@(negedge clk);rst_n=1;source=1;
 for(integer n=0;n<350&&(published<3||dump_state!=2||views_seen!=126);n++)frame();
 if(published<3||views_seen!=126||dump_state!=2)$fatal(1,"moving coverage incomplete published=%0d views=%0d",published,views_seen);
 abort_at(3);abort_at(6);abort_at(9);abort_at(12);
 for(integer n=0;n<150&&!valid;n++)frame();
 if(!valid||loss_ticks<4)$fatal(1,"no recovery after aborts");
 $fclose(dump_file);
 $display("PASS motion: %0d pixels and all six views, moving snapshots, VS/HS/DE alignment, frame-atomic display, analyze/copy abort and recovery",checked);$finish;
end
initial begin #60000000;$fatal(1,"motion timeout");end
endmodule
