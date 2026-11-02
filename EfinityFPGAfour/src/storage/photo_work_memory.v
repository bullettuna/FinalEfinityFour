`timescale 1ns/1ps
// Serialized 16/32-bit workspace access over the existing full-strobe AXI port.
// Four fully associative 128-bit write-through cache lines amortize stencil,
// queue and pixel accesses. Invalidate between frames/owners. No hidden dirty data.
// Once offered, AXI VALID is held until acceptance. Timeouts latch fault and
// continue draining the transaction; reset is required before reusing this unit.
module photo_work_memory #(parameter TIMEOUT=48000000)(
 input clk,input rst_n,input invalidate,input req,input wr,input size32,
 input [31:0] addr,input [31:0] data,
 output ready,output reg done,output reg [31:0] result,output reg fault,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,rvalid,output rready
);
 localparam IDLE=0,LOOK=1,RA=2,RD=3,EDIT=4,WA=5,WD=6,WB=7,RESP=8,DRAIN=9;
 reg [3:0] state;reg [31:0] address,payload,timer;reg write_req,wide;
 reg [3:0] valid;reg [27:0] tags[0:3];reg [127:0] lines[0:3];
 reg [1:0] victim,selected;reg [127:0] word_data;
 reg hit;reg [1:0] hit_index;integer k;
 always @*begin hit=0;hit_index=0;for(k=0;k<4;k=k+1)
  if(valid[k]&&tags[k]==address[31:4])begin hit=1;hit_index=k;end end
 wire [6:0] shift={address[3:0],3'b000};
 wire [127:0] mask=(wide?128'hffffffff:128'hffff)<<shift;
 assign ready=state==IDLE&&!fault;
 assign awaddr={address[31:4],4'b0};assign awlen=0;assign awvalid=state==WA;
 assign wdata=word_data;assign wlast=1;assign wvalid=state==WD;
 assign araddr={address[31:4],4'b0};assign arlen=0;assign arvalid=state==RA;
 assign rready=state==RD||state==DRAIN;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;address<=0;payload<=0;timer<=0;write_req<=0;wide<=0;
   valid<=0;victim<=0;selected<=0;word_data<=0;done<=0;result<=0;fault<=0;end
  else begin
   done<=0;
   if(invalidate&&state==IDLE)begin valid<=0;victim<=0;end
   if(state==IDLE||state==LOOK||state==EDIT||state==RESP)timer<=0;
   else if(timer<TIMEOUT)timer<=timer+1'b1;else fault<=1;
   case(state)
    IDLE:if(req&&!fault)begin
     address<=addr;payload<=data;write_req<=wr;wide<=size32;
     if(addr[0]||(size32&&addr[1]))begin fault<=1;done<=1;end else state<=LOOK;
    end
    LOOK:begin
     if(hit)begin selected<=hit_index;word_data<=lines[hit_index];state<=EDIT;end
     else begin selected<=victim;victim<=victim+1'b1;state<=RA;end
    end
    RA:if(arready)begin state<=RD;timer<=0;end
    RD:if(rvalid)begin
     if(rresp!=0||!rlast)fault<=1;
     if(!rlast)state<=DRAIN;
     else begin word_data<=rdata;tags[selected]<=address[31:4];lines[selected]<=rdata;
      valid[selected]<=rresp==0;state<=EDIT;end
    end
    DRAIN:if(rvalid&&rlast)begin state<=RESP;end
    EDIT:begin
     result<=word_data>>shift;
     if(write_req&&!fault)begin word_data<=(word_data&~mask)|(({96'd0,payload}<<shift)&mask);state<=WA;end
     else state<=RESP;
    end
    WA:if(awready)begin state<=WD;timer<=0;end
    WD:if(wready)begin state<=WB;timer<=0;end
    WB:if(bvalid)begin
     if(bresp!=0)fault<=1;
     lines[selected]<=word_data;tags[selected]<=address[31:4];valid[selected]<=bresp==0;
     state<=RESP;
    end
    RESP:begin done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
