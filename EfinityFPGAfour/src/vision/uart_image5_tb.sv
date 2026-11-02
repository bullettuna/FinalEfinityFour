`timescale 1ns/1ps
module uart_image5_tb;
reg clk=0,rst_n=0,rx_valid=0,tx_done=0;reg [7:0] rx_data=0;
always #5 clk=~clk;
wire tx_start,median,cleanup,freeze,diagnostic,shape,capture,split;wire [7:0] tx_data;
wire [1:0] mode;wire [10:0] high,low;
uart_vision_ctrl #(.EDGE_TEST_PROFILE(1),.PERSON_AVAILABLE(0),.PHOTO_AVAILABLE(0),
 .SOBEL_AVAILABLE(0),.SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SPLIT_AVAILABLE(0),
 .DEFAULT_VIDEO_MODE(2),.DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30),
 .DEFAULT_MEDIAN_ENABLE(1),.DEFAULT_GRAY_CANNY_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(tx_done),.tx_start(tx_start),.tx_data(tx_data),
 .video_mode_req(mode),.edge_threshold_req(high),.canny_low_threshold_req(low),
 .median_enable_req(median),.edge_cleanup_req(cleanup),.freeze_req(freeze),.diagnostic_pattern_req(diagnostic),
 .shape_enable_req(shape),.photo_capture_req(capture),.split_enable_req(split),
 .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
 .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0));
task send(input [7:0] command,reply,input bit respond);
 begin
 @(negedge clk);rx_data=command;rx_valid=1;@(posedge clk);#1;
 if(tx_start!==respond||(respond&&tx_data!==reply))$fatal(1,"image5 command %h got %b/%h want %b/%h",command,tx_start,tx_data,respond,reply);
 if(shape||capture||split)$fatal(1,"removed hardware emitted request");
 @(negedge clk);rx_valid=0;tx_done=respond;@(negedge clk);tx_done=0;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;@(negedge clk);
 if(mode!=2||high!=60||low!=30||!median||!cleanup||freeze||diagnostic)$fatal(1,"image5 defaults");
 send("V","5",1);send("C","0",1);send("G","1",1);send("E","2",1);
 send("T","0",1);send("T","1",1);send("T","2",1);send("?","2",1);
 send("M","0",1);if(median)$fatal(1,"M off");send("M","1",1);
 send("D","0",1);if(cleanup)$fatal(1,"D off");send("d","1",1);if(!cleanup)$fatal(1,"D on");
 send("H",0,0);send("9",0,0);send("0",0,0);send(13,"K",1);send(10,0,0);
 send("L",0,0);send("3",0,0);send("5",0,0);send(13,"K",1);
 if(high!=90||low!=35)$fatal(1,"H/L setting");
 send("+","+",1);send("-","-",1);if(high!=90||low!=35)$fatal(1,"threshold steps");
 send("R","R",1);if(high!=60||low!=30)$fatal(1,"threshold reset");
 send("F","1",1);send("F","0",1);send("Z","1",1);send("Z","0",1);
 send("U","!",1);send("N",0,0);send("3",0,0);send(13,"!",1);
 if(high!=60||low!=30)$fatal(1,"unsupported pose command leaked threshold digits");
 send("b","!",1);send("O","!",1);send("|","!",1);
 // White-balance WD must not toggle the image5 D filter.
 send("W",0,0);send("D","W",1);if(!cleanup)$fatal(1,"WD toggled cleanup");
 repeat(120)begin @(posedge clk);#1;if(tx_start)$fatal(1,"unsolicited serial spam");end
 $display("PASS image5 UART: V=5, default E/60/30, M/D, C/G/E/T, H/L/R, F/Z, rejected removed modes, no unsolicited output");$finish;
end
initial begin #100000;$fatal(1,"image5 UART timeout");end
endmodule
