`timescale 1ns/1ps
module gray_canny_alignment_tb;
parameter WIDTH=32;
localparam HEIGHT=10;
reg clk=0,rst_n=0,vs=0,hs=0,de=0;
reg [7:0] gray=0;
wire avs,ahs,ade,cvs,chs,cde;
wire [7:0] original_gray,edge_pixel;
integer f,y,x,n,output_frame=-1,output_row=0,output_x=0,checked=0;
reg old_vs=0,old_de=0;
always #5 clk=~clk;
function [7:0] pattern;
    input integer frame,row,column;
    begin pattern=(column*19+row*53+frame*97)&255;end
endfunction
gray_canny_alignment #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) dut (
    .clk(clk),.rst_n(rst_n),.in_vsync(vs),.in_hsync(hs),.in_href(de),.in_gray(gray),
    .out_vsync(avs),.out_hsync(ahs),.out_href(ade),.out_gray(original_gray));
canny_edge #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) reference_canny (
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(vs),.per_frame_hsync(hs),.per_frame_href(de),
    .per_img_gray(gray),.per_img_red(gray),.per_img_green(gray),.per_img_blue(gray),
    .low_threshold(11'd20),.high_threshold(11'd45),
    .post_frame_vsync(cvs),.post_frame_hsync(chs),.post_frame_href(cde),.post_img_edge(edge_pixel));
always @(posedge clk)begin
    #2;
    if(rst_n)begin
        if({avs,ahs,ade}!=={cvs,chs,cde})$fatal(1,"Original gray timing differs from actual legacy Canny");
        if(!avs)begin output_row=0;output_x=0;end
        if(avs&&!old_vs)output_frame=output_frame+1;
        if(ade)begin
            if(original_gray!==pattern(output_frame,output_row>4 ? output_row-4 : 0,output_x))
                $fatal(1,"Raw gray mismatch frame=%0d row=%0d x=%0d got=%0d expected=%0d",output_frame,output_row,output_x,original_gray,pattern(output_frame,output_row>4?output_row-4:0,output_x));
            output_x=output_x+1;checked=checked+1;
        end
        if(!ade&&old_de)begin
            if(output_x!=WIDTH)$fatal(1,"Line length changed");
            output_x=0;output_row=output_row+1;
        end
        old_vs=avs;old_de=ade;
    end
end
task pixel;
    input v,h,d;
    input [7:0] g;
    begin @(negedge clk);vs=v;hs=h;de=d;gray=g;end
endtask
initial begin
    repeat(4)@(negedge clk);rst_n=1;
    for(f=0;f<3;f=f+1)begin
        for(n=0;n<80;n=n+1)pixel(0,0,0,0);
        for(y=0;y<HEIGHT;y=y+1)begin
            for(x=0;x<WIDTH;x=x+1)pixel(1,1,1,pattern(f,y,x));
            for(n=0;n<40;n=n+1)pixel(1,0,0,0);
        end
    end
    repeat(80)pixel(0,0,0,0);
    if(checked!=3*WIDTH*HEIGHT)$fatal(1,"Missing raw gray pixels");
    $display("PASS original-gray alignment width=%0d: three frames exact unsmoothed pixels and actual Canny sync/DE alignment",WIDTH);$finish;
end
initial begin #10000000;$fatal(1,"Alignment timeout");end
endmodule
