`timescale 1ns/1ps
module pose6_debug_uart_tb;
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 reg [7:0] opcode=0;reg [1:0] reload_reply=0;
 reg [31:0] size=235232,bytes_seen=235232,runs=32'h1234abcd;
 reg model_ready=1;wire busy,valid;wire [7:0] data;
 string expected_snapshot="BIN FOUND=1 SIZE=000396E0 HDR=1 CRC=1 BYTES=000396E0\015\012";
 integer cycle=0,count=0;reg ready=0;reg [7:0] captured[0:255],held;reg stalled=0;
 pose6_debug_uart dut(.clk(clk),.rst_n(rst_n),.start(start),.opcode(opcode),.reload_reply(reload_reply),
  .card_initialized(1'b1),.fat_valid(1'b1),.file_found(1'b1),.header_valid(1'b1),.crc_valid(1'b1),
  .model_ready(model_ready),.self_test_pass(1'b1),.enabled(1'b1),.model_busy(1'b0),.boot_stage(4'd3),
  .error_code(8'h21),.sd_command(6'd17),.sd_reason(4'hb),.file_size(size),.read_bytes(bytes_seen),.runs(runs),
  .busy(busy),.valid(valid),.data(data),.ready(ready));
 always @(negedge clk)ready=cycle%5==0;
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(stalled&&valid&&data!==held)$fatal(1,"ASCII changed under UART backpressure");
  stalled<=valid&&!ready;held<=data;
  if(valid&&ready)begin captured[count]<=data;count<=count+1;end
 end
 task check(input [7:0] op,input string expected);
  integer j;
  begin
   @(negedge clk);count=0;opcode=op;start=1;
   @(negedge clk);start=0;
   wait(!busy);#1;
   if(count!=expected.len())$fatal(1,"ASCII length op=%c got=%0d expected=%0d",op,count,expected.len());
   for(j=0;j<count;j=j+1)if(captured[j]!==expected[j])$fatal(1,"ASCII op=%c byte=%0d got=%h expected=%h",op,j,captured[j],expected[j]);
  end
 endtask
 initial begin
  #32;rst_n=1;
  check("S","SD INIT=1 FAT=1 STAGE=3 ERR=21 CMD=11 REASON=B\015\012");
  check("F","BIN FOUND=1 SIZE=000396E0 HDR=1 CRC=1 BYTES=000396E0\015\012");
  check("V","MODEL READY=1 TEST=1 ENABLE=1 BUSY=0 RUNS=1234ABCD ERR=21\015\012");
  check("+","MODEL ON\015\012");model_ready=0;
  check("+","MODEL NOT_READY\015\012");check("-","MODEL OFF\015\012");
  check("R","SD RELOAD\015\012");reload_reply=1;check("R","SD STOP_FIRST\015\012");
  reload_reply=2;check("R","SD BUSY\015\012");reload_reply=3;check("R","SD UNSUPPORTED\015\012");
  check("H","~6S SD; ~6F BIN; ~6V MODEL; ~6+ ON; ~6- OFF; ~6R RELOAD\015\012");
  // Mutate live counters after the first byte: a reply owns one snapshot.
  @(negedge clk);count=0;opcode="F";start=1;
  @(negedge clk);start=0;
  wait(count==1);size=0;bytes_seen=0;
  wait(!busy);#1;
  if(count!=expected_snapshot.len())$fatal(1,"ASCII snapshot length");
  for(integer q=0;q<count;q=q+1)if(captured[q]!==expected_snapshot[q])$fatal(1,"ASCII snapshot was not held");
  $display("PASS image6 ASCII diagnostics: all seven commands, rejection messages, hexadecimal fields, immutable snapshots and UART backpressure");
  $finish;
 end
 initial begin #1000000;$fatal(1,"ASCII diagnostic timeout");end
endmodule
