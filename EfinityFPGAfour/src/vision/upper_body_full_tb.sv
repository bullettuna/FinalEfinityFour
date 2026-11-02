`timescale 1ns/1ps
module upper_body_full_tb;
localparam SIZE=8160,CASES=3;
reg clk=0,rst_n=0,load=0,start=0;
reg [12:0] addr=0,result_addr=0;reg mask=0,raw=0;
wire [1:0] result,arms;wire busy,done,valid,overflow;
reg [3:0] vectors[0:SIZE*CASES-1];reg [2:0] stats[0:CASES-1];
integer checked=0,max_cycles=0,cycles;
always #5 clk=~clk;
upper_body_constraint dut(
 .clk(clk),.rst_n(rst_n),.cancel(1'b0),.load_en(load),.load_addr(addr),.load_mask(mask),.load_skeleton(raw),
 .start(start),.result_addr(result_addr),.result_class(result),.busy(busy),.done(done),.body_valid(valid),.arm_flags(arms),.overflow(overflow));
initial begin
 $readmemh("body_full.mem",vectors);$readmemh("body_full_stats.mem",stats);
 repeat(5)@(negedge clk);rst_n=1;
 for(integer c=0;c<CASES;c++)begin
  for(integer i=0;i<SIZE;i++)begin
   load=1;addr=i;mask=vectors[c*SIZE+i][0];raw=vectors[c*SIZE+i][1];@(negedge clk);
  end
  load=0;start=1;@(negedge clk);start=0;cycles=0;
  while(!done&&cycles<2000000)begin @(negedge clk);cycles++;end
  if(!done||busy||overflow||{arms,valid}!==stats[c])$fatal(1,"full-grid body status case=%0d got=%h expected=%h",c,{arms,valid},stats[c]);
  if(cycles>max_cycles)max_cycles=cycles;
  for(integer i=0;i<SIZE;i++)begin
   result_addr=i;repeat(2)@(negedge clk);
   if(result!==vectors[c*SIZE+i][3:2])$fatal(1,"full-grid body class case=%0d pixel=%0d",c,i);
   checked++;
  end
 end
 $display("PASS 120x68 upper-body: %0d classified pixels, max %0d clocks, translation and single-arm recovery",checked,max_cycles);$finish;
end
initial begin #100000000;$fatal(1,"full-grid body timeout");end
endmodule
