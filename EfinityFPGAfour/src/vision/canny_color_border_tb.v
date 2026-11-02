`timescale 1ns/1ps
// Reproduce the neutral Bayer startup rows -> coloured scene transition.
// Compare the original colour rendering with startup-edge suppression.
module canny_color_border_tb;
parameter WIDTH=32;
localparam HEIGHT=24;
reg clk=0,rst_n=0,vs=0,hs=0,de=0;
reg [23:0] rgb=0;
wire cvs,chs,cde,ovs,ohs,ode,gvs,ghs,gde,bvs,bhs,bde;
wire [7:0] cr,cg,cb,ce;
wire [23:0] old_rgb,guarded_rgb,background_rgb;
integer f,y,x,n,frame=-1,row=0,column=0,top_red=0,body_edges=0,pixels=0;
reg old_vs=0,old_de=0;
always #5 clk=~clk;
canny_edge #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) canny (
    .clk(clk),.rst_n(rst_n),.per_frame_vsync(vs),.per_frame_hsync(hs),.per_frame_href(de),
    .per_img_gray(rgb[15:8]),.per_img_red(rgb[23:16]),.per_img_green(rgb[15:8]),.per_img_blue(rgb[7:0]),
    .low_threshold(11'd20),.high_threshold(11'd45),
    .post_frame_vsync(cvs),.post_frame_hsync(chs),.post_frame_href(cde),
    .post_img_edge(ce),.post_img_red(cr),.post_img_green(cg),.post_img_blue(cb));
rgb_edge_colorizer #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) old_overlay (
    .clk(clk),.rst_n(rst_n),.overlay_enable(1'b1),
    .per_frame_vsync(cvs),.per_frame_hsync(chs),.per_frame_href(cde),
    .per_img_red(cr),.per_img_green(cg),.per_img_blue(cb),.per_img_edge(ce),
    .post_frame_vsync(ovs),.post_frame_hsync(ohs),.post_frame_href(ode),
    .post_img_red(old_rgb[23:16]),.post_img_green(old_rgb[15:8]),.post_img_blue(old_rgb[7:0]));
rgb_edge_colorizer #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT),.TOP_EDGE_GUARD(8)) guarded_overlay (
    .clk(clk),.rst_n(rst_n),.overlay_enable(1'b1),
    .per_frame_vsync(cvs),.per_frame_hsync(chs),.per_frame_href(cde),
    .per_img_red(cr),.per_img_green(cg),.per_img_blue(cb),.per_img_edge(ce),
    .post_frame_vsync(gvs),.post_frame_hsync(ghs),.post_frame_href(gde),
    .post_img_red(guarded_rgb[23:16]),.post_img_green(guarded_rgb[15:8]),.post_img_blue(guarded_rgb[7:0]));
rgb_edge_colorizer #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) background_overlay (
    .clk(clk),.rst_n(rst_n),.overlay_enable(1'b0),
    .per_frame_vsync(cvs),.per_frame_hsync(chs),.per_frame_href(cde),
    .per_img_red(cr),.per_img_green(cg),.per_img_blue(cb),.per_img_edge(ce),
    .post_frame_vsync(bvs),.post_frame_hsync(bhs),.post_frame_href(bde),
    .post_img_red(background_rgb[23:16]),.post_img_green(background_rgb[15:8]),.post_img_blue(background_rgb[7:0]));
always @(posedge clk)begin
    #2;
    if(rst_n)begin
        if({gvs,ghs,gde,bvs,bhs,bde}!=={ovs,ohs,ode,ovs,ohs,ode})$fatal(1,"Guard changed video timing");
        if(!ovs)begin row=0;column=0;end
        if(ovs&&!old_vs)frame=frame+1;
        if(ode)begin
            pixels=pixels+1;column=column+1;
            if(row<10 && old_rgb[23:16]>old_rgb[15:8]+50 && old_rgb[23:16]>old_rgb[7:0]+50)
                top_red=top_red+1;
            if(row<9 && guarded_rgb!==background_rgb)$fatal(1,"Startup edge coloured row=%0d x=%0d",row,column-1);
            if(row>=9 && guarded_rgb!==old_rgb)$fatal(1,"Guard modified valid body edge or background");
            if(frame==0 && row>=9 && guarded_rgb!==background_rgb)$fatal(1,"Flat body retained false startup edge");
            if(row>=10 && old_rgb!==background_rgb)body_edges=body_edges+1;
        end
        if(!ode&&old_de)begin
            if(column!=WIDTH)$fatal(1,"Overlay DE width changed");
            row=row+1;column=0;
        end
        old_vs=ovs;old_de=ode;
    end
end
task pixel;
    input v,h,d;
    input [23:0] color;
    begin @(negedge clk);vs=v;hs=h;de=d;rgb=color;end
endtask
initial begin
    repeat(4)@(negedge clk);rst_n=1;
    for(f=0;f<3;f=f+1)begin
        for(n=0;n<80;n=n+1)pixel(0,0,0,0);
        for(y=0;y<HEIGHT;y=y+1)begin
            for(x=0;x<WIDTH;x=x+1)
                pixel(1,1,1,y<2 ? 24'h606060 : ((f!=0&&y>=12&&x>=WIDTH/2) ? 24'he0e040 : 24'h40c8c8));
            for(n=0;n<40;n=n+1)pixel(1,0,0,0);
        end
    end
    repeat(80)pixel(0,0,0,0);
    if(top_red==0)$fatal(1,"Did not reproduce startup red edges");
    if(body_edges==0)$fatal(1,"Real scene produced no edges");
    if(pixels!=3*WIDTH*HEIGHT)$fatal(1,"Overlay pixel count changed");
    $display("PASS O border guard width=%0d: reproduced %0d top red pixels, suppressed startup overlay without crop/timing change, preserved %0d real body edges and all background pixels over three frames",WIDTH,top_red,body_edges);$finish;
end
initial begin #10000000;$fatal(1,"Border test timeout");end
endmodule
