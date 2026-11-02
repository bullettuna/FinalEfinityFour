`timescale 1ns/1ps
module ft_uart_tb;
 reg clk=0,rst_n=0,rx_valid=0,ready=0,legacy_start=0,done=0;
 reg [7:0] rx=0;wire lvalid,ldone,start,run_n;wire [7:0] data;wire [1:0] mode,resolution;wire edge_packed;reg stopped=1;
 always #5 clk=~clk;
 ft_uart_control dut(.clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(rx_valid),.link_ready(ready),.link_stopped(stopped),
  .legacy_rx_valid(lvalid),.legacy_start(legacy_start),.legacy_data(8'h32),.command_done(done),.legacy_done(ldone),
  .command_start(start),.command_data(data),.mode(mode),.resolution(resolution),.edge_packed(edge_packed),.run_n(run_n));
 task send(input [7:0] c,input bit legacy,input bit reply,input [7:0] expected);
  integer waited;reg seen;
  begin
   @(negedge clk);rx=c;rx_valid=1;#1;if(lvalid!==legacy)$fatal(1,"prefix leaked to legacy UART");
   @(posedge clk);@(negedge clk);rx_valid=0;seen=0;
   for(waited=0;waited<(reply?20:5);waited=waited+1)begin
    @(posedge clk);#1;
    if(start)begin if(!reply||data!==expected)$fatal(1,"FT UART reply mismatch %h %h",c,data);seen=1;waited=20;end
   end
   if(reply&&!seen)$fatal(1,"missing FT UART reply");
   if(reply)begin repeat(2)@(negedge clk);done=1;@(negedge clk);done=0;end
   repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  send("!",0,0,0);send("V",0,1,"A");send("!",0,0,0);send("1",0,1,"N");
  if(mode||run_n)$fatal(1,"armed without clock");ready=1;
  send("!",0,0,0);send("?",0,1,"A");send("!",0,0,0);send("2",0,1,"2");
  repeat(35)@(negedge clk);if(!run_n||mode!=2)$fatal(1,"gray mode not armed");
  send("C",1,0,0);send("G",1,0,0);send("E",1,0,0);
  send("!",0,0,0);send("S",0,1,"2");send("!",0,0,0);send("0",0,1,"0");if(run_n)$fatal(1,"stop failed");
  send("!",0,0,0);send("3",0,1,"3");repeat(35)@(negedge clk);send("!",0,0,0);send("0",0,1,"0");ready=0;
  ready=1;repeat(40)@(negedge clk);if(run_n)$fatal(1,"reconnect auto-armed");
  send("!",0,0,0);send("P",0,1,"1");
  send("!",0,0,0);send("7",0,1,"7");if(mode!=3||edge_packed)$fatal(1,"byte-edge selection");
  send("!",0,0,0);send("3",0,1,"3");if(mode!=3||!edge_packed)$fatal(1,"packed-edge selection");
  send("!",0,0,0);send("5",0,1,"5");if(resolution!=1)$fatal(1,"640 selection");
  send("!",0,0,0);send("6",0,1,"6");if(resolution!=2)$fatal(1,"1920 selection");
  send("!",0,0,0);send("R",0,1,"6");
  send("!",0,0,0);send("4",0,1,"4");if(resolution!=0)$fatal(1,"320 selection");
  send("!",0,0,0);send("1",0,1,"1");stopped=0;
  send("!",0,0,0);send("0",0,0,0);
  repeat(50)begin @(posedge clk);#1;if(start||run_n)$fatal(1,"early stop acknowledgement");end
  @(negedge clk);stopped=1;wait(start);#1;if(data!="0")$fatal(1,"deferred stop reply");
  repeat(2)@(negedge clk);done=1;@(negedge clk);done=0;
  $display("PASS FT UART prefix isolation, readiness, resolution selection, deferred stop acknowledgement and explicit start");$finish;
 end
endmodule
