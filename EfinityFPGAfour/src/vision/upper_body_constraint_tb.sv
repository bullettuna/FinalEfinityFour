`timescale 1ns/1ps
module upper_body_constraint_tb;
localparam SIZE=1024,CASES=15;
reg clk=0,rst_n=0,cancel=0,load=0,start=0;
reg [9:0] addr=0,result_addr=0;reg mask=0,raw=0;
wire [1:0] result,arms;wire busy,done,valid,overflow;
reg [3:0] vectors[0:SIZE*CASES-1],stats[0:CASES-1];
integer checked=0,max_cycles=0;
always #5 clk=~clk;
upper_body_constraint #(.WIDTH(32),.HEIGHT(32),.MAX_ENDPOINTS(8)) dut(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.load_en(load),.load_addr(addr),.load_mask(mask),.load_skeleton(raw),
 .start(start),.result_addr(result_addr),.result_class(result),.busy(busy),.done(done),.body_valid(valid),.arm_flags(arms),.overflow(overflow));
task run_case(input integer c,input bit check_result);
 integer cycles;
 begin
  for(integer i=0;i<SIZE;i++)begin
   load=1;addr=i;mask=vectors[c*SIZE+i][0];raw=vectors[c*SIZE+i][1];@(negedge clk);
  end
  load=0;start=1;@(negedge clk);start=0;cycles=0;
  while(!done&&cycles<300000)begin @(negedge clk);cycles++;end
  if(!done||busy)$fatal(1,"body timeout case=%0d state=%0d",c,dut.state);
  if(cycles>max_cycles)max_cycles=cycles;
  if(check_result)begin
   if({overflow,arms,valid}!==stats[c])$fatal(1,"body status case=%0d got=%h expected=%h",c,{overflow,arms,valid},stats[c]);
   for(integer i=0;i<SIZE;i++)begin
    result_addr=i;repeat(2)@(negedge clk);
    if(result!==vectors[c*SIZE+i][3:2])$fatal(1,"body class case=%0d pixel=%0d got=%d expected=%d",c,i,result,vectors[c*SIZE+i][3:2]);
    if(result!=0&&vectors[c*SIZE+i][1:0]!=3)$fatal(1,"invented bone outside mask/raw");
    checked++;
   end
  end
 end
endtask
initial begin
 $readmemh("body.mem",vectors);$readmemh("body_stats.mem",stats);
 repeat(5)@(negedge clk);rst_n=1;
 for(integer c=0;c<CASES;c++)run_case(c,1);
 // Cancel during graph traversal; a subsequent fresh job must recover.
 fork
  run_case(0,0);
  begin wait(dut.state==15);@(negedge clk);cancel=1;@(negedge clk);cancel=0;end
 join_any
 disable fork;
 if(busy||valid||arms!=0)$fatal(1,"body cancellation retained model");
 // Empty job resets the temporal prior before the repeat oracle.
 run_case(9,1);run_case(0,1);
 $display("PASS upper-body: %0d classified pixels, max %0d clocks, geometric rejection, overflow, temporal updates and cancel/recovery",checked,max_cycles);$finish;
end
initial begin #100000000;$fatal(1,"body test timeout");end
endmodule
