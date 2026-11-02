`timescale 1ns/1ps
module ft_uart_vision_tb;
 reg clk=0,rst_n=0,valid=0,done=0;reg [7:0] rx=0;
 wire lv,ls,ld,start,run_n;wire [7:0] data,legacy_data;
 wire [1:0] video,mode;wire [10:0] high,low;wire median,cleanup;
 always #5 clk=~clk;
 ft_uart_control bridge(.clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(valid),.link_ready(1'b1),.link_stopped(1'b1),
  .legacy_rx_valid(lv),.legacy_start(ls),.legacy_data(legacy_data),.command_done(done),.legacy_done(ld),
  .command_start(start),.command_data(data),.mode(mode),.run_n(run_n));
 uart_vision_ctrl #(.EDGE_TEST_PROFILE(1),.PERSON_AVAILABLE(0),.PHOTO_AVAILABLE(0),.SOBEL_AVAILABLE(0),
  .SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SPLIT_AVAILABLE(0),.DEFAULT_VIDEO_MODE(2),
  .DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30),.DEFAULT_MEDIAN_ENABLE(1)) legacy(
  .clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(lv),.tx_done(ld),.tx_start(ls),.tx_data(legacy_data),
  .video_mode_req(video),.edge_threshold_req(high),.canny_low_threshold_req(low),.median_enable_req(median),.edge_cleanup_req(cleanup),
  .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
  .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0));
 task send(input [7:0] c,input bit reply,input [7:0] expected);
  integer waited;reg seen;
  begin
   @(negedge clk);rx=c;valid=1;@(posedge clk);@(negedge clk);valid=0;seen=0;
   for(waited=0;waited<(reply?20:5);waited=waited+1)begin
    @(posedge clk);#1;
    if(start)begin if(!reply||data!==expected)$fatal(1,"integrated UART %h got %h",c,data);seen=1;waited=20;end
   end
   if(reply&&!seen)$fatal(1,"missing integrated UART reply %h",c);
   if(reply)begin repeat(2)@(negedge clk);done=1;@(negedge clk);done=0;end
   repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  send("V",1,"5");send("!",0,0);send("V",1,"A");
  send("!",0,0);send("1",1,"1");repeat(40)@(negedge clk);
  send("C",1,"0");send("G",1,"1");send("E",1,"2");
  send("M",1,"0");send("D",1,"0");
  send("H",0,0);send("9",0,0);send("0",0,0);send(13,1,"K");
  send("L",0,0);send("3",0,0);send("5",0,0);send(13,1,"K");
  if(high!=90||low!=35||video!=2||median||cleanup||mode!=1)$fatal(1,"FT prefix altered existing Canny controls");
  send("!",0,0);send("0",1,"0");send("R",1,"R");
  if(high!=60||low!=30||run_n)$fatal(1,"stop/reset isolation failed");
  // A queued FT reply must not steal completion of a legacy byte.
  @(negedge clk);rx="C";valid=1;@(negedge clk);valid=0;
  wait(start);#1;if(data!="0")$fatal(1,"legacy ownership setup");
  @(negedge clk);rx="!";valid=1;@(negedge clk);valid=0;
  @(negedge clk);rx="V";valid=1;@(negedge clk);valid=0;
  repeat(8)@(negedge clk);done=1;#1;if(!ld)$fatal(1,"FT queued reply stole legacy completion");
  @(negedge clk);done=0;wait(start);#1;if(data!="A")$fatal(1,"queued FT response missing");
  repeat(3)@(negedge clk);done=1;#1;if(ld)$fatal(1,"FT completion leaked to legacy controller");
  @(negedge clk);done=0;repeat(4)@(negedge clk);
  send("G",1,"1");
  repeat(2000)begin @(posedge clk);#1;if(start)$fatal(1,"unsolicited serial output");end
  $display("PASS combined FT + actual image5 UART: V/!V, C/G/E/M/D/H/L/R retained, control ownership and numeric isolation, no spam");$finish;
 end
endmodule
