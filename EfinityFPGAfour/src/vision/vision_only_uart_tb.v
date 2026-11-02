`timescale 1ns/1ps
// The legacy test image must reject every photo/card/gallery command.
module vision_only_uart_tb;
reg clk=0, rst_n=0, rx_valid=0, tx_done=0;
reg [7:0] rx_data=0;
wire [7:0] tx_data;
wire tx_start, gc, cc, shape, median, capture, init_card, gallery, prev_photo, next_photo, diagnostic;
wire [1:0] mode;
wire split;
always #5 clk=~clk;
uart_vision_ctrl #(.SOBEL_AVAILABLE(0), .PHOTO_AVAILABLE(0),
    .SPLIT_AVAILABLE(1),
    .DEFAULT_VIDEO_MODE(2), .DEFAULT_MEDIAN_ENABLE(1)) dut (
    .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
    .tx_done(tx_done), .tx_data(tx_data), .tx_start(tx_start),
    .video_mode_req(mode), .gray_canny_enable_req(gc), .color_canny_enable_req(cc),
    .shape_enable_req(shape), .median_enable_req(median),
    .diagnostic_pattern_req(diagnostic),
    .split_enable_req(split),
    .photo_capture_req(capture), .sd_info_query_req(init_card),
    .photo_gallery_toggle_req(gallery), .photo_gallery_prev_req(prev_photo),
    .photo_gallery_next_req(next_photo)
);
always @(posedge clk) begin
    #1;
    if(rst_n && {capture,init_card,gallery,prev_photo,next_photo} !== 5'd0)
        $fatal(1,"Disabled photo/TF command emitted a request");
end
task send;
    input [7:0] command, reply;
    begin
        @(negedge clk); rx_data=command; rx_valid=1;
        @(posedge clk); #2;
        if(!tx_start || tx_data!==reply) $fatal(1,"Command %02x reply %02x expected %02x",command,tx_data,reply);
        @(negedge clk); rx_valid=0; tx_done=1;
        @(posedge clk); #2;
        if(tx_start) $fatal(1,"Duplicate reply for %02x",command);
        @(negedge clk); tx_done=0;
        repeat(3) begin @(posedge clk); #2; if(tx_start) $fatal(1,"Repeated reply"); end
    end
endtask
initial begin
    repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
    @(posedge clk); #2;
    if(mode!==2 || !gc || !cc || shape || !median) $fatal(1,"Reset profile mismatch");
    send("i","!"); send("I","!"); send("b","!");
    send("x","!"); send("X","!"); send("<","!"); send(">","!");
    send("A","C"); send("V","C");
    send("Z","1"); if(!diagnostic) $fatal(1,"Z entry failed");
    send("z","0"); if(diagnostic) $fatal(1,"z exit failed");
    send("C","0"); if(mode!==0) $fatal(1,"C failed");
    send("G","1"); if(mode!==1) $fatal(1,"G failed");
    send("M","0"); if(median) $fatal(1,"M off failed");
    send("M","1"); if(!median) $fatal(1,"M on failed");
    send("E","2"); if(mode!==2) $fatal(1,"E failed");
    send("D","1"); if(!shape) $fatal(1,"D on failed");
    send("D","0"); if(shape) $fatal(1,"D off failed");
    send("d","1"); if(!shape) $fatal(1,"Vision-image lowercase d changed meaning");
    send("D","0");
    send("O","3"); if(mode!==3) $fatal(1,"O failed");
    send("U","!");
    send("|","1"); if(!split || mode!==2 || shape) $fatal(1,"Split entry must select grayscale Canny without shape overlay");
    send("?","2"); if(!split) $fatal(1,"Query exited split");
    send("M","0"); if(!split) $fatal(1,"M exited split");
    send("|","0"); if(split || mode!==2) $fatal(1,"Split toggle exit failed");
    send("|","1"); send("C","0"); if(split) $fatal(1,"C must exit split");
    send("|","1"); send("G","1"); if(split) $fatal(1,"G must exit split");
    send("|","1"); send("E","2"); if(split) $fatal(1,"E must exit split");
    send("|","1"); send("O","3"); if(split) $fatal(1,"O must exit split");
    send("|","1"); send("T","3"); if(split) $fatal(1,"T must exit split");
    send("D","1"); send("|","1"); if(shape || !split) $fatal(1,"Split must leave recognition mode");
    send("D","1"); if(split || !shape) $fatal(1,"D must restore full-screen recognition");
    send("D","0");
    $display("PASS vision-only UART: gray/edge split toggle and mode exits, card/photo/gallery disabled, Canny/shape/M retained");
    $finish;
end
initial begin #100000; $fatal(1,"UART timeout"); end
endmodule
