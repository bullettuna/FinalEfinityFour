`timescale 1ns/1ps
module pose6_protocol_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [7:0] rx_data=0;reg rx_valid=0,can_load=1;
 wire legacy,model_ready,input_ready,test_start,tx_valid;
 wire [31:0] model_crc,input_crc;wire [7:0] tx_data;
 wire cv,cw;wire [31:0] ca;wire [127:0] cd;
 reg ready=0,rv=0;reg pending=0;integer delay_count=0,cycle=0,writes=0;
 reg [7:0] replies[0:31];integer reply_count=0,test_count=0,legacy_count=0,j;
 pose6_uart_loader #(.MODEL_BYTES(32),.INPUT_BYTES(32),.CLOCK_HZ(10000),.EXPECTED_MODEL_CRC(32'h91267e8a)) loader(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.legacy_rx_valid(legacy),.can_load(can_load),.clear_input(1'b0),
  .model_ready(model_ready),.input_ready(input_ready),.test_start(test_start),.model_crc(model_crc),.input_crc(input_crc),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_accept(1'b1),.command_valid(cv),.command_ready(ready),.command_write(cw),.command_address(ca),.command_data(cd),
  .response_valid(rv),.memory_fault(1'b0),.diagnostic_busy(1'b0),.diagnostic_start(),.external_model_ready(1'b0),.debug_busy(1'b0),.invalidate_model(1'b0),.debug_start(),.debug_opcode());
 always @(negedge clk)ready=!pending&&(cycle%5!=2);
 always @(posedge clk)begin
  cycle<=cycle+1;rv<=0;
  if(legacy)begin if(rx_data!="?")$fatal(1,"binary protocol leaked into legacy decoder");legacy_count<=legacy_count+1;end
  if(tx_valid)begin replies[reply_count]<=tx_data;reply_count<=reply_count+1;end
  if(test_start)test_count<=test_count+1;
  if(cv&&ready)begin
   if(!cw||ca[3:0]!=0)$fatal(1,"loader command");
   for(j=0;j<16;j=j+1)if(cd[j*8+:8]!==((ca[4]?16:0)+j))begin
    if(!(writes==3&&j==15&&cd[j*8+:8]==0))$fatal(1,"loader word byte %0d",j);
   end
   writes<=writes+1;pending<=1;delay_count<=5;
  end
  if(pending)begin
   if(delay_count!=0)delay_count<=delay_count-1;
   else begin pending<=0;rv<=1;end
  end
 end
 task send(input [7:0] b);
  begin @(negedge clk);rx_data=b;rx_valid=1;@(negedge clk);rx_valid=0;repeat(10)@(negedge clk);end
 endtask
 task header(input [7:0] op,input [31:0] length,input [31:0] crc);
  integer k;begin send("~");send("6");send(op);
   for(k=0;k<4;k=k+1)send(length>>(k*8));
   for(k=0;k<4;k=k+1)send(crc>>(k*8));
  end
 endtask
 task payload(input corrupt);
  integer k;begin for(k=0;k<32;k=k+1)send(corrupt&&k==31?0:k);repeat(20)@(negedge clk);end
 endtask
 task expect_reply(input [7:0] b);
  begin if(reply_count==0||replies[reply_count-1]!==b)$fatal(1,"reply got %h expected %h",replies[reply_count-1],b);end
 endtask
 reg available=0;wire release_result,pv;wire [7:0] pd;reg pready=0;reg [191:0] points;
 integer fd,packet_bytes=0;
 pose6_packet packet(clk,rst_n,available,release_result,points,32'd1234,32'hbbffdf52,32'h11223344,32'h55667788,8'h0b,pv,pd,pready);
 always @(negedge clk)pready=cycle%7!=3;
 always @(posedge clk)if(pv&&pready)begin $fwrite(fd,"%c",pd);packet_bytes<=packet_bytes+1;end
 initial begin
  fd=$fopen("points.bin","wb");#22;rst_n=1;
  send("?");send("~");send("6");send("Q");expect_reply("N");
  header("L",32,32'h91267e8a);expect_reply("L");payload(0);expect_reply("K");
  if(!model_ready||model_crc!=32'h91267e8a||writes!=2)$fatal(1,"model readiness");
  header("L",32,32'h91267e8a);payload(1);expect_reply("E");if(model_ready)$fatal(1,"CRC failure enabled model");
  header("L",32,32'h91267e8a);payload(0);expect_reply("K");
  header("I",32,32'h91267e8a);payload(0);expect_reply("K");
  if(!input_ready)$fatal(1,"input readiness");
  send("~");send("6");send("T");expect_reply("T");if(test_count!=1)$fatal(1,"test trigger");
  can_load=0;send("~");send("6");send("L");expect_reply("B");can_load=1;
  header("L",31,32'h91267e8a);expect_reply("E");
  header("L",32,32'h12345678);expect_reply("E");
  send("~");send("6");send("L");send(32);repeat(10020)@(negedge clk);expect_reply("E");
  if(legacy_count!=1)$fatal(1,"legacy byte count");
  for(j=0;j<4;j=j+1)begin points[j*48+:16]=400+j*40;points[j*48+16+:16]=800+j*20;points[j*48+32+:16]=40000+j;end
  @(negedge clk);available=1;wait(pv);repeat(3)@(negedge clk);points=0;
  wait(release_result);repeat(8)@(negedge clk);
  if(pv||packet_bytes!=72)$fatal(1,"packet duplicate/count");
  available=0;$fclose(fd);
  $display("PASS image6 UART model/input upload, CRC rejection, busy, timeout, no legacy leakage and backpressured point packet");$finish;
 end
 initial begin #1000000;$fatal(1,"protocol timeout");end
endmodule
