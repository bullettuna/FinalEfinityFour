`timescale 1ns/1ps
// Real board divider and UART receiver, with gapless PC 115200/8N1 traffic.
module pose6_uart_wire_tb;
 reg clk=0,rst_n=0,rxd=1;
 always #5.208333 clk=~clk;
 wire tick,rx_valid,legacy,tx_valid;wire [7:0] rx_data,tx_data;
 integer rx_count=0,reply_count=0;
 reg [7:0] expected[0:31],replies[0:31];
 integer expected_count=0;
 wire debug_start;wire [7:0] debug_opcode;integer debug_count=0;
 reg [7:0] debug_expected[0:6];
 integer_divider #(.DEVIDE_CNT(52)) divider(clk,rst_n,tick);
 uart_receiver receiver(clk,rst_n,tick,rxd,rx_data,rx_valid);
 pose6_uart_loader #(.EXPECTED_MODEL_CRC(32'hbbffdf52)) loader(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.legacy_rx_valid(legacy),
  .can_load(1'b1),.clear_input(1'b0),.model_ready(),.input_ready(),.test_start(),.model_crc(),.input_crc(),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_accept(1'b1),
  .command_valid(),.command_ready(1'b1),.command_write(),.command_address(),.command_data(),
  .response_valid(1'b0),.memory_fault(1'b0),.diagnostic_busy(1'b0),.diagnostic_start(),.external_model_ready(1'b0),.debug_busy(1'b0),.invalidate_model(1'b0),.debug_start(debug_start),.debug_opcode(debug_opcode));
 always @(posedge clk)if(rst_n)begin
  if(rx_valid)begin
   if(rx_count>=expected_count||rx_data!==expected[rx_count])$fatal(1,"UART byte %0d got %h expected %h",rx_count,rx_data,expected[rx_count]);
   rx_count<=rx_count+1;
  end
  if(tx_valid)begin replies[reply_count]<=tx_data;reply_count<=reply_count+1;end
  if(debug_start)begin
   if(debug_count>=7||debug_opcode!==debug_expected[debug_count])$fatal(1,"Wire debug opcode %h index=%0d",debug_opcode,debug_count);
   debug_count<=debug_count+1;
  end
 end
 task send(input [7:0] b,input realtime bit_ns);
  begin
   expected[expected_count]=b;expected_count=expected_count+1;
   rxd=0;#(bit_ns);
   for(integer j=0;j<8;j=j+1)begin rxd=b[j];#(bit_ns);end
   rxd=1;#(bit_ns);
  end
 endtask
 task run_header(input realtime bit_ns,input integer gap_ns);
  begin
   rst_n=0;rxd=1;#1000;rx_count=0;reply_count=0;expected_count=0;
   rst_n=1;#1234;
   send("~",bit_ns);#(gap_ns);send("6",bit_ns);#(gap_ns);send("L",bit_ns);#(gap_ns);
   send(8'ha0,bit_ns);#(gap_ns);send(8'h76,bit_ns);#(gap_ns);send(8'h02,bit_ns);#(gap_ns);send(8'h00,bit_ns);#(gap_ns);
   send(8'h52,bit_ns);#(gap_ns);send(8'hdf,bit_ns);#(gap_ns);send(8'hff,bit_ns);#(gap_ns);send(8'hbb,bit_ns);
   #2000;
   if(rx_count!=11||reply_count!=1||replies[0]!=="L")$fatal(1,"Header rejected: bit=%f gap=%0d rx=%0d replies=%0d last=%h",bit_ns,gap_ns,rx_count,reply_count,replies[0]);
   $display("PASS real UART frozen-model header: bit=%f ns, gap=%0d ns, 11 exact bytes, accepted L",bit_ns,gap_ns);
  end
 endtask
 initial begin
  run_header(8680.555556,0);
  run_header(8650.0,0);
  run_header(8750.0,0);
  run_header(8680.555556,1000000);
  rst_n=0;rxd=1;#1000;rx_count=0;reply_count=0;expected_count=0;debug_count=0;
  debug_expected[0]="H";debug_expected[1]="S";debug_expected[2]="F";debug_expected[3]="V";
  debug_expected[4]="-";debug_expected[5]="+";debug_expected[6]="R";
  rst_n=1;#1234;
  for(integer k=0;k<7;k=k+1)begin
   send("~",8680.555556);send("6",8680.555556);send(debug_expected[k],8680.555556);
  end
  #2000;
  if(debug_count!=7||rx_count!=21||reply_count!=0)$fatal(1,"New command real-wire parsing");
  $display("PASS image6 ASCII commands over physical UART receiver: seven gapless 115200/8N1 commands, exact action pulses");
  $display("PASS image6 real UART wire: gapless and paced binary headers, board divider/receiver, no byte-level bypass");$finish;
 end
 initial begin #20000000;$fatal(1,"UART wire timeout");end
endmodule
