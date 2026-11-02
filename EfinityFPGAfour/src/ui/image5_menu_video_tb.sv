`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"
module image5_menu_video_tb;
 reg clk=0,pclk=0,rst_n=0,vs=0,hs=0,de=0;
 reg [23:0] rgb=0;reg [`M5_DISP_WIDTH-1:0] requested=0;
 wire [`M5_DISP_WIDTH-1:0] active;wire ovs,ohs,ode;wire [23:0] orgb;
 always #5 clk=~clk;always #7 pclk=~pclk;
 image5_menu_cdc cdc(.clk(clk),.rst_n(rst_n),.requested(requested),
  .pclk(pclk),.prst_n(rst_n),.frame_vsync(vs),.active(active));
 image5_menu_render #(.H_DISP(640),.V_DISP(360)) dut(.clk(pclk),.rst_n(rst_n),
  .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_rgb(rgb),.disp(active),
  .out_vsync(ovs),.out_hsync(ohs),.out_href(ode),.out_rgb(orgb));
 reg [26:0] q[0:2];integer qx[0:2],qy[0:2];
 integer image_width=640,image_height=360;integer arg_dummy;
 integer px=0,py=0,f=-1,file=0,pixels=0,ink=0,selected=0,edited=0;
 reg checking=1;reg [`M5_DISP_WIDTH-1:0] previous_active;
 initial begin for(integer j=0;j<3;j++)begin q[j]=0;qx[j]=0;qy[j]=0;end end
 always @(posedge pclk)begin
  previous_active=active;
  if(rst_n)begin
   q[2]=q[1];q[1]=q[0];q[0]={vs,hs,de,rgb};
   qx[2]=qx[1];qx[1]=qx[0];qx[0]=px;
   qy[2]=qy[1];qy[1]=qy[0];qy[0]=py;
   #1;
   if(active!==previous_active&&vs)$fatal(1,"Display changed during active frame");
   if(checking)begin
    if({ovs,ohs,ode}!==q[2][26:24])$fatal(1,"Menu skewed VS/HS/DE");
    if(active[`M5D_STATE+:2]==0||!q[2][24]||qx[2]<8||qx[2]>=548||qy[2]<8||qy[2]>=296)begin
     if(orgb!==q[2][23:0])$fatal(1,"Menu changed closed/outside pixels");
    end else begin
     if(orgb!=24'h101020&&orgb!=24'hffffff&&orgb!=24'hffff00&&orgb!=24'h00ffff)
      $fatal(1,"Unexpected menu color");
     if(orgb==24'hffffff)ink++;
     if(orgb==24'hffff00)selected++;
     if(orgb==24'h00ffff)edited++;
    end
    if(ode&&file!=0)begin
     pixels++;$fwrite(file,"%0d %0d %0d\n",orgb[23:16],orgb[15:8],orgb[7:0]);
    end
   end
  end
 end
 task tick(input bit v,h,d,input [23:0] color,input integer x,y);
  @(negedge pclk);vs=v;hs=h;de=d;rgb=color;px=x;py=y;
 endtask
 task blank;
  repeat(24)tick(0,0,0,0,0,0);
 endtask
 task show(input integer which);
  string name;
  begin
   f=which;ink=0;selected=0;edited=0;pixels=0;
   case(which)0:name="menu_closed.ppm";1:name="menu_browse.ppm";2:name="menu_edit.ppm";3:name="menu_adc.ppm";4:name="menu_boot.ppm";default:name="menu_load.ppm";endcase
   file=$fopen(name,"w");$fwrite(file,"P3\n640 360\n255\n");
   for(integer y=0;y<image_height;y++)begin
    for(integer x=0;x<image_width;x++)tick(1,x<8,1,{8'h20,x[7:0],y[7:0]},x,y);
    repeat(40)tick(1,0,0,0,0,y);
   end
   // Keep VS high until all three pipeline stages have drained.
   repeat(5)tick(1,0,0,0,0,360);
   $fclose(file);file=0;
   if(pixels!=640*360)$fatal(1,"Frame pixels %0d",pixels);
   if(which!=0&&ink==0)$fatal(1,"No menu glyphs");
   if((which==1||which>=3)&&selected==0)$fatal(1,"No selected row");
   if(which==2&&edited==0)$fatal(1,"No EDIT row");
   blank();
  end
 endtask
 reg [`M5_DISP_WIDTH-1:0] base,saved,latest;
 initial begin
  // Runtime dimensions prevent xelab from expanding hundreds of thousands
  // of task calls during elaboration; the tested geometry remains 640x360.
  arg_dummy=$value$plusargs("WIDTH=%d",image_width);arg_dummy=$value$plusargs("HEIGHT=%d",image_height);
  if(image_width!=640||image_height!=360)$fatal(1,"fixed geometry required");
  repeat(5)@(negedge pclk);rst_n=1;
  base=0;base[`M5D_VIEW+:2]=2;base[`M5D_FLAGS+:7]=7'b1010011;
  base[`M5D_HIGH+:16]=16'h0060;base[`M5D_LOW+:16]=16'h0030;
  base[`M5D_WBR+:16]=16'h0496;base[`M5D_WBG+:16]=16'h0416;base[`M5D_WBB+:16]=16'h0313;
  base[`M5D_GAMMA+:12]=12'h255;base[`M5D_USB_MODE+:3]=3;base[`M5D_USB_SIZE+:2]=1;
  base[`M5D_ADC0+:16]=16'h2048;base[`M5D_ADC1+:16]=16'h4095;
  requested=base;blank();show(0);
  base[`M5D_STATE+:2]=`M5_BROWSE;requested=base;blank();show(1);
  base[`M5D_STATE+:2]=`M5_EDIT;base[`M5D_CURSOR+:5]=`M5_CANNY;
  base[`M5D_HIGH+:16]=16'h0065;base[`M5D_LOW+:16]=16'h0032;requested=base;blank();show(2);
  base[`M5D_STATE+:2]=`M5_BROWSE;base[`M5D_CURSOR+:5]=`M5_ADC;base[`M5D_WINDOW+:5]=11;
  requested=base;blank();show(3);
  base[`M5D_BOOT+:2]=1;base[`M5D_BOOT_STATUS+:4]=1;
  base[`M5D_CURSOR+:5]=`M5_BOOT;base[`M5D_WINDOW+:5]=13;requested=base;blank();show(4);
  base[`M5D_CURSOR+:5]=`M5_LOAD;requested=base;blank();show(5);
  checking=0;tick(1,0,0,0,0,0);saved=active;
  for(integer n=1;n<=25;n++)begin
   @(negedge clk);requested={5{30'h3A5A0000+n}};
  end
  latest=requested;repeat(20)@(negedge pclk);
  if(active!==saved)$fatal(1,"CDC committed outside blanking");
  blank();repeat(30)tick(0,0,0,0,0,0);
  if(active!==latest)$fatal(1,"CDC did not coalesce latest atomic record");
  $display("PASS image5 menu video: fixed three-register VS/HS/DE/RGB delay, closed/outside equality, browse/edit/ADC glyphs, atomic blank-only CDC and rapid update coalescing");$finish;
 end
 initial begin #30000000;$fatal(1,"Menu video watchdog");end
endmodule
