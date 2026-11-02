`timescale 1ns/1ps
// Real active-low LCD sync, back/front porches and all six display branches.
// M and display requests arrive during active lines. No monitor depends on
// the processing modules' internal row counters or their reported PASS state.
module image1_video_timing_tb;
parameter WIDTH=64,HEIGHT=48,FRAMES=12;
localparam HS=44,HB=148,HF=88,HT=WIDTH+HS+HB+HF;
localparam VS=5,VB=36,VF=4,VT=HEIGHT+VS+VB+VF;
reg clk=0,rst_n=0,median_req=1;
reg [2:0] source_req=2;
always #3.36 clk=~clk;
wire lvs,lhs,lde,lreq;
wire [11:0] lx,ly;
wire [47:0] lrgb;
wire [7:0] fixture=(lx<WIDTH/2)?8'd40:8'd200;
lcd_driver #(.H_SYNC(HS),.H_BACK(HB),.H_DISP(WIDTH),.H_FRONT(HF),.H_TOTAL(HT),
 .V_SYNC(VS),.V_BACK(VB),.V_DISP(HEIGHT),.V_FRONT(VF),.V_TOTAL(VT)) lcd(
 .clk(clk),.rst_n(rst_n),.lcd_hs(lhs),.lcd_vs(lvs),.lcd_en(lde),
 .lcd_request(lreq),.lcd_xpos(lx),.lcd_ypos(ly),.lcd_rgb(lrgb),.lcd_data({6{fixture}}));
wire gvs,ghs,gde;
wire [7:0] gray,gr,gg,gb;
grey gray_stage(.clk(clk),.rst_n(rst_n),.gray_en(1'b0),
 .per_frame_vsync(lvs),.per_frame_href(lde),.per_frame_hsync(lhs),
 .per_img_red(lrgb[23:16]),.per_img_green(lrgb[15:8]),.per_img_blue(lrgb[7:0]),
 .post_frame_vsync(gvs),.post_frame_href(gde),.post_frame_hsync(ghs),
 .post_img_gray(gray),.post_img_red(gr),.post_img_green(gg),.post_img_blue(gb));
wire mvs,mhs,mde,median_active;
wire [7:0] mg,mr,mgg,mb,original;
image1_median_frontend #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) median(
 .clk(clk),.rst_n(rst_n),.median_enable_req(median_req),
 .per_frame_vsync(gvs),.per_frame_href(gde),.per_frame_hsync(ghs),
 .per_img_gray(gray),.per_img_red(gr),.per_img_green(gg),.per_img_blue(gb),
 .post_frame_vsync(mvs),.post_frame_href(mde),.post_frame_hsync(mhs),
 .post_img_gray(mg),.post_img_red(mr),.post_img_green(mgg),.post_img_blue(mb),
 .post_original_gray(original),.median_active(median_active));
wire evs,ehs,ede;
wire [7:0] edge_pixel,er,eg,eb;
canny_edge #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) canny(
 .clk(clk),.rst_n(rst_n),.per_frame_vsync(mvs),.per_frame_href(mde),.per_frame_hsync(mhs),
 .per_img_gray(mg),.per_img_red(mr),.per_img_green(mgg),.per_img_blue(mb),
 .low_threshold(11'd10),.high_threshold(11'd20),
 .post_frame_vsync(evs),.post_frame_href(ede),.post_frame_hsync(ehs),
 .post_img_edge(edge_pixel),.post_img_red(er),.post_img_green(eg),.post_img_blue(eb));
wire ovs,ohs,ode;
wire [7:0] obr,obg,obb;
rgb_edge_colorizer #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) overlay(
 .clk(clk),.rst_n(rst_n),.overlay_enable(1'b1),
 .per_frame_vsync(evs),.per_frame_href(ede),.per_frame_hsync(ehs),
 .per_img_red(er),.per_img_green(eg),.per_img_blue(eb),.per_img_edge(edge_pixel),
 .post_frame_vsync(ovs),.post_frame_href(ode),.post_frame_hsync(ohs),
 .post_img_red(obr),.post_img_green(obg),.post_img_blue(obb));
wire avs,ahs,ade;
wire [7:0] aligned;
gray_canny_alignment #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) alignment(
 .clk(clk),.rst_n(rst_n),.in_vsync(mvs),.in_hsync(mhs),.in_href(mde),.in_gray(original),
 .out_vsync(avs),.out_hsync(ahs),.out_href(ade),.out_gray(aligned));
wire svs,shs,sde,split_active;
wire [23:0] srgb;
gray_edge_split #(.IMG_HDISP(WIDTH)) split(
 .clk(clk),.rst_n(rst_n),.split_req(source_req==4),.in_vsync(evs),.in_hsync(ehs),.in_href(ede),
 .aligned_gray(aligned),.aligned_edge(edge_pixel),.out_vsync(svs),.out_hsync(shs),
 .out_href(sde),.out_rgb(srgb),.split_active(split_active));
wire dvs,dhs,dde;
wire [7:0] dr,dg,db;
shape_recognition_pipeline #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT),
 .ROI_X_MIN(0),.ROI_X_MAX(WIDTH-1),.ROI_Y_MIN(0),.ROI_Y_MAX(HEIGHT-1)) shapes(
 .clk(clk),.rst_n(rst_n),.processing_enable(1'b0),.rect_line_fit_enable(1'b1),.line_support_level(2'd1),
 .per_frame_vsync(evs),.per_frame_href(ede),.per_frame_hsync(ehs),.per_img_edge(edge_pixel),
 .per_img_red(er),.per_img_green(eg),.per_img_blue(eb),
 .post_frame_vsync(dvs),.post_frame_href(dde),.post_frame_hsync(dhs),
 .post_img_red(dr),.post_img_green(dg),.post_img_blue(db));
wire [5:0] all_vs={dvs,svs,ovs,evs,mvs,gvs};
wire [5:0] all_hs={dhs,shs,ohs,ehs,mhs,ghs};
wire [5:0] all_de={dde,sde,ode,ede,mde,gde};
wire [143:0] all_rgb={dr,dg,db,srgb,obr,obg,obb,{3{edge_pixel}},{3{mg}},gr,gg,gb};
wire out_vs,out_hs,out_de;
wire [23:0] out_rgb;
wire [2:0] source_active;
image1_video_mux display_mux(.clk(clk),.rst_n(rst_n),.source_req(source_req),
 .in_vsync(all_vs),.in_hsync(all_hs),.in_href(all_de),.in_rgb(all_rgb),
 .out_vsync(out_vs),.out_hsync(out_hs),.out_href(out_de),.out_rgb(out_rgb),.source_active(source_active));

reg [6:0] expected_vs=0,expected_hs=0,expected_de=0;
reg [39:0] fixed_vs=0,fixed_hs=0,fixed_de=0;
integer cycles=0,last_hs=0,last_frame=0;
reg [2:0] previous_source=2;
reg previous_de=0,previous_vs=0,previous_hs=0,seen_frame=0;
integer x=0,rows=0,frames=0,low_hs=0,checked=0,switches=0;
reg [5:0] visited=0,nonzero=0;
reg [2:0] expected_timing;
reg [23:0] expected_rgb;
reg safe_to_switch;
always @(posedge clk)begin
 if(!rst_n)begin expected_vs=0;expected_hs=0;expected_de=0;end
 else begin
  expected_vs={expected_vs[5:0],gvs};
  expected_hs={expected_hs[5:0],ghs};
  expected_de={expected_de[5:0],gde};
  fixed_vs={fixed_vs[38:0],gvs};fixed_hs={fixed_hs[38:0],ghs};fixed_de={fixed_de[38:0],gde};
  cycles=cycles+1;
  expected_timing={fixed_vs[39],fixed_hs[39],fixed_de[39]};
  expected_rgb=display_mux.aligned_de[5]?display_mux.aligned_rgb[source_active*24+:24]:24'd0;
  safe_to_switch=!(|display_mux.aligned_vs)&&!(|display_mux.aligned_de)&&(&display_mux.aligned_hs);
  #1;
  if({mvs,mhs,mde}!=={expected_vs[6],expected_hs[6],expected_de[6]})
   $fatal(1,"FAIL M changes seven-clock sync latency");
  if(cycles>80 && (display_mux.aligned_vs!=={6{dvs}} || display_mux.aligned_hs!=={6{dhs}} || display_mux.aligned_de!=={6{dde}}))
   $fatal(1,"FAIL display branches have different sync phase vs=%b hs=%b de=%b",display_mux.aligned_vs,display_mux.aligned_hs,display_mux.aligned_de);
  if({evs,ehs,ede}!=={avs,ahs,ade})$fatal(1,"FAIL split original alignment");
  if({out_vs,out_hs,out_de}!==expected_timing || out_rgb!==expected_rgb)
   $fatal(1,"FAIL registered video data/timing mismatch");
  if(source_active!=previous_source)begin
   if(!safe_to_switch || out_de)$fatal(1,"FAIL display source switches outside safe blank");
   switches=switches+1;
  end
  previous_source=source_active;
  if(out_vs&&!previous_vs)begin
   if(seen_frame && rows!=HEIGHT)$fatal(1,"FAIL incomplete frame rows=%0d",rows);
   if(seen_frame)begin
    if(cycles-last_frame!=HT*VT)$fatal(1,"FAIL frame period changes during mode switch");
    frames=frames+1;
   end
   last_frame=cycles;
   seen_frame=1;rows=0;
  end
  if(out_de)begin
   if(!out_vs || !out_hs)$fatal(1,"FAIL active pixel during sync pulse");
   x=x+1;checked=checked+1;visited[source_active]=1;
   if(out_rgb!=0)nonzero[source_active]=1;
  end
  if(!out_de&&previous_de)begin
   if(x!=WIDTH)$fatal(1,"FAIL line width %0d",x);
   x=0;rows=rows+1;
  end
  if(!out_hs)low_hs=low_hs+1;
  if(out_hs&&!previous_hs)begin
   if(seen_frame && low_hs!=HS)$fatal(1,"FAIL runt horizontal sync %0d",low_hs);
   if(seen_frame && last_hs!=0 && cycles-last_hs!=HT)$fatal(1,"FAIL horizontal period changes during mode switch");
   last_hs=cycles;low_hs=0;
  end
  previous_de=out_de;previous_vs=out_vs;previous_hs=out_hs;
 end
end
integer f;
initial begin
 repeat(8)@(negedge clk);rst_n=1;
 for(f=0;f<FRAMES;f=f+1)begin
  // Submit requests partway through a real active line.
  wait(lde);repeat(WIDTH/2)@(negedge clk);
  source_req=f%6;median_req=f%2;
  @(negedge lvs);
  $display("INFO raster stimulus frame %0d/%0d complete",f+1,FRAMES);
 end
 @(posedge lvs);repeat(HT)@(negedge clk);
 if(visited!==6'b111111 || nonzero!==6'b111111 || switches<6 || frames<FRAMES-1)
  $fatal(1,"FAIL paths/frames not exercised visited=%b switches=%0d frames=%0d",visited,switches,frames);
 $display("PASS real LCD sync %0dx%0d: C/G/E/O/split/shape, active-line M/mode changes, %0d complete frames, %0d pixels",WIDTH,HEIGHT,frames,checked);
 $finish;
end
initial begin #1000000000;$fatal(1,"FAIL timeout");end
endmodule
