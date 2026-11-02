`timescale 1ns/1ps
// Snapshot-level stability, acknowledged bundled-data CDC, and periodic reports
// while recognized. Loss is reported once; '#' queries remain available.
module person_pose_uart #(
 parameter integer CLOCK_HZ=96000000,REPORT_HZ=2
)(
 input pclk,input prst_n,input sample_tick,input [2:0] sample_pose,
 input [9:0] sample_similarity,sample_margin,sample_edge_support,
 input clk,input rst_n,input query,
 output tx_valid,output reg [7:0] tx_data,output tx_last,input tx_accept,input tx_done
);
reg [2:0] candidate,stable_pose;
reg [1:0] count;
reg [32:0] pending_payload,mailbox;
reg dirty,request;
reg acknowledge;
(* async_reg="true" *)reg ack_meta,ack_sync,req_meta,req_sync;
always @(posedge pclk or negedge prst_n)begin
 if(!prst_n)begin
  candidate<=0;stable_pose<=0;count<=0;pending_payload<=0;mailbox<=0;dirty<=0;request<=0;ack_meta<=0;ack_sync<=0;
 end else begin
  ack_meta<=acknowledge;ack_sync<=ack_meta;
  if(dirty&&request==ack_sync)begin mailbox<=pending_payload;request<=!request;dirty<=0;end
  if(sample_tick)begin
   if(sample_pose==0)begin
    candidate<=0;stable_pose<=0;count<=0;
    pending_payload<={3'd0,sample_similarity,sample_margin,sample_edge_support};dirty<=1;
   end else if(sample_pose!=candidate)begin candidate<=sample_pose;count<=1;end
   else begin
    if(count<3)count<=count+1'b1;
    if(count>=2)begin
     stable_pose<=sample_pose;
     pending_payload<={sample_pose,sample_similarity,sample_margin,sample_edge_support};dirty<=1;
    end
   end
  end
 end
end
reg [32:0] latest,message_payload;
reg [2:0] reported_pose;
reg pending,sending,waiting_done;
localparam integer REPORT_INTERVAL=(CLOCK_HZ/REPORT_HZ)>0?CLOCK_HZ/REPORT_HZ:1;
localparam integer TIMER_BITS=REPORT_INTERVAL>1?$clog2(REPORT_INTERVAL):1;
reg [TIMER_BITS-1:0] report_counter;
reg [5:0] index;
wire [2:0] message_pose=message_payload[32:30];
wire [9:0] score=message_payload[29:20],gap=message_payload[19:10],edge_score=message_payload[9:0];
assign tx_valid=sending&&!waiting_done;
assign tx_last=index==34;
// Four decimal digits represent per-mille values 0000..1000.
function [7:0] digit;
 input [9:0] value;input [1:0] position;
 begin case(position)
  0:digit="0"+value/1000;
  1:digit="0"+(value/100)%10;
  2:digit="0"+(value/10)%10;
  default:digit="0"+value%10;
 endcase end
endfunction
always @(*)begin
 tx_data=" ";
 case(index)
  0:tx_data="P";1:tx_data="O";2:tx_data="S";3:tx_data="E";4:tx_data=":";5:tx_data="0"+message_pose;
  7:tx_data="S";8:tx_data="C";9:tx_data="O";10:tx_data="R";11:tx_data="E";12:tx_data=":";
  18:tx_data="G";19:tx_data="A";20:tx_data="P";21:tx_data=":";
  27:tx_data="E";28:tx_data=":";
  33:tx_data=13;34:tx_data=10;
  default:begin
   if(index>=13&&index<=16)tx_data=digit(score,index-13);
   else if(index>=22&&index<=25)tx_data=digit(gap,index-22);
   else if(index>=29&&index<=32)tx_data=digit(edge_score,index-29);
  end
 endcase
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  req_meta<=0;req_sync<=0;acknowledge<=0;latest<=0;message_payload<=0;reported_pose<=0;
  pending<=0;sending<=0;waiting_done<=0;index<=0;
  report_counter<=0;
 end else begin
  req_meta<=request;req_sync<=req_meta;
  // One coalesced pending line prevents a backlog if UART is occupied. Take
  // current scores when the next line starts; a line in flight stays immutable.
  if(latest[32:30]==0)report_counter<=0;
  else if(report_counter<REPORT_INTERVAL-1)report_counter<=report_counter+1'b1;
  else pending<=1;
  if(!sending)begin
   if(pending&&req_sync==acknowledge)begin
    message_payload<=latest;reported_pose<=latest[32:30];sending<=1;index<=0;pending<=0;report_counter<=0;
   end
  end else if(waiting_done)begin
   if(tx_done)begin waiting_done<=0;if(tx_last)sending<=0;else index<=index+1'b1;end
  end else if(tx_accept)waiting_done<=1;
  if(req_sync!=acknowledge)begin
   latest<=mailbox;acknowledge<=req_sync;
   if(mailbox[32:30]!=reported_pose)pending<=1;
  end
  if(query)pending<=1;
 end
end
endmodule
