`timescale 1ns/1ps
module uart_skeleton_ctrl_tb;
reg clk=0,rst_n=0,rv=0,done=0;reg [7:0] rx=0;
wire [7:0] tx;wire start,white,lighting,capture;wire [1:0] mode,noise;
wire [2:0] view;wire [7:0] threshold;
always #5 clk=~clk;
uart_skeleton_ctrl #(.PERSON_AVAILABLE(1),.PERSON_EDGE_AVAILABLE(0),.PERSON_EXTRA_VIEW(1),.LIGHTING_AVAILABLE(1),.WHITE_AVAILABLE(1),
 .PERSON_VERSION("4"),.MEDIAN_AVAILABLE(0),.PHOTO_AVAILABLE(0),.SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SOBEL_AVAILABLE(0),.DEFAULT_VIDEO_MODE(0)) dut(
 .clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(rv),.tx_done(done),.tx_data(tx),.tx_start(start),
 .white_background_req(white),.lighting_suppress_req(lighting),.background_capture_req(capture),.video_mode_req(mode),
 .person_view_req(view),.person_noise_req(noise),.difference_threshold_req(threshold),
 .background_ready(1'b1),.background_busy(1'b0),.background_fault(1'b0),.person_stats_busy(1'b0),
 .person_edge_source_active(1'b0),.person_edge_frame_fault(1'b0),.person_edge_foreground_present(1'b0));
integer replies=0;reg [7:0] response;
always @(negedge clk)begin
 done=0;
 if(start)begin response=tx;replies++;done=1;end
 if(rst_n&&(capture||!white||!lighting))$fatal(1,"fixed white source changed");
end
task send(input [7:0] c);
 begin @(negedge clk);rx=c;rv=1;@(negedge clk);rv=0;repeat(8)@(negedge clk);end
endtask
task command(input [7:0] c,input [7:0] expected);
 integer before_count;
 begin before_count=replies;send(c);if(replies!=before_count+1||response!=expected)$fatal(1,"command %c reply=%c",c,response);end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 command("V","4");command("I","W");command("Q","1");
 for(integer n=1;n<=7;n++)begin command(n%2?"U":"u","0"+(n%7));if(view!=n%7)$fatal(1,"U/u cycle");end
 command("U","1");command("4","4");if(view!=4)$fatal(1,"U4 direct selection");
 command("U","5");command("6","6");if(view!=6)$fatal(1,"U6 direct selection");
 command("C","0");if(mode!=0||view!=0)$fatal(1,"C exit mask");
 command("G","1");if(mode!=1||view!=0)$fatal(1,"G exit mask");
 command("E","!");command("T","!");command("%","!");command("~","!");command("b","!");
 command("H","!");send("9");send(13);if(mode!=1)$fatal(1,"unsupported command altered mode");
 send("N");send("3");send("2");command(13,"K");if(threshold!=32)$fatal(1,"N32 threshold");
 send("N");send("6");send("0");command(13,"K");if(threshold!=60)$fatal(1,"N60 threshold");
 command("U","1");command("3","3");send(13);send(10);
 if(threshold!=60||view!=3)$fatal(1,"U3 plus CR/LF altered N60 threshold or view");
 command("D","0");command("D","1");command("D","2");
 $display("PASS image4 UART commands: version, fixed white source, U/u and direct view, C/G, N/D and rejected Canny controls");$finish;
end
initial begin #50000;$fatal(1,"decoder timeout");end
endmodule
