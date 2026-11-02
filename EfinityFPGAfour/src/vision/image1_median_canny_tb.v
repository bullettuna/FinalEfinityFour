`timescale 1ns/1ps
// End-to-end regression using independent impulse/step fixtures. Filtered
// fixtures have analytically known medians; the actual Canny output must lose
// impulse edges while retaining the step. Check raw split pixels separately.
module image1_median_canny_tb;
parameter WIDTH=64, HEIGHT=48;
parameter INITIAL_MEDIAN=0;
reg clk=0, rst_n=0, req=INITIAL_MEDIAN, vs=0, de=0, hs=0;
reg [7:0] gray=0, red=0, green=0, blue=0;
always #5 clk=~clk;
wire pvs,pde,phs,median_active;
wire [7:0] pg,pr,ppg,pb,original;
image1_median_frontend #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT),.DEFAULT_MEDIAN_ENABLE(INITIAL_MEDIAN)) dut(
 .clk(clk),.rst_n(rst_n),.median_enable_req(req),
 .per_frame_vsync(vs),.per_frame_href(de),.per_frame_hsync(hs),
 .per_img_gray(gray),.per_img_red(red),.per_img_green(green),.per_img_blue(blue),
 .post_frame_vsync(pvs),.post_frame_href(pde),.post_frame_hsync(phs),
 .post_img_gray(pg),.post_img_red(pr),.post_img_green(ppg),.post_img_blue(pb),
 .post_original_gray(original),.median_active(median_active));
wire cvs,cde,chs,avs,ade,ahs;
wire [7:0] edge_pixel,aligned_original;
canny_edge #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) actual_canny(
 .clk(clk),.rst_n(rst_n),.per_frame_vsync(pvs),.per_frame_href(pde),.per_frame_hsync(phs),
 .per_img_gray(pg),.per_img_red(pr),.per_img_green(ppg),.per_img_blue(pb),
 .low_threshold(11'd10),.high_threshold(11'd20),
 .post_frame_vsync(cvs),.post_frame_href(cde),.post_frame_hsync(chs),.post_img_edge(edge_pixel));
gray_canny_alignment #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT)) split_alignment(
 .clk(clk),.rst_n(rst_n),.in_vsync(pvs),.in_href(pde),.in_hsync(phs),.in_gray(original),
 .out_vsync(avs),.out_href(ade),.out_hsync(ahs),.out_gray(aligned_original));

function filtered_frame;
 input integer frame;
 begin filtered_frame=(frame<4)?((frame%2)^INITIAL_MEDIAN):(frame==4);end
endfunction
function [7:0] sample;
 input integer frame,row,column,channel,clean;
 integer value;
 begin
  if(frame<2)value=80;
  else if(frame<4)value=(column<WIDTH/2)?40:200;
  else case(channel)
    0:value=(column<WIDTH/2)?200:20;
    1:value=(column<WIDTH/2)?40:180;
    default:value=(column<WIDTH/2)?80:100;
  endcase
  if(!clean && row>2 && row<HEIGHT-3 && column>2 && column<WIDTH-3 &&
     (frame<2 || column<WIDTH/2-4 || column>WIDTH/2+4)) begin
    if(column%16==8 && row%16==8)value=255;
    if(column%16==4 && row%16==4)value=0;
  end
  sample=value;
 end
endfunction
function [7:0] luminance;
 input integer frame,row,column,clean;
 integer rr,gg,bb;
 begin
  rr=sample(frame,row,column,0,clean);gg=sample(frame,row,column,1,clean);bb=sample(frame,row,column,2,clean);
  luminance=(frame<4)?rr:(54*rr+183*gg+19*bb+128)>>8;
 end
endfunction

integer pf=-1,py=0,px=0,cf=-1,cy=0,cx=0,checked=0,canny_checked=0;
integer edge_count[0:5];
reg old_pvs=0,old_pde=0,old_cvs=0,old_cde=0;
integer src_y,shift_y,j;
integer before_file,after_file;
always @(posedge clk)begin
 #2;
 if(rst_n)begin
  if(pvs&&!old_pvs)begin pf=pf+1;py=0;px=0;end
  if(pde)begin
   if(pf<0 || pf>5)$fatal(1,"FAIL extra frontend frame");
   if(median_active!==filtered_frame(pf))$fatal(1,"FAIL M changed within active frame %0d",pf);
   if(pg!==luminance(pf,py,px,filtered_frame(pf)))
    $fatal(1,"FAIL gray median f/y/x=%0d/%0d/%0d got=%0d expected=%0d",pf,py,px,pg,luminance(pf,py,px,filtered_frame(pf)));
   if(pr!==sample(pf,py,px,0,filtered_frame(pf)) || ppg!==sample(pf,py,px,1,filtered_frame(pf)) || pb!==sample(pf,py,px,2,filtered_frame(pf)))
    $fatal(1,"FAIL aligned RGB median f/y/x=%0d/%0d/%0d got=%0d/%0d/%0d expected=%0d/%0d/%0d",pf,py,px,pr,ppg,pb,sample(pf,py,px,0,filtered_frame(pf)),sample(pf,py,px,1,filtered_frame(pf)),sample(pf,py,px,2,filtered_frame(pf)));
   src_y=filtered_frame(pf)&&py>0 ? py-1 : py;
   if(original!==luminance(pf,src_y,px,0))$fatal(1,"FAIL original-gray frontend alignment");
   px=px+1;checked=checked+1;
  end
  if(!pde&&old_pde)begin
   if(px!=WIDTH)$fatal(1,"FAIL frontend width %0d",px);
   px=0;py=py+1;
  end
  if(!pvs&&old_pvs && py!=HEIGHT)$fatal(1,"FAIL frontend height %0d",py);
  if({cvs,cde,chs}!=={avs,ade,ahs})$fatal(1,"FAIL raw split / actual Canny timing");
  if(cvs&&!old_cvs)begin cf=cf+1;cy=0;cx=0;end
  if(cde)begin
   if(cf<0 || cf>5)$fatal(1,"FAIL extra Canny frame");
   shift_y=filtered_frame(cf)?5:4;
   src_y=cy>shift_y ? cy-shift_y : 0;
   if(aligned_original!==luminance(cf,src_y,cx,0))
    $fatal(1,"FAIL unfiltered split f/y/x=%0d/%0d/%0d got=%0d expected=%0d",cf,cy,cx,aligned_original,luminance(cf,src_y,cx,0));
   if(edge_pixel!==8'h00 && edge_pixel!==8'hff)$fatal(1,"FAIL non-binary Canny output");
   if(edge_pixel!=0)edge_count[cf]=edge_count[cf]+1;
   if(cf==2 || cf==3)begin
    if(filtered_frame(cf))$fwrite(after_file,"%c",edge_pixel);
    else $fwrite(before_file,"%c",edge_pixel);
   end
   cx=cx+1;canny_checked=canny_checked+1;
  end
  if(!cde&&old_cde)begin
   if(cx!=WIDTH)$fatal(1,"FAIL Canny width %0d",cx);
   cx=0;cy=cy+1;
  end
  if(!cvs&&old_cvs && cy!=HEIGHT)$fatal(1,"FAIL Canny height %0d",cy);
  old_pvs=pvs;old_pde=pde;old_cvs=cvs;old_cde=cde;
 end
end
task pixel;
 input v,h,d;
 input [7:0] g,r,gr,b;
 begin @(negedge clk);vs=v;hs=h;de=d;gray=g;red=r;green=gr;blue=b;end
endtask
integer f,y,x,n;
reg [7:0] fixture_r,fixture_g,fixture_b,fixture_gray;
initial begin
 for(j=0;j<6;j=j+1)edge_count[j]=0;
 before_file=$fopen("median_off_edges.pgm","wb");after_file=$fopen("median_on_edges.pgm","wb");
 $fwrite(before_file,"P5\n%0d %0d\n255\n",WIDTH,HEIGHT);
 $fwrite(after_file,"P5\n%0d %0d\n255\n",WIDTH,HEIGHT);
 repeat(4)@(negedge clk);rst_n=1;
 for(f=0;f<6;f=f+1)begin
  repeat(40)pixel(0,0,0,0,0,0,0);
  for(y=0;y<HEIGHT;y=y+1)begin
   if(y==HEIGHT/2)begin
    req=(f<5)?filtered_frame(f+1):0;
   end
   for(x=0;x<WIDTH;x=x+1)begin
    fixture_r=sample(f,y,x,0,0);fixture_g=sample(f,y,x,1,0);fixture_b=sample(f,y,x,2,0);
    fixture_gray=(f<4)?fixture_r:(54*fixture_r+183*fixture_g+19*fixture_b+128)>>8;
    pixel(1,1,1,fixture_gray,fixture_r,fixture_g,fixture_b);
   end
   repeat(20)pixel(1,0,0,0,0,0,0);
  end
 end
 repeat(100)pixel(0,0,0,0,0,0,0);
 $fclose(before_file);$fclose(after_file);
 if(pf!=5 || cf!=5 || checked!=6*WIDTH*HEIGHT || canny_checked!=checked)
  $fatal(1,"FAIL dropped/extra pixels frontend=%0d Canny=%0d",checked,canny_checked);
 if(edge_count[INITIAL_MEDIAN?1:0]==0 || edge_count[INITIAL_MEDIAN?0:1]!=0)$fatal(1,"FAIL impulse noise suppression");
 if(edge_count[INITIAL_MEDIAN?3:2]<=edge_count[INITIAL_MEDIAN?2:3] || edge_count[INITIAL_MEDIAN?2:3]==0)$fatal(1,"FAIL noisy step cleanup/preservation");
 $display("PASS image1 median before actual Canny %0dx%0d: exact gray/RGB medians, bypass, active-frame M requests, six complete frames, original split alignment",WIDTH,HEIGHT);
 $display("PASS boot median=%0d; impulse-only edges %0d -> %0d; noisy-step edges %0d -> %0d; checked=%0d pixels",INITIAL_MEDIAN,edge_count[INITIAL_MEDIAN?1:0],edge_count[INITIAL_MEDIAN?0:1],edge_count[INITIAL_MEDIAN?3:2],edge_count[INITIAL_MEDIAN?2:3],checked);
 $finish;
end
initial begin #250000000;$fatal(1,"FAIL timeout");end
endmodule
