`timescale 1ns/1ps
module person_pose_uart_tb;
reg pclk=0,clk=0,rst_n=0,tick=0,query=0;
localparam INTERVAL=10000;
always #5 pclk=~pclk;always #7 clk=~clk;
reg [2:0] pose=0;reg [9:0] score=0,gap=0,edge_score=0;
wire valid,last;wire [7:0] data;reg accept=0,done=0;
integer physical_wait=0,line_count=0,cycles=0;string lines[0:31];string building="";
integer line_cycle[0:31];reg blocked=0;
person_pose_uart #(.CLOCK_HZ(20000),.REPORT_HZ(2)) dut(.pclk(pclk),.prst_n(rst_n),.sample_tick(tick),.sample_pose(pose),
 .sample_similarity(score),.sample_margin(gap),.sample_edge_support(edge_score),
 .clk(clk),.rst_n(rst_n),.query(query),.tx_valid(valid),.tx_data(data),.tx_last(last),.tx_accept(accept),.tx_done(done));
always @(posedge clk)begin
 cycles++;
 accept<=0;done<=0;
 if(physical_wait>0)begin physical_wait<=physical_wait-1;if(physical_wait==1)done<=1;end
 else if(valid&&!done&&!blocked)begin
  accept<=1;physical_wait<=5;
  if(building.len()==0)line_cycle[line_count]=cycles;
  building={building,data};
  if(last)begin lines[line_count]=building;line_count++;building="";end
 end
end
task sample(input integer p,s,g,e);
 begin
 @(negedge pclk);pose=p;score=s;gap=g;edge_score=e;tick=1;
 @(negedge pclk);tick=0;repeat(25)@(negedge pclk);
 end
endtask
task wait_lines(input integer n);
 integer cycles;
 begin cycles=0;while(line_count<n&&cycles<INTERVAL+2000)begin @(negedge clk);cycles++;end
 if(line_count!=n)$fatal(1,"UART line count %0d expected %0d",line_count,n);
 repeat(20)@(negedge clk);end
endtask
task ask;begin @(negedge clk);query=1;@(negedge clk);query=0;end endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 ask();wait_lines(1);
 if(lines[0]!=$sformatf("POSE:0 SCORE:0000 GAP:0000 E:0000%c%c",8'd13,8'd10))$fatal(1,"initial query %s hex=%h",lines[0],lines[0]);
 sample(2,1000,123,1000);sample(2,1000,123,1000);
 repeat(100)@(negedge clk);if(line_count!=1)$fatal(1,"recognized before third snapshot");
 sample(2,1000,123,1000);wait_lines(2);
 if(lines[1]!=$sformatf("POSE:2 SCORE:1000 GAP:0123 E:1000%c%c",8'd13,8'd10))$fatal(1,"stable report %s",lines[1]);
 repeat(5)sample(2,876,111,543);
 repeat(300)@(negedge clk);if(line_count!=2)$fatal(1,"pose repeated before report interval");
 ask();wait_lines(3);
 if(lines[2]!=$sformatf("POSE:2 SCORE:0876 GAP:0111 E:0543%c%c",8'd13,8'd10))$fatal(1,"query latest scores %s",lines[2]);
 sample(3,900,200,700);sample(3,900,200,700);sample(0,400,10,20);wait_lines(4);
 if(lines[3]!=$sformatf("POSE:0 SCORE:0400 GAP:0010 E:0020%c%c",8'd13,8'd10))$fatal(1,"lost person report %s",lines[3]);
 // A newer classification/query arrives while the previous line is blocked.
 sample(4,900,200,700);sample(4,900,200,700);sample(4,900,200,700);
 sample(0,0,0,0);ask();wait_lines(6);
 if(lines[4]!=$sformatf("POSE:4 SCORE:0900 GAP:0200 E:0700%c%c",8'd13,8'd10)||lines[5]!=$sformatf("POSE:0 SCORE:0000 GAP:0000 E:0000%c%c",8'd13,8'd10))$fatal(1,"busy UART lost/mixed payloads");
 // Successful recognition must keep reporting without more sample ticks or #.
 sample(5,950,240,800);sample(5,950,240,800);sample(5,950,240,800);wait_lines(7);
 sample(5,850,200,600);wait_lines(8);wait_lines(9);
 if(lines[7]!=$sformatf("POSE:5 SCORE:0850 GAP:0200 E:0600%c%c",8'd13,8'd10)||lines[8]!=lines[7])$fatal(1,"periodic report missing/current scores wrong");
 for(integer i=7;i<=8;i++)if(line_cycle[i]-line_cycle[i-1]<INTERVAL||line_cycle[i]-line_cycle[i-1]>INTERVAL+8)
  $fatal(1,"wrong repeat period: %0d",line_cycle[i]-line_cycle[i-1]);
 // Extended UART backpressure retains a bounded pending update, not a FIFO of
 // repeated old classifications. A new sample must appear in the next line.
 blocked=1;repeat(INTERVAL+20)@(negedge clk);
 sample(5,780,170,500);ask();repeat(2*INTERVAL)@(negedge clk);
 if(line_count!=9)$fatal(1,"blocked UART transmitted");
 blocked=0;wait_lines(11);
 if(lines[10]!=$sformatf("POSE:5 SCORE:0780 GAP:0170 E:0500%c%c",8'd13,8'd10))$fatal(1,"coalesced report not latest result");
 repeat(1000)@(negedge clk);if(line_count!=11)$fatal(1,"periodic backlog flooded UART");
 sample(0,0,0,0);wait_lines(12);
 if(lines[11]!=$sformatf("POSE:0 SCORE:0000 GAP:0000 E:0000%c%c",8'd13,8'd10))$fatal(1,"loss did not clear repeated pose");
 repeat(3*INTERVAL)@(negedge clk);if(line_count!=12)$fatal(1,"unknown/lost result repeated");
 ask();wait_lines(13);
 if(lines[12]!=lines[11])$fatal(1,"query after loss failed");
 $display("PASS pose UART: asynchronous mailbox, three-snapshot confirmation, timed repeat/current scores, query/change/loss, bounded busy-message updates and no unknown spam");$finish;
end
initial begin #4000000;$fatal(1,"UART test timeout");end
endmodule
