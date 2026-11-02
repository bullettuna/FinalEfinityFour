`timescale 1ns/1ps
`include "images/image2_video_guard/image2_menu_defs.vh"
module image2_menu_control_tb;
reg clk=0,rst_n=0;always #5 clk=~clk;
reg key1_short=0,key1_long=0,key_event=0,knob_sample=0;
reg [1:0] key_code=0;reg [11:0] knob_value=2048;
reg [7:0] rx_data=0;reg rx_valid=0;
wire menu_open,write_valid;wire [4:0] write_addr;wire [11:0] write_value;
wire [`MENU_DISP_WIDTH-1:0] disp;
wire [1:0] view,cleanup;wire [10:0] high_,low_,wbr,wbg,wbb,minimum;
wire freeze,test_,median,gamma_;wire [8:0] gp;wire [7:0] black;
wire capture,gallery,prev_,next_,delete_,query_;
integer captures=0,galleries=0,prevs=0,nexts=0,deletes=0,queries=0;
reg event_valid=0,sd_busy=0,confirm_=0,busy=0,album=0;
reg [3:0] stage=0,event_=0;reg [7:0] error_=0;reg [31:0] file_=7654321;
image2_vision_ctrl #(.PHOTO_EDGE_PROFILE(1),.PHOTO_AVAILABLE(1),.VISION_AVAILABLE(1),
 .SHAPE_AVAILABLE(0),.OVERLAY_AVAILABLE(0),.SPLIT_AVAILABLE(0),.SOBEL_AVAILABLE(0),
 .DEFAULT_VIDEO_MODE(0),.DEFAULT_EDGE_THRESHOLD(60),.DEFAULT_CANNY_LOW_THRESHOLD(30),
 .DEFAULT_WB_RED_GAIN(335),.DEFAULT_WB_GREEN_GAIN(248),.DEFAULT_WB_BLUE_GAIN(280)) ctrl(
 .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(1'b1),
 .menu_write_valid(write_valid),.menu_write_addr(write_addr),.menu_write_value(write_value),
 .video_mode_req(view),.edge_threshold_req(high_),.canny_low_threshold_req(low_),
 .wb_red_gain_req(wbr),.wb_green_gain_req(wbg),.wb_blue_gain_req(wbb),
 .freeze_req(freeze),.diagnostic_pattern_req(test_),.median_enable_req(median),
 .gamma_enable_req(gamma_),.gamma_strength_req(gp),.black_threshold_req(black),
 .photo_cleanup_level_req(cleanup),.photo_min_pixels_req(minimum),
 .photo_capture_req(capture),.photo_gallery_toggle_req(gallery),
 .photo_gallery_prev_req(prev_),.photo_gallery_next_req(next_),.photo_delete_req(delete_),.sd_info_query_req(query_));
image2_menu_ctrl dut(
 .clk(clk),.rst_n(rst_n),.key1_short(key1_short),.key1_long(key1_long),.key_event(key_event),.key_code(key_code),
 .knob_value(knob_value),.knob_sample(knob_sample),.cur_view(view),.cur_split(1'b0),.cur_shape(1'b0),
 .cur_freeze(freeze),.cur_test(test_),.cur_median(median),.cur_gamma(gamma_),.cur_high(high_),.cur_low(low_),
 .cur_wb_r(wbr),.cur_wb_g(wbg),.cur_wb_b(wbb),.cur_gamma_p(gp),.cur_black(black),
 .cur_cleanup(cleanup),.cur_minimum(minimum),.ui_stage(stage),.ui_event(event_),.ui_error(error_),
 .ui_sd_detail(10'h244),
 .ui_event_valid(event_valid),.ui_sd_busy(sd_busy),.ui_delete_confirm(confirm_),.ui_busy(busy),.ui_gallery(album),.ui_file(file_),.video_health(64'h0004000300020001),
 .menu_open(menu_open),.write_valid(write_valid),.write_addr(write_addr),.write_value(write_value),.disp(disp));
always @(posedge clk)begin
 if(capture)captures=captures+1;if(gallery)galleries=galleries+1;
 if(prev_)prevs=prevs+1;if(next_)nexts=nexts+1;
 if(delete_)deletes=deletes+1;if(query_)queries=queries+1;
end
task short_;begin @(negedge clk);key1_short=1;@(negedge clk);key1_short=0;repeat(4)@(negedge clk);end endtask
task key_(input [1:0] v);begin @(negedge clk);key_code=v;key_event=1;@(negedge clk);key_event=0;repeat(3)@(negedge clk);end endtask
task select_(input [4:0] idx);begin
 while(dut.cursor!=idx)key_(2);repeat(3)@(negedge clk);
 if(dut.window_start>idx||idx>=dut.window_start+8)$fatal(1,"scroll window");
end endtask
task report_(input [3:0] ev,input [7:0] err);begin
 @(negedge clk);event_=ev;error_=err;event_valid=1;@(negedge clk);event_valid=0;repeat(3)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;repeat(70)@(negedge clk);
 if(menu_open||captures||queries)$fatal(1,"power-up action");
 if(disp[`MD_FILE_OFF+:28]!==28'h7654321)$fatal(1,"file BCD %h",disp[`MD_FILE_OFF+:28]);
 @(negedge clk);key1_long=1;@(negedge clk);key1_long=0;
 short_;if(view!=1)$fatal(1,"color->gray");short_;if(view!=2)$fatal(1,"gray->edge");short_;if(view!=0)$fatal(1,"edge->color");
 select_(1);short_;select_(2);short_;select_(18);short_;
 select_(19);short_;select_(20);short_;select_(21);short_;
 if(captures!=1||galleries!=1||queries!=1||prevs!=1||nexts!=1||deletes!=1)$fatal(1,"menu action routing");
 select_(17);short_;key_(1);if(minimum!=21)$fatal(1,"minimum edit");short_;
 select_(16);short_;if(cleanup!=2)$fatal(1,"cleanup enum");short_;if(cleanup!=0)$fatal(1,"cleanup wrap");
 select_(5);short_;key_(1);short_;if(high_!=61||low_!=30)$fatal(1,"linked threshold");
 select_(7);short_;repeat(32)key_(1);short_;if(low_!=high_)$fatal(1,"low limit");
 select_(8);short_;if(high_!=60||low_!=30||minimum!=21)$fatal(1,"threshold-only reset");
 select_(3);short_;if(!freeze)$fatal(1,"freeze");
 select_(4);short_;if(!test_)$fatal(1,"test");
 select_(10);short_;key_(1);short_;if(wbr!=336)$fatal(1,"WB edit");
 select_(13);short_;if(wbr!=335)$fatal(1,"WB reset");
 sd_busy=1;repeat(2)@(negedge clk);if(disp[`MD_SD_OFF+:2]!=1)$fatal(1,"SD wait");
 sd_busy=0;report_(5,0);if(disp[`MD_SD_OFF+:2]!=2)$fatal(1,"SD pass");
 repeat(100)@(negedge clk);if(disp[`MD_SD_OFF+:2]!=2)$fatal(1,"SD feedback not persistent");
 report_(6,8'h24);if(disp[`MD_SD_OFF+:2]!=3||disp[`MD_ERROR_OFF+:8]!=8'h24||disp[`MD_SD_COMMAND_OFF+:6]!=6'h24||disp[`MD_SD_REASON_OFF+:4]!=4)$fatal(1,"SD fail");
 report_(4,0);if(disp[`MD_EVENT_OFF+:4]!=4||disp[`MD_SD_OFF+:2]!=3)$fatal(1,"busy rejection erased SD result");
 confirm_=1;album=1;stage=8;busy=1;repeat(2)@(negedge clk);
 if(!disp[`MD_DELETE_OFF]||!disp[`MD_GALLERY_OFF]||!disp[`MD_BUSY_OFF]||disp[`MD_STAGE_OFF+:4]!=8)$fatal(1,"actual storage feedback");
 select_(17);short_;repeat(8)begin @(negedge clk);knob_sample=1;@(negedge clk);knob_sample=0;end
 // A deadband prevents averaged ADC jitter from editing area threshold.
 knob_value=2050;@(negedge clk);knob_sample=1;@(negedge clk);knob_sample=0;repeat(5)@(negedge clk);
 if(minimum!=21)$fatal(1,"knob jitter changed parameter");
 short_;@(negedge clk);key1_long=1;@(negedge clk);key1_long=0;repeat(3)@(negedge clk);
 if(menu_open)$fatal(1,"menu close");
 $display("PASS image2 P4 menu: real control writes, 22 rows, C/G/E, capture/album/SD/delete, numeric bounds, WB, persistent feedback and knob deadband");$finish;
end
initial begin #200000;$fatal(1,"menu timeout");end
endmodule
