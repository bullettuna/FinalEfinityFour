`timescale 1ns/1ps
module ft_async_link_tb;
 parameter WIDTH=384,HEIGHT=216,FAST=0,FRAMES=2,ABORT_ONLY=0;
 reg clk=0,pclk=0,rst_n=0,run=0;reg [1:0] mode=0,resolution=0;
 always #5.208333 clk=~clk;always #3.36 pclk=~pclk;
 reg vs=0,de=0;reg [7:0] gray=0,edge_pixel=0;
 wire [31:0] awaddr,araddr;wire [7:0] awlen,arlen;wire awvalid,awready,wvalid,wready,wlast,bvalid;
 wire arvalid,arready,rvalid,rready,rlast;wire [127:0] wdata,rdata;wire [1:0] bresp,rresp;
 wire stopped,link_ready,wr,woe;wire [7:0] dout,doe;
 reg edge_packed=1;reg txe=0;reg block_write=0,inject_error=0;
 image5_ft_link #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) dut(
  .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(run),.mode(mode),.resolution(resolution),.edge_packed(edge_packed),.txe_n_async(txe),
  .gray_vs(vs),.gray_de(de),.gray_pixel(gray),.edge_vs(vs),.edge_de(de),.edge_pixel(edge_pixel),
  .link_ready(link_ready),.stopped(stopped),.data_o(dout),.data_oe(doe),.wr_n(wr),.wr_oe(woe),
  .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 // Short, independently stalled AXI transactions; no USB-rate RREADY hold.
 reg [127:0] mem[0:WIDTH*HEIGHT/16-1];
 integer cycle=0,wa=0,ra=0,wb=0,rb=0;reg wa_busy=0,ra_busy=0,bv=0;
 assign awready=!block_write&&!wa_busy&&!bv&&cycle%7!=0;assign wready=wa_busy&&cycle%5!=0;
 assign bvalid=bv;assign bresp=inject_error?2:0;
 assign arready=!ra_busy&&cycle%11!=0;assign rvalid=ra_busy&&cycle%3!=0;
 assign rdata=mem[ra+rb];assign rlast=rb==7;assign rresp=0;
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(bv)bv<=0;
  if(awvalid&&awready)begin
   if(awlen!=7||awaddr<32'h01800000||awaddr+128>32'h01800000+WIDTH*HEIGHT)$fatal(1,"DDR address ownership");
   wa<=(awaddr-32'h01800000)/16;wb<=0;wa_busy<=1;
  end
  if(wvalid&&wready)begin
   mem[wa+wb]<=wdata;wb<=wb+1;
   if((wb==7)!=wlast)$fatal(1,"AXI WLAST");
   if(wlast)begin wa_busy<=0;bv<=1;end
  end
  if(arvalid&&arready)begin ra<=(araddr-32'h01800000)/16;rb<=0;ra_busy<=1;end
  if(rvalid&&rready)begin rb<=rb+1;if(rlast)ra_busy<=0;end
 end
 integer x,y,frame_id=0;
 initial forever begin
  repeat(10)@(negedge pclk);vs=1;
  for(y=0;y<HEIGHT;y=y+1)begin
   for(x=0;x<WIDTH;x=x+1)begin
    @(negedge pclk);de=1;gray=(x*3+y*5+frame_id*17)&255;
    edge_pixel=(x==13||y==7||(x==0&&y==0))?255:0;
   end
   @(negedge pclk);de=0;repeat(8)@(negedge pclk);
  end
  vs=0;frame_id=frame_id+1;
 end
 // Model the real registered pads, then sample WR FALLING edges (no AC5).
 reg [7:0] qdata;reg qwr=1;
 always @(posedge clk)begin qdata<=dout;qwr<=wr;end
 wire [7:0] pdata;wire pwr;
 assign #3.5 pdata=qdata;assign #2.5 pwr=woe?qwr:1'b1;
 integer out=0,bytes_out=0,target=0,case_no=0;reg collect=0;
 always @(negedge pwr)if(collect&&!FAST)begin
  if(txe)$fatal(1,"actual TXE high at write");
  $fwrite(out,"%c",pdata);bytes_out=bytes_out+1;
 end
 initial if(!FAST)forever begin
  @(negedge pwr);#14;txe=1;@(posedge pwr);#(49+(bytes_out%7)*51.3);txe=0;
 end
 wire fast_ready=cycle%7!=0;
 initial if(FAST)force dut.ready=fast_ready;
 always @(posedge clk)if(collect&&FAST&&dut.valid&&dut.ready)begin $fwrite(out,"%c",dut.byte_data);bytes_out=bytes_out+1;end
 integer r,m,s;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
  if(!stopped||doe||!pwr)$fatal(1,"unsafe initial state");
  if(!ABORT_ONLY)for(m=1;m<=4;m=m+1)begin
   for(r=0;r<(m==1?1:3);r=r+1)begin
    @(negedge clk);mode=m==4?3:m;edge_packed=m!=4;resolution=r;bytes_out=0;
    out=$fopen($sformatf("async_%0d_%0d.bin",m,r),"wb");if(!out)$fatal(1,"output open");
    s=r==0?6:r==1?3:1;target=FRAMES*(28+(m==1?4096:m==3?((WIDTH/s)*(HEIGHT/s))/8:(WIDTH/s)*(HEIGHT/s)));
    collect=1;run=1;
    wait(bytes_out>=target);@(negedge clk);run=0;
    wait(stopped);repeat(8)@(posedge clk);collect=0;$fclose(out);
    if(wa_busy||ra_busy||doe||!pwr)$fatal(1,"stop abandoned AXI or pad transaction");
    $display("CASE mode=%d res=%d count=%d",m,r,bytes_out);
   end
  end
  // Stopping mid-capture must finish the producer and every accepted AXI
  // descriptor, not reset the client out from under the video arbiter.
  for(m=1;m<=3;m=m+1)begin
   @(negedge clk);mode=2;resolution=2;run=1;
   wait(dut.u_snapshot.ws==m);#1.7;run=0;
   wait(stopped);repeat(8)@(posedge clk);
   if(wa_busy||ra_busy||doe||!pwr)$fatal(1,"mid-capture stop abandoned transaction");
  end
  // A failed write response invalidates the entire captured frame.
  @(negedge clk);inject_error=1;run=1;
  wait(dut.u_snapshot.fault);run=0;inject_error=0;
  if(dut.available)$fatal(1,"published failed AXI frame");wait(stopped);
  // Overflow a deliberately blocked 16KiB capture FIFO; never publish it.
  @(negedge clk);block_write=1;run=1;
  wait(dut.u_snapshot.capturing);wait(!dut.u_snapshot.capturing);
  block_write=0;wait(dut.u_snapshot.fault);
  if(dut.available)$fatal(1,"published overflow frame");run=0;wait(stopped);
  // A following intact frame must recover without requiring FPGA reset.
  @(negedge clk);run=1;wait(dut.available);run=0;wait(stopped);
  $display("PASS async DDR: stop in AW/W/B, B-response error and overflow discard, intact-frame recovery");
  if(!ABORT_ONLY)$display("PASS async image link %dx%d FAST=%d: counter, all three sizes gray/edge, DDR backpressure, owned frame and graceful transaction drain",WIDTH,HEIGHT,FAST);$finish;
 end
 initial begin #(64'd10000000000);$fatal(1,"async image timeout state %d written %d fault %d",dut.u_snapshot.capture_state,dut.u_snapshot.written,dut.u_snapshot.fault);end
endmodule
