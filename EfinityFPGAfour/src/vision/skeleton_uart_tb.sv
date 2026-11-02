`timescale 1ns/1ps
module skeleton_uart_tb #(parameter BODY_MODE=0);
localparam LENGTH=BODY_MODE?58:45,INTERVAL=4000;
reg clk=0,pclk=0,rst_n=0,prst_n=0,tick=0,valid=0,query=0,enabled=0,accept=0,done=0;
reg model_valid=0;reg [1:0] model_arms=0;
reg [7:0] iteration=8'h12;reg [15:0] pixels=16'h1234,ends=16'h0002,branches=16'h0001,pruned=16'h0003;
wire tv,last;wire [7:0] data;
always #5 clk=~clk;
always #7 pclk=~pclk;
skeleton_uart #(.CLOCK_HZ(2000),.REPORT_SECONDS(2),.BODY_AVAILABLE(BODY_MODE)) dut(
 .clk(clk),.rst_n(rst_n),.pclk(pclk),.prst_n(prst_n),.sample_tick(tick),.sample_valid(valid),.sample_converged(1'b1),
 .sample_iterations(iteration),.sample_pixels(pixels),.sample_endpoints(ends),.sample_branches(branches),.sample_pruned(pruned),
 .sample_body_valid(model_valid),.sample_arm_flags(model_arms),.report_enable(enabled),.query(query),
 .tx_valid(tv),.tx_data(data),.tx_last(last),.tx_accept(accept),.tx_done(done));
string suffix="";string line="";string messages[0:15];integer starts[0:15];
integer lines=0,delay=0,cycles=0,enable_cycle;
always @(negedge clk)begin
 cycles++;accept=0;done=0;
 if(rst_n)begin
  if(delay>0)begin delay--;if(delay==0)done=1;end
  else if(tv)begin
   if(line.len()==0)starts[lines]=cycles;
   line={line,data};accept=1;delay=3;
   if(last)begin
    if(line.len()!=LENGTH||line.getc(LENGTH-2)!=13||line.getc(LENGTH-1)!=10)$fatal(1,"bad UART framing");
    messages[lines]=line;lines++;line="";
   end
  end
 end
end
task sample(input bit present,input [15:0] count);
 begin @(negedge pclk);valid=present;pixels=count;model_valid=present;model_arms=present?(count==16'hABCD ? 1 : 3):0;tick=1;@(negedge pclk);tick=0;end
endtask
task ask;
 begin @(negedge clk);query=1;@(negedge clk);query=0;end
endtask
task verify_line(input integer n,input bit present,input [15:0] count,input [1:0] arms);
 string expected;
 begin
  suffix="";
  if(BODY_MODE)suffix=$sformatf(" BODY:%0d ARM:%0d",present,arms);
  expected=$sformatf("SKEL:%0d C:1 I:12 P:%04X E:0002 B:0001 R:0003%s%c%c",present,count,suffix,13,10);
  // Simulator %X may produce lower-case hex; wire format is upper-case.
  expected=expected.toupper();
  if(messages[n]!=expected)$fatal(1,"wrong mailbox payload %s expected %s",messages[n],expected);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;prst_n=1;
 sample(1,16'h1234);
 repeat(INTERVAL+100)@(negedge clk);
 for(integer i=0;i<10;i++)sample(i%2,16'h1234);
 repeat(100)@(negedge clk);
 if(lines!=0||tv)$fatal(1,"boot/validity changes emitted unsolicited status");
 sample(1,16'h1234);repeat(20)@(negedge clk);ask();wait(lines==1);
 verify_line(0,1,16'h1234,3);
 repeat(INTERVAL+100)@(negedge clk);
 if(lines!=1)$fatal(1,"manual query enabled periodic reporting");
 // First automatic line must wait the full two-second interval after entry.
 @(negedge clk);enabled=1;enable_cycle=cycles;
 wait(tv);sample(1,16'hABCD);wait(lines==2);
 if(starts[1]-enable_cycle<INTERVAL||starts[1]-enable_cycle>INTERVAL+20)$fatal(1,"wrong entry delay");
 if(messages[1]!=messages[0])$fatal(1,"message changed during transmission");
 wait(lines==3);verify_line(2,1,16'hABCD,1);
 if(starts[2]-starts[1]!=INTERVAL)$fatal(1,"wrong two-second report period");
 // Rapid valid/invalid transitions must not bypass rate limiting.
 for(integer i=0;i<10;i++)sample(i%2,16'hABCD);
 sample(0,0);repeat(1000)@(negedge clk);
 if(lines!=3)$fatal(1,"validity transition bypassed rate limit");
 wait(lines==4);verify_line(3,0,0,0);
 if(starts[3]-starts[2]!=INTERVAL)$fatal(1,"invalid result report not rate limited");
 // Exit while transmitting: finish exactly this line, no truncated UART message.
 wait(!dut.sending);wait(tv);@(negedge clk);enabled=0;wait(lines==5);
 if(messages[4]!=messages[3])$fatal(1,"exit truncated in-flight message");
 repeat(INTERVAL+100)@(negedge clk);
 if(lines!=5||tv||dut.auto_pending)$fatal(1,"exit retained automatic report");
 ask();wait(lines==6);verify_line(5,0,0,0);
 repeat(INTERVAL+100)@(negedge clk);if(lines!=6)$fatal(1,"disabled query leaked periodic report");
 // A queued auto report under backpressure must be discarded on exit.
 force dut.req_sync=1'b1;force dut.acknowledge=1'b0;
 @(negedge clk);enabled=1;repeat(INTERVAL+20)@(negedge clk);
 if(!dut.auto_pending||tv)$fatal(1,"did not queue blocked automatic report");
 enabled=0;repeat(5)@(negedge clk);release dut.req_sync;release dut.acknowledge;
 repeat(100)@(negedge clk);if(lines!=6||tv||dut.auto_pending)$fatal(1,"queued report escaped after exit");
 @(negedge clk);enabled=1;enable_cycle=cycles;wait(lines==7);
 if(starts[6]-enable_cycle<INTERVAL)$fatal(1,"re-entry reused old timer");
 $display("PASS skeleton UART: quiet boot, U6-style gating, exact two-second period, rate-limited validity changes, asynchronous immutable messages, exit drain/discard, manual queries and re-entry");$finish;
end
initial begin #1000000;$fatal(1,"UART timeout lines=%0d",lines);end
endmodule
