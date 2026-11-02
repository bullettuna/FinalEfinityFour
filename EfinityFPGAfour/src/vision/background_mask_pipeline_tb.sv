`timescale 1ns/1ps
module background_mask_pipeline_tb #(parameter WIDTH=32,HEIGHT=24,H_TOTAL=48,NOISE=1,REFINE=0);
 localparam SW=WIDTH/2,SH=HEIGHT/2,TD=12*H_TOTAL;
 reg clk=0,rst=0,vs=0,hs=0,de=0,bg_valid=1,sample_valid=1;
 reg [7:0] cr=0,br=0,threshold=24;
 always #5 clk=~clk;
 wire ov,oh,oe,om,orm,owm,err,cv,cm;wire [7:0] avgc,avgb;
 background_mask_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(H_TOTAL),.REFINE_AVAILABLE(REFINE)) dut(
  .clk(clk),.rst_n(rst),.in_vsync(vs),.in_hsync(hs),.in_href(de),
  .background_valid(bg_valid),.background_sample_valid(sample_valid),.current_raw(cr),.background_raw(br),.binary_mode(1'b0),.binary_pixel(1'b0),.original_edge(1'b0),.noise_mode(NOISE),.diff_threshold(threshold),
  .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_mask(om),.out_raw_mask(orm),.out_weak_mask(owm),.stream_error(err),
  .debug_cell_valid(cv),.debug_cell_mask(cm),.debug_current_mean(avgc),.debug_background_mean(avgb));
 reg golden[0:4][0:SH+3][0:SW-1];
 reg weak_golden[0:SH+3][0:SW-1];
 integer mode=0,expected_threshold=24,cycles=0,out_x=0,out_y=-1,checked=0,cells=0,frames=0;
 reg old_de=0;reg [2:0] history[0:TD+1];reg [2:0] want_timing;
 function integer raw_background(input integer x,y);
  raw_background=50+(x%2)*20+(y%2)*40+(x/2)%11+(y/2)%7;
 endfunction
 function integer raw_current(input integer x,y);
  integer sx,sy,value;
  begin
   sx=x/2;sy=y/2;value=raw_background(x,y);
   if(mode!=0&&mode!=4)begin
    if((sx>=3&&sx<=9&&sy>=2&&sy<=8&&!(sx==6&&sy==5))||
       (sx>=SW-5&&sy>=SH-5)||sx==SW-3||(sx==1&&sy==SH-2))value=value+80;
   end
   if(x%2==0&&y%2==0&&!(mode!=0&&mode!=4&&sx>=3&&sx<=9&&sy>=2&&sy<=8))value=value+40;
   raw_current=value;
  end
 endfunction
 task make_golden;
  integer sc,sb,xx,yy;reg result,support;
  begin
   for(integer y=0;y<SH+4;y=y+1)for(integer x=0;x<SW;x=x+1)begin
    sc=0;sb=0;
    for(integer a=0;a<2;a=a+1)for(integer b=0;b<2;b=b+1)begin
     sc=sc+raw_current(x*2+b,y*2+a);sb=sb+raw_background(x*2+b,y*2+a);
    end
    sc=(sc+2)/4;sb=(sb+2)/4;
    golden[0][y][x]=y<SH&&mode!=3&&((sc>=sb?sc-sb:sb-sc)>=expected_threshold);
    weak_golden[y][x]=REFINE&&y<SH&&mode!=3&&((sc>=sb?sc-sb:sb-sc)>=(expected_threshold>1?expected_threshold/2:expected_threshold));
   end
   for(integer k=1;k<=4;k=k+1)
    for(integer y=0;y<SH+4;y=y+1)for(integer x=0;x<SW;x=x+1)begin
     result=(k==1||k==4);support=0;
     for(integer a=0;a<3;a=a+1)for(integer b=0;b<3;b=b+1)begin
      yy=y+a-2;if(yy<0)yy=0;
      xx=x+b-1;if(xx<0)xx=0;if(xx>=SW)xx=SW-1;
      if(k==1||k==4)result=result&golden[k-1][yy][xx];else result=result|golden[k-1][yy][xx];
      if(a!=1||b!=1)support=support|golden[k-1][yy][xx];
     end
     if(k<=2 && NOISE!=1)begin
      yy=y>0?y-1:0;
      result=golden[k-1][yy][x]&&((k==1&&NOISE==2)?support:1'b1);
     end
     golden[k][y][x]=result;
    end
   if(mode==1&&!golden[4][SH+3][SW-1])$fatal(1,"bottom/right foreground coverage missing");
  end
 endtask
 always @(posedge clk)begin
  history[cycles%(TD+2)]={vs,hs,de};
  #1;
  if(rst&&cycles>TD+2)begin
   want_timing=history[(cycles-TD-1)%(TD+2)];
   if({ov,oh,oe}!==want_timing)$fatal(1,"mask timing changed got=%b expected=%b cycle=%d",{ov,oh,oe},want_timing,cycles);
  end
  if(!ov)out_y=-1;
  if(oe)begin
   if(!old_de)begin out_x=0;out_y=out_y+1;end
   if(out_y>=HEIGHT||out_x>=WIDTH)$fatal(1,"output frame geometry wrong");
   if(om!==golden[4][out_y/2+4][out_x/2])
    $fatal(1,"mask mismatch mode=%d x=%d y=%d got=%b expected=%b tag=%d/%d wr=%d",mode,out_x,out_y,om,golden[4][out_y/2+4][out_x/2],dut.tag0,dut.tag1,dut.write_y);
   if(orm!==golden[0][out_y/2][out_x/2])$fatal(1,"raw-mask alignment mismatch x=%d y=%d",out_x,out_y);
   if(owm!==weak_golden[out_y/2][out_x/2])$fatal(1,"weak-mask alignment/frame threshold mismatch x=%d y=%d got=%b expected=%b",out_x,out_y,owm,weak_golden[out_y/2][out_x/2]);
   out_x=out_x+1;checked=checked+1;
   if(out_x==WIDTH&&out_y==HEIGHT-1)frames=frames+1;
  end
  old_de=oe;
  if(cv)begin
   automatic integer x=dut.average.cell_x,y=dut.average.cell_y;
   automatic integer sc=0,sb=0;
   for(integer a=0;a<2;a=a+1)for(integer b=0;b<2;b=b+1)begin sc=sc+raw_current(x*2+b,y*2+a);sb=sb+raw_background(x*2+b,y*2+a);end
   if(avgc!=(sc+2)/4||avgb!=(sb+2)/4||cm!==golden[0][y][x])
    $fatal(1,"Bayer pair alignment/average mismatch mode=%d x=%d y=%d got=%d/%d mask=%b",mode,x,y,avgc,avgb,cm);
   cells=cells+1;
  end
  if(err)$fatal(1,"row serialization overflow");
  cycles=cycles+1;
 end
 task tick;
  begin hs=cycles%H_TOTAL>=4;@(negedge clk);end
 endtask
 task run_frame(input integer new_mode);
  integer old_checked,old_cells;
  begin
   mode=new_mode;threshold=new_mode==2?100:24;expected_threshold=threshold;
   bg_valid=new_mode!=3;sample_valid=new_mode!=3;make_golden();old_checked=checked;old_cells=cells;
   vs=0;de=0;repeat(5*H_TOTAL)tick();vs=1;repeat(36*H_TOTAL)tick();
   for(integer y=0;y<HEIGHT;y=y+1)begin
    for(integer x=0;x<WIDTH;x=x+1)begin
     de=1;br=raw_background(x,y);cr=raw_current(x,y);
     if(new_mode==2&&y==HEIGHT/2)threshold=0;
     tick();
    end
    de=0;repeat(H_TOTAL-WIDTH)tick();
   end
   // Match the board's short four-line front porch: RAW VSYNC goes low
   // while the last four synthetic morphology rows are still flushing.
   repeat(4*H_TOTAL)tick();vs=0;repeat(5*H_TOTAL)tick();vs=1;repeat(7*H_TOTAL)tick();
   if(checked-old_checked!=WIDTH*HEIGHT||cells-old_cells!=SW*SH)$fatal(1,"frame/cell count mismatch %d %d",checked-old_checked,cells-old_cells);
   $display("PASS difference mode %d: Bayer mean + four morphology stages + exact 2x pixels/timing",new_mode);
  end
 endtask
 initial begin
  make_golden();repeat(5)@(negedge clk);rst=1;
  run_frame(0);run_frame(1);run_frame(2);run_frame(3);run_frame(4);
  if(frames!=5)$fatal(1,"frame count wrong");
  $display("PASS fixed-background mask pipeline: noise/lines/holes, threshold frame latch, missing background, last rows and stale-frame isolation");$finish;
 end
 initial begin #300000000;$fatal(1,"background pipeline timeout");end
endmodule
