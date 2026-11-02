`timescale 1ns/1ps
module video_diagnostic_mux_tb #(
    parameter FULL_HD=0
);
localparam W=FULL_HD?1920:32, H=FULL_HD?1080:24;
localparam HS=FULL_HD?44:3, HB=FULL_HD?148:5, HT=FULL_HD?2200:50;
localparam VS=5, VB=FULL_HD?36:3, VT=FULL_HD?1125:35;
reg clk=0,rst_n=0,request=0;
reg live_vsync=0,live_hsync=0,live_href=0;
wire ovs,ohs,ode,selected;
wire [23:0] rgb;
reg [23:0] live_rgb=24'h123456;
integer h=0,v=0,cycles=0,frames=0,pixels=0,lines=0,line_pixels=0;
reg de_d=0,selected_d=0;
always #5 clk=~clk;
video_diagnostic_mux #(.H_SYNC(HS),.H_BACK(HB),.H_DISP(W),.H_TOTAL(HT),
    .V_SYNC(VS),.V_BACK(VB),.V_DISP(H),.V_TOTAL(VT)) dut (
    .clk(clk),.rst_n(rst_n),.diagnostic_req(request),
    .live_vsync(live_vsync),.live_hsync(live_hsync),.live_href(live_href),.live_rgb(live_rgb),
    .out_vsync(ovs),.out_hsync(ohs),.out_href(ode),.out_rgb(rgb),.diagnostic_active(selected)
);
// Golden timing counter, deliberately independent of the DUT's counters.
reg expected_vs=0,expected_hs=0,expected_de=0;
reg [23:0] expected_rgb=0;
integer x,y;
always @(posedge clk) begin
    if(!rst_n) begin
        h=0;v=0;expected_vs=0;expected_hs=0;expected_de=0;
        live_vsync<=0;live_hsync<=0;live_href<=0;
    end else begin
        expected_hs=h>=HS;
        expected_de=h>=HS+HB && h<HS+HB+W && v>=VS+VB && v<VS+VB+H;
        x=h-HS-HB;y=v-VS-VB;
        if(!expected_de) expected_rgb=0;
        else if(x<4 || x>=W-4 || y<4 || y>=H-4 ||
                (x>=W/2-2&&x<W/2+2) || (y>=H/2-2&&y<H/2+2)) expected_rgb=24'hffffff;
        else expected_rgb=y<H/2?(x<W/2?24'hff0000:24'h00ff00):(x<W/2?24'h0000ff:24'hffff00);
        if(h==HT-1) begin
            expected_vs=v>=VS;
            h=0;v=v==VT-1?0:v+1;
        end else h=h+1;
        live_vsync<=expected_vs;live_hsync<=expected_hs;live_href<=expected_de;
        #1;
        if(selected!==selected_d && (ode || live_href || ovs || live_vsync))
            $fatal(1,"Diagnostic switch outside vertical blanking");
        selected_d=selected;
        if(!selected) begin
            if({ovs,ohs,ode,rgb}!=={live_vsync,live_hsync,live_href,live_rgb})
                $fatal(1,"Normal-video passthrough changed latency/data");
        end else begin
            if({ovs,ohs,ode,rgb}!=={expected_vs,expected_hs,expected_de,expected_rgb})
                $fatal(1,"Pattern RGB/sync mismatch at %0d,%0d",x,y);
        end
        if(ode) begin pixels=pixels+1;line_pixels=line_pixels+1;end
        if(de_d&&!ode) begin
            if(line_pixels!=W) $fatal(1,"DE width %0d expected %0d",line_pixels,W);
            line_pixels=0;lines=lines+1;
        end
        de_d=ode;
        cycles=cycles+1;
        if(cycles==HT*VT) begin
            if(pixels!=W*H || lines!=H) $fatal(1,"Frame size pixels=%0d lines=%0d",pixels,lines);
            frames=frames+1;pixels=0;lines=0;cycles=0;
        end
    end
end
initial begin
    repeat(4) @(negedge clk);rst_n=1;
    // Request while an active line is in flight; selection must wait for blank.
    wait(live_href);@(negedge clk);request=1;
    wait(selected); wait(frames>=3);
    // Live RGB changing underneath must not change the generated picture.
    @(negedge clk);live_rgb=24'habcdef;
    wait(frames>=4); wait(live_href);@(negedge clk);request=0;
    wait(!selected);wait(frames>=6);
    $display("PASS diagnostic mux: %0dx%0d, six exact frames, independent fixed pattern, blanking-only entry/exit, zero-latency live passthrough",W,H);
    $finish;
end
initial begin #(HT*VT*80);$fatal(1,"Diagnostic mux timeout");end
endmodule
