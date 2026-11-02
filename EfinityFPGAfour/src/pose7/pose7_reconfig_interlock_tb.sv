`timescale 1ns/1ps
module pose7_reconfig_interlock_tb;
reg clk=0,pclk=0,rst_n=0,stop_=0,rv=0,mv=0;always #5 clk=~clk;always #3.367 pclk=~pclk;
reg [7:0] rx=0;reg [4:0] ma=16;wire idle_;wire [31:0] aw,ar;wire av,wv,arv;wire [7:0] reply;
`ifdef POSE7_LATEST_CANDIDATE
image7_ft_link_latest #(
`elsif POSE7_PERF_CANDIDATE
image7_ft_link_fast #(
`else
image7_ft_link #(
`endif
.AUTO_BOOT(0),.MENU_ENABLE(1),.MULTIBOOT_ENABLE(1)) dut(
 .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(1'b0),.mode(2'd0),.resolution(2'd0),.edge_packed(1'b1),.txe_n_async(1'b1),
 .gray_vs(1'b0),.gray_de(1'b0),.gray_pixel(8'd0),.edge_vs(1'b0),.edge_de(1'b0),.edge_pixel(8'd0),
 .uart_rx_data(rx),.uart_rx_valid(rv),.uart_legacy_valid(),.uart_tx_valid(),.uart_tx_data(reply),.uart_tx_accept(1'b1),.uart_tx_last(),
 .menu_write_valid(mv),.menu_write_addr(ma),.menu_write_value(12'd0),.menu_status(),.stop_for_reconfig(stop_),.reconfig_idle(idle_),
 .video_diagnostic_data(384'd0),.ddr_ready(1'b1),.sd_clk(),.sd_cmd_o(),.sd_cmd_oe(),.sd_cmd_i(1'b1),
 .sd_dat_i(4'hf),.sd_dat_o(),.sd_dat_oe(),.result_strobe(),.result_points(),.result_valid(),.boot_status(),.boot_error(),
 .link_ready(),.stopped(),.data_o(),.data_oe(),.wr_n(),.wr_oe(),.awaddr(aw),.awlen(),.awvalid(av),.awready(1'b0),
 .wdata(),.wlast(),.wvalid(wv),.wready(1'b0),.bvalid(1'b0),.bresp(2'd0),.araddr(ar),.arlen(),.arvalid(arv),.arready(1'b0),
 .rdata(128'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0),.rready());
task send_(input [7:0] b);
 begin @(negedge clk);rx=b;rv=1;@(negedge clk);rv=0;repeat(4)@(negedge clk);end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;repeat(10)@(negedge clk);
 force dut.boot_state=3;force dut.u_loader.input_ready=1;
 if(!dut.u_loader.can_load)$fatal(1,"test precondition: idle manual loader must be available");
 send_("~");send_("6");send_("I");
 if(!dut.loader_busy||idle_)$fatal(1,"partial upload must inhibit Flash reconfiguration");
 stop_=1;repeat(5)@(negedge clk);
 if(dut.u_loader.can_load||dut.infer_enable||dut.model_enabled||idle_)$fatal(1,"stop did not block upload/inference");
 mv=1;send_("~");send_("6");send_("T");mv=0;
 if(dut.test_start||dut.menu_check_state!=0||dut.state!=0||av||wv||arv)$fatal(1,"new work entered while switch pending");
 force dut.u_loader.timer=95999999;repeat(8)@(negedge clk);release dut.u_loader.timer;repeat(8)@(negedge clk);
 if(!idle_||dut.loader_busy)$fatal(1,"abandoned upload timeout did not release safe switch");
 force dut.diagnostic_busy=1;#1;if(idle_)$fatal(1,"diagnostic must finish");release dut.diagnostic_busy;
 force dut.debug_busy=1;#1;if(idle_)$fatal(1,"debug reply must finish");release dut.debug_busy;
 force dut.menu_check_state=1;#1;if(idle_)$fatal(1,"pending SD recheck must finish");
 force dut.menu_check_state=0;repeat(2)@(negedge clk);release dut.menu_check_state;
 send_("~");send_("6");send_("T");repeat(10)@(negedge clk);
 if(dut.test_start||dut.state!=0||av||wv||arv||!idle_)$fatal(1,"stopped UART bypassed reconfiguration interlock");
 $display("PASS image7 reconfiguration interlocks: actual partial upload, ignored new UART/menu work, watchdog release, pending SD check and diagnostic/debug ownership");$finish;
end
initial begin #100000;$fatal(1,"interlock test timeout");end
endmodule
