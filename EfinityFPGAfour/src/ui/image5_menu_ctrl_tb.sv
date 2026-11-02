`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"
module image5_menu_ctrl_tb;
 reg clk=0,rst_n=0,short_key=0,long_key=0,event_key=0,sample=0,ready=0,rx_valid=0,stopped=1;
 reg [1:0] code=0;reg [11:0] knob=2048;reg [7:0] rx=0;
 always #5 clk=~clk;
 wire open,wr,lv,ls,ld,cmd_start,run_n,packed_edge,busy;
 wire [4:0] addr;wire [11:0] value;wire [7:0] legacy_data,cmd_data;
 wire [1:0] view,mode,size;wire [10:0] high,low,wbr,wbg,wbb;wire [8:0] gamma_p;
 wire median,cleanup,freeze,test,gamma;
 wire [`M5_DISP_WIDTH-1:0] disp;
 reg manual=0;reg [4:0] manual_addr=0;reg [11:0] manual_value=0;
 wire write_valid=manual||wr;wire [4:0] write_addr=manual?manual_addr:addr;
 wire [11:0] write_value=manual?manual_value:value;
 reg done=0;integer replies=0;reg [7:0] last_reply;
 always @(posedge clk)begin
  done<=cmd_start;
  if(cmd_start)begin replies<=replies+1;last_reply<=cmd_data;end
 end
 image5_menu_ctrl dut(.clk(clk),.rst_n(rst_n),.key1_short(short_key),.key1_long(long_key),
  .key_event(event_key),.key_code(code),.knob_value(knob),.knob_sample(sample),.knob_ready(ready),
  .cur_view(view),.cur_median(median),.cur_cleanup(cleanup),.cur_freeze(freeze),.cur_test(test),.cur_gamma(gamma),
  .cur_high(high),.cur_low(low),.cur_wb_r(wbr),.cur_wb_g(wbg),.cur_wb_b(wbb),.cur_gamma_p(gamma_p),
  .cur_usb_mode(mode==3&&!packed_edge?3'd4:{1'b0,mode}),.cur_usb_size(size),.usb_busy(busy),.adc1(12'hfff),
  .menu_open(open),.write_valid(wr),.write_addr(addr),.write_value(value),.disp(disp));
 image5_menu_vision_ctrl #(.MENU_AVAILABLE(1),.EDGE_TEST_PROFILE(1),.PERSON_AVAILABLE(0),.PHOTO_AVAILABLE(0),
  .SOBEL_AVAILABLE(0),.SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SPLIT_AVAILABLE(0),
  .DEFAULT_VIDEO_MODE(2),.DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30),
  .DEFAULT_MEDIAN_ENABLE(1),.DEFAULT_GAMMA_ENABLE(1),.DEFAULT_GAMMA_STRENGTH(255),
  .DEFAULT_WB_RED_GAIN(496),.DEFAULT_WB_GREEN_GAIN(416),.DEFAULT_WB_BLUE_GAIN(313)) bank(
  .clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(lv),.tx_done(ld),.tx_start(ls),.tx_data(legacy_data),
  .menu_write_valid(write_valid),.menu_write_addr(write_addr),.menu_write_value(write_value),
  .video_mode_req(view),.edge_threshold_req(high),.canny_low_threshold_req(low),.median_enable_req(median),
  .edge_cleanup_req(cleanup),.freeze_req(freeze),.diagnostic_pattern_req(test),
  .wb_red_gain_req(wbr),.wb_green_gain_req(wbg),.wb_blue_gain_req(wbb),.gamma_enable_req(gamma),.gamma_strength_req(gamma_p),
  .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
  .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0));
 image5_ft_uart_control #(.MENU_AVAILABLE(1),.ADC_QUERY_AVAILABLE(1)) ft(
  .clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(rx_valid),.link_ready(1'b1),.link_stopped(stopped),
  .legacy_rx_valid(lv),.legacy_start(ls),.legacy_data(legacy_data),.command_done(done),.legacy_done(ld),
  .command_start(cmd_start),.command_data(cmd_data),.mode(mode),.resolution(size),.edge_packed(packed_edge),.run_n(run_n),
  .adc_query_ready(1'b1),.adc_query(),.menu_write_valid(write_valid),.menu_write_addr(write_addr),
  .menu_write_value(write_value),.configuration_busy(busy));
 task click;
  @(negedge clk);short_key=1;@(negedge clk);short_key=0;repeat(6)@(negedge clk);
 endtask
 task hold_key;
  @(negedge clk);long_key=1;@(negedge clk);long_key=0;repeat(6)@(negedge clk);
 endtask
 task key(input [1:0] which);
  @(negedge clk);code=which;event_key=1;@(negedge clk);event_key=0;repeat(6)@(negedge clk);
 endtask
 task adc(input [11:0] val);
  @(negedge clk);knob=val;sample=1;@(negedge clk);sample=0;repeat(3)@(negedge clk);
 endtask
 task settle;repeat(8)adc(knob);endtask
 task automatic nav(input [4:0] target);
  integer n=0;
  while(dut.cursor!=target&&n<20)begin key(2);n++;end
  if(dut.cursor!=target||dut.state!=`M5_BROWSE)$fatal(1,"Navigation %0d actual=%0d state=%0d",target,dut.cursor,dut.state);
  if(disp[`M5D_CURSOR+:5]<disp[`M5D_WINDOW+:5]||disp[`M5D_CURSOR+:5]>=disp[`M5D_WINDOW+:5]+8)
   $fatal(1,"Cursor outside window");
 endtask
 task send(input [7:0] c);
  @(negedge clk);rx=c;rx_valid=1;@(negedge clk);rx_valid=0;repeat(12)@(negedge clk);
 endtask
 task set_bank(input [4:0] a,input [11:0] v);
  @(negedge clk);manual_addr=a;manual_value=v;manual=1;
  @(negedge clk);manual=0;repeat(6)@(negedge clk);
 endtask
 integer prior;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;ready=1;
  repeat(12)adc(4095);
  if(open||high!=60||low!=30||wr)$fatal(1,"Power-on knob grabbed parameters");
  if(wbr!=496||wbg!=416||wbb!=313||!gamma||gamma_p!=255)$fatal(1,"Image1 color defaults");
  hold_key();if(!open||dut.state!=`M5_BROWSE)$fatal(1,"Long open");
  click();key(2);if(view!=1)$fatal(1,"VIEW edit");
  key(2);key(2);if(view!=0)$fatal(1,"VIEW lower bound");click();
  nav(`M5_MEDIAN);click();if(median)$fatal(1,"Median off");click();
  nav(`M5_CLEANUP);click();if(cleanup)$fatal(1,"Cleanup off");click();
  nav(`M5_FREEZE);click();if(!freeze)$fatal(1,"Freeze on");click();
  nav(`M5_TEST);click();if(!test)$fatal(1,"Test on");click();
  nav(`M5_CANNY);click();knob=2000;settle();key(1);
  if(high!=61||low!=30)$fatal(1,"Linked +1");
  adc(2016);if(high!=65||low!=32)$fatal(1,"Relative knob edit");
  adc(2015);if(high!=65)$fatal(1,"Knob deadband");
  send("H");send("1");send("0");send("0");send(13);key(1);
  if(high!=101||low!=50)$fatal(1,"Menu did not use live serial value");click();
  nav(`M5_CANNY_H);click();set_bank(`M5_CANNY_H,1);key(2);key(2);
  if(high!=0||low!=0)$fatal(1,"High/low zero clamp");click();
  nav(`M5_CANNY_RST);click();if(high!=60||low!=30)$fatal(1,"Threshold reset");
  nav(`M5_CANNY_L);click();set_bank(`M5_CANNY_L,60);key(1);
  if(low!=60)$fatal(1,"Low > high");key(2);if(low!=59)$fatal(1,"Low step");click();send("R");
  nav(`M5_WB_R);click();settle();key(2);if(wbr!=495)$fatal(1,"WB fine step");
  key(1);adc(knob+16);if(wbr!=500)$fatal(1,"WB knob step");click();
  nav(`M5_WB_RST);click();if(wbr!=496||wbg!=416||wbb!=313)$fatal(1,"WB reset");
  nav(`M5_GAMMA);click();if(gamma)$fatal(1,"Gamma off");click();
  nav(`M5_GAMMA_P);click();set_bank(`M5_GAMMA_P,256);key(1);if(gamma_p!=256)$fatal(1,"Gamma bound");
  key(2);if(gamma_p!=255)$fatal(1,"Gamma step");click();
  prior=replies;nav(`M5_USB_MODE);click();
  key(1);if(mode!=1)$fatal(1,"USB count");key(1);if(mode!=2)$fatal(1,"USB gray");
  key(1);if(mode!=3||!packed_edge)$fatal(1,"USB edge1");key(1);if(mode!=3||packed_edge)$fatal(1,"USB edge8");
  key(1);if(packed_edge)$fatal(1,"USB enum upper bound");click();
  nav(`M5_USB_SIZE);click();key(1);if(size!=1)$fatal(1,"USB 640");
  stopped=0;key(1);repeat(20)@(negedge clk);
  if(!busy||size!=1||run_n)$fatal(1,"USB size changed before safe stop");
  key(2);stopped=1;repeat(10)@(negedge clk);if(busy||size!=2)$fatal(1,"USB 1920 commit");click();
  nav(`M5_USB_STOP);click();if(mode!=0||run_n)$fatal(1,"USB stop");
  if(replies!=prior)$fatal(1,"Menu emitted unsolicited serial replies");
  send("!");send("5");if(size!=1||last_reply!="5")$fatal(1,"Serial USB control lost");
  send("!");send("M");if(last_reply!="1")$fatal(1,"Menu capability query");
  nav(`M5_ADC);click();if(dut.state!=`M5_BROWSE)$fatal(1,"ADC readonly");
  hold_key();repeat(12)adc(0);if(open||high!=60||low!=30)$fatal(1,"Menu close/knob isolation");
  $display("PASS image5 menu: 19 items, browse/edit/key/knob, deadband/settle, live UART bank, clamps/defaults, silent USB changes with drain/busy, readonly ADC, closed-knob isolation");
  $finish;
 end
 initial begin #3000000;$fatal(1,"Menu controller watchdog");end
endmodule
