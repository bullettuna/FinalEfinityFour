`timescale 1ns/1ps

// Compare the complete registered box + Chinese label path with frames drawn
// independently by Pillow. Includes blanking/sync alignment and both objects.
module shape_label_overlay_tb;
parameter WIDTH = 640, HEIGHT = 240;
localparam FRAME_PIXELS = WIDTH*HEIGHT;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
reg vsync = 0, href = 0, hsync = 0, edge_mask = 0;
reg [7:0] red = 0, green = 0, blue = 0;
reg valid1 = 0, valid2 = 0;
reg [11:0] x1 = 0, xmax1 = 0, x2 = 0, xmax2 = 0;
reg [10:0] y1 = 0, ymax1 = 0, y2 = 0, ymax2 = 0;
reg [1:0] type1 = 0, type2 = 0;
wire box_vsync, box_href, box_hsync, out_vsync, out_href, out_hsync;
wire [7:0] box_r, box_g, box_b, out_r, out_g, out_b;
shape_overlay #(.ROI_X_MIN(8), .ROI_X_MAX(WIDTH-9),
                .ROI_Y_MIN(8), .ROI_Y_MAX(HEIGHT-9)) boxes(
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(vsync),.per_frame_href(href),
    .per_frame_hsync(hsync),.per_img_mask(edge_mask),
    .per_img_red(red),.per_img_green(green),.per_img_blue(blue),
    .bbox_valid(valid1),.bbox_x_min(x1),.bbox_x_max(xmax1),
    .bbox_y_min(y1),.bbox_y_max(ymax1),.shape_type(type1),
    .bbox2_valid(valid2),.bbox2_x_min(x2),.bbox2_x_max(xmax2),
    .bbox2_y_min(y2),.bbox2_y_max(ymax2),.shape2_type(type2),
    .post_frame_vsync(box_vsync),.post_frame_href(box_href),.post_frame_hsync(box_hsync),
    .post_img_red(box_r),.post_img_green(box_g),.post_img_blue(box_b)
);
shape_label_overlay #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) labels(
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(box_vsync),.per_frame_href(box_href),
    .per_frame_hsync(box_hsync),.per_img_red(box_r),.per_img_green(box_g),.per_img_blue(box_b),
    .bbox_valid(valid1),.bbox_x_min(x1),.bbox_y_min(y1),.shape_type(type1),
    .bbox2_valid(valid2),.bbox2_x_min(x2),.bbox2_y_min(y2),.shape2_type(type2),
    .post_frame_vsync(out_vsync),.post_frame_href(out_href),.post_frame_hsync(out_hsync),
    .post_img_red(out_r),.post_img_green(out_g),.post_img_blue(out_b)
);
reg [23:0] expected [0:5*FRAME_PIXELS-1];
integer input_index = -1;
integer index_pipe [0:3];
reg [2:0] timing_pipe [0:3];
integer i, checked = 0, ppm;
always @(posedge clk) begin
    if (!rst_n) begin
        for (i=0;i<4;i=i+1) begin
            index_pipe[i] <= -1;
            timing_pipe[i] <= 0;
        end
    end else begin
        index_pipe[0] <= input_index;
        timing_pipe[0] <= {vsync,href,hsync};
        for (i=1;i<4;i=i+1) begin
            index_pipe[i] <= index_pipe[i-1];
            timing_pipe[i] <= timing_pipe[i-1];
        end
        #1;
        if ({out_vsync,out_href,out_hsync} !== timing_pipe[3])
            $fatal(1,"FAIL timing alignment at pixel %0d",index_pipe[3]);
        if (index_pipe[3] >= 0) begin
            if ({out_r,out_g,out_b} !== expected[index_pipe[3]])
                $fatal(1,"FAIL pixel %0d (frame=%0d x=%0d y=%0d): got %06x expected %06x",
                    index_pipe[3],index_pipe[3]/FRAME_PIXELS,
                    index_pipe[3]%WIDTH,(index_pipe[3]%FRAME_PIXELS)/WIDTH,
                    {out_r,out_g,out_b},expected[index_pipe[3]]);
            if (index_pipe[3] < FRAME_PIXELS)
                $fwrite(ppm,"%c%c%c",out_r,out_g,out_b);
            checked = checked + 1;
        end else if (!out_href && {out_r,out_g,out_b} !== 24'd0)
            $fatal(1,"FAIL nonblack blanking");
    end
end
integer f,x,y;
initial begin
    $readmemh("shape_labels_expected.mem",expected);
    ppm = $fopen("shape_labels_actual.ppm","wb");
    $fwrite(ppm,"P6\n%0d %0d\n255\n",WIDTH,HEIGHT);
    repeat (4) @(negedge clk);
    rst_n = 1;
    for (f=0;f<5;f=f+1) begin
        valid1=1; valid2=1;
        x1=50; xmax1=250; y1=80; ymax1=150; type1=1;
        x2=360; xmax2=550; y2=160; ymax2=220; type2=2;
        case(f)
            1: begin type1=2; type2=1; end
            2: begin
                x1=WIDTH-10; xmax1=WIDTH-2; y1=2; ymax1=70;
                x2=3; xmax2=170; y2=HEIGHT-10; ymax2=HEIGHT-2;
            end
            3: begin type1=0; valid2=0; end
            4: begin
                type1=2; type2=1;
                x2=x1; xmax2=xmax1; y2=y1; ymax2=ymax1;
            end
        endcase
        vsync=1;
        for (y=0;y<HEIGHT;y=y+1) begin
            for (x=0;x<WIDTH;x=x+1) begin
                href=1; hsync=y%2; edge_mask=(x==WIDTH/2);
                red=180+x%40; green=180+y%40; blue=180+(x+y)%40;
                input_index=f*FRAME_PIXELS+y*WIDTH+x;
                @(negedge clk);
            end
            href=0; input_index=-1; edge_mask=0; hsync=0;
            repeat (6) @(negedge clk);
        end
        vsync=0;
        repeat (8) @(negedge clk);
    end
    $fclose(ppm);
    if (checked != 5*FRAME_PIXELS) $fatal(1,"FAIL lost active pixels: %0d",checked);
    $display("PASS Chinese labels, independent types, clipping, overlap, unknown/invalid clearing, RGB/sync: %0d pixels",checked);
    $finish;
end
initial begin
    #200000000;
    $fatal(1,"FAIL timeout");
end
endmodule
