`timescale 1ns/1ps
// Latest-result mailbox. Neither video nor inference waits for the other.
// Four Q14.2 points in 640x360 map to native 1920x1080; all overlay timing
// and RGB gain the same single pixel-clock register stage.
module pose6_hdmi_overlay #(
 parameter PIXEL_HZ=148500000,RESULT_TIMEOUT=148500000,MIN_PEAK=13759
)(
 input sclk,srst_n,pclk,prst_n,
 input result_strobe,input [191:0] result_points,input result_valid,
 input [3:0] boot_status,input [7:0] boot_error,
 input in_vsync,in_hsync,in_href,input [23:0] in_rgb,
 output reg out_vsync,out_hsync,out_href,output reg [23:0] out_rgb
);
 reg [192:0] mailbox;
 reg request_toggle,ack_toggle;
 (* async_reg="true" *)reg ack_meta,ack_sync,req_meta,req_sync;
 always @(posedge sclk or negedge srst_n)begin
  if(!srst_n)begin mailbox<=0;request_toggle<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=ack_toggle;ack_sync<=ack_meta;
   if(result_strobe&&ack_sync==request_toggle)begin mailbox<={result_valid,result_points};request_toggle<=!request_toggle;end
  end
 end
 (* async_reg="true" *) reg [11:0] status_meta,status_sync;
 (* async_reg="true" *) reg [192:0] data_meta,data_sync;
 reg capture_wait;
 reg seen,pending,pending_valid,frame_valid;
 reg [191:0] pending_points,frame_points;
 reg [31:0] age;
 reg vs_d,de_d;
 reg [10:0] px,py;
 reg [3:0] frame_status;reg [7:0] frame_error;
 reg [2:0] prepare;
 reg [10:0] x[0:3],y[0:3];reg [3:0] point_ok;
 reg signed [12:0] dx[0:2],dy[0:2];
 reg [10:0] x0[0:2],y0[0:2],minx[0:2],maxx[0:2],miny[0:2],maxy[0:2];
 reg [12:0] tolerance[0:2];reg [2:0] line_ok;
 reg signed [25:0] product_a[0:2],product_b[0:2],row_error[0:2],pixel_error[0:2];
 wire [3:0] point_hit;
 wire [2:0] line_hit;
 genvar g;
 generate for(g=0;g<4;g=g+1)begin:g_points
  assign point_hit[g]=frame_valid&&age<RESULT_TIMEOUT&&point_ok[g]&&
   px+11'd5>=x[g]&&px<=x[g]+11'd5&&py+11'd5>=y[g]&&py<=y[g]+11'd5;
 end
 for(g=0;g<3;g=g+1)begin:g_lines
  wire signed [25:0] e=de_d?pixel_error[g]:row_error[g];
  wire [25:0] magnitude=e[25]?-e:e;
  assign line_hit[g]=frame_valid&&age<RESULT_TIMEOUT&&line_ok[g]&&prepare==0&&
   px>=minx[g]&&px<=maxx[g]&&py>=miny[g]&&py<=maxy[g]&&magnitude<=tolerance[g];
 end endgenerate
 function [10:0] screen_x;
  input [15:0] q;reg [17:0] scaled;
  begin scaled=(q*3+2)>>2;screen_x=scaled>1919?1919:scaled[10:0];end
 endfunction
 function [10:0] screen_y;
  input [15:0] q;reg [17:0] scaled;
  begin scaled=(q*3+2)>>2;screen_y=scaled>1079?1079:scaled[10:0];end
 endfunction
 function [14:0] glyph;
  input [7:0] ch;
  begin case(ch)
   "A":glyph={3'b010,3'b101,3'b111,3'b101,3'b101};
   "B":glyph={3'b110,3'b101,3'b110,3'b101,3'b110};
   "C":glyph={3'b111,3'b100,3'b100,3'b100,3'b111};
   "D":glyph={3'b110,3'b101,3'b101,3'b101,3'b110};
   "E":glyph={3'b111,3'b100,3'b110,3'b100,3'b111};
   "F":glyph={3'b111,3'b100,3'b110,3'b100,3'b100};
   "I":glyph={3'b111,3'b010,3'b010,3'b010,3'b111};
   "L":glyph={3'b100,3'b100,3'b100,3'b100,3'b111};
   "O","0":glyph={3'b111,3'b101,3'b101,3'b101,3'b111};
   "R":glyph={3'b110,3'b101,3'b110,3'b101,3'b101};
   "S":glyph={3'b111,3'b100,3'b111,3'b001,3'b111};
   "T":glyph={3'b111,3'b010,3'b010,3'b010,3'b010};
   "W":glyph={3'b101,3'b101,3'b101,3'b111,3'b101};
   "Y":glyph={3'b101,3'b101,3'b010,3'b010,3'b010};
   "1":glyph={3'b010,3'b110,3'b010,3'b010,3'b111};
   "2":glyph={3'b110,3'b001,3'b010,3'b100,3'b111};
   "3":glyph={3'b110,3'b001,3'b010,3'b001,3'b110};
   "4":glyph={3'b101,3'b101,3'b111,3'b001,3'b001};
   "5":glyph={3'b111,3'b100,3'b110,3'b001,3'b110};
   "6":glyph={3'b011,3'b100,3'b111,3'b101,3'b111};
   "7":glyph={3'b111,3'b001,3'b010,3'b010,3'b010};
   "8":glyph={3'b111,3'b101,3'b111,3'b101,3'b111};
   "9":glyph={3'b111,3'b101,3'b111,3'b001,3'b110};
   default:glyph=0;
  endcase end
 endfunction
 function [7:0] hex_char;
  input [3:0] n;
  begin hex_char=n<10?"0"+n:"A"+n-10;end
 endfunction
 wire [5:0] hud_x=px-16;
 wire [3:0] hud_y=py-12;
 wire [2:0] slot=hud_x[5:3];
 wire [1:0] gx=hud_x[2:1];wire [2:0] gy=hud_y[3:1];
 reg [31:0] label_text;reg [7:0] character;
 reg [14:0] font;
 always @*begin
  case(frame_status)
   1:label_text="LOAD";2:label_text="TEST";3:label_text="RDY ";4:label_text="ERR ";default:label_text="WAIT";
  endcase
  if(slot<4)character=label_text[(3-slot)*8+:8];
  else if(slot==5)character=hex_char(frame_error[7:4]);
  else if(slot==6)character=hex_char(frame_error[3:0]);
  else character=" ";
  font=glyph(character);
 end
 wire hud=px>=16&&px<80&&py>=12&&py<22&&gx<3&&gy<5&&font[(4-gy)*3+2-gx];
 reg [23:0] rgb;
 always @*begin
  rgb=in_rgb;
  if(|line_hit)rgb=24'hdddddd;
  if(point_hit[0])rgb=24'h49ddff;
  if(point_hit[1])rgb=24'hffcc55;
  if(point_hit[2])rgb=24'h59ff99;
  if(point_hit[3])rgb=24'hff7799;
  if(hud)rgb=frame_status==4?24'hff4444:frame_status==3?24'h44ff88:24'hffcc55;
 end
 integer i,a,b;
 reg [12:0] ax,ay;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin
   req_meta<=0;req_sync<=0;ack_toggle<=0;seen<=0;pending<=0;pending_valid<=0;frame_valid<=0;
   data_meta<=0;data_sync<=0;capture_wait<=0;
   pending_points<=0;frame_points<=0;age<=RESULT_TIMEOUT;vs_d<=0;de_d<=0;px<=0;py<=0;
   status_meta<=0;status_sync<=0;frame_status<=0;frame_error<=0;prepare<=0;point_ok<=0;line_ok<=0;
   out_vsync<=0;out_hsync<=0;out_href<=0;out_rgb<=0;
   for(i=0;i<4;i=i+1)begin x[i]<=0;y[i]<=0;end
   for(i=0;i<3;i=i+1)begin dx[i]<=0;dy[i]<=0;x0[i]<=0;y0[i]<=0;minx[i]<=0;maxx[i]<=0;miny[i]<=0;maxy[i]<=0;
    tolerance[i]<=0;product_a[i]<=0;product_b[i]<=0;row_error[i]<=0;pixel_error[i]<=0;end
  end else begin
   req_meta<=request_toggle;req_sync<=req_meta;status_meta<={boot_status,boot_error};status_sync<=status_meta;
   data_meta<=mailbox;data_sync<=data_meta;
   vs_d<=in_vsync;de_d<=in_href;
   out_vsync<=in_vsync;out_hsync<=in_hsync;out_href<=in_href;out_rgb<=in_href?rgb:in_rgb;
   if(age<RESULT_TIMEOUT)age<=age+1'b1;
   if(!in_href)px<=0;else px<=px+1'b1;
   if(!in_vsync)py<=0;else if(de_d&&!in_href)py<=py+1'b1;
   if(vs_d&&!in_vsync)begin
    frame_status<=status_sync[11:8];frame_error<=status_sync[7:0];prepare<=1;
    if(pending)begin frame_points<=pending_points;frame_valid<=pending_valid;pending<=0;end
    else if(age>=RESULT_TIMEOUT)frame_valid<=0;
   end
   if(capture_wait)begin
    pending_points<=data_sync[191:0];pending_valid<=data_sync[192];pending<=1;
    seen<=req_sync;ack_toggle<=req_sync;age<=0;capture_wait<=0;
   end else if(req_sync!=seen)capture_wait<=1;
   case(prepare)
    1:begin
     for(i=0;i<4;i=i+1)begin x[i]<=screen_x(frame_points[i*48+:16]);y[i]<=screen_y(frame_points[i*48+16+:16]);
      point_ok[i]<=frame_points[i*48+32+:16]>=MIN_PEAK&&frame_points[i*48+:16]<=2560&&frame_points[i*48+16+:16]<=1440;end
     prepare<=2;
    end
    2:begin
     for(i=0;i<3;i=i+1)begin
      a=i==2?1:0;b=i==0?1:i==1?2:3;
      dx[i]<=$signed({1'b0,x[b]})-$signed({1'b0,x[a]});dy[i]<=$signed({1'b0,y[b]})-$signed({1'b0,y[a]});
      x0[i]<=x[a];y0[i]<=y[a];minx[i]<=x[a]<x[b]?x[a]:x[b];maxx[i]<=x[a]>x[b]?x[a]:x[b];
      miny[i]<=y[a]<y[b]?y[a]:y[b];maxy[i]<=y[a]>y[b]?y[a]:y[b];line_ok[i]<=point_ok[a]&&point_ok[b];
     end
     prepare<=3;
    end
    3:begin
     for(i=0;i<3;i=i+1)begin
      product_a[i]<=dy[i]*$signed({1'b0,x0[i]});product_b[i]<=dx[i]*$signed({1'b0,y0[i]});
      ax=dx[i][12]?-dx[i]:dx[i];ay=dy[i][12]?-dy[i]:dy[i];tolerance[i]<=ax>ay?ax:ay;
     end
     prepare<=4;
    end
    4:begin
     for(i=0;i<3;i=i+1)begin row_error[i]<=product_a[i]-product_b[i];pixel_error[i]<=product_a[i]-product_b[i];end
     prepare<=0;
    end
    default:for(i=0;i<3;i=i+1)begin
     if(in_href)pixel_error[i]<=(de_d?pixel_error[i]:row_error[i])-dy[i];
     if(de_d&&!in_href)row_error[i]<=row_error[i]+dx[i];
    end
   endcase
  end
 end
endmodule
