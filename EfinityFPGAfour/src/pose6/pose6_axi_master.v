`timescale 1ns/1ps
// One aligned 128-bit transaction. VALID and addresses remain owned until
// handshaken; software stop never cancels a live DDR transaction.
module pose6_axi_master(
 input clk,input rst_n,input command_valid,output command_ready,input command_write,
 input [31:0] command_address,input [127:0] command_data,
 output reg response_valid,output reg [127:0] response_data,output reg fault,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 reg [2:0] state;reg [31:0] address;reg [127:0] data;
 assign command_ready=state==0;
 assign awaddr=address;assign araddr=address;assign wdata=data;
 assign awlen=0;assign arlen=0;assign wlast=1;
 assign awvalid=state==1;assign wvalid=state==2;assign arvalid=state==4;assign rready=state==5;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;address<=0;data<=0;response_valid<=0;response_data<=0;fault<=0;end
  else begin
   response_valid<=0;
   case(state)
    0:if(command_valid)begin
     address<=command_address;data<=command_data;state<=command_write?1:4;
     if(command_address[3:0]!=0)fault<=1;
    end
    1:if(awready)state<=2;
    2:if(wready)state<=3;
    3:if(bvalid)begin if(bresp!=0)fault<=1;response_valid<=1;state<=0;end
    4:if(arready)state<=5;
    5:if(rvalid)begin
     if(rresp!=0||!rlast)fault<=1;
     response_data<=rdata;response_valid<=1;state<=0;
    end
   endcase
  end
 end
endmodule
