`timescale 1ns/1ps
// TXE is sampled by the periphery input FF at ft_sample (11.667 ns after
// CLKOUT at B8). TX clock is advanced by 2.5ns; pad Tco restores the write
// phase. Queue advance uses this correctly phased TXE sample, never a stale
// two-flop synchronizer. A rejected one-cycle write pulse retries its byte.
module ft245_sync_tx(
 input clk,input rst_n,input txe_n_sampled,
 input valid,input [7:0] data,output reg ready,
 output [7:0] data_o,output wr_n
);
 localparam IDLE=0,ARM=1,WRITE=2,GAP=3;
 reg [1:0] state;reg [7:0] held_data;reg qualified,launched;
 // These are D inputs of periphery output FFs, not physical pad levels.
 // Sampling them at clk launches exactly the same WRITE transition as state.
 assign data_o=held_data;
 // Qualify a new pulse from a registered ready indication, and separately
 // check the correctly phased TXE at the accepting edge. An in-flight pulse
 // rejected by new backpressure never advances the source. No late TXE-to-WR
 // path has to cross the chip from A13 to C3.
 assign wr_n=!rst_n||state!=ARM||!qualified;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;held_data<=0;ready<=0;qualified<=0;launched<=0;end
  else begin
   // Register acceptance once; the packet/CRC logic gets a full cycle.
   // GAP prevents launching the next byte before its source advances.
   qualified<=!txe_n_sampled;
   ready<=state==WRITE&&launched&&!txe_n_sampled;
   case(state)
   IDLE:begin
    if(valid&&qualified)begin held_data<=data;state<=ARM;end
   end
   ARM:begin launched<=qualified;state<=WRITE;end
   WRITE:state<=GAP;
   GAP:state<=IDLE;
   default:state<=IDLE;
   endcase
  end
 end
endmodule
