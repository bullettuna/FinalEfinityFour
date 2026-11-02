`timescale 1ns/1ps
// Production 128-beat reads, real shared DDR arbiter, and E/RAW frame resets
// at different phases. Old E response tails must never seed the next frame.
module axi4_edge_reset_tb #(parameter RESET_DELAY=60);
reg clk=0,pclk=0,reset=1,raw_vs=1,edge_vs=1,enable=0,pop=0;
always #5 clk=~clk; always #3 pclk=~pclk;
wire [31:0] araddr,ma;wire [7:0] arlen,ml;wire av,ard,rv,rl,rr,flush,urgent;
wire [127:0] rd,mrd;wire [1:0] resp;wire [7:0] byte_data;wire byte_valid;
wire mav,mready;reg mrv=0,mrl=0;reg [127:0] mrdata=0;
integer addr=0,left=0,ticks=0,accepted=0;
assign mrd=mrdata;
assign mready=left==0&&!mrv;
axi4_ctrl #(.C_W_WIDTH(32),.C_BURST_LEN(128),.C_RD_END_ADDR(2048),.C_BUF_SIZE(14),
 .BACKGROUND_BUILD(1),.C_PHOTO0_BASE_ADDR(32'h20000),.C_PHOTO_BYTES(8192)) dut(
 .axi_clk(clk),.axi_reset(reset),.axi_awready(1'b0),.axi_wready(1'b0),.axi_bvalid(1'b0),.axi_bresp(2'd0),
 .axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(av),.axi_arready(ard),
 .axi_rdata(rd),.axi_rvalid(rv),.axi_rlast(rl),.axi_rresp(resp),.axi_rready(rr),
 .read_frame_flush(flush),.read_urgent(urgent),
 .wframe_pclk(clk),.wframe_vsync(1'b0),.wframe_data_en(1'b0),.wframe_data(32'd0),
 .rframe_pclk(pclk),.rframe_vsync(raw_vs),.rframe_data_en(1'b0),.freeze_i(1'b1),
 .background_capture_i(1'b0),.background_read_enable_i(1'b0),
 .photo_write_valid_i(1'b0),.photo_load_start_i(1'b0),.photo_load_end_i(1'b0),
 .photo_read_enable_i(enable),.photo_read_buffer_i(1'b0),.photo_rframe_pclk(pclk),
 .photo_rframe_vsync(edge_vs),.photo_rframe_data_en(pop),
 .photo_rframe_data(byte_data),.photo_rframe_valid(byte_valid));
photo_axi_mux mux(.clk(clk),.rst_n(!reset),.v_read_flush(flush),.v_read_urgent(urgent),
 .v_awaddr(32'd0),.v_awlen(8'd0),.v_awvalid(1'b0),.v_wdata(128'd0),.v_wstrb(16'd0),.v_wlast(1'b0),.v_wvalid(1'b0),
 .v_araddr(araddr),.v_arlen(arlen),.v_arvalid(av),.v_arready(ard),.v_rdata(rd),.v_rresp(resp),.v_rlast(rl),.v_rvalid(rv),.v_rready(rr),
 .p_awaddr(32'd0),.p_awlen(8'd0),.p_awvalid(1'b0),.p_wdata(128'd0),.p_wlast(1'b0),.p_wvalid(1'b0),
 .p_araddr(32'd0),.p_arlen(8'd0),.p_arvalid(1'b0),.p_rready(1'b1),
 .m_awready(1'b0),.m_wready(1'b0),.m_bvalid(1'b0),.m_bresp(2'd0),
 .m_araddr(ma),.m_arlen(ml),.m_arvalid(mav),.m_arready(mready),
 .m_rdata(mrd),.m_rvalid(mrv),.m_rlast(mrl),.m_rresp(2'd0),.m_rready());
function automatic [7:0] pattern(input integer position);
 pattern=8'((position*29+(position/16)*7+(position/256)*31)^((position>>3)*17));
endfunction
always @(posedge clk)begin
 if(!reset)begin
  ticks<=ticks+1;
  if(mav&&mready)begin addr=ma;left=ml+1;accepted++;end
  if(mrv&&mux.m_rready)begin mrv<=0;addr+=16;left--;end
  if(!mrv&&left>0&&ticks%5==0)begin
   for(integer b=0;b<16;b++)mrdata[(15-b)*8+:8]<=pattern(addr-131072+b);
   mrv<=1;mrl<=left==1;
  end
 end
end
initial begin
 repeat(10)@(negedge clk);reset=0;repeat(100)@(negedge clk);enable=1;
 wait(mrv&&ma>=32'h20000&&left==8);@(negedge pclk);
 // RAW first, E later: an outstanding frame transaction crosses both.
 raw_vs=0;repeat(RESET_DELAY)@(negedge pclk);edge_vs=0;
 repeat(36)@(negedge pclk);raw_vs=1;edge_vs=1;
 repeat(2200)@(negedge clk);
 for(integer i=0;i<1024;i++)begin
  @(negedge pclk);pop=1;#1;
  if(!byte_valid||byte_data!==pattern(i))$fatal(1,"E reset crossed outstanding burst: byte=%0d got=%h expected=%h valid=%b",i,byte_data,pattern(i),byte_valid);
  @(negedge pclk);pop=0;repeat(2)@(negedge pclk);
 end
 $display("PASS E/RAW asynchronous frame resets discard stale 128-beat DDR response tails; byte alignment retained");$finish;
end
initial begin #1000000;$fatal(1,"E reset regression timeout");end
endmodule
