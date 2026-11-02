`timescale 1ns/1ps
// Native SD command/response serializer. Changes CMD on falling SDCLK;
// samples at rising SDCLK. Long response CRC excludes the 8-bit R2 header.
module sd4_command #(parameter TIMEOUT_CLOCKS=2048, RESPONSE_GAP_CLOCKS=8)(
 input clk,input rst_n,input rise,input fall,input start,
 input [5:0] command,input [31:0] argument,
 input [1:0] response_kind, // 0:none, 1:R1/R6/R7, 2:R2, 3:R3
 input cmd_i,output reg cmd_o,output reg cmd_oe,
 output reg busy,output reg done,output reg error,output reg [3:0] error_reason,
 output reg [135:0] response
);
 reg [2:0] state;reg [47:0] tx;
 reg [7:0] count,length;reg [1:0] kind;reg [5:0] index;
 reg [15:0] timeout;reg [6:0] crc;
 reg [3:0] pending_error;
 localparam ERR_NONE=0,ERR_TIMEOUT=1,ERR_CRC=2,ERR_FRAME=3;
 function [6:0] step_crc;
 input [6:0] c;input b;
 begin step_crc={c[5:0],1'b0}^((c[6]^b)?7'h09:7'h00);end
 endfunction
 function [6:0] packet_crc;
 input [39:0] v;reg [6:0] c;integer i;
 begin c=0;for(i=39;i>=0;i=i-1)c=step_crc(c,v[i]);packet_crc=c;end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin state<=0;tx<=0;count<=0;length<=0;kind<=0;index<=0;
   timeout<=0;crc<=0;cmd_o<=1;cmd_oe<=0;busy<=0;done<=0;error<=0;
   error_reason<=ERR_NONE;pending_error<=ERR_NONE;response<=0;end
  else begin
   done<=0;error<=0;
   case(state)
    0: if(start) begin
     tx<={2'b01,command,argument,packet_crc({2'b01,command,argument}),1'b1};
     index<=command;kind<=response_kind;count<=0;busy<=1;state<=1;response<=0;crc<=0;
     length<=response_kind==2?136:48;timeout<=0;
     pending_error<=ERR_NONE;error_reason<=ERR_NONE;
    end
    1: if(fall) begin
     cmd_oe<=1;cmd_o<=tx[47];tx<={tx[46:0],1'b1};
     if(count==47) begin state<=2;count<=0;end else count<=count+1'b1;
    end
    2: if(fall) begin cmd_oe<=0;cmd_o<=1;state<=kind==0?5:3;end
    3: if(rise) begin
     if(!cmd_i) begin response<=0;count<=1;crc<=0;state<=4;end
     else if(timeout==TIMEOUT_CLOCKS-1) state<=7;
     else timeout<=timeout+1'b1;
    end
    4: if(rise) begin
     response<={response[134:0],cmd_i};
     if(count<length-8 && (kind!=2 || count>=8)) crc<=step_crc(crc,cmd_i);
     if(count==length-1) state<=6;else count<=count+1'b1;
    end
    // Keep CMD released for N_RC/N_CC >= 8 SD clocks. Do not notify the
    // caller until this gap has completed, even when a response is invalid.
    5: if(rise) begin
     if(count==RESPONSE_GAP_CLOCKS-1) begin
      state<=0;busy<=0;error_reason<=pending_error;
      if(pending_error==ERR_NONE) done<=1;else error<=1;
     end else count<=count+1'b1;
    end
    6: begin
     count<=0;state<=5;
     if(!response[0] ||
        (kind==1 && (response[47:46]!=0 || response[45:40]!=index)) ||
        (kind==2 && response[135:128]!=8'h3f) ||
        (kind==3 && response[47:40]!=8'h3f)) pending_error<=ERR_FRAME;
     else if(kind!=3 && response[7:1]!=crc) pending_error<=ERR_CRC;
     else pending_error<=ERR_NONE;
    end
    7: begin state<=5;count<=0;cmd_oe<=0;pending_error<=ERR_TIMEOUT;end
    default:state<=0;
   endcase
  end
 end
endmodule
