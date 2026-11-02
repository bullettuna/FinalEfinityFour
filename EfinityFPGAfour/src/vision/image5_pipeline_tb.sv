`timescale 1ns/1ps
// Independent array oracles for the new median and both binary-prune passes;
// end-to-end tests exercise noisy, moving and flat frames without a camera.
module image5_pipeline_tb #(parameter WIDTH=96,HEIGHT=72);
reg clk=0,rst_n=0,vs=0,hs=0,de=0,mreq=1,dreq=1;
reg [7:0] gray=0;reg bit_pixel=0;
always #5 clk=~clk;
wire mv,mh,me;wire [7:0] mg;
wire pv,ph,pe,pbit,qv,qh,qe,qbit;
wire ev,eh,ee;wire [7:0] edge_value;
image5_gray_median #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) median_dut(
 .clk(clk),.rst_n(rst_n),.enable_req(mreq),.in_vsync(vs),.in_hsync(hs),.in_href(de),.in_gray(gray),
 .out_vsync(mv),.out_hsync(mh),.out_href(me),.out_gray(mg));
image5_edge_prune #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) prune0(
 .clk(clk),.rst_n(rst_n),.enable_req(dreq),.in_vsync(vs),.in_hsync(hs),.in_href(de),.in_edge(bit_pixel),
 .out_vsync(pv),.out_hsync(ph),.out_href(pe),.out_edge(pbit));
image5_edge_prune #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) prune1(
 .clk(clk),.rst_n(rst_n),.enable_req(dreq),.in_vsync(pv),.in_hsync(ph),.in_href(pe),.in_edge(pbit),
 .out_vsync(qv),.out_hsync(qh),.out_href(qe),.out_edge(qbit));
image5_canny_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) dut(
 .clk(clk),.rst_n(rst_n),.in_vsync(vs),.in_hsync(hs),.in_href(de),.in_gray(gray),
 .median_req(mreq),.cleanup_req(dreq),.high_threshold(11'd60),.low_threshold(11'd30),
 .gray_vsync(),.gray_hsync(),.gray_href(),.gray_pixel(),
 .out_vsync(ev),.out_hsync(eh),.out_href(ee),.out_edge(edge_value));
integer source_gray[0:HEIGHT-1][0:WIDTH-1];
integer expected_m[0:HEIGHT-1][0:WIDTH-1];
bit source_bit[0:HEIGHT-1][0:WIDTH-1];
bit expected_p[0:HEIGHT-1][0:WIDTH-1],expected_q[0:HEIGHT-1][0:WIDTH-1];
integer frame=-1,mcount=0,pcount=0,ecount=0,mwidth=0,pwidth=0,ewidth=0;
integer edges[0:3],noise[0:3],minx[0:3],maxx[0:3];
integer ticks=0,first_input=-1,mdelay=-1,pdelay=-1,edelay=-1;
integer raw_edges=0,pruned_edges=0,max_y=0;
reg mev=0,qev=0,eev=0;
function integer clampx(input integer x);clampx=x<0?0:x>=WIDTH?WIDTH-1:x;endfunction
function integer rowidx(input integer y);rowidx=y<0?0:y;endfunction
task prepare(input integer f,input bit enabled);
 integer x,y,dx,dy,n,k,j,t,values[0:8],center,shift;
 begin
 shift=f==2?WIDTH/5:0;
 for(y=0;y<HEIGHT;y=y+1)for(x=0;x<WIDTH;x=x+1)begin
  // Cropped upper body with outstretched arms, never a pose template.
  source_gray[y][x]=220;
  if((x>=WIDTH/3+shift&&x<2*WIDTH/3+shift&&y>=HEIGHT/4&&y<HEIGHT-5)||
     (x>=WIDTH/6+shift&&x<5*WIDTH/6+shift&&y>=HEIGHT/3&&y<HEIGHT/2))source_gray[y][x]=40;
  if((f==1||f==2)&&x<WIDTH/4&&x%9==4&&y%9==4)source_gray[y][x]=0;
  if(f==3)source_gray[y][x]=220;
  source_bit[y][x]=((x==WIDTH/2&&y>=14&&y<HEIGHT-4)||
    (y==HEIGHT/2&&x>=WIDTH/3&&x<WIDTH-4)||
    (x==y&&x>13&&x<WIDTH/3)||
    (x==5&&y%11==4)||(x>=9&&x<=10&&y==18)||(x>=15&&x<=17&&y==20));
 end
 for(y=0;y<HEIGHT;y=y+1)for(x=0;x<WIDTH;x=x+1)begin
  k=0;
  for(dy=-2;dy<=0;dy=dy+1)for(dx=-1;dx<=1;dx=dx+1)begin
   values[k]=source_gray[rowidx(y+dy)][clampx(x+dx)];k=k+1;
  end
  for(k=0;k<9;k=k+1)for(j=k+1;j<9;j=j+1)if(values[j]<values[k])begin t=values[k];values[k]=values[j];values[j]=t;end
  expected_m[y][x]=enabled?values[4]:source_gray[rowidx(y-1)][x];
  n=0;
  for(dy=-2;dy<=0;dy=dy+1)for(dx=-1;dx<=1;dx=dx+1)
   if(dy!=-1||dx!=0)n=n+source_bit[rowidx(y+dy)][clampx(x+dx)];
  expected_p[y][x]=source_bit[rowidx(y-1)][x]&&(!enabled||n>=2);
 end
 for(y=0;y<HEIGHT;y=y+1)for(x=0;x<WIDTH;x=x+1)begin
  n=0;
  for(dy=-2;dy<=0;dy=dy+1)for(dx=-1;dx<=1;dx=dx+1)
   if(dy!=-1||dx!=0)n=n+expected_p[rowidx(y+dy)][clampx(x+dx)];
  expected_q[y][x]=expected_p[rowidx(y-1)][x]&&(!enabled||n>=2);
 end
 end
endtask
task check_delay(input integer actual,input integer kind);
 begin
 case(kind)
 0:begin if(mdelay<0)mdelay=actual;else if(mdelay!=actual)$fatal(1,"M changed median video latency");end
 1:begin if(pdelay<0)pdelay=actual;else if(pdelay!=actual)$fatal(1,"D changed prune video latency");end
 2:begin if(edelay<0)edelay=actual;else if(edelay!=actual)$fatal(1,"M/D changed Canny video latency");end
 endcase
 end
endtask
always @(posedge clk)begin
 ticks=ticks+1;
 if(rst_n&&de&&first_input<0)first_input=ticks;
 #1;
 if(rst_n&&frame>=0)begin
  if(dut.ce&&dut.edge_pixel==255)raw_edges=raw_edges+1;
  if(dut.e1&&dut.p1)pruned_edges=pruned_edges+1;
  if(dut.e1&&dut.py>max_y)max_y=dut.py;
  if(me)begin
   if(mcount==0)check_delay(ticks-first_input,0);
   if(mcount>=WIDTH*HEIGHT)$fatal(1,"extra median pixels");
   if(mg!==expected_m[mcount/WIDTH][mcount%WIDTH])$fatal(1,"median oracle f=%0d x/y=%0d/%0d got=%0d want=%0d",frame,mcount%WIDTH,mcount/WIDTH,mg,expected_m[mcount/WIDTH][mcount%WIDTH]);
   mcount=mcount+1;mwidth=mwidth+1;
  end else if(mev)begin if(mwidth!=WIDTH)$fatal(1,"median line width");mwidth=0;end
  if(qe)begin
   if(pcount==0)check_delay(ticks-first_input,1);
   if(pcount>=WIDTH*HEIGHT)$fatal(1,"extra prune pixels");
   if(qbit!==expected_q[pcount/WIDTH][pcount%WIDTH])$fatal(1,"prune oracle f=%0d x/y=%0d/%0d got=%0d want=%0d",frame,pcount%WIDTH,pcount/WIDTH,qbit,expected_q[pcount/WIDTH][pcount%WIDTH]);
   pcount=pcount+1;pwidth=pwidth+1;
  end else if(qev)begin if(pwidth!=WIDTH)$fatal(1,"prune line width");pwidth=0;end
  if(ee)begin
   if(ecount==0)check_delay(ticks-first_input,2);
   if(ecount>=WIDTH*HEIGHT)$fatal(1,"extra Canny pixels");
   if(edge_value!==0&&edge_value!==255)$fatal(1,"Canny output not binary or unknown");
   if((ecount/WIDTH<12||ecount/WIDTH>=HEIGHT-2||ecount%WIDTH<2||ecount%WIDTH>=WIDTH-2)&&edge_value!==0)$fatal(1,"border guard coordinate error");
   if(edge_value==255)begin
    edges[frame]=edges[frame]+1;
    if(ecount%WIDTH<WIDTH/4&&ecount/WIDTH>=16)noise[frame]=noise[frame]+1;
    if(ecount/WIDTH>HEIGHT/2+12&&ecount/WIDTH<HEIGHT-8&&ecount%WIDTH>=WIDTH/3-4)begin
     if(ecount%WIDTH<minx[frame])minx[frame]=ecount%WIDTH;
     if(ecount%WIDTH>maxx[frame])maxx[frame]=ecount%WIDTH;
    end
   end
   ecount=ecount+1;ewidth=ewidth+1;
  end else begin
   if(edge_value!==0)$fatal(1,"nonzero blanking output");
   if(eev)begin if(ewidth!=WIDTH)$fatal(1,"Canny line width");ewidth=0;end
  end
  mev=me;qev=qe;eev=ee;
 end
end
task send_frame(input integer f,input bit enabled);
 integer x,y;
 begin
 frame=f;mreq=enabled;dreq=enabled;
 mcount=0;pcount=0;ecount=0;first_input=-1;raw_edges=0;pruned_edges=0;max_y=0;
 edges[f]=0;noise[f]=0;minx[f]=WIDTH;maxx[f]=-1;
 prepare(f,enabled);
 repeat(96)@(negedge clk);
 vs=1;
 for(y=0;y<HEIGHT;y=y+1)begin
  de=1;
  for(x=0;x<WIDTH;x=x+1)begin
   gray=source_gray[y][x];bit_pixel=source_bit[y][x];@(negedge clk);
  end
  de=0;gray=0;bit_pixel=0;hs=1;repeat(40)@(negedge clk);hs=0;
  // A request in the middle of a frame must not split that frame.
  if(f==0&&y==HEIGHT/2)begin mreq=0;dreq=0;end
 end
 vs=0;repeat(96)@(negedge clk);
 if(mcount!=WIDTH*HEIGHT||pcount!=WIDTH*HEIGHT||ecount!=WIDTH*HEIGHT)$fatal(1,"lost frame pixels %0d %0d %0d",mcount,pcount,ecount);
 $display("FRAME %0d edges=%0d noise=%0d torsoX=%0d..%0d raw=%0d pruned=%0d maxY=%0d",f,edges[f],noise[f],minx[f],maxx[f],raw_edges,pruned_edges,max_y);
 end
endtask
initial begin
 repeat(8)@(negedge clk);rst_n=1;
 send_frame(0,1);send_frame(1,1);send_frame(2,0);send_frame(3,1);
 if(edges[0]<HEIGHT/2||edges[1]<HEIGHT/2)$fatal(1,"body outline was lost");
 if(noise[1]>=noise[2]||noise[2]==0)$fatal(1,"median failed to reduce isolated noise");
 if(edges[3]!=0)$fatal(1,"flat frame retained preceding moving-frame edges");
 if(minx[2]-minx[1]<WIDTH/6)$fatal(1,"moving torso did not move with input");
 $display("PASS image5 %0dx%0d: independent median/prune array oracles, mid-frame requests, fixed M/D latency (%0d/%0d/%0d), binary geometry, denoising, moving upper body, fresh flat frame",WIDTH,HEIGHT,mdelay,pdelay,edelay);
 $finish;
end
initial begin #1000000000;$fatal(1,"image5 pipeline timeout");end
endmodule
