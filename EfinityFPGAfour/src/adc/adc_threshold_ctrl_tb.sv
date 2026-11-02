`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"
module adc_threshold_ctrl_tb;
parameter PERSON_PROFILE=0,PHOTO_PROFILE=0,MENU_PROFILE=0;
localparam [10:0] DEFAULT_HIGH=MENU_PROFILE?25:(PHOTO_PROFILE?60:45),
                  DEFAULT_LOW=MENU_PROFILE?8:(PHOTO_PROFILE?30:22);
reg clk=0,pclk=0,rst_n=0,ready=0,vsync=0,rx_valid=0;
reg menu_valid=0;
reg [4:0] menu_addr=0;
reg [10:0] menu_value=0;
reg [11:0] knob=0;
reg [7:0] rx_data=0;
reg tx_done=0;
wire [10:0] uart_high,uart_low,high_request,low_request,high_active,low_active;
wire uart_update,tx_start;
wire [7:0] tx_data;
wire [7:0] difference;
wire [2:0] person_view;
integer updates=0,reply_count=0;
always #5 clk=~clk;
always #7 pclk=~pclk;
uart_vision_ctrl #(.SOBEL_AVAILABLE(0),.PHOTO_AVAILABLE(PHOTO_PROFILE),.PHOTO_EDGE_PROFILE(PHOTO_PROFILE),
    .PERSON_AVAILABLE(PERSON_PROFILE),.PERSON_EDGE_AVAILABLE(0),
    .PERSON_EXTRA_VIEW(PERSON_PROFILE),.PERSON_VERSION("8"),.MEDIAN_AVAILABLE(0),
    .SHAPE_AVAILABLE(!(PERSON_PROFILE||PHOTO_PROFILE)),.OVERLAY_AVAILABLE(!(PERSON_PROFILE||PHOTO_PROFILE)),
    .DEFAULT_EDGE_THRESHOLD(DEFAULT_HIGH),.DEFAULT_CANNY_LOW_THRESHOLD(DEFAULT_LOW)) uart_ctrl (
    .clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),.rx_data(rx_data),
    .menu_write_valid(menu_valid),.menu_write_addr(menu_addr),.menu_write_value(menu_value),
    .tx_done(tx_done),.tx_start(tx_start),.tx_data(tx_data),
    .background_ready(1'b1),.background_busy(1'b0),.background_fault(1'b0),
    .person_stats_busy(1'b0),.person_edge_source_active(1'b0),
    .person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0),
    .difference_threshold_req(difference),.person_view_req(person_view),
    .edge_threshold_req(uart_high),.canny_low_threshold_req(uart_low),.threshold_update(uart_update));
adc_threshold_ctrl #(.DEFAULT_HIGH(DEFAULT_HIGH),.DEFAULT_LOW(DEFAULT_LOW),.KNOB_DIRECT(!MENU_PROFILE)) ctrl(.clk(clk),.rst_n(rst_n),.knob_value(knob),.knob_ready(ready),
    .knob_enable(1'b1),
    .uart_update(uart_update),.uart_high(uart_high),.uart_low(uart_low),
    .high_threshold(high_request),.low_threshold(low_request));
edge_threshold_cdc #(.DEFAULT_HIGH(DEFAULT_HIGH),.DEFAULT_LOW(DEFAULT_LOW)) cdc(.clk(clk),.rst_n(rst_n),.high_request(high_request),.low_request(low_request),
    .pclk(pclk),.prst_n(rst_n),.frame_vsync(vsync),.high_active(high_active),.low_active(low_active));
always @(posedge clk) begin
    if(!rst_n) begin tx_done<=0;reply_count<=0;end
    else begin
        tx_done<=reply_count==1;
        if(tx_start) reply_count<=3;
        else if(reply_count!=0) reply_count<=reply_count-1;
        if(uart_update) updates=updates+1;
    end
end
reg previous_vsync=0,edge_now;
reg [21:0] previous_pair={DEFAULT_HIGH,DEFAULT_LOW};
reg ratio_check=0;
always @(posedge pclk) begin
    edge_now=!previous_vsync&&vsync;
    previous_vsync=vsync;
    #1;
    if(rst_n && {high_active,low_active}!=previous_pair && !edge_now)
        $fatal(1,"Threshold changed within a frame");
    if(rst_n && low_active>high_active) $fatal(1,"Low threshold exceeds high");
    if(rst_n && ratio_check && low_active!=(high_active>>1)) $fatal(1,"Torn threshold pair");
    previous_pair={high_active,low_active};
end
task expect_request(input integer h,input integer l);
    repeat(3) @(negedge clk);
    if(high_request!=h || low_request!=l)
        $fatal(1,"Wrong threshold request: %0d/%0d expected %0d/%0d",high_request,low_request,h,l);
endtask
task frame;
    @(negedge pclk);vsync=0;repeat(6) @(posedge pclk);
    @(negedge pclk);vsync=1;repeat(2) @(posedge pclk);
    @(negedge pclk);vsync=0;repeat(8) @(posedge pclk);
endtask
task apply_frames;
    repeat(8) @(negedge clk);frame();frame();frame();
    if(high_active!=high_request || low_active!=low_request) $fatal(1,"Latest pair did not reach frame boundary");
endtask
task send_byte(input [7:0] value);
        @(negedge clk);rx_data=value;rx_valid=1;
        @(negedge clk);rx_valid=0;
        repeat(12) @(negedge clk);
endtask
task send_text(input string value);
    integer n;
    for(n=0;n<value.len();n=n+1) send_byte(value[n]);
endtask
task menu_write(input [4:0] addr,input [10:0] value);
    @(negedge clk);menu_addr=addr;menu_value=value;menu_valid=1;
    @(negedge clk);menu_valid=0;
    repeat(3) @(negedge clk);
endtask
integer n,old_updates;
initial begin
    repeat(5) @(negedge clk);rst_n=1;
    expect_request(DEFAULT_HIGH,DEFAULT_LOW);
    if(MENU_PROFILE) begin
        // A ready ADC at either endpoint must never seize image1 thresholds.
        ready=1;
        for(n=0;n<4096;n=n+1) begin
            @(negedge clk);knob=n;
            @(negedge clk);
            if(high_request!==25 || low_request!==8)
                $fatal(1,"Image1 knob overrode startup 25/8 at ADC=%0d",n);
        end
        apply_frames();
        menu_write(`MENU_ITEM_CANNY_H,100);expect_request(100,8);
        menu_write(`MENU_ITEM_CANNY_L,30);expect_request(100,30);apply_frames();
        knob=0;expect_request(100,30);
        menu_write(`MENU_ITEM_CANNY,80);expect_request(80,40);apply_frames();
        knob=4095;expect_request(80,40);
        menu_write(`MENU_ITEM_CANNY_RST,0);expect_request(25,8);apply_frames();
        send_text("H99");send_byte(8'h0d);expect_request(99,8);
        knob=0;expect_request(99,8);
        send_text("R");expect_request(25,8);apply_frames();
        @(negedge clk);rst_n=0;knob=4095;
        repeat(5) @(negedge clk);rst_n=1;
        expect_request(25,8);apply_frames();
        $display("PASS image1 KNOB_DIRECT=0: all 4096 knob positions preserve 25/8, menu Canny H/L/link/reset and UART override/reset, atomic frame updates and ready-at-reset");
        $finish;
    end
    ready=1;knob=0;expect_request(0,0);
    knob=7;expect_request(0,0);
    knob=8;expect_request(4,2);
    knob=2048;expect_request(1024,512);apply_frames();
    // R must take effect even when UART registers are already at defaults.
    send_text("R");expect_request(DEFAULT_HIGH,DEFAULT_LOW);apply_frames();
    knob=2055;expect_request(DEFAULT_HIGH,DEFAULT_LOW);
    knob=2056;expect_request(1028,514);apply_frames();
    if(PERSON_PROFILE) begin
        old_updates=updates;
        send_text("N32");send_byte(8'h0d);expect_request(1028,514);
        if(difference!=32 || updates!=old_updates)
            $fatal(1,"Image3 N command interfered with Canny/ADC ownership");
        repeat(6) send_text("U");
        if(person_view!=6 || updates!=old_updates)
            $fatal(1,"Image3 U6 preview interfered with Canny thresholds");
    end
    if(PHOTO_PROFILE)begin
        old_updates=updates;send_text("N48");send_byte(8'h0d);expect_request(1028,514);
        send_text("@");expect_request(1028,514);
        if(updates!=old_updates)$fatal(1,"Photo N/capture interfered with ADC thresholds");
    end
    old_updates=updates;
    send_text("H100");send_byte(8'h0d);expect_request(100,DEFAULT_LOW);
    send_text("L25");send_byte(8'h0d);expect_request(100,25);
    send_text("+");expect_request(101,25);
    if(updates!=old_updates+3) $fatal(1,"UART threshold commits did not emit one pulse each");
    apply_frames();
    knob=4095;expect_request(2047,1023);apply_frames();
    knob=4088;expect_request(2047,1023);
    knob=0;expect_request(0,0);apply_frames();
    // Request changes faster than either clock crossing or frame consumption.
    ratio_check=1;
    fork
        begin for(n=0;n<64;n=n+1) begin @(negedge clk);knob=n*64;repeat(3) @(negedge clk);end end
        begin repeat(12) frame();end
    join
    knob=4095;expect_request(2047,1023);apply_frames();
    @(negedge clk);rst_n=0;ready=0;repeat(5) @(negedge clk);rst_n=1;
    expect_request(DEFAULT_HIGH,DEFAULT_LOW);apply_frames();
    $display("PASS knob threshold mapping/endpoints/deadband, UART H/L/+ and default R override, atomic asynchronous frame updates, coalescing and reset; image3 profile=%0d image2 profile=%0d",PERSON_PROFILE,PHOTO_PROFILE);
    $finish;
end
initial begin #100000; $fatal(1,"Threshold test timeout");end
endmodule
