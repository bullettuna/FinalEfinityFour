`timescale 1ns/1ps
module person_pose_matcher_tb;
reg clk=0,rst_n=0,start=0,cancel=0,candidate=1,edges_valid=1;
always #5 clk=~clk;
reg [8:0] xmin=0,xmax=63,ymin=0,ymax=63;
wire [8:0] rx,ry;wire busy,done;wire [2:0] pose;wire [9:0] score,gap,edge_score;
localparam CASES=23;
reg [1:0] vectors[0:4096*CASES-1];
reg [31:0] expected[0:CASES*9-1],counts[0:CASES*15-1];
reg mask_q,edge_q;
integer test_id=0;
// Model the same one-clock RAM read latency as selector selected/canny RAMs.
always @(posedge clk)begin
 mask_q<=vectors[test_id*4096+(ry-ymin)*64+rx-xmin][0];
 edge_q<=vectors[test_id*4096+(ry-ymin)*64+rx-xmin][1];
end
person_pose_matcher dut(.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),
 .candidate_valid(candidate),.edge_frame_valid(edges_valid),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),
 .busy(busy),.done(done),.read_x(rx),.read_y(ry),.mask_pixel(mask_q),.canny_pixel(edge_q),
 .pose_id(pose),.similarity(score),.margin(gap),.edge_support(edge_score));
task run_case(input integer n);
 integer cycles;
 begin
 test_id=n;candidate=expected[n*9+4]!=0;edges_valid=expected[n*9+5]!=0;
 xmin=expected[n*9+6];xmax=xmin+expected[n*9+7]-1;ymin=xmin;ymax=ymin+expected[n*9+8]-1;
 @(negedge clk);start=1;@(negedge clk);start=0;
 cycles=0;while(!done&&cycles<15000)begin @(negedge clk);cycles++;end
 if(!done)$fatal(1,"matcher timeout case=%0d",n);
 if(pose!==expected[n*9]||score!==expected[n*9+1]||gap!==expected[n*9+2]||edge_score!==expected[n*9+3])
  $fatal(1,"case %0d actual pose/score/gap/edge=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",n,pose,score,gap,edge_score,expected[n*9],expected[n*9+1],expected[n*9+2],expected[n*9+3]);
 for(integer p=0;p<5;p++)if(dut.intersections[p]!==counts[n*15+p*3]||dut.unions[p]!==counts[n*15+p*3+1]||dut.scores[p]!==counts[n*15+p*3+2])
  $fatal(1,"C++ per-template intersection/union/rounded score mismatch case=%0d pose=%0d",n,p+1);
 $display("MATCH case=%0d pose=%0d score=%0d gap=%0d edge=%0d",n,pose,score,gap,edge_score);
 @(negedge clk);
 end
endtask
initial begin
 $readmemh("vectors.mem",vectors);$readmemh("expected.mem",expected);$readmemh("counts.mem",counts);
 repeat(4)@(negedge clk);rst_n=1;
 for(integer n=0;n<CASES;n++)run_case(n);
 // Cancellation must abandon an in-flight result rather than publish it.
 candidate=1;edges_valid=1;@(negedge clk);start=1;@(negedge clk);start=0;
 repeat(80)@(negedge clk);cancel=1;@(negedge clk);cancel=0;
 repeat(13000)begin @(negedge clk);if(done||busy||pose!=0)$fatal(1,"cancelled result escaped");end
 $display("PASS pose IoU matches C++ oracle, unknown/tie/edge rejection, translated crop and cancellation");$finish;
end
initial begin #5000000;$fatal(1,"matcher test timeout");end
endmodule
