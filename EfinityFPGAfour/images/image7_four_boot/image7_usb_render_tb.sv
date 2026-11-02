`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"
`include "images/image5_canny/image5_menu_defs.vh"
`include "images/image7_four_boot/image7_usb_menu_defs.vh"
module image7_usb_render_tb #(parameter IMAGE=7);
 reg clk=0,rst_n=0,vs=0,hs=0,de=0;reg [23:0] rgb=0;always #5 clk=~clk;
 reg [155:0] record_=0;wire ovs,ohs,ode;wire [23:0] out_;
 generate if(IMAGE==1)begin:g1
 stable_menu_render1 r(clk,rst_n,vs,hs,de,rgb,record_[129:0],ovs,ohs,ode,out_);
 end else if(IMAGE==5)begin:g5
 stable_menu_render5 r(clk,rst_n,vs,hs,de,rgb,record_[155:0],ovs,ohs,ode,out_);
 end else begin:g7
 image7_usb_menu_render r(clk,rst_n,vs,hs,de,rgb,record_[154:0],ovs,ohs,ode,out_);
 end endgenerate
 // image5 has two extra unrelated display bits; all fields under test fit.
 integer px=0,py=0,frame_=0,file_,writes=0;reg checking=0;
 wire badge=de&&px>=8&&px<26&&py>=8&&py<32;
 wire [5:0] glyph=(IMAGE==1?8'h31:IMAGE==5?8'h32:8'h33)-8'h20;
 wire [2:0] fr=(py-8)/3,fc=(px-8)/3;wire [7:0] bits_;
 menu_font_8x8 ref_font(glyph,fr,bits_);
 wire [23:0] expected_rgb=badge?(bits_[7-fc]?24'hffffff:24'h101020):rgb;
 reg [23:0] pipe[0:2];reg [2:0] vp=0,hp=0,dp=0,compare_=0;
 always @(posedge clk)begin
  if(!rst_n)begin vp<=0;hp<=0;dp<=0;compare_<=0;end
  else begin
   vp<={vp[1:0],vs};hp<={hp[1:0],hs};dp<={dp[1:0],de};
   compare_<={compare_[1:0],checking&&(!de||badge||record_[1:0]==0||px<40||px>=580||py<8||py>=296)};
   pipe[0]<=expected_rgb;pipe[1]<=pipe[0];pipe[2]<=pipe[1];
   #1;
   if(frame_==1&&de&&g7.r.item_row&&g7.r.row_item==20)begin
    if(g7.r.cell_col==1&&g7.r.ch0!="U")$fatal(1,"USB label missing");
    if(g7.r.cell_col==10&&g7.r.ch0!="O")$fatal(1,"USB ON value missing");
    if(g7.r.cell_col==11&&g7.r.ch0!="N")$fatal(1,"USB ON state incorrect");
   end
   if(ovs!==vp[2]||ohs!==hp[2]||ode!==dp[2])$fatal(1,"image%0d sync/DE pipeline changed",IMAGE);
   if(compare_[2]&&out_!==pipe[2])$fatal(1,"image%0d badge/passthrough RGB differs",IMAGE);
   if(ode&&checking)begin $fwrite(file_,"%c%c%c",out_[23:16],out_[15:8],out_[7:0]);writes=writes+1;end
  end
 end
 task drive(input bit v,input bit h,input bit d,input integer x,input integer y);
  begin @(negedge clk);vs=v;hs=h;de=d;px=x;py=y;rgb={x[7:0],y[7:0],8'h40};end
 endtask
 initial begin
  #40;rst_n=1;
  for(frame_=0;frame_<2;frame_=frame_+1)begin
   record_=0;
   if(frame_==1)begin
    record_[1:0]=1;
    if(IMAGE==7)begin
     record_[2+:5]=20;record_[7+:5]=13;record_[`M7_MD_USB_POINTS_OFF]=1;record_[`M7_MD_STATUS_OFF+:16]=16'h0403;record_[`M7_MD_CHECK_OFF+:8]=8'h2e;
    end
   end
   file_=$fopen(frame_==0?"closed.ppm":"menu.ppm","wb");$fwrite(file_,"P6\n640 360\n255\n");writes=0;checking=1;
   repeat(6)drive(0,0,0,0,0);
   for(integer y=0;y<360;y=y+1)begin
    repeat(4)drive(1,0,0,0,y);
    for(integer x=0;x<640;x=x+1)drive(1,1,1,x,y);
    repeat(6)drive(1,0,0,0,y);
   end
   repeat(6)drive(0,0,0,0,0);checking=0;$fclose(file_);
   if(writes!=640*360)$fatal(1,"active frame size changed");
  end
  $display("PASS USB UI image%0d: permanent correct digit, 3-clock sync/RGB path, closed/open menu and exact frame dimensions",IMAGE);$finish;
 end
 initial begin #10000000;$fatal(1,"render timeout");end
endmodule
