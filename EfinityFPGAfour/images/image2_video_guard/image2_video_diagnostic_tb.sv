`timescale 1ns/1ps
module image2_video_diagnostic_tb;
 reg clk=0,cam_clk=0,pixel_clk=0,rst_n=0;
 always #5 clk=~clk;always #3 cam_clk=~cam_clk;always #4 pixel_clk=~pixel_clk;
 reg cam_vs=0,cam_de=0,rx_valid=0,ready=0;reg [7:0] rx_data=0;
 wire legacy,valid,last;wire [7:0] data_byte;wire [383:0] data;
 integer cycles=0,legacy_d=0,legacy_z=0,legacy_h=0;
 reg [31:0] awaddr=0,araddr=0;reg awv=0,arv=0;
 image2_video_diagnostic #(.RX_TIMEOUT(30)) dut(
 .clk(clk),.cam_clk(cam_clk),.pixel_clk(pixel_clk),.rst_n(rst_n),.cam_vs(cam_vs),.cam_de(cam_de),
 .underflow_count(32'd7),.bad_frame_count(32'd1),.status(32'd6),
 .video_awaddr(awaddr),.video_araddr(araddr),.video_awvalid(awv),.video_awready(1'b1),
 .video_arvalid(arv),.video_arready(1'b1),.aux_awvalid(1'b0),.aux_awready(1'b1),.aux_arvalid(1'b0),.aux_arready(1'b1),
 .rx_valid(rx_valid),.rx_data(rx_data),.legacy_valid(legacy),.tx_valid(valid),.tx_last(last),.tx_data(data_byte),.tx_accept(ready),.data(data));
 defparam dut.counters.EXPECTED_WORDS=4;
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(legacy&&rx_data=="D")legacy_d=legacy_d+1;
  if(legacy&&rx_data=="Z")legacy_z=legacy_z+1;
  if(legacy&&rx_data=="H")legacy_h=legacy_h+1;
 end
 task send(input [7:0] v);begin @(negedge clk);rx_valid=1;rx_data=v;@(negedge clk);rx_valid=0;repeat(2)@(negedge clk);end endtask
 task frame(input integer words);begin
  @(negedge cam_clk);cam_vs=1;@(negedge cam_clk);cam_de=1;
  repeat(words)@(negedge cam_clk);cam_de=0;
  repeat(2)@(negedge cam_clk);cam_vs=0;repeat(4)@(negedge cam_clk);
 end endtask
 integer fd,n=0;reg [7:0] held;reg [383:0] snapshot;
 initial begin
  repeat(8)@(negedge clk);rst_n=1;
  frame(4);frame(3);frame(4);repeat(10)@(negedge clk);
  if(data[63:32]!=3||data[95:64]!=2||data[127:96]!=11||data[287:256]!=7)$fatal(1,"passive camera counters");
  send("Z");send("H");send("D");
  if(legacy_z!=1||legacy_h!=1||legacy_d!=1)$fatal(1,"legacy pass-through");
  send("~");send("2");send("D");wait(valid);
  if(legacy_d!=1)$fatal(1,"diagnostic D leaked to cleanup control");
  snapshot=data;held=data_byte;repeat(10)@(negedge clk);
  if(!valid||data_byte!=held)$fatal(1,"packet changed under UART backpressure");
  // Live camera observations may change while the outgoing snapshot is held.
  frame(4);repeat(10)@(negedge clk);
  fd=$fopen("image2_video_diag.bin","wb");
  while(n<56)begin
   @(negedge clk);ready=0;held=data_byte;repeat(3)@(negedge clk);
   if(!valid||data_byte!=held)$fatal(1,"stalled payload changed");
   if(last!=(n==55))$fatal(1,"last marker");
   $fwrite(fd,"%c",data_byte);ready=1;@(negedge clk);ready=0;n=n+1;
  end
  $fclose(fd);repeat(5)@(negedge clk);if(valid)$fatal(1,"packet stuck");
  send("~");repeat(35)@(negedge clk);send("D");if(legacy_d!=2)$fatal(1,"prefix timeout did not release legacy parser");
  send("~");send("x");send("Z");if(legacy_z!=2)$fatal(1,"malformed prefix stuck");
  if(data[63:32]!=4||data[95:64]!=3)$fatal(1,"live observer stopped during query");
  $display("PASS image2 passive video diagnostics, exact packed counters, legacy isolation, timeout and immutable UART snapshot");$finish;
 end
 initial begin #100000;$fatal(1,"diagnostic timeout");end
endmodule
