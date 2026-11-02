`timescale 1ns/1ps
module uart_person_raw_tb #(parameter EXTRA=0,DEFAULT_HIGH=45,DEFAULT_LOW=22,LIGHTING=0,WHITE=0);
reg clk=0,rst_n=0,rx_valid=0,tx_done=0;reg [7:0] rx_data=0;
always #5 clk=~clk;
wire tx_start,capture,source,tolerance,stats,median;wire [7:0] tx_data,difference;
wire [2:0] view;wire [1:0] mode;wire [10:0] high,low;
wire lighting,white_mode;
uart_vision_ctrl #(.PERSON_AVAILABLE(1),.PERSON_EDGE_AVAILABLE(0),.PERSON_EXTRA_VIEW(EXTRA),
 .PERSON_VERSION(WHITE?"W":LIGHTING?"L":EXTRA?"8":"7"),.LIGHTING_AVAILABLE(LIGHTING),.WHITE_AVAILABLE(WHITE),.MEDIAN_AVAILABLE(0),.PHOTO_AVAILABLE(0),
 .SOBEL_AVAILABLE(0),.SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),
 .DEFAULT_EDGE_THRESHOLD(DEFAULT_HIGH),.DEFAULT_CANNY_LOW_THRESHOLD(DEFAULT_LOW)) dut(
 .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(tx_done),.tx_start(tx_start),.tx_data(tx_data),
 .person_view_req(view),.person_edge_source_req(source),.person_edge_tolerance_req(tolerance),
 .person_stats_query_req(stats),.person_stats_busy(1'b0),.background_capture_req(capture),
 .background_ready(1'b1),.background_busy(1'b0),.background_fault(1'b0),
 .person_edge_source_active(1'b0),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0),
 .difference_threshold_req(difference),.edge_threshold_req(high),.canny_low_threshold_req(low),
 .median_enable_req(median),.video_mode_req(mode),.lighting_suppress_req(lighting),.white_background_req(white_mode));
task send(input [7:0] command,reply,input bit respond);
 begin
 @(negedge clk);rx_data=command;rx_valid=1;@(posedge clk);#1;
 if(tx_start!==respond||(respond&&tx_data!==reply))$fatal(1,"RAW UART command %h got %b/%h expected %b/%h",command,tx_start,tx_data,respond,reply);
 if(source||stats||median)$fatal(1,"disabled hardware command emitted request");
 if(command=="b"&&capture!==!white_mode)$fatal(1,"RAW capture/white rejection wrong");
 @(negedge clk);rx_valid=0;tx_done=respond;@(negedge clk);tx_done=0;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 send("V",WHITE?"W":LIGHTING?"L":EXTRA?"8":"7",1);send("I","R",1);send("J","R",1);
 if(white_mode)$fatal(1,"white mode changed existing power-on behavior");
 send("%",WHITE?"1":"!",1);if(white_mode!==WHITE)$fatal(1,"white mode enable failed");
 send("I",WHITE?"W":"R",1);send("J",WHITE?"W":"R",1);
 send("b",WHITE?"!":"K",1);send("Q","1",1);
 send("%",WHITE?"0":"!",1);if(white_mode)$fatal(1,"white mode exit failed");
 if(lighting!==LIGHTING)$fatal(1,"wrong lighting reset default");
 send("~",LIGHTING?"0":"!",1);if(lighting)$fatal(1,"lighting bypass failed");
 send("~",LIGHTING?"1":"!",1);if(lighting!==LIGHTING)$fatal(1,"lighting enable failed");
 send("X","!",1);send("O","!",1);send("S","!",1);send("M","!",1);
 send("S","!",1);send("1",0,0);send(13,"!",1);send(10,0,0);
 if(high!=DEFAULT_HIGH||low!=DEFAULT_LOW)$fatal(1,"rejected command changed Canny thresholds");
 send("b","K",1);send("Q","1",1);
 for(integer i=1;i<=(EXTRA?6:5);i++)begin send("U","0"+i,1);if(view!=i)$fatal(1,"wrong U view");end
 send("U","0",1);send("E","2",1);if(mode!=2)$fatal(1,"ordinary Canny was disabled");
 send("G","1",1);send("C","0",1);
 send("N",0,0);send("3",0,0);send("2",0,0);send(13,"K",1);
 if(difference!=32||high!=DEFAULT_HIGH||low!=DEFAULT_LOW)$fatal(1,"RAW/Canny controls not isolated");
 if(DEFAULT_HIGH==0 && DEFAULT_LOW==0)begin
  send("H",0,0);send("4",0,0);send("5",0,0);send(13,"K",1);
  send("L",0,0);send("2",0,0);send("2",0,0);send(13,"K",1);
  if(high!=45||low!=22)$fatal(1,"Manual H/L setting failed");
  repeat(60)send("-","-",1);
  if(high!=0||low!=0)$fatal(1,"Repeated minus did not saturate high/low at zero");
  send("+","+",1);if(high!=1||low!=0)$fatal(1,"Plus failed after saturation");
  send("R","R",1);if(high!=0||low!=0)$fatal(1,"R did not restore zero defaults");
  if(difference!=32)$fatal(1,"Canny reset changed RAW threshold");
  $display("PASS image3 zero defaults, manual H45/L22, repeated minus to 0/0, plus, R restore and N isolation");
 end
 $display("PASS RAW-only UART profile: E display retained, removed E subtraction/median rejected, RAW capture and N isolated, U cycling extra=%0d",EXTRA);$finish;
end
initial begin #100000;$fatal(1,"RAW-only UART timeout");end
endmodule
