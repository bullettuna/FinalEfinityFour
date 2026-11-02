`timescale 1ns/1ps
`include "src/stable_ui/image7_menu_defs.vh"
module stable_menu_control_tb;
 reg clk=0,pclk=0,rst_n=0,prst_n=0,vs=1,short_=0,long_=0,event_=0;reg [1:0] key=0;
 always #5 clk=~clk;always #3.367 pclk=~pclk;
 reg [15:0] status=16'h003f;reg [7:0] feedback=0;
 wire [153:0] disp,active;wire valid;wire [4:0] addr;integer writes=0;reg [4:0] last_addr;
 stable_menu_ctrl7 c(.clk(clk),.rst_n(rst_n),.boot_selected(2'd0),.boot_status(4'd0),.check_feedback(feedback),
  .key1_short(short_),.key1_long(long_),.key_event(event_),.key_code(key),.knob_value(12'd2048),.knob_sample(1'b0),
  .cur_view(2'd0),.cur_infer(1'b1),.cur_skeleton(1'b1),.cur_freeze(1'b0),.cur_test(1'b0),.cur_median(1'b1),.cur_gamma(1'b1),
  .cur_high(11'd23),.cur_low(11'd11),.cur_wb_r(11'd496),.cur_wb_g(11'd416),.cur_wb_b(11'd313),.cur_gamma_p(9'd255),.cur_black(8'd96),.status(status),
  .menu_open(),.write_valid(valid),.write_addr(addr),.write_value(),.disp(disp));
 image7_menu_cdc #(.WIDTH(154)) cdc(clk,rst_n,pclk,prst_n,vs,disp,active);
 always @(posedge clk)if(valid)begin writes<=writes+1;last_addr<=addr;end
 task pulse(input integer which);
  begin @(negedge clk);case(which)0:long_=1;1:short_=1;2:begin event_=1;key=2;end endcase
   @(negedge clk);long_=0;short_=0;event_=0;key=0;repeat(5)@(negedge clk);end
 endtask
 task commit;
  begin #300;vs=0;#300;vs=1;#300;vs=0;#300;vs=1;end
 endtask
 initial begin
  #60;rst_n=1;prst_n=1;#300;
  if(disp[`M7_MD_HIGH_OFF+:16]!=16'h0023||disp[`M7_MD_LOW_OFF+:16]!=16'h0011||disp[`M7_MD_WBR_OFF+:16]!=16'h0496||disp[`M7_MD_WBG_OFF+:16]!=16'h0416||disp[`M7_MD_WBB_OFF+:16]!=16'h0313||disp[`M7_MD_GAMMA_OFF+:12]!=12'h255)$fatal(1,"effective settings displayed incorrectly");
  pulse(0);for(integer i=0;i<16;i=i+1)pulse(2);pulse(1);
  if(writes!=1||last_addr!=16)$fatal(1,"SD CHECK key not connected to action");
  feedback=8'h12;status=16'h0080;commit();
  if(active[`M7_MD_CHECK_OFF+:8]!=8'h12||!active[`M7_MD_STATUS_OFF+7])$fatal(1,"accepted WAIT feedback lost at CDC");
  feedback=8'h14;status=16'h0403;#300;
  if(active[`M7_MD_CHECK_OFF+:8]!=8'h12)$fatal(1,"feedback tore during active frame");
  commit();if(active[`M7_MD_CHECK_OFF+:8]!=8'h14)$fatal(1,"SD PASS sequence not committed");
  pulse(2);pulse(1);if(writes!=2||last_addr!=17)$fatal(1,"BIN CHECK key not connected to action");
  feedback=8'h2e;commit();if(active[`M7_MD_CHECK_OFF+:8]!=8'h2e||active[`M7_MD_STATUS_OFF+:16]!=16'h0403)$fatal(1,"BIN FAIL E04 sequence lost");
  feedback=8'h3c;status=16'h003f;commit();repeat(100)@(negedge clk);
  if(active[`M7_MD_CHECK_OFF+:8]!=8'h3c)$fatal(1,"completion did not persist");
  $display("PASS stable menu control: real SD/BIN key actions, effective H23/L11/WB/Gamma, all 154 CDC bits, WAIT/PASS/FAIL E04 sequence and persistent completion");$finish;
 end
 initial begin #100000;$fatal(1,"stable menu control timeout");end
endmodule
