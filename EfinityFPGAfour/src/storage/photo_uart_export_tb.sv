`timescale 1ns/1ps
module photo_uart_export_tb #(parameter WIDTH=64,HEIGHT=16);
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 reg [1:0] mode=2;reg median=1;reg [1:0] clean=1;
 reg [10:0] minimum=20,high=60,low=30;
 wire busy,done,error,read_start,valid,last,accept,tx_done;
 wire [19:0] offset;wire [7:0] data;
 reg rd_done=0,rd_error=0,rd_valid=0;reg [8:0] rd_index=0;reg [7:0] rd_byte=0;
 photo_uart_export #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.mode(mode),.median_enable(median),.cleanup_level(clean),
  .min_pixels(minimum),.high_threshold(high),.low_threshold(low),.busy(busy),.done(done),.error(error),
  .read_start(read_start),.read_offset(offset),.read_done(rd_done),.read_error(rd_error),
  .read_valid(rd_valid),.read_index(rd_index),.read_byte(rd_byte),
  .tx_valid(valid),.tx_data(data),.tx_last(last),.tx_accept(accept),.tx_done(tx_done));
 reg cmd_start=0;wire cmd_done;wire [7:0] phy_data;wire phy_start;reg phy_done=0;
 wire unused1,unused2,unused3,unused4,unused5,unused6;
 uart_tx_arbiter arb(.clk(clk),.rst_n(rst_n),.cmd_tx_start(cmd_start),.cmd_tx_data(8'h4b),.cmd_tx_done(cmd_done),
  .msg_tx_valid(1'b0),.msg_tx_data(8'd0),.msg_tx_last(1'b0),.msg_tx_accept(unused1),.msg_tx_done(unused2),
  .msg2_tx_valid(1'b0),.msg2_tx_data(8'd0),.msg2_tx_last(1'b0),.msg2_tx_accept(unused3),.msg2_tx_done(unused4),
  .msg3_tx_valid(valid),.msg3_tx_data(data),.msg3_tx_last(last),.msg3_tx_accept(accept),.msg3_tx_done(tx_done),
  .msg4_tx_valid(1'b0),.msg4_tx_data(8'd0),.msg4_tx_last(1'b0),.msg4_tx_accept(unused5),.msg4_tx_done(unused6),
  .uart_tx_done(phy_done),.uart_tx_data(phy_data),.uart_tx_start(phy_start));
 integer cycle=0,delay_tx=0,bytes=0,fd=0,requests=0,cmd_replies=0;
 reg inject_error=0;reg binary_source=1;
 integer left=0,index=0,base=0;reg [15:0] value;
 function automatic [15:0] test_pixel(input integer n);
  if(binary_source)test_pixel=(n%13==0||n%31==1)?16'hffff:0;
  else test_pixel={5'(n%32),6'(n%64),5'(n%32)};
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;phy_done<=0;rd_valid<=0;rd_done<=0;rd_error<=0;cmd_start<=0;
  if(delay_tx>0)begin delay_tx<=delay_tx-1;if(delay_tx==1)phy_done<=1;end
  if(phy_start)begin
   if(delay_tx!=0)$fatal(1,"overlapping UART bytes");
   delay_tx<=3+cycle%7;
   if(bytes<40+(binary_source?WIDTH*HEIGHT/8:WIDTH*HEIGHT))begin
    $fwrite(fd,"%c",phy_data);bytes<=bytes+1;
    if(bytes==45)cmd_start<=1;
   end else begin if(phy_data!="K")$fatal(1,"command reply corruption");cmd_replies<=cmd_replies+1;end
  end
  if(read_start)begin
   if(left!=0||offset!=requests*512)$fatal(1,"sector ownership/offset");
   if(inject_error&&requests==1)rd_error<=1;
   else begin left<=512;index<=0;base<=offset;end
   requests<=requests+1;
  end
  if(left>0&&cycle%3!=0)begin
   value=test_pixel((base+index)/2);rd_valid<=1;rd_index<=index;
   rd_byte<=index%2?value[15:8]:value[7:0];index<=index+1;left<=left-1;
  end
  if(left==1&&cycle%3!=0)begin
   // read_done follows the final valid byte, as in the real DMA.
  end
  if(left==0&&index==512)begin rd_done<=1;index<=0;end
  if(cycle>50000000)$fatal(1,"export timeout");
 end
 task automatic run_capture(input integer kind,input string filename);
  integer expected;
  begin
   @(negedge clk);mode=kind==0?1:2;binary_source=kind!=0;inject_error=kind==2;
   bytes=0;requests=0;cmd_replies=0;fd=$fopen(filename,"wb");if(!fd)$fatal(1,"open output");
   start=1;@(negedge clk);start=0;
   // Settings changing in flight must not change packet metadata.
   repeat(20)@(negedge clk);median=0;clean=2;minimum=77;high=99;low=44;
   wait(done);if(error!=(kind==2))$fatal(1,"error flag");
   expected=40+(binary_source?WIDTH*HEIGHT/8:WIDTH*HEIGHT);
   if(bytes!=expected)$fatal(1,"packet size got %d expected %d",bytes,expected);
   if(kind!=2&&requests!=WIDTH*HEIGHT*2/512)$fatal(1,"sector count");
   $fclose(fd);wait(cmd_replies==1);repeat(20)@(negedge clk);
   median=1;clean=1;minimum=20;high=60;low=30;
  end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  run_capture(1,"edge_packet.bin");run_capture(0,"gray_packet.bin");run_capture(2,"failed_packet.bin");
  $display("PASS UART exporter %dx%d: edge packing, gray, snapshot metadata, DDR failure, arbitration/backpressure",WIDTH,HEIGHT);$finish;
 end
endmodule
