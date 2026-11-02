`timescale 1ns/1ps
module image7_menu_config_tb;
reg clk=0,rst_n=0;always #5 clk=~clk;
reg [7:0] rx=0;reg rv=0,mv=0;reg [4:0] ma=0;reg [11:0] md=0;
wire [1:0] view_;wire [10:0] h,l,r,g,b;wire fr,diag;
image7_vision_ctrl #(.OVERLAY_AVAILABLE(0),.DEFAULT_VIDEO_MODE(0),.DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30)) dut(
 .clk(clk),.rst_n(rst_n),.rx_data(rx),.rx_valid(rv),.tx_done(1'b1),
 .menu_write_valid(mv),.menu_write_addr(ma),.menu_write_value(md),
 .video_mode_req(view_),.edge_threshold_req(h),.canny_low_threshold_req(l),
 .wb_red_gain_req(r),.wb_green_gain_req(g),.wb_blue_gain_req(b),.freeze_req(fr),.diagnostic_pattern_req(diag),
 .background_ready(1'b0),.background_busy(1'b0),.background_fault(1'b0));
task write_menu(input [4:0] a,input [11:0] d);
 begin @(negedge clk);mv=1;ma=a;md=d;@(negedge clk);mv=0;repeat(2)@(negedge clk);end
endtask
task serial_byte(input [7:0] ch);
 begin @(negedge clk);rx=ch;rv=1;@(negedge clk);rv=0;repeat(2)@(negedge clk);end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
 if(h!=60||l!=30||view_!=0)$fatal(1,"changed image7 defaults");
 write_menu(6,20);if(h!=20||l!=20)$fatal(1,"high must clamp low");
 write_menu(7,2047);if(l!=20)$fatal(1,"low overflow");
 write_menu(8,0);if(h!=60||l!=30)$fatal(1,"reset");
 write_menu(10,511);if(r!=511)$fatal(1,"WB write");
 serial_byte("W");serial_byte("R");serial_byte("4");serial_byte("0");serial_byte("0");serial_byte(13);
 if(r!=400)$fatal(1,"serial must override menu");
 write_menu(10,700);if(r!=700)$fatal(1,"menu must override serial");
 write_menu(0,1);if(view_!=1)$fatal(1,"menu view");serial_byte("C");if(view_!=0)$fatal(1,"serial COLOR");
 write_menu(0,3);if(view_!=0)$fatal(1,"disabled overlay mode exposed");
 write_menu(4,1);if(!diag)$fatal(1,"test on");write_menu(4,0);if(diag)$fatal(1,"test off");
 write_menu(3,1);if(!fr)$fatal(1,"freeze");
 // Non-video controls must not alter unsupported split/shape settings.
 write_menu(1,1);write_menu(2,1);write_menu(16,0);write_menu(17,0);
 if(dut.split_enable_req||dut.shape_enable_req)$fatal(1,"model/menu addresses affected video");
 $display("PASS image7_menu_config: preserved defaults, threshold clamping, RGB, WB, UART/menu last writer, freeze/test, isolated model controls");$finish;
end
endmodule
