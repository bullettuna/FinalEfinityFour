`timescale 1ns/1ps
module uart_person_roi_tb;
reg clk=0,rst_n=0,rx_valid=0,tx_done=0;
reg [7:0] rx_data=0;
reg ready=0,busy=0,fault=0,stats_busy=0;
reg actual_source=0,foreground_present=0,frame_fault=0;
wire [7:0] tx_data,difference;
wire tx_start,capture,photo,shape;
wire [2:0] view;wire [1:0] noise;wire [10:0] high_threshold,wb_blue;
wire edge_source,tolerance;
wire stats_query;
always #5 clk=~clk;
uart_vision_ctrl #(.PERSON_AVAILABLE(1),.PHOTO_AVAILABLE(0),.SOBEL_AVAILABLE(0),
 .SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.DEFAULT_EDGE_THRESHOLD(45)) dut(
 .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(tx_done),.tx_data(tx_data),.tx_start(tx_start),
 .background_capture_req(capture),.person_view_req(view),.person_edge_source_req(edge_source),.difference_threshold_req(difference),.person_noise_req(noise),
 .person_edge_tolerance_req(tolerance),
 .person_stats_query_req(stats_query),.person_stats_busy(stats_busy),
 .background_ready(ready),.background_busy(busy),.background_fault(fault),
 .person_edge_source_active(actual_source),.person_edge_foreground_present(foreground_present),.person_edge_frame_fault(frame_fault),
 .photo_capture_req(photo),.shape_enable_req(shape),.edge_threshold_req(high_threshold),.wb_blue_gain_req(wb_blue));
task automatic send(input [7:0] command,reply,input bit response);
 begin
 @(negedge clk);rx_data=command;rx_valid=1;@(posedge clk);#2;
 if(tx_start!==response || (response&&tx_data!==reply))$fatal(1,"UART %02x response=%b/%02x expected=%b/%02x",command,tx_start,tx_data,response,reply);
 if(photo||shape)$fatal(1,"person command enabled photo/shape");
 if(command=="b"&&!busy&&!capture)$fatal(1,"independent capture absent");
 if((command=="S"||command=="s")&&stats_query!==!stats_busy)$fatal(1,"stats request/busy gating");
 @(negedge clk);rx_valid=0;tx_done=response;@(posedge clk);#2;
 if(capture)$fatal(1,"capture pulse repeated");@(negedge clk);tx_done=0;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 send("Q","0",1);send("b","K",1);busy=1;send("Q","B",1);send("b","!",1);
 busy=0;ready=1;send("Q","1",1);fault=1;send("Q","!",1);fault=0;
 for(integer i=1;i<=5;i++)begin send("U","0"+i,1);if(view!=i)$fatal(1,"view cycling");end
 send("U","0",1);
 send("N",0,0);send("3",0,0);send("2",0,0);send(13,"K",1);send(10,0,0);
 if(difference!=32||high_threshold!=45)$fatal(1,"N leaked into Canny");
 send("n",0,0);send("9",0,0);send("9",0,0);send("9",0,0);send(13,"K",1);
 if(difference!=255)$fatal(1,"N saturation");
 send("D","0",1);if(noise!=0)$fatal(1,"noise bypass");send("D","1",1);send("D","2",1);
 send("U","1",1);send("C","0",1);if(view)$fatal(1,"C did not exit person view");
 send("W",0,0);send("B",0,0);send("2",0,0);send("8",0,0);send("0",0,0);send(13,"K",1);
 if(wb_blue!=280)$fatal(1,"WB prefix not isolated");
 if(!tolerance)$fatal(1,"3x3 tolerance must default on");
 send("U","1",1);send("O","0",1);if(tolerance||view!=1||high_threshold!=45)$fatal(1,"O changed view/threshold");
 send("o","1",1);if(!tolerance||view!=1)$fatal(1,"O tolerance toggle");
 send("O","0",1);send("0","0",1);send(13,0,0);send(10,0,0);
 if(tolerance||view!=1||high_threshold!=45)$fatal(1,"O0 argument leaked into threshold/view");
 send("o","1",1);send("1","1",1);send(13,0,0);
 if(!tolerance||view!=1||high_threshold!=45)$fatal(1,"O1 argument leaked into threshold/view");
 send("O","0",1);send("2","!",1);send(13,"!",1);
 if(tolerance||high_threshold!=45)$fatal(1,"invalid O2 changed threshold");
 send("O","1",1);send("1","1",1);send("0","!",1);send(13,"!",1);
 if(!tolerance||high_threshold!=45)$fatal(1,"invalid O10 changed threshold");
 send("V","6",1);send("S",0,0);send(13,0,0);send(10,0,0);
 stats_busy=1;send("s","!",1);send(13,0,0);send(10,0,0);stats_busy=0;
 send("S",0,0);send("1","!",1);send(13,"!",1);
 if(view!=1||high_threshold!=45)$fatal(1,"S changed display/threshold");
 send("I","R",1);send("J","R",1);
 send("x","E",1);if(!edge_source)$fatal(1,"edge source missing");
 send("I","R",1); // Requested source is not the applied pixel-domain source.
 actual_source=1;send("i","E",1);send("J","0",1);
 foreground_present=1;send("J","1",1);frame_fault=1;send("J","!",1);frame_fault=0;
 busy=1;send("X","!",1);if(!edge_source)$fatal(1,"source changed while capture busy");busy=0;
 send("X","R",1);if(edge_source)$fatal(1,"RAW source missing");actual_source=0;send("I","R",1);send("J","R",1);
 $display("PASS person UART: independent capture/status, five views, noise modes, N clamp/CRLF and Canny/WB/photo isolation");$finish;
end
initial begin #100000;$fatal(1,"person UART timeout");end
endmodule
