`timescale 1ns/1ps

// Mirror-1 UART profile: Canny only, shape/photo/gallery controls preserved.
module uart_canny_only_tb;
reg clk=0, rst_n=0, rx_valid=0, tx_done=0;
reg [7:0] rx_data=0;
wire [7:0] tx_data;
wire tx_start, gray_canny, color_canny, shape, freeze, median;
wire capture, init_card, gallery, prev_photo, next_photo;
wire [1:0] mode;
wire [10:0] high_threshold, low_threshold;
always #5 clk=~clk;

uart_vision_ctrl #(.SOBEL_AVAILABLE(0), .DEFAULT_VIDEO_MODE(2),
    .DEFAULT_EDGE_THRESHOLD(45), .DEFAULT_CANNY_LOW_THRESHOLD(22),
    .DEFAULT_MEDIAN_ENABLE(1)) dut (
    .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
    .tx_done(tx_done), .tx_data(tx_data), .tx_start(tx_start),
    .video_mode_req(mode), .gray_canny_enable_req(gray_canny),
    .color_canny_enable_req(color_canny), .shape_enable_req(shape),
    .freeze_req(freeze), .edge_threshold_req(high_threshold),
    .median_enable_req(median),
    .canny_low_threshold_req(low_threshold), .photo_capture_req(capture),
    .sd_info_query_req(init_card), .photo_gallery_toggle_req(gallery),
    .photo_gallery_prev_req(prev_photo), .photo_gallery_next_req(next_photo)
);

task send;
    input [7:0] value, reply;
    input expect_reply;
    input [4:0] requests;
    begin
        @(negedge clk); rx_data=value; rx_valid=1;
        @(posedge clk); #1;
        if (!gray_canny || !color_canny)
            $fatal(1,"Unavailable standalone Sobel was selected");
        if (tx_start !== expect_reply || (expect_reply && tx_data !== reply))
            $fatal(1,"Unexpected Canny-only reply byte=%02x got=%02x",value,tx_data);
        if ({capture,init_card,gallery,prev_photo,next_photo} !== requests)
            $fatal(1,"Photo/gallery request mismatch for %02x",value);
        @(negedge clk); rx_valid=0; tx_done=expect_reply;
        @(posedge clk); #1;
        if ({capture,init_card,gallery,prev_photo,next_photo} !== 5'd0)
            $fatal(1,"Photo/gallery request exceeded one clock");
        @(negedge clk); tx_done=0;
    end
endtask

initial begin
    repeat(4) @(posedge clk);
    @(negedge clk); rst_n=1;
    @(posedge clk); #1;
    if (mode!==2 || !gray_canny || !color_canny || shape || freeze || !median)
        $fatal(1,"Canny-only reset profile mismatch");
    send("A","C",1,0); send("A","C",1,0);
    send("V","C",1,0); send("V","C",1,0);
    send("M","0",1,0); if(median) $fatal(1,"M did not disable median");
    send("M","1",1,0); if(!median) $fatal(1,"M did not enable median");
    send("C","0",1,0); if(mode!==0) $fatal(1,"Color mode failed");
    send("G","1",1,0); if(mode!==1) $fatal(1,"Gray mode failed");
    send("E","2",1,0); if(mode!==2) $fatal(1,"Canny edge mode failed");
    send("O","3",1,0); if(mode!==3) $fatal(1,"Canny overlay mode failed");
    send("D","1",1,0); if(!shape) $fatal(1,"Shape enable failed");
    send("D","0",1,0); if(shape) $fatal(1,"Shape disable failed");
    send("i",0,0,5'b01000); send("b",0,0,5'b10000);
    send("x","X",1,5'b00100); send("<","<",1,5'b00010);
    send(">",">",1,5'b00001);
    send("F","1",1,0); if(!freeze) $fatal(1,"Freeze failed");
    send("F","0",1,0);
    send("H",0,0,0); send("1",0,0,0); send("2",0,0,0);
    send("0",0,0,0); send(8'h0d,"K",1,0);
    send("L",0,0,0); send("4",0,0,0); send("0",0,0,0);
    send(8'h0d,"K",1,0);
    if(high_threshold!==120 || low_threshold!==40) $fatal(1,"Canny threshold update failed");
    $display("PASS Canny-only UART: A/V fixed C, modes, shape, TF/photo/gallery pulses and thresholds");
    $finish;
end
initial begin #100000; $fatal(1,"Canny-only UART timeout"); end
endmodule
