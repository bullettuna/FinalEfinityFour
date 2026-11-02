`timescale 1ns/1ps
// FT245 asynchronous FIFO: one physical WR# falling edge per accepted byte.
// ready means ownership of the pending register, not a USB acknowledgement.
module ft245_async_tx #(
 parameter SETUP_CYCLES=10, LOW_CYCLES=10, HOLD_CYCLES=10,
 RECOVERY_CYCLES=10, GAP_CYCLES=96, STABLE_CYCLES=4
)(
 input clk,input rst_n,input run_enable,input txe_n_async,
 input valid,input [7:0] data,output ready,
 output reg [7:0] data_o,output [7:0] data_oe,
 output reg wr_n,output wr_oe,output stopped
);
 localparam STOP=0,IDLE=1,PERMISSION=2,SETUP=3,LOW=4,HOLD=5,RECOVERY=6,FLUSH=7;
 reg [2:0] state;
 (* async_reg="true" *) reg txe_meta,txe_sync;
 reg [7:0] stable,timer,gap;
 reg oe;reg [7:0] held;
 assign ready=run_enable&&state==IDLE;
 assign data_oe={8{oe}};
 assign wr_oe=oe;
 assign stopped=state==STOP;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin txe_meta<=1;txe_sync<=1;end
  else begin txe_meta<=txe_n_async;txe_sync<=txe_meta;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=STOP;stable<=0;timer<=0;gap<=GAP_CYCLES;
   oe<=0;wr_n<=1;data_o<=0;held<=0;end
  else begin
   if(gap<GAP_CYCLES)gap<=gap+1'b1;
   if(txe_sync||state==LOW||state==HOLD||state==RECOVERY)stable<=0;
   else if(stable<STABLE_CYCLES)stable<=stable+1'b1;
   case(state)
    STOP:begin oe<=0;wr_n<=1;if(run_enable)state<=IDLE;end
    IDLE:if(!run_enable)state<=FLUSH;
         else if(valid)begin held<=data;state<=PERMISSION;end
    PERMISSION:if(!run_enable)state<=FLUSH;
      else if(stable==STABLE_CYCLES&&gap==GAP_CYCLES)begin
       data_o<=held;oe<=1;timer<=0;state<=SETUP;
      end
    SETUP:if(!run_enable)state<=FLUSH;
      else if(txe_sync)begin stable<=0;state<=PERMISSION;end
      else if(timer==SETUP_CYCLES-1)begin
       wr_n<=0;timer<=0;gap<=0;stable<=0;state<=LOW;
      end else timer<=timer+1'b1;
    LOW:if(timer==LOW_CYCLES-1)begin wr_n<=1;timer<=0;state<=HOLD;end
        else timer<=timer+1'b1;
    HOLD:if(timer==HOLD_CYCLES-1)begin timer<=0;state<=RECOVERY;end
         else timer<=timer+1'b1;
    RECOVERY:if(timer==RECOVERY_CYCLES-1)begin
      timer<=0;state<=run_enable?IDLE:FLUSH;
     end else timer<=timer+1'b1;
    // Allow the registered pads to observe high WR and held AD before OE
    // releases. Normal stop never asynchronously truncates a write pulse.
    FLUSH:begin wr_n<=1;oe<=0;timer<=0;state<=STOP;end
    default:state<=STOP;
   endcase
  end
 end
endmodule
