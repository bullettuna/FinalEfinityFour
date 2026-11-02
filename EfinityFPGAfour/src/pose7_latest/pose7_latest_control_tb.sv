`timescale 1ns/1ps
module pose7_latest_control_tb;
 reg clk=0,pclk=0,rst_n=0,rv=0;reg [7:0] rx=0;always #5 clk=~clk;always #3 pclk=~pclk;
 wire legacy_rx,ready,stopped,config_idle,run_;wire [1:0] mode,res;wire packed_;
 wire reply_start;wire [7:0] reply;integer replies=0;reg [7:0] last_reply;
 ft_uart_control ctrl(.clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(legacy_rx),.link_ready(ready),.link_stopped(stopped),
  .legacy_rx_valid(),.legacy_start(1'b0),.legacy_data(8'd0),.command_done(reply_start),.legacy_done(),.command_start(reply_start),.command_data(reply),
  .mode(mode),.resolution(res),.edge_packed(packed_),.run_n(run_),.adc_query_ready(1'b0),.adc_query());
 image7_ft_link_latest #(.AUTO_BOOT(1),.MENU_ENABLE(1),.MULTIBOOT_ENABLE(1)) dut(
  .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(run_),.mode(mode),.resolution(res),.edge_packed(packed_),.txe_n_async(1'b1),
  .gray_vs(1'b0),.gray_de(1'b0),.gray_pixel(8'd0),.edge_vs(1'b0),.edge_de(1'b0),.edge_pixel(8'd0),
  .uart_rx_data(rx),.uart_rx_valid(rv),.uart_legacy_valid(legacy_rx),.uart_tx_last(),.uart_tx_valid(),.uart_tx_data(),.uart_tx_accept(1'b1),
  .stop_for_reconfig(1'b0),.reconfig_idle(config_idle),.menu_write_valid(1'b0),.menu_write_addr(5'd0),.menu_write_value(12'd0),.menu_status(),
  .video_diagnostic_data(384'd0),.ddr_ready(1'b1),.sd_clk(),.sd_cmd_o(),.sd_cmd_oe(),.sd_cmd_i(1'b1),.sd_dat_i(4'hf),.sd_dat_o(),.sd_dat_oe(),
  .result_strobe(),.result_points(),.result_valid(),.boot_status(),.boot_error(),.link_ready(ready),.stopped(stopped),
  .data_o(),.data_oe(),.wr_n(),.wr_oe(),.awaddr(),.awlen(),.awvalid(),.awready(1'b0),.wdata(),.wlast(),.wvalid(),.wready(1'b0),.bvalid(1'b0),.bresp(2'd0),
  .araddr(),.arlen(),.arvalid(),.arready(1'b0),.rdata(128'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0),.rready());
 always @(posedge clk)if(reply_start)begin replies<=replies+1;last_reply<=reply;end
 task send(input [7:0] c);
  begin @(negedge clk);rx=c;rv=1;@(negedge clk);rv=0;repeat(5)@(negedge clk);end
 endtask
 task expect_reply(input integer previous,input [7:0] wanted);
  begin
   repeat(100)@(negedge clk);
   if(replies!=previous+1||last_reply!==wanted)$fatal(1,"USB setting stuck/misrouted while autonomous model runs");
   if(config_idle||!dut.model_enabled||!dut.infer_enable)$fatal(1,"USB setting stopped model or relaxed Flash drain");
  end
 endtask
 integer before_;
 initial begin
  #50;rst_n=1;
  force dut.boot_state=3;force dut.auto_run=1;force dut.model_enabled=1;force dut.state=4;force dut.point_available=0;
  repeat(30)@(negedge clk);
  before_=replies;send("!");send("3");expect_reply(before_,"3");if(mode!=3)$fatal(1,"USB mode not committed");
  before_=replies;send("!");send("5");expect_reply(before_,"5");if(res!=1)$fatal(1,"USB size not committed");
  force dut.point_available=1;force dut.tx_stopped=0;before_=replies;send("!");send("0");
  repeat(50)@(negedge clk);if(replies!=before_)$fatal(1,"USB mode cut an in-flight immutable packet");
  force dut.point_available=0;release dut.tx_stopped;expect_reply(before_,"0");
  if(mode!=0)$fatal(1,"USB stop not committed");
  $display("PASS latest USB control: actual UART loader and FT prefix controller change mode/size/stop during autonomous inference, wait for owned packet, preserve model and strict Flash drain");$finish;
 end
 initial begin #100000;$fatal(1,"USB control timeout");end
endmodule
