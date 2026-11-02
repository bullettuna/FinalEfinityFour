`timescale 1ns/1ps
module image5_inputs_tb;
 reg clk=0,rst_n=0,key_n=1,rx_valid=0,sample_valid=0,sample_channel=0;
 reg [7:0] rx_data=0;reg [11:0] sample_data=0;
 always #5 clk=~clk;
 wire [11:0] raw0,raw1,knob,key_voltage;
 wire knob_ready,key_event;wire [1:0] key_code;
 wire query,query_ready,lv,ls,ld,cmd_start,cmd_done,run_n;
 wire [7:0] legacy_data,cmd_data;
 wire [10:0] high,low;
 wire av,al,aa,ad,kv,kl,ka,kd,phy_start,phy_done,serial_tx;
 wire [7:0] abyte,kbyte,phy_data;
 adc_input_ctrl #(.DEBOUNCE_SAMPLES(3)) inputs(
  .clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.sample_channel(sample_channel),.sample_data(sample_data),
  .raw_ch0(raw0),.raw_ch1(raw1),.knob_value(knob),.knob_ready(knob_ready),.knob_sample(),
  .key_voltage(key_voltage),.key_event(key_event),.key_code(key_code));
 image5_adc_uart report(.clk(clk),.rst_n(rst_n),.query(query),.query_ready(query_ready),
  .raw_ch0(raw0),.raw_ch1(raw1),.knob_value(knob),.key_voltage(key_voltage),.knob_ready(knob_ready),
  .key_event(key_event),.key_code(key_code),.tx_valid(av),.tx_data(abyte),.tx_last(al),.tx_accept(aa),.tx_done(ad));
 key_uart_reporter #(.DEBOUNCE_CYCLES(8)) gpio_key(.clk(clk),.rst_n(rst_n),.key_n(key_n),
  .tx_valid(kv),.tx_data(kbyte),.tx_last(kl),.tx_accept(ka),.tx_done(kd));
 ft_uart_control #(.ADC_QUERY_AVAILABLE(1)) bridge(.clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),
  .link_ready(1'b1),.link_stopped(1'b1),.legacy_rx_valid(lv),.legacy_start(ls),.legacy_data(legacy_data),
  .command_done(cmd_done),.legacy_done(ld),.command_start(cmd_start),.command_data(cmd_data),
  .mode(),.resolution(),.edge_packed(),.run_n(run_n),.adc_query_ready(query_ready),.adc_query(query));
 uart_vision_ctrl #(.EDGE_TEST_PROFILE(1),.PERSON_AVAILABLE(0),.PHOTO_AVAILABLE(0),.SOBEL_AVAILABLE(0),
  .SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SPLIT_AVAILABLE(0),.DEFAULT_VIDEO_MODE(2),
  .DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30)) legacy(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(lv),.tx_done(ld),.tx_start(ls),.tx_data(legacy_data),
  .edge_threshold_req(high),.canny_low_threshold_req(low),
  .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
  .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0));
 uart_tx_arbiter arb(.clk(clk),.rst_n(rst_n),.cmd_tx_start(cmd_start),.cmd_tx_data(cmd_data),.cmd_tx_done(cmd_done),
  .msg_tx_valid(1'b0),.msg_tx_data(8'd0),.msg_tx_last(1'b0),.msg_tx_accept(),.msg_tx_done(),
  .msg2_tx_valid(1'b0),.msg2_tx_data(8'd0),.msg2_tx_last(1'b0),.msg2_tx_accept(),.msg2_tx_done(),
  .msg3_tx_valid(kv),.msg3_tx_data(kbyte),.msg3_tx_last(kl),.msg3_tx_accept(ka),.msg3_tx_done(kd),
  .msg4_tx_valid(av),.msg4_tx_data(abyte),.msg4_tx_last(al),.msg4_tx_accept(aa),.msg4_tx_done(ad),
  .uart_tx_done(phy_done),.uart_tx_data(phy_data),.uart_tx_start(phy_start));
 uart_transfer phy(.clk(clk),.rst_n(rst_n),.clken_16bps(1'b1),.txd(serial_tx),
  .txd_en(phy_start),.txd_data(phy_data),.txd_flag(phy_done));
 string lines[0:31],current="";
 integer line_count=0,commands=0,busy_replies=0,k1=0,k2=0,k3=0,k23=0,i;
 reg [7:0] decoded;
 initial forever begin
  @(negedge serial_tx);
  if(rst_n)begin
   repeat(24)@(posedge clk);#1;
   for(integer bitn=0;bitn<8;bitn=bitn+1)begin
    decoded[bitn]=serial_tx;repeat(16)@(posedge clk);#1;
   end
   if(serial_tx!==1)$fatal(1,"Bad UART stop bit");
   if(current==""&&(decoded=="5"||decoded=="B"))begin
    if(decoded=="B")busy_replies++;else commands++;
   end else if(decoded==10)begin
    lines[line_count]=current;line_count++;current="";
   end else if(decoded!=13)current=$sformatf("%s%c",current,decoded);
  end
 end
 task send(input [7:0] c);
  @(negedge clk);rx_data=c;rx_valid=1;@(negedge clk);rx_valid=0;repeat(8)@(negedge clk);
 endtask
 task ask;
  send("!");send("A");
 endtask
 task sample(input bit channel,input [11:0] value);
  @(negedge clk);sample_channel=channel;sample_data=value;sample_valid=1;
  @(negedge clk);sample_valid=0;repeat(3)@(negedge clk);
 endtask
 task samples(input [11:0] value,input integer count);
  for(integer j=0;j<count;j++)begin sample(0,12'hABC);sample(1,value);end
 endtask
 task await_lines(input integer count);
  integer wd=0;
  while(line_count<count&&wd<120000)begin @(negedge clk);wd++;end
  if(line_count!=count)$fatal(1,"Input UART timeout %0d/%0d",line_count,count);
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(1000)@(negedge clk);
  if(line_count||commands||current!=""||high!=60||low!=30)$fatal(1,"Power-on output or wrong defaults");
  ask();await_lines(1);
  if(lines[0]!="adc0=0x000 adc1=0x000 knob=0x000 key=0x000 ready=0")$fatal(1,"Unready snapshot: %s",lines[0]);
  samples(12'hFFF,12);
  if(!knob_ready||knob!=12'hABC||key_voltage!=12'hFFF)$fatal(1,"ADC warmup");
  ask();wait(report.status_active);
  // Change live inputs while the first snapshot is still physically sending.
  sample(0,12'h123);sample(1,12'h800);
  key_n=0;send("V");samples(12'h800,8);
  await_lines(4);
  if(lines[1]!="adc0=0xABC adc1=0xFFF knob=0xABC key=0xFFF ready=1")$fatal(1,"Torn snapshot: %s",lines[1]);
  repeat(10000)@(negedge clk);
  if(line_count!=4||commands!=1)$fatal(1,"Held key repeated or command missing");
  for(i=2;i<4;i++)begin
   if(lines[i]=="key  1")k1++;
   else if(lines[i]=="key  2")k2++;
   else $fatal(1,"Wrong key line %s",lines[i]);
  end
  if(k1!=1||k2!=1)$fatal(1,"Key line loss");
  // Changing a held single key into a combination must not retrigger.
  samples(12'h32E,8);repeat(5000)@(negedge clk);
  if(line_count!=4)$fatal(1,"Combination change retriggered");
  key_n=1;samples(12'hFFF,8);repeat(30)@(negedge clk);
  samples(12'h3F8,8);await_lines(5);
  if(lines[4]!="key  3")$fatal(1,"SW3 decode");
  samples(12'hFFF,8);samples(12'h32E,8);await_lines(6);
  if(lines[5]!="key  2+3")$fatal(1,"Combo decode");
  samples(12'hFFF,8);
  // Two accepted diagnostics (one active, one pending); third replies B.
  ask();wait(report.status_active);ask();ask();
  await_lines(8);repeat(1500)@(negedge clk);
  if(busy_replies!=1)$fatal(1,"Busy diagnostic query not rejected");
  sample(0,0);sample(0,4095);repeat(10000)@(negedge clk);
  if(line_count!=8||high!=60||low!=30)$fatal(1,"Knob changed thresholds or streamed ADC");
  $display("PASS image5 inputs actual UART: silent acquisition, snapshot ready/data, atomic diagnostics, bounded busy query, GPIO/ADC key queues, debounce/no-repeat, FT prefix isolation, fixed 60/30");
  $finish;
 end
 initial begin #6000000;$fatal(1,"Image5 input test watchdog");end
endmodule
