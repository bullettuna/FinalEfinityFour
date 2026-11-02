`timescale 1ns/1ps
module photo_event_queue_tb;
 reg clk=0,rst_n=0,event_valid=0,event_critical=0,enable_tx=0;
 always #5 clk=~clk;
 reg [3:0] kind=4;wire txvalid,txlast;wire [7:0] data;reg accept=0,done=0;
 photo_event_uart dut(.clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_critical(event_critical),
  .event_kind(kind),.event_code(8'h1c),.event_command(6'd13),.event_reason(4'd1),
  .event_stage(4'd0),.event_rd(4'd0),.event_axi(4'd0),.event_beats(6'd0),
  .room(),.tx_valid(txvalid),.tx_data(data),.tx_last(txlast),.tx_accept(accept),.tx_done(done));
 integer delay=0,ddr=0,tf=0,fail=0,fault=0;string line="";
 always @(posedge clk)begin
  accept<=0;done<=0;
  if(delay>0)begin delay=delay-1;if(delay==0)done<=1;end
  else if(enable_tx&&txvalid&&!accept)begin
   accept<=1;delay=3;line={line,data};
   if(txlast)begin
    if(line.getc(line.len()-2)!=13||line.getc(line.len()-1)!=10)$fatal(1,"truncated queue message");
    if(line==string'({"DDR_OK",8'h0d,8'h0a}))ddr=ddr+1;
    else if(line==string'({"tfOK",8'h0d,8'h0a}))tf=tf+1;
    else if(line==string'({"TF_FAIL:SAVE_TIMEOUT ST=1C",8'h0d,8'h0a}))fail=fail+1;
    else if(line==string'({"FAULT:RESET_REQUIRED AXI=0 RD=0",8'h0d,8'h0a}))fault=fault+1;
    else if(line.substr(0,7)!="BUSY ST=")$fatal(1,"unexpected queued message %s",line);
    line="";
   end
  end
 end
 task automatic send_event(input [3:0] k,input critical);
  begin @(negedge clk);kind=k;event_critical=critical;event_valid=1;@(negedge clk);event_valid=0;end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  repeat(24)send_event(4,0);
  if(dut.count!=12)$fatal(1,"status queries consumed result reserve");
  send_event(0,1);send_event(1,1);send_event(8,1);
  repeat(24)send_event(9,0);send_event(9,1);
  if(dut.count!=16)$fatal(1,"critical result reserve not usable");
  enable_tx=1;wait(ddr==1&&tf==1&&fail==1&&fault==1);repeat(40)@(negedge clk);
  if(ddr!=1||tf!=1||fail!=1||fault!=1)$fatal(1,"critical result duplicated/lost");
  $display("PASS repeated BUSY/fault queries preserve completion/error queue reserve");$finish;
 end
 initial begin #1000000;$fatal(1,"event queue regression timeout");end
endmodule
