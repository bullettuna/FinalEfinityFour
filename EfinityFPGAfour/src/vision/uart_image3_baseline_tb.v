`timescale 1ns/1ps
// Verify image3 cannot activate hardware omitted by its compile-time profile.
module uart_image3_baseline_tb;
reg clk=0, rst_n=0, rx_valid=0, tx_done=0;
reg [7:0] rx_data=0;
wire [7:0] tx_data;
wire tx_start, shape, query, split, freeze, diagnostic, median;
wire capture, init_card, gallery, previous_photo, next_photo, delete_photo;
wire [1:0] mode;
wire [10:0] high_threshold, low_threshold, wb_blue;
always #5 clk=~clk;
uart_vision_ctrl #(
    .SOBEL_AVAILABLE(0), .PHOTO_AVAILABLE(0), .VISION_AVAILABLE(1),
    .SHAPE_AVAILABLE(0), .OVERLAY_AVAILABLE(0), .SPLIT_AVAILABLE(0),
    .DEFAULT_VIDEO_MODE(2), .DEFAULT_EDGE_THRESHOLD(45),
    .DEFAULT_CANNY_LOW_THRESHOLD(22), .DEFAULT_MEDIAN_ENABLE(1),
    .DEFAULT_SHAPE_ENABLE(1) // Unavailable shape must override even this default.
) dut (
    .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
    .tx_done(tx_done), .tx_data(tx_data), .tx_start(tx_start),
    .video_mode_req(mode), .shape_enable_req(shape), .status_query_req(query),
    .split_enable_req(split), .freeze_req(freeze), .median_enable_req(median),
    .diagnostic_pattern_req(diagnostic), .edge_threshold_req(high_threshold),
    .canny_low_threshold_req(low_threshold), .wb_blue_gain_req(wb_blue),
    .photo_capture_req(capture), .sd_info_query_req(init_card),
    .photo_gallery_toggle_req(gallery), .photo_gallery_prev_req(previous_photo),
    .photo_gallery_next_req(next_photo), .photo_delete_req(delete_photo)
);
always @(posedge clk) begin
    #1;
    if(rst_n && (shape || query || split || mode==3 ||
        capture || init_card || gallery || previous_photo || next_photo || delete_photo))
        $fatal(1,"image3 activated an excluded function");
end
task send;
    input [7:0] command, reply;
    input expect_reply;
    begin
        @(negedge clk); rx_data=command; rx_valid=1;
        @(posedge clk); #2;
        if(tx_start!==expect_reply || (expect_reply && tx_data!==reply))
            $fatal(1,"image3 UART %02x: reply %02x expected %02x, start=%b",command,tx_data,reply,tx_start);
        @(negedge clk); rx_valid=0; tx_done=expect_reply;
        @(posedge clk); #2;
        if(tx_start) $fatal(1,"Repeated image3 reply");
        @(negedge clk); tx_done=0;
    end
endtask
initial begin
    repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
    @(posedge clk); #2;
    if(mode!==2 || !median || shape) $fatal(1,"image3 reset mismatch");
    send("?","2",1); send("A","C",1);
    send("O","!",1); send("o","!",1); send("V","!",1);
    send("D","!",1); send("d","!",1); send("Q","!",1); send("q","!",1);
    send("J","!",1); send("j","!",1); send("|","!",1);
    send("i","!",1); send("I","!",1); send("b","!",1);
    send("x","!",1); send("X","!",1); send("<","!",1); send(">","!",1);
    send("B",0,0); send("9",0,0); send("6",0,0); send(13,"!",1);
    send("K",0,0); send("2",0,0); send(13,"!",1);
    send("k",0,0); send("3",0,0); send(13,"!",1);
    send("B",0,0); send(13,"!",1);
    if(high_threshold!==45 || low_threshold!==22) $fatal(1,"Rejected shape numbers changed edge thresholds");
    send("H",0,0); send("1",0,0); send("2",0,0); send("0",0,0); send(13,"K",1);
    send("L",0,0); send("4",0,0); send("0",0,0); send(13,"K",1);
    if(high_threshold!==120 || low_threshold!==40) $fatal(1,"Canny thresholds not migrated");
    send("W",0,0); send("B",0,0); send("2",0,0); send("8",0,0); send("0",0,0); send(13,"K",1);
    if(wb_blue!==280) $fatal(1,"WB prefix incorrectly rejected as shape threshold");
    send("C","0",1); if(mode!==0) $fatal(1,"C mode");
    send("T","1",1); if(mode!==1) $fatal(1,"T color-to-gray");
    send("T","2",1); if(mode!==2) $fatal(1,"T gray-to-edge");
    send("T","0",1); if(mode!==0) $fatal(1,"T must skip absent overlay");
    send("G","1",1); send("M","0",1); if(median) $fatal(1,"M off");
    send("M","1",1); send("E","2",1); send("S","2",1);
    send("F","1",1); if(!freeze) $fatal(1,"Freeze missing"); send("F","0",1);
    send("Z","1",1); if(!diagnostic) $fatal(1,"Diagnostic missing"); send("Z","0",1);
    send("R","R",1);
    if(high_threshold!==45 || low_threshold!==22) $fatal(1,"R reset");
    $display("PASS image3 UART: camera/Canny controls retained; shape/photo/overlay/split rejected; numeric prefixes safe");
    $finish;
end
initial begin #100000; $fatal(1,"image3 UART timeout"); end
endmodule
