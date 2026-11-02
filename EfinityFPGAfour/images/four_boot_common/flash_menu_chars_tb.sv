`timescale 1ns/1ps
module flash_menu_chars_tb #(parameter IMAGE_ID=7);
localparam BOOT=IMAGE_ID==1?17:IMAGE_ID==5?19:IMAGE_ID==2?22:18;
localparam LOAD=BOOT+1,COUNT=IMAGE_ID==7?21:BOOT+2,VALUE_COL=IMAGE_ID==5?13:12;
localparam BOFF=IMAGE_ID==1?124:IMAGE_ID==5?150:IMAGE_ID==2?267:140;
localparam SOFF=BOFF+2;
reg clk=0,rst_n=0;always #5 clk=~clk;
reg [272:0] d=0;reg [4:0] col=0;reg [3:0] row=0;wire [7:0] character;
generate
 if(IMAGE_ID==1)begin:g1
 menu_text_render r(.clk(clk),.rst_n(rst_n),.in_vsync(1'b0),.in_hsync(1'b0),.in_href(1'b0),.in_rgb(24'd0),.disp(d[130-1:0]),.out_vsync(),.out_hsync(),.out_href(),.out_rgb());
 initial begin force r.in_region=1'b1;force r.cell_col=col;force r.cell_row=row;end
 assign character=r.ch0;
 end else if(IMAGE_ID==5)begin:g5
 stable_menu_render5 r(.clk(clk),.rst_n(rst_n),.in_vsync(1'b0),.in_hsync(1'b0),.in_href(1'b0),.in_rgb(24'd0),.disp(d[156-1:0]),.out_vsync(),.out_hsync(),.out_href(),.out_rgb());
 initial begin force r.in_region=1'b1;force r.cell_col=col;force r.cell_row=row;end
 assign character=r.ch0;
 end else if(IMAGE_ID==2)begin:g2
 image2_menu_render r(.clk(clk),.rst_n(rst_n),.in_vsync(1'b0),.in_hsync(1'b0),.in_href(1'b0),.in_rgb(24'd0),.disp(d),.out_vsync(),.out_hsync(),.out_href(),.out_rgb());
 initial begin force r.in_region=1'b1;force r.cell_col=col;force r.cell_row=row;end
 assign character=r.ch0;
 end else begin:g7
 image7_usb_menu_render r(.clk(clk),.rst_n(rst_n),.in_vsync(1'b0),.in_hsync(1'b0),.in_href(1'b0),.in_rgb(24'd0),.disp(d[155-1:0]),.out_vsync(),.out_hsync(),.out_href(),.out_rgb());
 initial begin force r.in_region=1'b1;force r.cell_col=col;force r.cell_row=row;end
 assign character=r.ch0;
 end
endgenerate
reg [47:0] name_;reg [63:0] state_;reg [79:0] label_="BOOT IMAGE";
reg [31:0] check_word;
task expect_(input [7:0] ch);
 begin #10;if(character!==ch)$fatal(1,"image%0d row=%0d col=%0d got=%h expected=%h",IMAGE_ID,row,col,character,ch);end
endtask
initial begin
 #30;rst_n=1;d[1:0]=1;d[2+:5]=LOAD;d[7+:5]=BOOT-6;
 row=7;
 for(integer i=0;i<10;i=i+1)begin col=i+1;expect_(label_[79-i*8-:8]);end
 for(integer slot=0;slot<4;slot=slot+1)begin
  d[BOFF+:2]=slot;case(slot)0:name_="IMAGE7";1:name_="IMAGE1";2:name_="IMAGE5";3:name_="IMAGE2";endcase
  for(integer i=0;i<6;i=i+1)begin col=VALUE_COL+i;expect_(name_[47-i*8-:8]);end
 end
 row=8;
 for(integer st=0;st<5;st=st+1)begin
  d[SOFF+:4]=st;
  case(st)0:state_="READY   ";1:state_="WAIT    ";2:state_="LOAD    ";3:state_="ERROR   ";4:state_="HERE    ";endcase
  for(integer i=0;i<8;i=i+1)begin col=VALUE_COL+i;expect_(state_[63-i*8-:8]);end
 end
 row=0;col=25;expect_("0"+(LOAD+1)/10);col=26;expect_("0"+(LOAD+1)%10);
 col=28;expect_("0"+COUNT/10);col=29;expect_("0"+COUNT%10);
 $display("PASS flash_menu_chars image%0d: every image name, all switch statuses, label/value spacing and two-digit current/total counters",IMAGE_ID);$finish;
end
endmodule
