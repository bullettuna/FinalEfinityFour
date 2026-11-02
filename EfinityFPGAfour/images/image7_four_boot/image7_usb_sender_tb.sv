`timescale 1ns/1ps
module image7_usb_sender_tb;
 reg clk=0,rst_n=0,enable=0,publish=0,shot=0,txe=1;always #5 clk=~clk;
 reg [527:0] points=0;reg [31:0] cycles=0,icrc=0,hcrc=0;
 wire valid,available,run_,release_,ready,stopped,wr,wo;wire [7:0] data,ad,oe;
 pose7_usb_sender dut(.clk(clk),.rst_n(rst_n),.stream_enable(enable),.publish(publish),.one_shot(shot),
  .points(points),.cycles(cycles),.model_crc(32'h1f704b5e),.input_crc(icrc),.heatmap_crc(hcrc),.flags(8'h03),
  .ready(ready),.valid(valid),.data(data),.available(available),.run_enable(run_),.release_result(release_));
 ft245_async_tx phy(.clk(clk),.rst_n(rst_n),.run_enable(run_),.txe_n_async(txe),.valid(valid),.data(data),.ready(ready),
  .data_o(ad),.data_oe(oe),.wr_n(wr),.wr_oe(wo),.stopped(stopped));
 integer writes=0,low_clocks=0,f,i;reg last_wr=1;
 always @(posedge clk)begin
  last_wr<=wr;
  if(!wr)begin
   low_clocks<=low_clocks+1;
   if(!wo||oe!=8'hff)$fatal(1,"WR without driven data");
  end
  if(last_wr&&!wr)begin $fwrite(f,"%c",ad);writes<=writes+1;end
  if(!last_wr&&wr)begin if(low_clocks<10)$fatal(1,"OFF truncated WR pulse");low_clocks<=0;end
 end
 task frame(input [7:0] tag,input diagnostic);
  begin
   @(negedge clk);for(i=0;i<11;i=i+1)points[i*48+:48]={16'd30000+i[15:0],16'd200+i[15:0],{tag,8'd0}+i[15:0]};
   cycles=tag;icrc=32'h11110000+tag;hcrc=32'h22220000+tag;shot=diagnostic;publish=1;
   @(negedge clk);publish=0;shot=0;
  end
 endtask
 initial begin
  f=$fopen("sender_packets.bin","wb");repeat(4)@(negedge clk);rst_n=1;
  frame(1,0);repeat(300)@(negedge clk);if(writes||available||!stopped)$fatal(1,"default OFF sent data");
  enable=1;frame(8'h11,0);repeat(200)@(negedge clk);if(!available||writes)$fatal(1,"missing backpressure");
  frame(8'h12,0);txe=0;wait(!available&&stopped);repeat(5)@(negedge clk);if(writes!=114)$fatal(1,"first packet/footer missing %0d",writes);
  frame(8'h22,0);wait(writes==121);repeat(3)@(negedge clk);enable=0;
  wait(stopped);repeat(200)@(negedge clk);if(available||writes!=121)$fatal(1,"OFF did not stop physical stream");
  frame(8'h32,0);repeat(200)@(negedge clk);if(writes!=121||available)$fatal(1,"OFF accepted ordinary result");
  enable=1;frame(8'h33,0);wait(!available&&stopped);repeat(5)@(negedge clk);if(writes!=235)$fatal(1,"resume not a full new packet");
  enable=0;txe=1;frame(8'h44,1);repeat(200)@(negedge clk);if(!available)$fatal(1,"explicit oracle reply missing");
  txe=0;wait(!available&&stopped);repeat(5)@(negedge clk);if(writes!=349)$fatal(1,"one-shot final CRC byte lost");
  txe=1;enable=1;frame(8'h55,0);repeat(200)@(negedge clk);enable=0;wait(stopped);repeat(200)@(negedge clk);
  if(writes!=349||available)$fatal(1,"blocked queue did not cancel");
  enable=1;txe=0;frame(8'h66,0);wait(!available&&stopped);repeat(5)@(negedge clk);if(writes!=463)$fatal(1,"second resume failed");
  enable=0;repeat(200)@(negedge clk);$fclose(f);
  $display("PASS USB point sender: default OFF, immutable stalled result, OFF during WR, no blocked-stop deadlock, clean restart, retained sequence and complete one-shot footer; writes=%0d",writes);$finish;
 end
 initial begin #5000000;$fatal(1,"USB sender timeout writes=%0d",writes);end
endmodule
