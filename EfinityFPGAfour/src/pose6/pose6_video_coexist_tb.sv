`timescale 1ns/1ps
// Exercise the actual image5/image6 link modules, not stand-in AXI clients.
// Two independent deterministic DDR models allow cycle-exact idle comparison.
module pose6_video_case #(parameter IMAGE6=0)(
 input clk,pclk,rst_n,run_n,input [1:0] phase,
 input vs,de,input [7:0] pixel,rx_data,input rx_valid,
 output [40:0] trace,
 output integer video_reads=0,video_writes=0,
 output integer snapshot_reads=0,snapshot_writes=0,model_writes=0,
 output integer max_read_cycles=0,max_write_cycles=0
);
 integer cycle=0,read_start=0,write_start=0;
 wire [31:0] paw,par_;wire [7:0] pawl,parl;
 wire pawv,pawr,pwv,pwr,pwl,pbv,parv,parr,prv,prr,prl;
 wire [127:0] pwd,prd;wire [1:0] pbresp,prresp;
 wire stopped;
 wire [383:0] diagnostic_data;
 generate if(IMAGE6)begin:g6
  image6_ft_link #(.WIDTH(96),.HEIGHT(72)) link(
   .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(run_n),.mode(2'd3),.resolution(2'd1),.edge_packed(1'b1),.txe_n_async(1'b1),
   .gray_vs(vs),.gray_de(de),.gray_pixel(pixel),.edge_vs(vs),.edge_de(de),.edge_pixel(pixel),
   .uart_rx_data(rx_data),.uart_rx_valid(rx_valid),.uart_legacy_valid(),.uart_tx_valid(),.uart_tx_data(),.uart_tx_accept(cycle%3!=1),
   .video_diagnostic_data(diagnostic_data),
   .link_ready(),.stopped(stopped),.data_o(),.data_oe(),.wr_n(),.wr_oe(),
   .awaddr(paw),.awlen(pawl),.awvalid(pawv),.awready(pawr),.wdata(pwd),.wlast(pwl),.wvalid(pwv),.wready(pwr),.bvalid(pbv),.bresp(pbresp),
   .araddr(par_),.arlen(parl),.arvalid(parv),.arready(parr),.rdata(prd),.rresp(prresp),.rlast(prl),.rvalid(prv),.rready(prr));
  always @(posedge clk)if(rst_n)begin
   if(link.model_ready!==0||link.state!==0)$fatal(1,"Inference self-started without weights");
   if(phase==0&&(link.mv!==0||link.mav_w!==0||link.mav_r!==0))$fatal(1,"Idle model issued DDR request");
  end
  reg [7:0] bytes[0:55];integer byte_count=0;
  integer diagnostic_file;
  initial diagnostic_file=$fopen("video_diag.bin","wb");
  reg [383:0] snapshot;
  reg [31:0] crc=32'hffffffff;
  function [31:0] crc_byte(input [31:0] previous,input [7:0] b);
   reg [31:0] c;integer k;
   begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
  endfunction
  always @(posedge clk)if(rst_n)begin
   if(link.diagnostic_start&&!link.diagnostic_busy)snapshot<=diagnostic_data;
   if(link.diagnostic_valid&&!link.loader_tx_valid&&cycle%3!=1)begin
    $fwrite(diagnostic_file,"%c",link.uart_tx_data);
    bytes[byte_count]<=link.uart_tx_data;
    if(byte_count<52)crc<=crc_byte(crc,link.uart_tx_data);
    if(byte_count>=4&&byte_count<52&&link.uart_tx_data!==snapshot[(byte_count-4)*8+:8])$fatal(1,"Diagnostic snapshot changed during reply");
    if(byte_count==55)begin
     if({bytes[3],bytes[2],bytes[1],bytes[0]}!==32'h31443650)$fatal(1,"Diagnostic header");
     if({link.uart_tx_data,bytes[54],bytes[53],bytes[52]}!==~crc)$fatal(1,"Diagnostic CRC");
     if(snapshot[63:32]==0||snapshot[95:64]==0||snapshot[127:96]==0)$fatal(1,"Camera diagnostic counters did not cross clock domains");
     $fclose(diagnostic_file);
     $display("PASS read-only ~6D diagnostic: actual loader, immutable counter snapshot, async camera counters, UART backpressure, 56-byte reply and CRC");
    end
    byte_count<=byte_count+1;
   end
  end
 end else begin:g5
  image5_ft_link #(.WIDTH(96),.HEIGHT(72)) link(
   .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(run_n),.mode(2'd3),.resolution(2'd1),.edge_packed(1'b1),.txe_n_async(1'b1),
   .gray_vs(vs),.gray_de(de),.gray_pixel(pixel),.edge_vs(vs),.edge_de(de),.edge_pixel(pixel),
   .link_ready(),.stopped(stopped),.data_o(),.data_oe(),.wr_n(),.wr_oe(),
   .awaddr(paw),.awlen(pawl),.awvalid(pawv),.awready(pawr),.wdata(pwd),.wlast(pwl),.wvalid(pwv),.wready(pwr),.bvalid(pbv),.bresp(pbresp),
   .araddr(par_),.arlen(parl),.arvalid(parv),.arready(parr),.rdata(prd),.rresp(prresp),.rlast(prl),.rvalid(prv),.rready(prr));
 end endgenerate
 // Live video uses the production 128-beat burst size. Both channels stay
 // busy; RREADY and every DDR channel independently apply backpressure.
 reg [1:0] vwstate=0,vrstate=0;
 reg [31:0] vwa=0,vra=32'h00800000;
 reg [7:0] vwbeat=0,vrbeat=0;
 wire vawv=vwstate==0&&rst_n,vwv=vwstate==1,vwl=vwbeat==127;
 wire vawr,vwr,vbv,varr,vrv,vrl;wire [1:0] vbresp,vrresp;wire [127:0] vrd;
 wire varv=vrstate==0&&rst_n,vrr=vrstate==1&&cycle%11!=4;
 function [127:0] pattern(input [31:0] a);
  pattern={a^32'h13579bdf,a^32'h2468ace0,a^32'hfeed1234,a};
 endfunction
 wire [127:0] vwd=pattern(vwa+vwbeat*16);
 wire [31:0] aw,ar;wire [7:0] awl,arl;
 wire awv,wv,wl,br,arv,rr;wire [127:0] wd;wire [15:0] strb;
 reg [1:0] ws=0,rs=0;
 reg [31:0] wa=0,ra=0;reg [7:0] wlen=0,rlen=0,wb=0,rb=0;
 reg [3:0] rdelay=0;
 wire awr=ws==0&&cycle%5!=1;
 wire wr=ws==1&&cycle%7!=2;
 wire bv=ws==2&&cycle%3!=1;
 wire arr=rs==0&&cycle%6!=3;
 wire rv=rs==2;wire rl=rb==rlen;wire [127:0] rd=pattern(ra+rb*16);
 wire stall;wire [3:0] debug_state;
 photo_axi_mux outer_mux(
  .clk(clk),.rst_n(rst_n),.v_read_flush(1'b0),.v_read_urgent(cycle%37<27),.read_stalled(stall),.read_debug(debug_state),
  .v_awaddr(vwa),.v_awlen(8'd127),.v_awvalid(vawv),.v_awready(vawr),.v_wdata(vwd),.v_wstrb(16'hffff),.v_wlast(vwl),.v_wvalid(vwv),.v_wready(vwr),.v_bvalid(vbv),.v_bresp(vbresp),
  .v_araddr(vra),.v_arlen(8'd127),.v_arvalid(varv),.v_arready(varr),.v_rdata(vrd),.v_rresp(vrresp),.v_rlast(vrl),.v_rvalid(vrv),.v_rready(vrr),
  .p_awaddr(paw),.p_awlen(pawl),.p_awvalid(pawv),.p_awready(pawr),.p_wdata(pwd),.p_wlast(pwl),.p_wvalid(pwv),.p_wready(pwr),.p_bvalid(pbv),.p_bresp(pbresp),
  .p_araddr(par_),.p_arlen(parl),.p_arvalid(parv),.p_arready(parr),.p_rdata(prd),.p_rresp(prresp),.p_rlast(prl),.p_rvalid(prv),.p_rready(prr),
  .m_awaddr(aw),.m_awlen(awl),.m_awvalid(awv),.m_awready(awr),.m_wdata(wd),.m_wstrb(strb),.m_wlast(wl),.m_wvalid(wv),.m_wready(wr),.m_bvalid(bv),.m_bresp(2'd0),.m_bready(br),
  .m_araddr(ar),.m_arlen(arl),.m_arvalid(arv),.m_arready(arr),.m_rdata(rd),.m_rresp(2'd0),.m_rlast(rl),.m_rvalid(rv),.m_rready(rr));
 assign trace={vawr,vwr,vbv,varr,vrv,vrl,vawv,vwv,varv,vrv?vrd[31:0]:32'd0};
 pose6_video_diag #(.EXPECTED_WORDS(6912)) observer(
  .clk(clk),.cam_clk(pclk),.pixel_clk(pclk),.rst_n(rst_n),.cam_vs(vs),.cam_de(de),
  .underflow_count(32'd0),.bad_frame_count(32'd0),.status(32'd6),
  .video_awaddr(vwa),.video_araddr(vra),.video_awvalid(vawv),.video_awready(vawr),.video_arvalid(varv),.video_arready(varr),
  .aux_awvalid(pawv),.aux_awready(pawr),.aux_arvalid(parv),.aux_arready(parr),.data(diagnostic_data));
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;
  if(phase==0&&(pawv!==0||parv!==0||pwv!==0))$fatal(1,"Idle link issued DDR request image%0d",IMAGE6?6:5);
  if(stall)$fatal(1,"DDR arbiter stalled");
  if(vwstate==0&&vawr)begin vwstate<=1;vwbeat<=0;write_start<=cycle;end
  if(vwv&&vwr)begin vwbeat<=vwbeat+1'b1;if(vwl)vwstate<=2;end
  if(vbv)begin
   if(vwstate!=2||vbresp!=0)$fatal(1,"Video write response");
   vwstate<=0;vwa<=vwa+2048;video_writes<=video_writes+1;
   if(cycle-write_start>max_write_cycles)max_write_cycles<=cycle-write_start;
  end
  if(vrstate==0&&varr)begin vrstate<=1;vrbeat<=0;read_start<=cycle;end
  if(vrv&&vrr)begin
   if(vrstate!=1||vrresp!=0||vrl!==(vrbeat==127)||vrd!==pattern(vra+vrbeat*16))$fatal(1,"Video read data/ownership");
   vrbeat<=vrbeat+1'b1;
   if(vrl)begin
    vrstate<=0;vra<=vra+2048;video_reads<=video_reads+1;
    if(cycle-read_start>max_read_cycles)max_read_cycles<=cycle-read_start;
   end
  end
  if((vwstate!=0&&cycle-write_start>1200)||(vrstate!=0&&cycle-read_start>1200))$fatal(1,"Video transaction blocked over 1200 cycles");
  if(awv&&awr)begin wa<=aw;wlen<=awl;wb<=0;ws<=1;end
  if(wv&&wr)begin
   if(wl!==(wb==wlen)||strb!==16'hffff)$fatal(1,"DDR write length/strobes");
   if(wa<32'h01000000&&wd!==pattern(wa+wb*16))$fatal(1,"DDR video write corrupted");
   if(wa>=32'h02000000)begin
    if(wa!=32'h02000000+model_writes*16||wlen!=0)$fatal(1,"Model write address");
    for(integer j=0;j<16;j=j+1)
     if(wd[j*8+:8]!==8'(model_writes*16+j))$fatal(1,"Model write data");
    model_writes<=model_writes+1;
   end
   wb<=wb+1'b1;if(wl)begin ws<=2;if(wa==32'h01800000||wa>32'h01800000&&wa<32'h02000000)snapshot_writes<=snapshot_writes+1;end
  end
  if(bv&&br)ws<=0;
  if(arv&&arr)begin
   ra<=ar;rlen<=arl;rb<=0;rs<=1;rdelay<=cycle%5+1;
   if(ar>=32'h01800000&&ar<32'h02000000)snapshot_reads<=snapshot_reads+1;
  end
  if(rs==1)begin if(rdelay!=0)rdelay<=rdelay-1'b1;else rs<=2;end
  if(rv&&rr)begin rb<=rb+1'b1;if(rl)rs<=0;end
 end
endmodule

module pose6_video_coexist_tb;
 `include "images/image6_pose_int16/pose6_model_identity.vh"
 reg clk=0,pclk=0,rst_n=0,run_n=0;
 always #5 clk=~clk;always #3 pclk=~pclk;
 reg [1:0] phase=0;
 reg [7:0] rx_data=0;reg rx_valid=0;
 integer px=0,py=0;
 always @(posedge pclk)if(!rst_n)begin px<=0;py<=0;end
 else if(px==103)begin px<=0;py<=py==79?0:py+1;end else px<=px+1;
 wire vs=py<72,de=py<72&&px>=1&&px<=96;
 wire [7:0] pixel=px%7==0?8'hff:8'd0;
 wire [40:0] t5,t6;
 wire [31:0] r5,w5,sr5,sw5,mw5,mr5,mt5,r6,w6,sr6,sw6,mw6,mr6,mt6;
 pose6_video_case #(.IMAGE6(0)) c5(clk,pclk,rst_n,run_n,phase,vs,de,pixel,rx_data,rx_valid,t5,r5,w5,sr5,sw5,mw5,mr5,mt5);
 pose6_video_case #(.IMAGE6(1)) c6(clk,pclk,rst_n,run_n,phase,vs,de,pixel,rx_data,rx_valid,t6,r6,w6,sr6,sw6,mw6,mr6,mt6);
 always @(negedge clk)if(rst_n&&phase==0&&t5!==t6)$fatal(1,"image5/image6 idle video traces differ");
 task send_byte(input [7:0] b);
  begin @(negedge clk);rx_data=b;rx_valid=1;@(negedge clk);rx_valid=0;repeat(3)@(negedge clk);end
 endtask
 integer before_r,before_w;
 initial begin
  #31;rst_n=1;
  repeat(25000)@(negedge clk);
  if(r6<100||w6<100)$fatal(1,"Insufficient idle video traffic");
  $display("PASS idle: zero image6 DDR requests; image5/image6 video cycle-exact over 25000 cycles (%0d reads, %0d writes)",r6,w6);
  send_byte("~");send_byte("6");send_byte("D");
  wait(c6.g6.byte_count==56);
  phase=1;run_n=1;before_r=r6;before_w=w6;
  repeat(30000)@(negedge clk);
  if(sw6!=6||sr6==0||sw5!=6||sr5==0||r6-before_r<100||w6-before_w<100)$fatal(1,"Snapshot/blocked USB did not coexist with video");
  $display("PASS blocked USB: both real links captured 768-byte snapshot; video progressed (%0d reads, %0d writes)",r6-before_r,w6-before_w);
  run_n=0;
  wait(c5.stopped&&c6.stopped);
  phase=2;before_r=r6;before_w=w6;
  send_byte("~");send_byte("6");send_byte("L");
  for(integer k=0;k<4;k=k+1)send_byte(POSE6_MODEL_BYTES>>(k*8));
  for(integer k=0;k<4;k=k+1)send_byte(POSE6_MODEL_CRC>>(k*8));
  for(integer k=0;k<32;k=k+1)begin send_byte(k);repeat(30)@(negedge clk);end
  repeat(3000)@(negedge clk);
  if(mw6!=2||r6-before_r<10||w6-before_w<10)$fatal(1,"Real model upload blocked video");
  $display("PASS model upload: actual UART loader and nested DDR mux wrote 32 checked bytes while video progressed");
  $display("PASS image6 video coexistence: 128-beat live bursts, async pixels, idle equivalence, snapshot with USB blocked, model upload; max image6 read/write service %0d/%0d cycles",mr6,mt6);
  $finish;
 end
 initial begin #3000000;$fatal(1,"Video coexistence timeout");end
endmodule
