`timescale 1ns/1ps
module person_pose_snapshot_tb;
localparam W=80,H=80,FW=W*4,FH=H*4;
reg clk=0,rst_n=0,vs=0,de=0,pixel=0,edge_pixel=1,edge_valid=1,invalidate=0;
always #5 clk=~clk;
reg [1:0] vectors[0:4096*23-1];
reg [31:0] snapshot_expected[0:5*7-1];
wire tick,busy,error;wire [2:0] pose;wire [9:0] score,gap,edge_score;
integer results=0;reg [2:0] last_pose;reg [9:0] last_score;
person_snapshot_selector #(.WIDTH(W),.HEIGHT(H),.MIN_AREA(8),.MIN_WIDTH(2),.MIN_HEIGHT(2),
 .QUEUE_BITS(10),.POSE_MATCH(1)) dut(
 .clk(clk),.rst_n(rst_n),.source_valid(1'b1),.invalidate(invalidate),.in_vsync(vs),.in_hsync(1'b0),.in_href(de),
 .in_mask(pixel),.in_weak_mask(pixel),.in_canny(edge_pixel),.in_canny_valid(edge_valid),
 .busy(busy),.processing_error(error),.pose_tick(tick),.pose_id(pose),.pose_similarity(score),.pose_margin(gap),.pose_edge_support(edge_score));
always @(posedge clk)if(tick)begin results<=results+1;last_pose<=pose;last_score<=score;end
function automatic bit foreground(input integer x,y,p);
 if(x/4>=5&&x/4<69&&y/4>=7&&y/4<71)foreground=vectors[p*4096+(y/4-7)*64+x/4-5][0];
 else foreground=0;
endfunction
task frame(input integer p,e,ev);
 begin
 @(negedge clk);vs=0;de=0;repeat(8)@(negedge clk);vs=1;repeat(8)@(negedge clk);
 for(integer y=0;y<FH;y++)begin
  for(integer x=0;x<FW;x++)begin @(negedge clk);de=1;pixel=foreground(x,y,p);edge_pixel=e!=0;edge_valid=ev!=0;end
  @(negedge clk);de=0;repeat(8)@(negedge clk);
 end
 @(negedge clk);vs=0;de=0;
 end
endtask
task result_wait;
 integer n;
 begin n=0;while(!dut.pending&&n<400000)begin @(negedge clk);n++;end
 repeat(3)@(negedge clk);
 if(!dut.pending||error)$fatal(1,"snapshot failed state=%0d error=%b",dut.state,error);
 end
endtask
initial begin
 $readmemh("vectors.mem",vectors);
 $readmemh("snapshot_expected.mem",snapshot_expected);
 repeat(5)@(negedge clk);rst_n=1;
 frame(3,1,1);
 // Change the live input during offline analysis. It must not alter either
 // member of the frozen mask/edge pair that belongs to pose 4.
 frame(0,0,1);result_wait();
 if(last_pose!=snapshot_expected[3*7]||last_score!=snapshot_expected[3*7+1]||
    dut.tight_x_min!=5+snapshot_expected[3*7+3]||dut.tight_y_min!=7+snapshot_expected[3*7+4]||
    dut.tight_x_max!=5+snapshot_expected[3*7+5]||dut.tight_y_max!=7+snapshot_expected[3*7+6])
  $fatal(1,"mixed snapshot or padded crop pose=%0d score=%0d bounds=%0d,%0d..%0d,%0d",last_pose,last_score,dut.tight_x_min,dut.tight_y_min,dut.tight_x_max,dut.tight_y_max);
 frame(0,1,1); // publish previous bank, next frame can capture again
 frame(1,0,1);result_wait();
 if(last_pose!=0||last_score!=snapshot_expected[1*7+1])$fatal(1,"missing Canny edges pose=%0d score=%0d expected_score=%0d",last_pose,last_score,snapshot_expected[1*7+1]);
 frame(0,1,1);frame(1,1,0);result_wait();
 if(last_pose!=0)$fatal(1,"invalid Canny epoch accepted");
 @(negedge clk);invalidate=1;@(negedge clk);invalidate=0;repeat(3)@(negedge clk);
 if(pose!=0||dut.pending||busy)$fatal(1,"invalidation retained stale match");
 $display("PASS selector/matcher integration: tight crop, frozen same-frame edge pair, live changes, missing edges/epoch rejection, invalidation");$finish;
end
initial begin #25000000;$fatal(1,"snapshot pose timeout");end
endmodule
