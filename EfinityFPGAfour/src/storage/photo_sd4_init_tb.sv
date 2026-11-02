`timescale 1ns/1ps
// Real SDSC CID/CSD, old-card CMD8 paths, strict command gaps and UART errors.
module photo_sd4_init_tb;
 reg clk=0,rst_n=0,q=0;
 always #5 clk=~clk;
 wire sdclk,cmdo,cmdoe,cmdi;
 wire [3:0] dato,datoe,dati;
 wire txvalid,txlast;wire [7:0] txdata;
 reg txaccept=0,txdone=0;
 photo_native_pipeline #(.WIDTH(64),.HEIGHT(8)) dut(
  .gallery_ddr_busy(1'b0),.gallery_ddr_failed(1'b0),.gallery_abort(1'b0),.gallery_ready(1'b0),
  .gallery_display_error(1'b0),
  .clk(clk),.rst_n(rst_n),.pclk(clk),.prst_n(rst_n),.capture_req(1'b0),.query_req(q),.capture_accepted(),
  .axi_read_stalled(1'b0),.axi_read_debug(4'd0),
  .in_vsync(1'b0),.in_href(1'b0),.red(8'd0),.green(8'd0),.blue(8'd0),
  .gallery_toggle_req(1'b0),.gallery_prev_req(1'b0),.gallery_next_req(1'b0),
  .gallery_mode(),.gallery_busy(),.gallery_error(),.gallery_file_number(),
  .gallery_load_start(),.gallery_load_byte_valid(),.gallery_load_byte(),.gallery_load_byte_offset(),.gallery_load_done(),.gallery_load_error(),
  .tx_valid(txvalid),.tx_data(txdata),.tx_last(txlast),.tx_accept(txaccept),.tx_done(txdone),
  .sd_clk(sdclk),.sd_cmd_o(cmdo),.sd_cmd_oe(cmdoe),.sd_cmd_i(cmdi),.sd_dat_i(dati),.sd_dat_o(dato),.sd_dat_oe(datoe),
  .awaddr(),.awlen(),.awvalid(),.awready(1'b0),.wdata(),.wlast(),.wvalid(),.wready(1'b0),.bvalid(1'b0),.bresp(2'd0),
  .araddr(),.arlen(),.arvalid(),.arready(1'b0),.rdata(128'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0),.rready());
 defparam dut.host.POWER_CYCLES=16;
 defparam dut.host.INIT_DIV=4;
 defparam dut.host.FAST_DIV=4;
 defparam dut.host.DATA_TIMEOUT=5000;
 defparam dut.host.INIT_RETRIES=3;
 sd4_card_model_tb #(.SDSC(1),.LEGACY_CMD8(1)) card(
  sdclk,cmdo,cmdoe,cmdi,dato,datoe,dati,1'b0,1'b0);

 integer uart_delay=0,lines=0;
 string line="",last_line="";
 always @(posedge clk)begin
  txaccept<=0;txdone<=0;
  if(uart_delay>0)begin uart_delay=uart_delay-1;if(uart_delay==0)txdone<=1;end
  else if(txvalid&&!txaccept)begin
   txaccept<=1;uart_delay=5;line={line,txdata};
   if(txlast)begin
    if(line.getc(line.len()-2)!=13 || line.getc(line.len()-1)!=10)$fatal(1,"UART CR/LF missing");
    last_line=line;lines=lines+1;$display("UART %s",line);line="";
   end
  end
 end
 task automatic query(input string expected);
  integer before_lines;
  begin
   before_lines=lines;
   @(negedge clk);q=1;@(negedge clk);q=0;
   wait(lines==before_lines+1);
   if(last_line!=string'({expected,8'h0d,8'h0a}))$fatal(1,"expected %s got %s",expected,last_line);
   repeat(300)@(negedge clk);
   if(lines!=before_lines+1 || dut.query_busy)$fatal(1,"query repeats or never releases busy");
  end
 endtask
 task automatic fault(input integer command,input integer mode,input string expected);
  begin card.failure_command=command;card.failure_mode=mode;query(expected);card.failure_command=-1;card.failure_mode=0;end
 endtask
 integer before_cmd0,before_cmd55,before_cmd13;
 initial begin
  repeat(20)@(negedge clk);rst_n=1;
  fault(55,1,"TF:INIT_FAIL CMD=55 ERR=TIMEOUT");
  query("TF:INIT_OK");
  if(dut.host.capacity_mb!=1888 || dut.host.high_capacity || !card.block_length_set || !card.four_bit)
   $fatal(1,"real SDSC initialization incomplete");
  before_cmd0=card.command_count[0];before_cmd13=card.command_count[13];
  query("TF:INIT_OK");
  if(card.command_count[0]!=before_cmd0 || card.command_count[13]!=before_cmd13+1)
   $fatal(1,"repeat i discarded initialized SD session");
  fault(13,4,"TF:INIT_FAIL CMD=13 ERR=STATUS");
  fault(9,2,"TF:INIT_FAIL CMD=09 ERR=CRC");
  card.cmd8_supported=1;before_cmd55=card.command_count[55];
  fault(8,2,"TF:INIT_FAIL CMD=08 ERR=CRC");
  if(card.command_count[55]!=before_cmd55)$fatal(1,"CRC failure mistaken for legacy CMD8");
  fault(8,5,"TF:INIT_FAIL CMD=08 ERR=ECHO");
  fault(55,3,"TF:INIT_FAIL CMD=55 ERR=FRAME");
  fault(55,4,"TF:INIT_FAIL CMD=55 ERR=STATUS");
  card.voltage_supported=0;query("TF:INIT_FAIL CMD=41 ERR=VOLTAGE");card.voltage_supported=1;
  card.stay_busy=1;query("TF:INIT_FAIL CMD=41 ERR=INIT_TIMEOUT");card.stay_busy=0;
  card.select_busy=1;query("TF:INIT_FAIL CMD=07 ERR=BUSY_TIMEOUT");card.select_busy=0;
  card.csd[127:126]=2;query("TF:INIT_FAIL CMD=09 ERR=CSD");
  card.csd=128'h002F00325F5A83AFEDB7FFBF96800011;
  card.cmd8_supported=0;card.cmd8_illegal=1;
  query("TF:INIT_OK");
  if(dut.host.capacity_mb!=1888 || dut.host.high_capacity)$fatal(1,"illegal CMD8 SDSC fallback wrong");
  $display("PASS strict native init gaps + 1888MB SDSC + CMD8 timeout/illegal/CRC + precise one-shot UART errors + recovery");
  $finish;
 end
 initial begin #100000000;$fatal(1,"initialization regression timeout");end
endmodule

// Intentionally violate the interval: the independent card model must reject
// the next command. The test runner expects this specific $fatal, not PASS.
module photo_sd4_gap_negative_tb;
 photo_sd4_init_tb scenario();
 defparam scenario.dut.host.cmd.RESPONSE_GAP_CLOCKS=1;
endmodule

module sd4_poll_timeout_tb;
 reg clk=0,rst_n=0,start=0;
 always #5 clk=~clk;
 wire sdclk,cmdo,cmdoe,cmdi,init_done,init_error;
 wire [3:0] dato,datoe,dati,reason;wire [5:0] command;
 sd4_host #(.INIT_DIV(4),.FAST_DIV(4),.POWER_CYCLES(16),.INIT_TIMEOUT(2000)) dut(
  .clk(clk),.rst_n(rst_n),.sd_clk(sdclk),.sd_cmd_o(cmdo),.sd_cmd_oe(cmdoe),.sd_cmd_i(cmdi),
  .sd_dat_i(dati),.sd_dat_o(dato),.sd_dat_oe(datoe),.init_start(start),.init_busy(),
  .init_done(init_done),.init_error(init_error),.error_command(command),.error_reason(reason),
  .high_capacity(),.initialized(),.capacity_mb(),.block_start(1'b0),.block_write(1'b0),.block_lba(32'd0),
  .block_busy(),.block_done(),.block_error(),.block_rx_valid(),.block_rx_data(),.block_byte_index(),.block_tx_byte(8'd0));
 sd4_card_model_tb card(sdclk,cmdo,cmdoe,cmdi,dato,datoe,dati,1'b0,1'b0);
 initial begin
  card.stay_busy=1;
  repeat(20)@(negedge clk);rst_n=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(init_error);
  if(init_done || command!=41 || reason!=6 || card.acmd_attempts>=8192 || dut.acmd_timer!=2000)
   $fatal(1,"ACMD41 did not use elapsed-time deadline");
  $display("PASS ACMD41 elapsed-time timeout before retry limit");$finish;
 end
 initial begin #1000000;$fatal(1,"ACMD41 timeout test stalled");end
endmodule
