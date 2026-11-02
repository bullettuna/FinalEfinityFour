`timescale 1ns/1ps
module skeleton_video_fullhd_tb;
localparam W=1920,H=1080,GW=120,GH=68,SIZE=GW*GH;
reg clk=0,rst_n=0,source=0,vs=0,de=0,pixel=0;
wire tick,valid,conv,busy;wire [7:0] iterations;wire [15:0] pixels;
reg [1:0] vectors[0:SIZE-1];
always #5 clk=~clk;
skeleton_video_pipeline dut(.clk(clk),.rst_n(rst_n),.source_valid(source),.selected_pixel(pixel),
 .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.reference_rgb(24'd0),.view(3'd4),
 .sample_tick(tick),.sample_valid(valid),.sample_converged(conv),.sample_iterations(iterations),.sample_pixels(pixels),.busy(busy));
initial begin
 $readmemh("fullhd.mem",vectors);
 repeat(5)@(negedge clk);rst_n=1;source=1;repeat(8)@(negedge clk);vs=1;
 for(integer y=0;y<H;y++)begin
  for(integer x=0;x<W;x++)begin
   de=1;pixel=vectors[(y/16)*GW+x/16][0];@(negedge clk);
  end
  de=0;repeat(280)@(negedge clk);
 end
 vs=0;wait(tick);@(negedge clk);
 if(!valid||!conv||pixels==0)$fatal(1,"fullHD did not converge");
 for(integer i=0;i<SIZE;i++)begin
  if((dut.front_bank?dut.display1[i]:dut.display0[i])!=={vectors[i][1],vectors[i][0]})$fatal(1,"fullHD capture/stride/thinning mismatch at %0d",i);
 end
 $display("PASS fullHD 1920x1080 -> 120x68: all 8160 mask/skeleton cells match independent reference; last eight-row block retained");$finish;
end
initial begin #100000000;$fatal(1,"fullHD bounded-completion timeout");end
endmodule
