`timescale 1ns/1ps
module skeleton_thinner_tb #(parameter LIMITED=0);
localparam W=32,H=32,SIZE=W*H,CASES=8;
reg clk=0,rst_n=0,cancel=0,load=0,pixel=0,start=0;
always #5 clk=~clk;
reg [9:0] addr=0,read_addr=0;
wire result,busy,done,converged;wire [7:0] iterations;wire [15:0] pixels,ends,branches,pruned;
reg [1:0] vectors[0:SIZE*CASES-1];reg [79:0] stats[0:CASES-1];
skeleton_thinner #(.WIDTH(W),.HEIGHT(H),.MAX_ITER(LIMITED?1:32)) dut(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.load_en(load),.load_addr(addr),.load_pixel(pixel),.start(start),
 .result_addr(read_addr),.result_pixel(result),.busy(busy),.done(done),.converged(converged),
 .iterations(iterations),.pixels(pixels),.endpoints(ends),.branches(branches),.pruned(pruned));
integer checked=0,cycles;
initial begin
 if(LIMITED)begin $readmemh("limited.mem",vectors);$readmemh("limited_stats.mem",stats);end
 else begin $readmemh("vectors.mem",vectors);$readmemh("vectors_stats.mem",stats);end
 repeat(5)@(negedge clk);rst_n=1;
 for(integer c=0;c<CASES;c++)begin
  for(integer i=0;i<SIZE;i++)begin load=1;addr=i;pixel=vectors[c*SIZE+i][0];@(negedge clk);end
  load=0;start=1;@(negedge clk);start=0;cycles=0;
  while(!done&&cycles<2000000)begin @(negedge clk);cycles++;end
  if(!done||busy)$fatal(1,"skeleton failed bounded completion case=%0d",c);
  if({pruned,branches,ends,pixels,converged,iterations}!==stats[c][72:0])
   $fatal(1,"skeleton stats case=%0d got=%h expected=%h",c,{pruned,branches,ends,pixels,converged,iterations},stats[c][72:0]);
  for(integer i=0;i<SIZE;i++)begin
   read_addr=i;repeat(2)@(negedge clk);
   if(result!==vectors[c*SIZE+i][1])$fatal(1,"skeleton pixel case=%0d x/y=%0d/%0d got=%b",c,i%W,i/W,result);
   checked++;
  end
 end
 start=1;@(negedge clk);start=0;repeat(50)@(negedge clk);cancel=1;@(negedge clk);cancel=0;
 if(busy||done)$fatal(1,"cancel failed");
 $display("PASS skeleton reference: %0d pixels, eight shapes, thin/prune/topology stats, cancel and limited=%0d",checked,LIMITED);$finish;
end
initial begin #250000000;$fatal(1,"skeleton timeout");end
endmodule
