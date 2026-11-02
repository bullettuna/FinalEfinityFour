`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"
`include "images/image5_canny/image5_menu_defs.vh"
`include "src/pose7/ui/image7_menu_defs.vh"
module flash_menu_tb #(parameter IMAGE_ID=7);
localparam SLOT=IMAGE_ID==7?0:IMAGE_ID==1?1:2;
localparam BOOT=IMAGE_ID==7?18:IMAGE_ID==1?17:19;
localparam LOAD=BOOT+1;
reg clk=0,rst_n=0,short_=0,long_=0,key_=0,safe_=0;always #5 clk=~clk;
reg [1:0] code=0;
wire valid,stop_,ena,config_;wire [4:0] address;wire [11:0] value;
wire [1:0] selected,cbsel;wire [3:0] status;wire [155:0] record_;
flash_image_switch #(.CURRENT_SLOT(SLOT),.SELECT_ADDR(BOOT),.LOAD_ADDR(LOAD),.TIMEOUT_CYCLES(1000)) sw(
 .clk(clk),.rst_n(rst_n),.write_valid(valid),.write_addr(address),.write_value(value),.safe_to_switch(safe_),.cfg_error(1'b0),
 .selected_slot(selected),.status(status),.stop_request(stop_),.cfg_cbsel(cbsel),.cfg_ena(ena),.cfg_config(config_));
generate
 if(IMAGE_ID==5)begin:g5
 wire [`M5_DISP_WIDTH-1:0] d;assign record_=d;
 image5_menu_ctrl c(.clk(clk),.rst_n(rst_n),.key1_short(short_),.key1_long(long_),.key_event(key_),.key_code(code),
 .knob_value(12'd2048),.knob_sample(1'b0),.knob_ready(1'b1),.cur_view(2'd2),.cur_median(1'b1),.cur_cleanup(1'b1),
 .cur_freeze(1'b0),.cur_test(1'b0),.cur_gamma(1'b1),.cur_high(11'd60),.cur_low(11'd30),
 .cur_wb_r(11'd496),.cur_wb_g(11'd416),.cur_wb_b(11'd313),.cur_gamma_p(9'd255),
 .cur_usb_mode(3'd0),.cur_usb_size(2'd0),.usb_busy(1'b0),.adc1(12'd4095),.boot_selected(selected),.boot_status(status),
 .menu_open(),.write_valid(valid),.write_addr(address),.write_value(value),.disp(d));
 end else if(IMAGE_ID==1)begin:g1
 wire [`MENU_DISP_WIDTH-1:0] d;assign record_=d;
 menu_ctrl c(.clk(clk),.rst_n(rst_n),.key1_short(short_),.key1_long(long_),.key_event(key_),.key_code(code),
 .knob_value(12'd2048),.knob_sample(1'b0),.cur_view(2'd2),.cur_split(1'b0),.cur_shape(1'b0),
 .cur_freeze(1'b0),.cur_test(1'b0),.cur_median(1'b1),.cur_gamma(1'b1),.cur_high(11'd25),.cur_low(11'd8),
 .cur_wb_r(11'd496),.cur_wb_g(11'd416),.cur_wb_b(11'd313),.cur_gamma_p(9'd255),.cur_black(8'd96),
 .boot_selected(selected),.boot_status(status),.menu_open(),.write_valid(valid),.write_addr(address),.write_value(value),.disp(d));
 end else begin:g7
 wire [`M7_MENU_DISP_WIDTH-1:0] d;assign record_=d;
 image7_menu_ctrl c(.clk(clk),.rst_n(rst_n),.key1_short(short_),.key1_long(long_),.key_event(key_),.key_code(code),
 .knob_value(12'd2048),.knob_sample(1'b0),.cur_view(2'd0),.cur_infer(1'b1),.cur_skeleton(1'b1),
 .cur_freeze(1'b0),.cur_test(1'b0),.cur_median(1'b1),.cur_gamma(1'b1),.cur_high(11'd60),.cur_low(11'd30),
 .cur_wb_r(11'd335),.cur_wb_g(11'd248),.cur_wb_b(11'd280),.cur_gamma_p(9'd42),.cur_black(8'd0),.status(16'h003f),
 .boot_selected(selected),.boot_status(status),.menu_open(),.write_valid(valid),.write_addr(address),.write_value(value),.disp(d));
 end
endgenerate
task pulse(input integer kind);
 begin @(negedge clk);case(kind)0:long_=1;1:short_=1;2:begin key_=1;code=2;end endcase
 @(negedge clk);long_=0;short_=0;key_=0;code=0;repeat(5)@(negedge clk);end
endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
 pulse(1);if(stop_||config_)$fatal(1,"closed menu issued reboot");
 pulse(0);for(integer k=0;k<BOOT;k=k+1)pulse(2);
 if(record_[2+:5]!=BOOT)$fatal(1,"new menu row missing");
 pulse(1);if(selected!=(SLOT+1)%3||stop_||ena||config_)$fatal(1,"selection action wrong");
 pulse(2);if(record_[2+:5]!=LOAD)$fatal(1,"LOAD row missing");
 pulse(1);if(!stop_||status!=1||ena||config_)$fatal(1,"LOAD did not wait for drain");
 safe_=1;wait(config_);#1;if(cbsel!=(SLOT+1)%3)$fatal(1,"menu routed wrong slot");
 $display("PASS flash_menu image%0d: actual menu keys -> selected slot -> separate LOAD -> drain -> internal CONFIG",IMAGE_ID);$finish;
end
initial begin #100000;$fatal(1,"menu switch timeout image=%0d",IMAGE_ID);end
endmodule
