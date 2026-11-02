`timescale 1ns/1ps
// Fixed Flash slot contract: 0=image7 (golden), 1=image1, 2=image5.
// Selection is a register edit; only a separate LOAD action may reboot.
// CONFIG stays low on reset/fallback, including when cfg_ERROR is asserted.
module flash_image_switch #(
 parameter CURRENT_SLOT=0, SELECT_ADDR=18, LOAD_ADDR=19,
 parameter CLOCK_HZ=96000000, TIMEOUT_CYCLES=960000000,
 parameter CAPTURE_CYCLES=8, TRIGGER_CYCLES=8
)(
 input clk,rst_n,write_valid,input [4:0] write_addr,input [11:0] write_value,
 input safe_to_switch,cfg_error,
 output reg [1:0] selected_slot,output reg [3:0] status,
 output reg stop_request,
 output reg [1:0] cfg_cbsel,output reg cfg_ena,cfg_config
);
 localparam IDLE=0,DRAIN=1,CAPTURE=2,TRIGGER=3,WAIT_REBOOT=4;
 localparam READY=0,WAITING=1,LOADING=2,FAILED=3,CURRENT=4;
 reg [2:0] state;
 reg [1:0] target;
 reg [29:0] timer;
 (* async_reg="true" *) reg error_meta,error_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin error_meta<=0;error_sync<=0;end
  else begin error_meta<=cfg_error;error_sync<=error_meta;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;selected_slot<=CURRENT_SLOT;target<=CURRENT_SLOT;
   status<=READY;stop_request<=0;cfg_cbsel<=CURRENT_SLOT;
   cfg_ena<=0;cfg_config<=0;timer<=0;
  end else begin
   case(state)
    IDLE:begin
     cfg_ena<=0;cfg_config<=0;stop_request<=0;timer<=0;
     if(error_sync)status<=FAILED;
     if(write_valid && write_addr==SELECT_ADDR && write_value<3)begin
      selected_slot<=write_value[1:0];status<=READY;
     end
     if(write_valid && write_addr==LOAD_ADDR)begin
      if(selected_slot==CURRENT_SLOT)status<=CURRENT;
      else begin target<=selected_slot;stop_request<=1;status<=WAITING;state<=DRAIN;end
     end
    end
    DRAIN:begin
     stop_request<=1;
     if(safe_to_switch)begin
      cfg_cbsel<=target;cfg_ena<=1;timer<=0;state<=CAPTURE;status<=LOADING;
     end else if(timer==TIMEOUT_CYCLES-1)begin
      state<=IDLE;status<=FAILED;stop_request<=0;timer<=0;
     end else timer<=timer+1'b1;
    end
    CAPTURE:begin
     // CBSEL and ENA settle for multiple 96 MHz edges before CONFIG rises.
     if(timer==CAPTURE_CYCLES-1)begin cfg_config<=1;timer<=0;state<=TRIGGER;end
     else timer<=timer+1'b1;
    end
    TRIGGER:begin
     if(timer==TRIGGER_CYCLES-1)begin cfg_config<=0;timer<=0;state<=WAIT_REBOOT;end
     else timer<=timer+1'b1;
    end
    WAIT_REBOOT:begin
     // Normally configuration destroys this logic. No repeated CONFIG pulses
     // if a missing/misprogrammed Flash leaves the old application running.
     if(timer==TIMEOUT_CYCLES-1)begin cfg_ena<=0;stop_request<=0;status<=FAILED;state<=IDLE;timer<=0;end
     else timer<=timer+1'b1;
    end
    default:begin state<=IDLE;cfg_ena<=0;cfg_config<=0;stop_request<=0;status<=FAILED;end
   endcase
  end
 end
endmodule
