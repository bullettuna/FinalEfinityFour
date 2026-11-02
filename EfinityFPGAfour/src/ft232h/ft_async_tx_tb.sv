`timescale 1ns/1ps
module ft_async_tx_tb;
 parameter DATA_DELAY=4.8,WR_DELAY=2.5;
 reg clk=0,rst_n=0,run=0,txe=1,valid=0;reg [7:0] data=0;
 always #5.208333 clk=~clk;
 wire ready,stopped,wr,oe;wire [7:0] dout,doe;
 ft245_async_tx dut(.clk(clk),.rst_n(rst_n),.run_enable(run),.txe_n_async(txe),
  .valid(valid),.data(data),.ready(ready),.data_o(dout),.data_oe(doe),.wr_n(wr),.wr_oe(oe),.stopped(stopped));
 reg [7:0] qdata;reg qwr=1;
 always @(posedge clk)begin qdata<=dout;qwr<=wr;end
 wire [7:0] pad_data;wire pad_wr;
 assign #(DATA_DELAY) pad_data=qdata;
 assign #(WR_DELAY) pad_wr=oe?qwr:1'b1;
 reg [7:0] expected[0:4095];integer accepted=0,issued=0;bit checking=0;
 realtime last_data=0,last_fall=-10000,last_rise=-10000;integer corners=0;
 always @(pad_data)begin
  if(checking&&$realtime-last_rise<95)$fatal(1,"AD hold after WR rise too short");
  last_data=$realtime;
 end
 always @(negedge pad_wr)if(rst_n)begin
  if(txe!==0)$fatal(1,"write while actual TXE high");
  if($realtime-last_data<95)$fatal(1,"AD setup too short");
  if($realtime-last_fall<995)$fatal(1,"write rate gap violated");
  if(checking)begin
   if(issued>=accepted||pad_data!==expected[issued])$fatal(1,"duplicate/missing byte %d %h %h",issued,pad_data,expected[issued]);
  end
  issued=issued+1;last_fall=$realtime;
 end
 always @(posedge pad_wr)if(rst_n&&last_fall>0)begin
  if($realtime-last_fall<100)$fatal(1,"WR low pulse truncated");last_rise=$realtime;
 end
 // Asynchronous status update, including delayed post-write busy and stalls.
 initial forever begin
  @(negedge pad_wr);
  #(corners%2?1:14);txe=1;
  @(posedge pad_wr);#(49+(corners%5)*213.7);txe=0;corners=corners+1;
 end
 always @(posedge clk)if(valid&&ready)begin expected[accepted]=data;accepted=accepted+1;end
 task stop_phase(input integer phase);
  integer before_count,before_accept;
  begin
   @(negedge clk);run=1;valid=1;data=8'hac;before_accept=accepted;
   wait(accepted>before_accept);@(negedge clk);valid=0;
   wait(dut.state==phase);#2.3;run=0;before_count=issued;
   wait(stopped);repeat(5)@(posedge clk);before_count=issued;
   if(!pad_wr||doe||oe)$fatal(1,"stop did not release pads");
   repeat(120)@(posedge clk);if(issued!=before_count)$fatal(1,"write after stop request");
  end
 endtask
 integer n;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(30)@(negedge clk);
  if(!stopped||doe)$fatal(1,"unsafe power-up");run=1;valid=1;checking=1;
  // Hold TXE high: upstream may give exactly one pending byte, no writes.
  repeat(150)@(negedge clk);if(accepted!=1||issued)$fatal(1,"backpressure pending ownership");txe=0;
  for(n=1;n<256;n=n+1)begin
   wait(ready);@(negedge clk);data=n;
   @(posedge clk);@(negedge clk);
  end
  valid=0;wait(issued==256);wait(dut.state==1);
  if(accepted!=256)$fatal(1,"pending accepted twice %d",accepted);
  checking=0;run=0;wait(stopped);repeat(120)@(posedge clk);
  for(n=2;n<=6;n=n+1)stop_phase(n);
  $display("PASS async PHY: pad setup/low/hold/gap, delayed TXE 1/14ns +49ns recovery, pending ownership, backpressure, graceful stop in every phase");$finish;
 end
 initial begin #10000000;$fatal(1,"async PHY timeout");end
endmodule
