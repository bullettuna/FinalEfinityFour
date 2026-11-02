`timescale 1ns/1ps
module uart_photo_only_tb;
reg clk=0,rst_n=0,rx_valid=0,tx_done=0;
reg [7:0] rx_data=0;
wire tx_start,shape,query,median,diagnostic,capture,init_card,gallery,prev_photo,next_photo;
wire delete_photo,split;
wire [7:0] tx_data;
wire [1:0] mode;
wire [10:0] high_threshold,low_threshold,wb_blue;
always #5 clk=~clk;
uart_vision_ctrl #(.SOBEL_AVAILABLE(0),.PHOTO_AVAILABLE(1),.VISION_AVAILABLE(0),
    .SPLIT_AVAILABLE(1), // Even a requested split must be rejected without vision.
    .DEFAULT_VIDEO_MODE(0),.DEFAULT_MEDIAN_ENABLE(0)) dut (
    .clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),.rx_data(rx_data),.tx_done(tx_done),
    .tx_start(tx_start),.tx_data(tx_data),.video_mode_req(mode),
    .shape_enable_req(shape),.status_query_req(query),.median_enable_req(median),
    .diagnostic_pattern_req(diagnostic),.edge_threshold_req(high_threshold),
    .split_enable_req(split),
    .canny_low_threshold_req(low_threshold),.wb_blue_gain_req(wb_blue),
    .photo_capture_req(capture),.sd_info_query_req(init_card),
    .photo_delete_req(delete_photo),
    .photo_gallery_toggle_req(gallery),.photo_gallery_prev_req(prev_photo),.photo_gallery_next_req(next_photo)
);
always @(posedge clk) begin #1;
    if(rst_n && (shape||query||median||split||mode>1)) $fatal(1,"Photo image activated unavailable vision mode");
end
task send;
    input [7:0] command,reply;
    input expect_reply;
    input [4:0] requests;
    reg wb_reserved;
    begin
        @(negedge clk);wb_reserved=dut.wb_prefix;rx_data=command;rx_valid=1;
        @(posedge clk);#2;
        if(tx_start!==expect_reply || (expect_reply&&tx_data!==reply)) $fatal(1,"UART %02x got %02x expected %02x",command,tx_data,reply);
        if({capture,init_card,gallery,prev_photo,next_photo}!==requests) $fatal(1,"Photo request mismatch for %02x",command);
        if(delete_photo!==(command=="d"&&!wb_reserved)) $fatal(1,"Delete request mismatch");
        @(negedge clk);rx_valid=0;tx_done=expect_reply;
        @(posedge clk);#2;
        if(tx_start || {capture,init_card,gallery,prev_photo,next_photo}!==0) $fatal(1,"Repeated pulse/reply");
        if(delete_photo) $fatal(1,"Repeated delete pulse");
        @(negedge clk);tx_done=0;
    end
endtask
initial begin
    repeat(4) @(posedge clk);@(negedge clk);rst_n=1;
    @(posedge clk);#2;if(mode!==0||median||shape) $fatal(1,"Photo reset defaults");
    send("i",0,0,5'b01000);send("I",0,0,5'b01000);send("b",0,0,5'b10000);
    send("d",0,0,0);
    send("x","X",1,5'b00100);send("<","<",1,5'b00010);send(">",">",1,5'b00001);
    send("G","1",1,0);send("T","0",1,0);send("T","1",1,0);send("C","0",1,0);
    send("E","!",1,0);send("S","!",1,0);send("O","!",1,0);
    send("|","!",1,0);
    send("D","!",1,0);send("Q","!",1,0);send("M","!",1,0);send("A","!",1,0);send("V","!",1,0);send("J","!",1,0);
    send("H",0,0,0);send("1",0,0,0);send("2",0,0,0);send("0",0,0,0);send(13,"!",1,0);
    send("L",0,0,0);send("4",0,0,0);send("0",0,0,0);send(13,"!",1,0);
    if(high_threshold!==160||low_threshold!==80) $fatal(1,"Disabled thresholds changed");
    send("W",0,0,0);send("b",0,0,0); // lowercase WB channel must NOT capture
    send("2",0,0,0);send("8",0,0,0);send("0",0,0,0);send(13,"K",1,0);
    if(wb_blue!==280) $fatal(1,"White balance failed");
    send("W",0,0,0);send("d","W",1,0); // WB reset must never delete a file
    send("Z","1",1,0);send("Z","0",1,0);
    $display("PASS photo-only UART: native TF/photo/gallery enabled, color/gray only, vision rejected, lowercase WB safe");$finish;
end
initial begin #100000;$fatal(1,"Photo UART timeout");end
endmodule
