`timescale 1ns/1ps
// B is a count of branch-candidate pixels, never a count of anatomical joints.
// All numeric fields except the two Boolean flags are hexadecimal.
module skeleton_uart #(parameter CLOCK_HZ=96000000,REPORT_SECONDS=2,BODY_AVAILABLE=0)(
 input pclk,input prst_n,input sample_tick,input sample_valid,input sample_converged,
 input [7:0] sample_iterations,input [15:0] sample_pixels,sample_endpoints,sample_branches,sample_pruned,
 input sample_body_valid,input [1:0] sample_arm_flags,
 input clk,input rst_n,input report_enable,input query,
 output tx_valid,output reg [7:0] tx_data,output tx_last,input tx_accept,input tx_done
);
 reg [76:0] pending_payload,mailbox;
 reg dirty,request,acknowledge;
 (* async_reg="true" *)reg ack_meta,ack_sync,req_meta,req_sync;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin pending_payload<=0;mailbox<=0;dirty<=0;request<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=acknowledge;ack_sync<=ack_meta;
   if(dirty&&request==ack_sync)begin mailbox<=pending_payload;request<=!request;dirty<=0;end
   if(sample_tick)begin
    pending_payload<={sample_valid,sample_converged,sample_iterations,sample_pixels,sample_endpoints,sample_branches,sample_pruned,BODY_AVAILABLE?sample_body_valid:1'b0,BODY_AVAILABLE?sample_arm_flags:2'b0};dirty<=1;
   end
  end
 end
 reg [76:0] latest,message_payload;
 reg query_pending,auto_pending,sending,waiting_done;
 localparam INTERVAL=CLOCK_HZ*REPORT_SECONDS>0?CLOCK_HZ*REPORT_SECONDS:1;
 localparam TB=INTERVAL>1?$clog2(INTERVAL):1;
 reg [TB-1:0] timer;
 reg [5:0] index;
 assign tx_valid=sending&&!waiting_done;
 assign tx_last=index==(BODY_AVAILABLE?57:44);
 wire [73:0] base_payload=message_payload[76:3];
 function [7:0] hex_digit;
  input [3:0] n;begin hex_digit=n<10?"0"+n:"A"+n-10;end
 endfunction
 always @(*)begin
  tx_data=" ";
  case(index)
   0:tx_data="S";1:tx_data="K";2:tx_data="E";3:tx_data="L";4:tx_data=":";5:tx_data="0"+base_payload[73];
   7:tx_data="C";8:tx_data=":";9:tx_data="0"+base_payload[72];
   11:tx_data="I";12:tx_data=":";13:tx_data=hex_digit(base_payload[71:68]);14:tx_data=hex_digit(base_payload[67:64]);
   16:tx_data="P";17:tx_data=":";
   18:tx_data=hex_digit(base_payload[63:60]);19:tx_data=hex_digit(base_payload[59:56]);
   20:tx_data=hex_digit(base_payload[55:52]);21:tx_data=hex_digit(base_payload[51:48]);
   23:tx_data="E";24:tx_data=":";
   25:tx_data=hex_digit(base_payload[47:44]);26:tx_data=hex_digit(base_payload[43:40]);
   27:tx_data=hex_digit(base_payload[39:36]);28:tx_data=hex_digit(base_payload[35:32]);
   30:tx_data="B";31:tx_data=":";
   32:tx_data=hex_digit(base_payload[31:28]);33:tx_data=hex_digit(base_payload[27:24]);
   34:tx_data=hex_digit(base_payload[23:20]);35:tx_data=hex_digit(base_payload[19:16]);
   37:tx_data="R";38:tx_data=":";
   39:tx_data=hex_digit(base_payload[15:12]);40:tx_data=hex_digit(base_payload[11:8]);
   41:tx_data=hex_digit(base_payload[7:4]);42:tx_data=hex_digit(base_payload[3:0]);
   43:tx_data=BODY_AVAILABLE?" ":13;44:tx_data=BODY_AVAILABLE?"B":10;
   45:tx_data="O";46:tx_data="D";47:tx_data="Y";48:tx_data=":";49:tx_data="0"+message_payload[2];
   51:tx_data="A";52:tx_data="R";53:tx_data="M";54:tx_data=":";55:tx_data=hex_digit({2'b0,message_payload[1:0]});
   56:tx_data=13;57:tx_data=10;
  endcase
 end
 // Include CR/LF in the same locked UART message.
 // BODY_AVAILABLE appends model validity and screen-left/right arm bits.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   req_meta<=0;req_sync<=0;acknowledge<=0;latest<=0;message_payload<=0;
   query_pending<=0;auto_pending<=0;sending<=0;waiting_done<=0;timer<=0;index<=0;
  end else begin
   req_meta<=request;req_sync<=req_meta;
   // Auto-report only in the explicitly selected view, including invalid status.
   // Validity changes never bypass the rate limit. Finish an in-flight line
   // on exit, discard queued automatic reports, and retain explicit queries.
   if(!report_enable)begin timer<=0;auto_pending<=0;end
   else if(timer<INTERVAL-1)timer<=timer+1'b1;
   else begin timer<=0;auto_pending<=1;end
   if(!sending)begin
    if((query_pending||(auto_pending&&report_enable))&&req_sync==acknowledge)begin
     message_payload<=latest;sending<=1;index<=0;query_pending<=0;auto_pending<=0;
    end
   end else if(waiting_done)begin
    if(tx_done)begin waiting_done<=0;if(tx_last)sending<=0;else index<=index+1'b1;end
   end else if(tx_accept)waiting_done<=1;
   if(req_sync!=acknowledge)begin
    latest<=mailbox;acknowledge<=req_sync;
   end
   if(query)query_pending<=1;
  end
 end
endmodule
