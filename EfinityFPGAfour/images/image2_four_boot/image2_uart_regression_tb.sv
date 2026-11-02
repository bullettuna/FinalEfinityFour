`timescale 1ns/1ps
module image2_uart_regression_tb;
 reg clk=0,rst_n=0,rx_valid=0,tx_done=0;reg [7:0] rx_data=0;
 always #5 clk=~clk;
 wire [7:0] tx_data;wire tx_start,photo,del,median,uart_photo;wire [1:0] mode,clean;wire [10:0] minimum,high,low;
 image2_vision_ctrl #(.PHOTO_EDGE_PROFILE(1),.VISION_AVAILABLE(1),.PHOTO_AVAILABLE(1),.SHAPE_AVAILABLE(0),
 .OVERLAY_AVAILABLE(0),.SOBEL_AVAILABLE(0),.DEFAULT_VIDEO_MODE(0),.DEFAULT_MEDIAN_ENABLE(1),
 .DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30)) dut(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(tx_done),.tx_data(tx_data),.tx_start(tx_start),
  .video_mode_req(mode),.edge_threshold_req(high),.canny_low_threshold_req(low),.median_enable_req(median),
  .photo_cleanup_level_req(clean),.photo_min_pixels_req(minimum),.photo_capture_req(photo),.photo_uart_req(uart_photo),.photo_delete_req(del),
  .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
  .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0));
 integer photos=0,deletes=0,replies=0,uart_photos=0;reg [7:0] last_reply;
 always @(posedge clk)begin
  tx_done<=tx_start;
  if(tx_start)begin replies<=replies+1;last_reply<=tx_data;end
  if(uart_photo)uart_photos<=uart_photos+1;
  if(photo)photos<=photos+1;if(del)deletes<=deletes+1;
 end
 task send(input [7:0] c);@(negedge clk);rx_data=c;rx_valid=1;@(negedge clk);rx_valid=0;repeat(6)@(negedge clk);endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  send("V");if(last_reply!="2")$fatal(1,"profile");
  send(":");if(last_reply!="U")$fatal(1,"UART-export capability");
  send("G");send("E");if(mode!=2)$fatal(1,"edge mode");
  send("@");if(uart_photos!=1)$fatal(1,"UART capture edge");
  send("T");if(mode!=0)$fatal(1,"three-mode cycle");
  send("@");if(uart_photos!=1||last_reply!="!")$fatal(1,"UART capture color rejected");
  send("W");send("@");if(uart_photos!=1)$fatal(1,"WB scope UART capture");send(13);
  send("M");if(median)$fatal(1,"median");
  send("D");if(clean!=2)$fatal(1,"cleanup strong");
  send("D");if(clean!=0)$fatal(1,"cleanup off");
  send("d");if(deletes!=1||clean!=0)$fatal(1,"lower d deletion scope");
  send("W");send("D");if(clean!=0||deletes!=1)$fatal(1,"WD collision");
  send("N");send("4");send("8");send(13);if(minimum!=48||high!=60)$fatal(1,"N minimum scope");
  send("H");send("9");send("0");send(13);send("L");send("4");send("5");send(13);
  if(high!=90||low!=45)$fatal(1,"thresholds");
  send("b");if(photos!=1)$fatal(1,"capture command");
  send("W");send("b");send("2");send("5");send("6");send(13);if(photos!=1)$fatal(1,"WB collision");
  send("R");if(high!=60||low!=30||minimum!=48||clean!=0)$fatal(1,"R only thresholds");
  $display("PASS image2 C/G/E, M, D cleanup, N area, H/L/R, lowercase delete, WB/WD and photo command scopes");$finish;
 end
endmodule
