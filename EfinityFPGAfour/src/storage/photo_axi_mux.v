`timescale 1ns/1ps
// Two 128-bit AXI clients, one outstanding read and one outstanding write.
// Ownership stays fixed through RLAST / B, including address backpressure.
module photo_axi_mux #(parameter READ_TIMEOUT=4800000)(
 input clk,input rst_n,
 input v_read_flush,input v_read_urgent,
 output reg read_stalled,output [3:0] read_debug,
 input [31:0] v_awaddr,input [7:0] v_awlen,input v_awvalid,output v_awready,
 input [127:0] v_wdata,input [15:0] v_wstrb,input v_wlast,input v_wvalid,output v_wready,
 output v_bvalid,output [1:0] v_bresp,
 input [31:0] v_araddr,input [7:0] v_arlen,input v_arvalid,output v_arready,
 output [127:0] v_rdata,output [1:0] v_rresp,output v_rlast,output v_rvalid,input v_rready,
 input [31:0] p_awaddr,input [7:0] p_awlen,input p_awvalid,output p_awready,
 input [127:0] p_wdata,input p_wlast,input p_wvalid,output p_wready,
 output p_bvalid,output [1:0] p_bresp,
 input [31:0] p_araddr,input [7:0] p_arlen,input p_arvalid,output p_arready,
 output [127:0] p_rdata,output [1:0] p_rresp,output p_rlast,output p_rvalid,input p_rready,
 output [31:0] m_awaddr,output [7:0] m_awlen,output m_awvalid,input m_awready,
 output [127:0] m_wdata,output [15:0] m_wstrb,output m_wlast,output m_wvalid,input m_wready,
 input m_bvalid,input [1:0] m_bresp,output m_bready,
 output [31:0] m_araddr,output [7:0] m_arlen,output m_arvalid,input m_arready,
 input [127:0] m_rdata,input [1:0] m_rresp,input m_rlast,input m_rvalid,output m_rready
);
 reg [1:0] ws,rs;
 reg wo,ro,wpref,rpref;
 reg [31:0] wr_addr,rd_addr,read_timer;
 reg [7:0] wr_len,rd_len;
 reg [8:0] read_beats;
 reg discard_video;
 wire choose_write=p_awvalid&&(!v_awvalid||wpref);
 wire video_read=v_arvalid&&!v_read_flush;
 wire choose_read=p_arvalid&&(!video_read||(!v_read_urgent&&rpref));
 // A one-entry request buffer owns the descriptor from the CLIENT handshake.
 // Frame reset may then withdraw/change the client's request without changing
 // an address already offered to DDR. Only a global reset cancels DDR VALID.
 assign m_awaddr=wr_addr;
 assign m_awlen=wr_len;
 assign m_awvalid=(ws==1);
 assign p_awready=(ws==0)&&choose_write;
 assign v_awready=(ws==0)&&!choose_write;
 assign m_wdata=wo?p_wdata:v_wdata;
 assign m_wstrb=wo?16'hffff:v_wstrb;
 assign m_wlast=wo?p_wlast:v_wlast;
 assign m_wvalid=(ws==2)&&(wo?p_wvalid:v_wvalid);
 assign p_wready=(ws==2)&&wo&&m_wready;
 assign v_wready=(ws==2)&&!wo&&m_wready;
 assign m_bready=(ws==3);
 assign p_bvalid=(ws==3)&&wo&&m_bvalid;
 assign v_bvalid=(ws==3)&&!wo&&m_bvalid;
 assign p_bresp=m_bresp;assign v_bresp=m_bresp;
 assign m_araddr=rd_addr;
 assign m_arlen=rd_len;
 assign m_arvalid=(rs==1);
 assign p_arready=(rs==0)&&choose_read;
 assign v_arready=(rs==0)&&!choose_read&&!v_read_flush;
 // Drain old video responses across VSYNC; never refill a new frame with them.
 assign m_rready=(rs==2)&&(ro?p_rready:((discard_video||v_read_flush)?1'b1:v_rready));
 assign p_rvalid=(rs==2)&&ro&&m_rvalid;
 assign v_rvalid=(rs==2)&&!ro&&!discard_video&&!v_read_flush&&m_rvalid;
 assign p_rdata=m_rdata;assign v_rdata=m_rdata;
 assign p_rresp=m_rresp;assign v_rresp=m_rresp;
 assign p_rlast=m_rlast;assign v_rlast=m_rlast;
 assign read_debug=(rs==0) ? 4'd0 : ((rs==1) ? 4'd1 :
                   ((read_beats>=({1'b0,rd_len}+9'd1)) ? 4'd3 : 4'd2));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   ws<=0;rs<=0;wo<=0;ro<=0;wpref<=0;rpref<=0;
   wr_addr<=0;rd_addr<=0;wr_len<=0;rd_len<=0;
   read_timer<=0;read_beats<=0;discard_video<=0;read_stalled<=0;
  end
  else begin
   case(ws)
    0: if(v_awvalid||p_awvalid) begin
     wo<=choose_write;wr_addr<=choose_write?p_awaddr:v_awaddr;
     wr_len<=choose_write?p_awlen:v_awlen;ws<=1;
    end
    1: if(m_awvalid&&m_awready) ws<=2;
    2: if(m_wvalid&&m_wready&&m_wlast) ws<=3;
    3: if(m_bvalid) begin ws<=0;wpref<=!wo;end
   endcase
   if(rs!=0&&!ro&&v_read_flush)discard_video<=1;
   if(rs!=0)begin
    if(read_timer<READ_TIMEOUT)read_timer<=read_timer+1'b1;
    else read_stalled<=1;
   end
   case(rs)
    0: begin
     read_timer<=0;read_stalled<=0;
     if(video_read||p_arvalid) begin
      ro<=choose_read;rd_addr<=choose_read?p_araddr:v_araddr;
      rd_len<=choose_read?p_arlen:v_arlen;read_beats<=0;
      discard_video<=0;rs<=1;
     end
    end
    1: if(m_arready)begin rs<=2;read_timer<=0;end
    2: if(m_rvalid&&m_rready)begin
     read_timer<=0;read_beats<=read_beats+1'b1;
     if(read_beats=={1'b0,rd_len}&&!m_rlast)read_stalled<=1;
     if(m_rlast)begin rs<=0;rpref<=!ro;read_stalled<=0;end
    end
    default:rs<=0;
   endcase
  end
 end
endmodule
