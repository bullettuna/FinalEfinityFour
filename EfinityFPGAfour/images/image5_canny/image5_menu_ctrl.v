`timescale 1ns/1ps
`include "images/image5_canny/image5_menu_defs.vh"
// One parameter bank: menu edits use current UART-owned values as their base.
// KEY2 is up/+1; KEY3 down/-1. The knob is relative, with settle/deadband.
module image5_menu_ctrl #(
 parameter integer KNOB_SCROLL_STEP=256,KNOB_DEADBAND=16
)(
 input [1:0] boot_selected,input [3:0] boot_status,
 input clk,input rst_n,input key1_short,key1_long,key_event,input [1:0] key_code,
 input [11:0] knob_value,input knob_sample,knob_ready,
 input [1:0] cur_view,input cur_median,cur_cleanup,cur_freeze,cur_test,cur_gamma,
 input [10:0] cur_high,cur_low,cur_wb_r,cur_wb_g,cur_wb_b,input [8:0] cur_gamma_p,
 input [2:0] cur_usb_mode,input [1:0] cur_usb_size,input usb_busy,
 input [11:0] adc1,
 output menu_open,output reg write_valid,output reg [4:0] write_addr,
 output reg [11:0] write_value,output reg [`M5_DISP_WIDTH-1:0] disp
);
 reg [1:0] state;reg [4:0] cursor,window_start;
 reg [11:0] knob_base;reg [3:0] settle;
 assign menu_open=state!=`M5_CLOSED;
 function [2:0] kind;
  input [4:0] item;
  begin
   case(item)
    `M5_MEDIAN,`M5_CLEANUP,`M5_FREEZE,`M5_TEST,`M5_GAMMA:kind=1;
    `M5_VIEW,`M5_USB_MODE,`M5_USB_SIZE:kind=2;
    `M5_CANNY_RST,`M5_WB_RST,`M5_USB_STOP:kind=3;
    `M5_ADC:kind=4;
    `M5_BOOT:kind=5;
    `M5_LOAD:kind=3;
    default:kind=0;
   endcase
  end
 endfunction
 reg [11:0] current_value,maximum;
 always @*begin
  current_value=0;maximum=2047;
  case(cursor)
   `M5_VIEW:begin current_value={10'd0,cur_view};maximum=2;end
   `M5_MEDIAN:current_value={11'd0,cur_median};
   `M5_CLEANUP:current_value={11'd0,cur_cleanup};
   `M5_FREEZE:current_value={11'd0,cur_freeze};
   `M5_TEST:current_value={11'd0,cur_test};
   `M5_GAMMA:current_value={11'd0,cur_gamma};
   `M5_CANNY,`M5_CANNY_H:current_value={1'b0,cur_high};
   `M5_CANNY_L:begin current_value={1'b0,cur_low};maximum={1'b0,cur_high};end
   `M5_WB_R:current_value={1'b0,cur_wb_r};
   `M5_WB_G:current_value={1'b0,cur_wb_g};
   `M5_WB_B:current_value={1'b0,cur_wb_b};
   `M5_GAMMA_P:begin current_value={3'd0,cur_gamma_p};maximum=256;end
   `M5_USB_MODE:begin current_value={9'd0,cur_usb_mode};maximum=4;end
   `M5_USB_SIZE:begin current_value={10'd0,cur_usb_size};maximum=2;end
   default:begin end
  endcase
 end
 wire signed [12:0] delta=$signed({1'b0,knob_value})-$signed({1'b0,knob_base});
 wire [12:0] magnitude=delta<0?-delta:delta;
 wire [4:0] scroll_steps=magnitude>>$clog2(KNOB_SCROLL_STEP);
 wire [12:0] edit_steps=magnitude>>(kind(cursor)==2?8:cursor==`M5_GAMMA_P?4:2);
 wire blocked=usb_busy&&(cursor==`M5_USB_MODE||cursor==`M5_USB_SIZE||cursor==`M5_USB_STOP);
 wire signed [13:0] candidate=$signed({2'b0,current_value})+
  (delta<0?-$signed({1'b0,edit_steps}):$signed({1'b0,edit_steps}));
 wire [11:0] bounded=candidate<0?12'd0:candidate>$signed({2'b0,maximum})?maximum:candidate[11:0];
 function [4:0] move_cursor;
  input [4:0] old,steps;input backwards;reg [5:0] n;
  begin
   if(backwards)n=old>=steps?{1'b0,old}-{1'b0,steps}:{1'b0,old}+`M5_COUNT-{1'b0,steps};
   else begin n={1'b0,old}+{1'b0,steps};if(n>=`M5_COUNT)n=n-`M5_COUNT;end
   move_cursor=n[4:0];
  end
 endfunction
 task write_item;
  input [11:0] value;
  begin write_valid<=1;write_addr<=cursor;write_value<=value;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=`M5_CLOSED;cursor<=0;window_start<=0;knob_base<=0;settle<=0;
   write_valid<=0;write_addr<=0;write_value<=0;
  end else begin
   write_valid<=0;
   if(key1_long)begin
    state<=menu_open?`M5_CLOSED:`M5_BROWSE;knob_base<=knob_value;settle<=8;
   end else if(key1_short)begin
    knob_base<=knob_value;settle<=8;
    if(state==`M5_EDIT)state<=`M5_BROWSE;
    else if(state==`M5_BROWSE&&!blocked)begin
     case(kind(cursor))
      0,2:state<=`M5_EDIT;
      1:write_item({11'd0,!current_value[0]});
      3:write_item(0);
      5:write_item({10'd0,boot_selected==2 ? 2'd0 : boot_selected+2'd1});
      default:begin end
     endcase
    end
   end else if(key_event)begin
    knob_base<=knob_value;
    if(state==`M5_BROWSE)begin
     if(key_code==1)cursor<=move_cursor(cursor,1,1);
     else if(key_code==2)cursor<=move_cursor(cursor,1,0);
    end else if(state==`M5_EDIT&&!blocked)begin
     if(key_code==1&&current_value<maximum)write_item(current_value+1'b1);
     else if(key_code==2&&current_value!=0)write_item(current_value-1'b1);
    end
   end else if(knob_sample)begin
    if(state==`M5_CLOSED||!knob_ready)knob_base<=knob_value;
    else if(settle!=0)begin settle<=settle-1'b1;knob_base<=knob_value;end
    else if(state==`M5_BROWSE&&scroll_steps!=0)begin
     cursor<=move_cursor(cursor,scroll_steps,delta<0);
     knob_base<=delta<0?knob_base-(scroll_steps<<$clog2(KNOB_SCROLL_STEP)):
                                knob_base+(scroll_steps<<$clog2(KNOB_SCROLL_STEP));
    end else if(state==`M5_EDIT)begin
     if(blocked)knob_base<=knob_value;
     else if(magnitude>=KNOB_DEADBAND&&edit_steps!=0)begin
      knob_base<=knob_value;if(bounded!=current_value)write_item(bounded);
     end
    end
   end
   if(menu_open)begin
    if(cursor<window_start)window_start<=cursor;
    else if(cursor>=window_start+8)window_start<=cursor-7;
   end
  end
 end
 function [15:0] bcd4;
  input [11:0] v;reg [15:0] b;integer i,j;
  begin
   b=0;
   for(i=11;i>=0;i=i-1)begin
    for(j=0;j<4;j=j+1)if(b[j*4+:4]>=5)b[j*4+:4]=b[j*4+:4]+4'd3;
    b={b[14:0],v[i]};
   end
   bcd4=b;
  end
 endfunction
 // Registered display fields precede the atomic frame-boundary mailbox.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)disp<=0;
  else begin
   disp<=0;
   disp[`M5D_BOOT+:2]<=boot_selected;disp[`M5D_BOOT_STATUS+:4]<=boot_status;
   disp[`M5D_STATE+:2]<=state;disp[`M5D_CURSOR+:5]<=cursor;
   disp[`M5D_WINDOW+:5]<=cursor<window_start?cursor:cursor>=window_start+8?cursor-5'd7:window_start;
   disp[`M5D_VIEW+:2]<=cur_view;
   disp[`M5D_FLAGS+:7]<={knob_ready,usb_busy,cur_gamma,cur_test,cur_freeze,cur_cleanup,cur_median};
   disp[`M5D_HIGH+:16]<=bcd4({1'b0,cur_high});disp[`M5D_LOW+:16]<=bcd4({1'b0,cur_low});
   disp[`M5D_WBR+:16]<=bcd4({1'b0,cur_wb_r});disp[`M5D_WBG+:16]<=bcd4({1'b0,cur_wb_g});
   disp[`M5D_WBB+:16]<=bcd4({1'b0,cur_wb_b});disp[`M5D_GAMMA+:12]<=bcd4({3'd0,cur_gamma_p});
   disp[`M5D_USB_MODE+:3]<=cur_usb_mode;disp[`M5D_USB_SIZE+:2]<=cur_usb_size;
   disp[`M5D_ADC0+:16]<=bcd4(knob_value);disp[`M5D_ADC1+:16]<=bcd4(adc1);
  end
 end
endmodule
