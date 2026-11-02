`timescale 1ns/1ps
module skeleton_video_pipeline_tb;
localparam W=64,H=63,GW=32,GH=32,SIZE=1024;
reg clk=0,rst_n=0,source=0,vs=0,hs=0,de=0,pixel=0;
reg [23:0] rgb=0;reg [2:0] view=4;
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
integer published=0,checks=0;
reg old_bank=0;
always @(posedge clk)begin
 #1;
 if(rst_n)begin
  if(dut.front_bank!=old_bank&&vs)$fatal(1,"display swapped in active frame");
  if(tick&&valid)published++;
  old_bank=dut.front_bank;
 end
end
task frame(input bit check_display);
 reg expected_de;reg [23:0] expected_rgb;
 begin
  vs=1;expected_de=0;expected_rgb=0;
  for(integer y=0;y<H;y++)begin
   for(integer x=0;x<W;x++)begin
    de=1;pixel=vectors[3*SIZE+(y/2)*GW+x/2][0];rgb=pixel?24'hffffff:0;
    @(negedge clk);
    if(check_display)begin
     if(oe!==expected_de)$fatal(1,"video DE delay");
     if(expected_de&&out!==expected_rgb)$fatal(1,"video pixel mismatch y/x=%0d/%0d got=%h expected=%h",y,x,out,expected_rgb);
     checks++;
    end
    expected_de=1;
    if(view==6)case(body_vectors[3*SIZE+(y/2)*GW+x/2])
     1:expected_rgb=24'h20ff20;2:expected_rgb=24'h20ffff;3:expected_rgb=24'hff20ff;
     default:expected_rgb=vectors[3*SIZE+(y/2)*GW+x/2][0]?24'h505050:0;
    endcase
    else expected_rgb=vectors[3*SIZE+(y/2)*GW+x/2][1]?24'hffffff:0;
   end
   de=0;pixel=0;rgb=0;@(negedge clk);
   if(check_display&&out!==expected_rgb)$fatal(1,"last pixel");
   expected_de=0;expected_rgb=0;repeat(3)@(negedge clk);
  end
  de=0;vs=0;repeat(12)@(negedge clk);
 end
endtask
initial begin
 $readmemh("body_video.mem",body_vectors);$readmemh("body_video_stats.mem",body_stats);
 $readmemh("vectors.mem",vectors);$readmemh("vectors_stats.mem",stats);
 repeat(5)@(negedge clk);rst_n=1;source=1;repeat(8)@(negedge clk);
 for(integer n=0;n<300&&published==0;n++)frame(0);
 if(published==0||!valid||!conv)$fatal(1,"no completed skeleton snapshot");
 if({pruned,branches,ends,pixels,conv,iterations}!==stats[3][72:0])$fatal(1,"pooled snapshot statistics mismatch");
 // 63 rows exercise a partial final block row, with preserved square aspect.
 for(integer i=0;i<SIZE;i++)begin
  if((dut.front_bank?dut.display1[i]:dut.display0[i])!=={vectors[3*SIZE+i][1],vectors[3*SIZE+i][0]})$fatal(1,"published bank pixel %0d",i);
 end
 if({arms,body_valid}!==body_stats[3])$fatal(1,"body snapshot metadata");
 for(integer i=0;i<SIZE;i++)begin
  if((dut.front_bank?dut.classes1[i]:dut.classes0[i])!==body_vectors[3*SIZE+i])$fatal(1,"body bank pixel %0d",i);
 end
 frame(1);view=6;repeat(12)@(negedge clk);frame(1);
 source=0;repeat(3)@(negedge clk);
 if(valid||dut.front_valid||busy||body_valid||arms!=0)$fatal(1,"source invalidation retained stale skeleton");
 // An incomplete input frame cannot publish partially captured RAM.
 source=1;vs=1;de=1;repeat(40)@(negedge clk);de=0;vs=0;repeat(10)@(negedge clk);
 if(busy||dut.front_valid)$fatal(1,"partial capture not discarded");
 $display("PASS skeleton video: complete pooling, partial last row, %0d displayed pixels, atomic bank swap, loss and partial-frame cancel",checks);$finish;
end
initial begin #30000000;$fatal(1,"video timeout");end
endmodule
