`timescale 1ns/1ps
// Exercise the actual shape pipeline on synthetic thin edge masks. The Canny
// kernels/stream are checked separately; no unavailable Sobel branch is used.
// Integration sampler fixture, not a legacy rollback acceptance test:
// its pair has a vertical side that legacy x-only subsampling can miss.
module shape_canny_stream_tb #(parameter PAIR_ONLY=0);
// Match the detector's fixed 4-pixel projection bins / 12-bin peak guard.
// A 48-pixel test side is below that separation limit, unlike live 1080p.
localparam W=320, H=240;
reg clk=0, rst_n=0, vsync=0, href=0;
reg [7:0] edge_pixel=0;
reg enable=1;
wire valid,valid2;
wire [1:0] kind,kind2;
always #5 clk=~clk;
shape_recognition_pipeline #(.IMG_HDISP(W),.IMG_VDISP(H),.MIN_AREA(16),
    .ROI_X_MIN(0),.ROI_X_MAX(W-1),.ROI_Y_MIN(0),.ROI_Y_MAX(H-1)) dut (
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(vsync),.per_frame_href(href),
    .per_frame_hsync(href),.per_img_edge(edge_pixel),
    .per_img_red(8'd160),.per_img_green(8'd100),.per_img_blue(8'd80),
    .processing_enable(enable),.rect_line_fit_enable(1'b1),.line_support_level(2'd0),
    .bbox_valid(valid),.shape_type(kind),.bbox2_valid(valid2),.shape2_type(kind2)
);
integer y,x,f,dx,dy,rr;
integer rect_hits=0,circle_hits=0,pair_hits=0;
task frame;
    input integer image_kind;
    begin
        @(negedge clk); vsync=0; href=0; edge_pixel=0;
        repeat(2100) @(negedge clk);
        vsync=1;
        repeat(8) @(negedge clk);
        for(y=0;y<H;y=y+1) begin
            href=1;
            for(x=0;x<W;x=x+1) begin
                dx=x-160;dy=y-120;rr=dx*dx+dy*dy;
                if(image_kind==1)
                    edge_pixel=((((x==96)||(x==223))&&(y>=56)&&(y<=183)) ||
                                (((y==56)||(y==183))&&(x>=96)&&(x<=223)))?255:0;
                else if(image_kind==2)
                    edge_pixel=(rr>=48*48 && rr<=50*50)?255:0;
                else if(image_kind==3) begin
                    dx=x-232;dy=y-112;rr=dx*dx+dy*dy;
                    edge_pixel=((((x==24)||(x==119))&&(y>=48)&&(y<=175)) ||
                        (((y==48)||(y==175))&&(x>=24)&&(x<=119)) ||
                        (rr>=40*40 && rr<=42*42))?255:0;
                end
                else edge_pixel=0;
                @(negedge clk);
            end
            href=0;edge_pixel=0;
            repeat(12) @(negedge clk);
        end
        repeat(64) @(negedge clk);
        if(image_kind!=0)
            $display("FRAME f=%0d img=%0d valid=%b kind=%0d bbox=%0d,%0d..%0d,%0d fg=%0d score=%b ready=%b density=%b",
                f,image_kind,valid,kind,dut.bbox_x_min,dut.bbox_y_min,
                dut.bbox_x_max,dut.bbox_y_max,dut.u_shape_frame_analyzer.foreground_count,
                dut.u_shape_frame_analyzer.rectangle_hough_score,
                dut.u_shape_frame_analyzer.rectangle_hough_ready,
                dut.u_shape_frame_analyzer.classification_input_valid);
        if(image_kind==3 && f==23) begin
            $display("PAIR valid2=%b kind2=%0d candidate=%b best=%b family=%0d quality=%0d selected=%0d/%0d/%0d/%0d count=%0d/%0d/%0d/%0d sides=%0d closed=%0d",
                valid2,kind2,dut.u_shape_frame_analyzer.rectangle_hough_candidate,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.best_valid,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.best_family,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.best_quality,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.selected_a0,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.selected_a1,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.selected_b0,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.selected_b1,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.validate_count_a0,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.validate_count_a1,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.validate_count_b0,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.validate_count_b1,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.validated_side_count,
                dut.u_shape_frame_analyzer.u_shape_hough_rectangle_parallel4.u_lane0.closed_side_count);
        end
        if(valid && kind==1 && image_kind==1) rect_hits=rect_hits+1;
        if(valid && kind==2 && image_kind==2) circle_hits=circle_hits+1;
        if(valid && valid2 && kind==1 && kind2==2 && image_kind==3) pair_hits=pair_hits+1;
    end
endtask
initial begin
    repeat(6) @(negedge clk);rst_n=1;
    for(f=0;f<3;f=f+1) frame(0);
    if(valid) $fatal(1,"Empty edge image produced a shape box");
    if(!PAIR_ONLY) begin
    for(f=0;f<24;f=f+1) frame(1);
    if(rect_hits==0) $fatal(1,"Rectangle contour was not classified");
    for(f=0;f<5;f=f+1) frame(0);
    if(valid) $fatal(1,"Removed rectangle kept a stale box");
    for(f=0;f<24;f=f+1) frame(2);
    if(circle_hits==0) $fatal(1,"Circle contour was not classified");
    end
    for(f=0;f<5;f=f+1) frame(0);
    for(f=0;f<24;f=f+1) frame(3);
    if(pair_hits==0) $fatal(1,"Two-object rectangle/circle classification failed");
    enable=0;frame(0);frame(0);
    if(valid || valid2 || kind!=0 || kind2!=0) $fatal(1,"Disabled shape recognition retained state");
    $display("PASS Canny-mask shape pipeline: empty, rectangle, circle, two objects, target loss and disable");
    $finish;
end
initial begin #200000000; $fatal(1,"Shape stream timeout"); end
endmodule
