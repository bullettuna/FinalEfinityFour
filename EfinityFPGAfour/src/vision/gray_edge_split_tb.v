`timescale 1ns/1ps
module gray_edge_split_tb;
parameter FULL_HD=0;
localparam W=FULL_HD ? 1920 : 32;
localparam H=FULL_HD ? 1080 : 6;
reg clk=0,rst_n=0,req=0,vs=0,hs=0,de=0;
reg [7:0] gray=0,edge_pixel=0;
wire ovs,ohs,ode,active;
wire [23:0] rgb;
integer f,y,x,n,visible_count,previous_x;
reg previous_vs=0,previous_de=0;
reg expected_active=0;
reg [7:0] expected_pixel;
always #5 clk=~clk;
gray_edge_split #(.IMG_HDISP(W)) dut (
    .clk(clk),.rst_n(rst_n),.split_req(req),
    .in_vsync(vs),.in_hsync(hs),.in_href(de),
    .aligned_gray(gray),.aligned_edge(edge_pixel),
    .out_vsync(ovs),.out_hsync(ohs),.out_href(ode),
    .out_rgb(rgb),.split_active(active)
);
// Model registered upstream video: the new pixel arrives just after the
// edge, while the DUT advances its coordinate using the preceding pixel.
task pixel;
    input v,h,d;
    input [7:0] g,e;
    begin
        @(posedge clk);
        if(!previous_vs || !previous_de)previous_x=0;
        else previous_x=previous_x+1;
        if(!previous_vs && !previous_de)expected_active=req;
        vs<=v;hs<=h;de<=d;gray<=g;edge_pixel<=e;
        #2;
        if({ovs,ohs,ode}!=={v,h,d})$fatal(1,"Timing changed or delayed");
        if(active!==expected_active)$fatal(1,"Split changed outside vertical blanking");
        expected_pixel=previous_x<W/2 ? g : e;
        if(rgb!==(d ? {expected_pixel,expected_pixel,expected_pixel} : 24'd0))
            $fatal(1,"Pixel mismatch f=%0d row=%0d x=%0d rgb=%h expected=%h",f,y,previous_x,rgb,expected_pixel);
        if(d)visible_count=visible_count+1;
        previous_vs=v;previous_de=d;
    end
endtask
initial begin
    previous_x=0;visible_count=0;
    repeat(4)@(negedge clk);
    rst_n=1;req=1;
    for(f=0;f<3;f=f+1)begin
        for(n=0;n<8;n=n+1)pixel(0,0,0,0,0);
        if(active!==(f!=1))$fatal(1,"New frame did not apply split request");
        for(y=0;y<H;y=y+1)begin
            pixel(1,0,0,0,0);pixel(1,1,0,0,0);
            for(x=0;x<W;x=x+1)begin
                if(y==H/2 && x==W/2)req=(f==1);
                pixel(1,1,1,(x*7+y*13+f*29)&255,((x+y)&1)?255:0);
                if(previous_x!=x)$fatal(1,"Line coordinate drift x=%0d actual=%0d",x,previous_x);
                if(active!==(f!=1))$fatal(1,"Mid-frame toggle tore the image");
            end
            pixel(1,1,0,0,0);pixel(1,0,0,0,0);
        end
    end
    if(visible_count!=3*W*H)$fatal(1,"Visible pixel count changed");
    // Asynchronous reset at an active pixel must clear mode and position.
    @(negedge clk);rst_n=0;#2;
    if(active!==0 || dut.pixel_x!==0)$fatal(1,"Reset failed");
    $display("PASS gray/edge split %0dx%0d: all pixels/boundary/line reset, unchanged RGB timing, blanking-only toggles, reset",W,H);
    $finish;
end
initial begin #100000000;$fatal(1,"Split simulation timeout");end
endmodule
