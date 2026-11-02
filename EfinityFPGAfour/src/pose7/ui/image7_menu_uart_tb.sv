`timescale 1ns/1ps
// The actual final-byte outputs protect status and binary diagnostics against
// concurrent key reports and single-byte legacy command replies.
module image7_menu_uart_tb;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg ds=0,bs=0,cmd=0,key_pending=0;
 wire dv,dl,bv,bl,accept,ka,phy_start;
 wire [7:0] dd,bd,phy_data;
 wire valid=dv||bv;wire [7:0] data_=dv?dd:bd;wire last_=dv?dl:bl;
 reg phy_done=0;integer countdown=0,ki=0,n=0;
 localparam [63:0] KEY_BITS=64'h6b65792020320d0a;wire [7:0] key_byte=KEY_BITS[(7-ki)*8+:8];
 string keyline="key  2\015\012";reg [7:0] received[0:255];
 pose7_diag_packet diag(.clk(clk),.rst_n(rst_n),.start(ds),.data(384'd0),
  .busy(),.valid(dv),.last(dl),.byte_data(dd),.ready(accept));
 pose7_debug_uart debug_(.clk(clk),.rst_n(rst_n),.start(bs),.opcode(8'h2d),.reload_reply(2'd0),
  .card_initialized(1'b0),.fat_valid(1'b0),.file_found(1'b0),.header_valid(1'b0),.crc_valid(1'b0),
  .model_ready(1'b0),.self_test_pass(1'b0),.enabled(1'b0),.model_busy(1'b0),
  .boot_stage(4'd0),.error_code(8'd0),.sd_command(6'd0),.sd_reason(4'd0),
  .file_size(32'd0),.read_bytes(32'd0),.runs(32'd0),
  .busy(),.valid(bv),.last(bl),.data(bd),.ready(accept&&!dv));
 uart_tx_arbiter arb(.clk(clk),.rst_n(rst_n),.cmd_tx_start(cmd),.cmd_tx_data(8'h4b),.cmd_tx_done(),
  .msg_tx_valid(1'b0),.msg_tx_data(8'd0),.msg_tx_last(1'b1),.msg_tx_accept(),.msg_tx_done(),
  .msg2_tx_valid(valid),.msg2_tx_data(data_),.msg2_tx_last(last_),.msg2_tx_accept(accept),.msg2_tx_done(),
  .msg3_tx_valid(key_pending),.msg3_tx_data(key_byte),.msg3_tx_last(ki==7),.msg3_tx_accept(ka),.msg3_tx_done(),
  .msg4_tx_valid(1'b0),.msg4_tx_data(8'd0),.msg4_tx_last(1'b1),.msg4_tx_accept(),.msg4_tx_done(),
  .uart_tx_done(phy_done),.uart_tx_data(phy_data),.uart_tx_start(phy_start));
 always @(posedge clk)begin
  phy_done<=0;
  if(phy_start)begin received[n]<=phy_data;n<=n+1;countdown<=5;end
  else if(countdown!=0)begin countdown<=countdown-1;if(countdown==1)phy_done<=1;end
  if(ka)begin if(ki==7)key_pending<=0;else ki<=ki+1;end
 end
 task interrupt_message;
  begin wait(n==3);@(negedge clk);key_pending=1;ki=0;cmd=1;@(negedge clk);cmd=0;end
 endtask
 function [31:0] crc_byte(input [31:0] prev,input [7:0] b);
  reg [31:0] c;begin c=prev^b;for(integer j=0;j<8;j=j+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 reg [31:0] crc;string off_message="MODEL OFF\015\012";
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  ds=1;@(negedge clk);ds=0;interrupt_message;
  wait(n==65);repeat(12)@(negedge clk);
  if({received[3],received[2],received[1],received[0]}!==32'h31443650)$fatal(1,"binary header interleaved");
  crc=32'hffffffff;
  for(integer i=0;i<52;i=i+1)begin
   if(i>=4 && received[i]!==0)$fatal(1,"key or command corrupted binary payload");
   crc=crc_byte(crc,received[i]);
  end
  if({received[55],received[54],received[53],received[52]}!==~crc)$fatal(1,"binary CRC interleaved");
  if(received[56]!=="K")$fatal(1,"queued command missing");
  for(integer i=0;i<8;i=i+1)if(received[57+i]!==keyline[i])$fatal(1,"key report missing i=%0d got=%h expected=%h",i,received[57+i],keyline[i]);
  n=0;bs=1;@(negedge clk);bs=0;interrupt_message;
  wait(n==20);repeat(12)@(negedge clk);
  for(integer i=0;i<11;i=i+1)if(received[i]!==off_message[i])$fatal(1,"ASCII status interleaved");
  if(received[11]!=="K")$fatal(1,"ASCII queued command missing");
  for(integer i=0;i<8;i=i+1)if(received[12+i]!==keyline[i])$fatal(1,"ASCII queued key missing i=%0d got=%h expected=%h",i,received[12+i],keyline[i]);
  $display("PASS image7_menu_uart: binary CRC/status intact under concurrent physical-key report and legacy reply");$finish;
 end
 initial begin #100000;$fatal(1,"UART contention timeout bytes=%0d",n);end
endmodule
