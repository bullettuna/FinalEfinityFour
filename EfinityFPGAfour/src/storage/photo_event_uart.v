`timescale 1ns/1ps
// Queued, one-shot status lines on the existing byte accept/done interface.
module photo_event_uart #(parameter ENABLE_DELETE=0)(input clk,input rst_n,input event_valid,input event_critical,input [3:0] event_kind,input [7:0] event_code,
 input [5:0] event_command,input [3:0] event_reason,
 input [16:0] event_file_number,
 input [3:0] event_stage,event_rd,event_axi,input [5:0] event_beats,
 output room,output tx_valid,output [7:0] tx_data,output tx_last,input tx_accept,input tx_done,
 output reg confirmation_sent,output [16:0] confirmation_file_number);
 reg [56:0] queue[0:15];reg [3:0] wp,rp;reg [4:0] count;
 reg sending,waiting;reg [3:0] kind,reason;reg [5:0] command,index;
 reg [7:0] code;
 reg [3:0] stage,rd,axi;reg [5:0] beats;
 reg [16:0] file_number,number_shift;
 reg [19:0] number_bcd,bcd_adjusted;
 reg [4:0] number_bits;
 reg formatting;
 assign confirmation_file_number=file_number;
 integer digit;
 // Reserve four entries for the accepted transaction's result/error/fault.
 // Repeated status queries must not consume the completion reserve.
 wire take=!sending&&!formatting&&count!=0,put=event_valid&&count<16&&(event_critical||count<12);
 reg [319:0] message;reg [5:0] length;
 reg [127:0] reason_tail;reg [4:0] reason_length;
 reg [63:0] stage_name;reg [3:0] stage_length;
 function [7:0] hexchar;input [3:0] v;begin hexchar=v<10?48+v:65+v-10;end endfunction
 wire [95:0] filename={"IMG",8'd48+{4'd0,number_bcd[19:16]},8'd48+{4'd0,number_bcd[15:12]},
   8'd48+{4'd0,number_bcd[11:8]},8'd48+{4'd0,number_bcd[7:4]},8'd48+{4'd0,number_bcd[3:0]},".BMP"};
 always @*begin
  bcd_adjusted=number_bcd;
  for(digit=0;digit<5;digit=digit+1)
   if(number_bcd[digit*4+:4]>=5)bcd_adjusted[digit*4+:4]=number_bcd[digit*4+:4]+4'd3;
 end
 function [15:0] command_ascii;
 input [5:0] v;reg [3:0] tens,units;
 begin
  if(v>=60)begin tens=6;units=v-60;end
  else if(v>=50)begin tens=5;units=v-50;end
  else if(v>=40)begin tens=4;units=v-40;end
  else if(v>=30)begin tens=3;units=v-30;end
  else if(v>=20)begin tens=2;units=v-20;end
  else if(v>=10)begin tens=1;units=v-10;end
  else begin tens=0;units=v;end
  command_ascii={8'd48+tens,8'd48+units};
 end
 endfunction
 always @*begin
  stage_length=8;
  case(stage)
   1:begin stage_name={"CAPTURE",8'd0};stage_length=7;end
   2:begin stage_name={"SD_INIT",8'd0};stage_length=7;end
   3:stage_name="DDR_READ";
   4:begin stage_name={"SD_READ",8'd0};stage_length=7;end
   5:stage_name="SD_WRITE";
   6:stage_name="DIR_SCAN";
   7:stage_name="FAT_SCAN";
   8:begin stage_name={"META",32'd0};stage_length=4;end
   9:begin stage_name={"RECOVER",8'd0};stage_length=7;end
   10:begin stage_name={"FAULT",24'd0};stage_length=5;end
   11:begin stage_name={"PROCESS",8'd0};stage_length=7;end
   12:stage_name="UART_OUT";
   default:begin stage_name={"IDLE",32'd0};stage_length=4;end
  endcase
 end
 // Each suffix is left-aligned in 16 bytes, including a real CR/LF.
 always @* begin
  case(reason)
   1:begin reason_tail={"TIMEOUT",8'h0d,8'h0a,56'd0};reason_length=7;end
   2:begin reason_tail={"CRC",8'h0d,8'h0a,88'd0};reason_length=3;end
   3:begin reason_tail={"FRAME",8'h0d,8'h0a,72'd0};reason_length=5;end
   4:begin reason_tail={"STATUS",8'h0d,8'h0a,64'd0};reason_length=6;end
   5:begin reason_tail={"ECHO",8'h0d,8'h0a,80'd0};reason_length=4;end
   6:begin reason_tail={"INIT_TIMEOUT",8'h0d,8'h0a,16'd0};reason_length=12;end
   7:begin reason_tail={"BUSY_TIMEOUT",8'h0d,8'h0a,16'd0};reason_length=12;end
   8:begin reason_tail={"CSD",8'h0d,8'h0a,88'd0};reason_length=3;end
   9:begin reason_tail={"DATA_CRC",8'h0d,8'h0a,48'd0};reason_length=8;end
   10:begin reason_tail={"DATA_TOKEN",8'h0d,8'h0a,32'd0};reason_length=10;end
   11:begin reason_tail={"DATA_TIMEOUT",8'h0d,8'h0a,16'd0};reason_length=12;end
   12:begin reason_tail={"ADDRESS",8'h0d,8'h0a,56'd0};reason_length=7;end
   13:begin reason_tail={"VOLTAGE",8'h0d,8'h0a,56'd0};reason_length=7;end
   default:begin reason_tail={"UNKNOWN",8'h0d,8'h0a,56'd0};reason_length=7;end
  endcase
 end
 always @* begin
  case(kind)
   0:begin message={"DDR_OK",8'h0d,8'h0a,256'd0};length=8;end
   1:begin message={"tfOK",8'h0d,8'h0a,272'd0};length=6;end
   2:begin message={"DDR_FAIL",8'h0d,8'h0a,240'd0};length=10;end
   3:begin
    if((code==1 || code==9) && reason!=0)begin
     message={"TF_FAIL:",hexchar(code[7:4]),hexchar(code[3:0])," CMD=",command_ascii(command)," ERR=",reason_tail,16'd0};
     length=24+reason_length;
    end else begin message={"TF_FAIL:",hexchar(code[7:4]),hexchar(code[3:0]),8'h0d,8'h0a,224'd0};length=12;end
   end
   4:begin
    message={"BUSY ST=",stage_name,192'd0} |
     ({" RD=",hexchar(rd)," B=",command_ascii(beats),"/32 AXI=",hexchar(axi),8'h0d,8'h0a,152'd0} >> ((8+stage_length)*8));
    length=29+stage_length;
   end
   5:begin message={"TF:INIT_OK",8'h0d,8'h0a,224'd0};length=12;end
   6:begin message={"TF:INIT_FAIL CMD=",command_ascii(command)," ERR=",reason_tail};length=26+reason_length;end
   7:begin
    case(code)
     1:begin message={"TF_FAIL:DDR_ADDR_TIMEOUT",8'h0d,8'h0a,112'd0};length=26;end
     2:begin message={"TF_FAIL:DDR_DATA_TIMEOUT",8'h0d,8'h0a,112'd0};length=26;end
     3:begin message={"TF_FAIL:DDR_RLAST",8'h0d,8'h0a,168'd0};length=19;end
     4:begin message={"TF_FAIL:DDR_RESPONSE",8'h0d,8'h0a,144'd0};length=22;end
     5:begin message={"TF_FAIL:DDR_FRAME",8'h0d,8'h0a,168'd0};length=19;end
     default:begin message={"TF_FAIL:DDR_ADDRESS",8'h0d,8'h0a,152'd0};length=21;end
    endcase
   end
   8:begin message={"TF_FAIL:SAVE_TIMEOUT ST=",hexchar(code[7:4]),hexchar(code[3:0]),8'h0d,8'h0a,96'd0};length=28;end
   10:begin message={"ALBUM:READY",8'h0d,8'h0a,216'd0};length=13;end
   11:begin message={"ALBUM:FAIL",8'h0d,8'h0a,224'd0};length=12;end
   12:begin message={"ALBUM:EXIT",8'h0d,8'h0a,224'd0};length=12;end
   13:begin message={"ALBUM:DISPLAY_FAIL",8'h0d,8'h0a,160'd0};length=20;end
   14:begin
    case(code)
     0:begin message={"DEL_CONFIRM ",filename,8'h0d,8'h0a,112'd0};length=26;end
     1:begin message={"DEL_OK ",filename,8'h0d,8'h0a,152'd0};length=21;end
     2:if(reason==15)begin message={"DEL_FAIL:",hexchar({2'd0,command[5:4]}),hexchar(command[3:0])," PARTIAL",8'h0d,8'h0a,152'd0};length=21;end
       else begin message={"DEL_FAIL:",hexchar({2'd0,command[5:4]}),hexchar(command[3:0]),8'h0d,8'h0a,216'd0};length=13;end
     3:begin message={"ALBUM:EMPTY",8'h0d,8'h0a,216'd0};length=13;end
     default:begin message={"DEL_CANCEL",8'h0d,8'h0a,224'd0};length=12;end
    endcase
   end
   15:begin
    if(code==0)begin message={"PROCESSING",8'h0d,8'h0a,224'd0};length=12;end
    else begin message={"PROCESS_FAIL:RESET_REQUIRED",8'h0d,8'h0a,88'd0};length=29;end
   end
   default:begin message={"FAULT:RESET_REQUIRED AXI=",hexchar(axi)," RD=",hexchar(rd),8'h0d,8'h0a,56'd0};length=33;end
  endcase
 end
 assign room=count<12;
 assign tx_valid=sending&&!waiting;
 assign tx_data=message[319-index*8 -:8];
 assign tx_last=index==length-1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin wp<=0;rp<=0;count<=0;sending<=0;waiting<=0;kind<=0;code<=0;command<=0;reason<=0;index<=0;
   stage<=0;rd<=0;axi<=0;beats<=0;file_number<=0;number_shift<=0;number_bcd<=0;number_bits<=0;formatting<=0;confirmation_sent<=0;end
  else begin
   confirmation_sent<=0;
   if(put)begin queue[wp]<={event_kind,event_code,event_command,event_reason,event_stage,event_rd,event_axi,event_beats,event_file_number};wp<=wp+1'b1;end
   if(take)begin
    {kind,code,command,reason,stage,rd,axi,beats,file_number}<=queue[rp];rp<=rp+1'b1;waiting<=0;index<=0;
    if(queue[rp][56:53]==14 && (queue[rp][52:45]==0 || queue[rp][52:45]==1))begin
     formatting<=1;sending<=0;number_shift<=queue[rp][16:0];number_bcd<=0;number_bits<=0;
    end else sending<=1;
   end
   if(formatting)begin
    number_bcd<={bcd_adjusted[18:0],number_shift[16]};number_shift<=number_shift<<1;
    if(number_bits==16)begin formatting<=0;sending<=1;end else number_bits<=number_bits+1'b1;
   end
   case({put,take})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
   if(tx_valid&&tx_accept)waiting<=1;
   if(sending&&waiting&&tx_done)begin
    waiting<=0;
    if(tx_last)begin sending<=0;if(ENABLE_DELETE && kind==14 && code==0)confirmation_sent<=1;end
    else index<=index+1'b1;
   end
  end
 end
endmodule
