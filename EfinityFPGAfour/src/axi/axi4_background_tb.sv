`timescale 1ns/1ps
// Behavioral width-converting FIFOs and an AXI byte memory. This exercises
// real AW/W/B and AR/R traffic, not forced internal frame-index pulses.
module W0_FIFO_32(input wr_clk_i,wr_en_i,input [31:0] wdata,input a_rst_i,
 input rd_clk_i,rd_en_i,output [127:0] rdata,output prog_empty_o,empty_o);
 reg [31:0] mem[0:1023];integer wp=0,rp=0;
 always @(posedge wr_clk_i or posedge a_rst_i)if(a_rst_i)wp<=0;else if(wr_en_i)begin mem[wp]<=wdata;wp<=wp+1;end
 always @(posedge rd_clk_i or posedge a_rst_i)if(a_rst_i)rp<=0;else if(rd_en_i)rp<=rp+4;
 assign rdata={mem[rp+3],mem[rp+2],mem[rp+1],mem[rp]};
 assign empty_o=wp==rp;assign prog_empty_o=wp-rp<16;
endmodule
module R0_FIFO_8(input wr_clk_i,wr_en_i,input [127:0] wdata,input a_rst_i,output prog_full_o,
 input rd_clk_i,rd_en_i,output [7:0] rdata,output empty_o,almost_empty_o);
 reg [7:0] mem[0:4095];integer wp=0,rp=0;
 always @(posedge wr_clk_i or posedge a_rst_i)if(a_rst_i)wp<=0;else if(wr_en_i)begin
  for(integer b=0;b<16;b++)mem[wp+b]<=wdata[(15-b)*8+:8];wp<=wp+16;end
 always @(posedge rd_clk_i or posedge a_rst_i)if(a_rst_i)rp<=0;else if(rd_en_i)rp<=rp+1;
 assign rdata=mem[rp];assign empty_o=wp==rp;assign almost_empty_o=wp-rp<32;assign prog_full_o=wp-rp>2048;
endmodule
module axi4_background_tb #(parameter PHOTO=1,ASYNC_VIDEO=0);
reg clk=0,reset=1,capture=0,wvs=0,we=0,rvs=0,re=0,freeze=0,background_read_enabled=1;
reg [31:0] wd=0;always #5 clk=~clk;
reg video_clock=0;always #7 video_clock=~video_clock;
wire pclk=ASYNC_VIDEO?video_clock:clk;
wire [31:0] awaddr,araddr;wire [7:0] awlen,arlen;wire awvalid,wvalid,wlast,arvalid,rready;
wire [127:0] wdata;wire bgvalid,bgbusy,bgerror,bgsample,bgfault;wire [7:0] bgdata,live;
reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
reg [1:0] bresp=0,rresp=0;reg [127:0] rdata=0;
reg [7:0] memory[0:8191];
integer clock_count=0,write_address=0,write_left=0,read_address=0,read_left=0,bg_reads=0,live_reads=0;
reg inject_write_error=0,inject_read_error=0;
axi4_ctrl #(.C_W_WIDTH(32),.C_R_WIDTH(8),.C_RD_END_ADDR(128),.C_BURST_LEN(4),.C_BUF_SIZE(8),
 .BACKGROUND_BUILD(1),.PHOTO_STREAM_BUILD(PHOTO),.C_BACKGROUND_BASE_ADDR(32'h1000)) dut(
 .axi_clk(clk),.axi_reset(reset),.axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
 .axi_wdata(wdata),.axi_wvalid(wvalid),.axi_wready(wready),.axi_wlast(wlast),.axi_bvalid(bvalid),.axi_bresp(bresp),
 .axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
 .axi_rdata(rdata),.axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rresp(rresp),.axi_rready(rready),
 .wframe_pclk(pclk),.wframe_vsync(wvs),.wframe_data_en(we),.wframe_data(wd),
 .rframe_pclk(pclk),.rframe_vsync(rvs),.rframe_data_en(re),.rframe_data(live),.freeze_i(freeze),
 .background_capture_i(capture),.background_read_enable_i(background_read_enabled),.background_valid(bgvalid),
 .background_capture_busy(bgbusy),.background_error(bgerror),.background_rframe_data(bgdata),
 .background_rframe_valid(bgsample),.background_stream_fault(bgfault),
 .photo_write_valid_i(0),.photo_load_start_i(0),.photo_load_end_i(0),.photo_read_enable_i(0),
 .photo_rframe_pclk(pclk),.photo_rframe_vsync(rvs),.photo_rframe_data_en(0));
always @(posedge clk)begin
 if(reset)begin awready<=0;wready<=0;bvalid<=0;arready<=0;rvalid<=0;clock_count<=0;end
 else begin
  clock_count<=clock_count+1;
  awready<=write_left==0&&!bvalid&&clock_count%3!=0;
  wready<=write_left!=0&&clock_count%4!=0;
  arready<=read_left==0&&!rvalid&&clock_count%3!=0;
  if(awvalid&&awready)begin write_address=awaddr;write_left=awlen+1;awready<=0;end
  if(wvalid&&wready)begin
   if(wlast!==(write_left==1))$fatal(1,"WLAST mismatch");
   for(integer b=0;b<16;b++)memory[write_address+b]<=wdata[b*8+:8];
   write_address=write_address+16;write_left=write_left-1;
   if(write_left==0)begin bvalid<=1;bresp<=inject_write_error&&write_address>=4096?2:0;wready<=0;end
  end
  if(bvalid)bvalid<=0;
  if(arvalid&&arready)begin
   read_address=araddr;read_left=arlen+1;arready<=0;
   if(araddr>=4096)bg_reads++;else live_reads++;
  end
  if(rvalid&&rready)begin rvalid<=0;read_address=read_address+16;read_left=read_left-1;end
  if(!rvalid&&read_left>0&&clock_count%4!=0)begin
   for(integer b=0;b<16;b++)rdata[b*8+:8]<=memory[read_address+b];
   rvalid<=1;rlast<=read_left==1;rresp<=inject_read_error&&read_address>=4096?2:0;
  end
 end
end
task automatic camera_frame(input integer value,words);
 begin
 @(negedge pclk);wvs=1;we=0;@(negedge pclk);
 for(integer i=0;i<words;i++)begin we=1;wd={4{8'(value)}};@(negedge pclk);end
 we=0;wvs=0;repeat(180)@(negedge pclk);
 end
endtask
task automatic request_background;
 begin @(negedge pclk);capture=1;@(negedge pclk);capture=0;end
endtask
task automatic read_frame(input integer expected,input bit fault_expected,input bit enable_during_blank=0);
 begin
 @(negedge pclk);rvs=1;repeat(4)@(negedge pclk);rvs=0;repeat(10)@(negedge pclk);
 if(enable_during_blank)background_read_enabled=1;
 repeat(40)@(negedge pclk);rvs=1;repeat(100)@(negedge pclk);
 for(integer i=0;i<128;i++)begin
  re=1;#1;
  if(!background_read_enabled&&bgsample!==0)$fatal(1,"disabled white-mode background reader emitted a sample");
  if(background_read_enabled&&!fault_expected&&(bgsample!==1||bgdata!==8'(expected)))$fatal(1,"paired background byte %0d got=%h valid=%b expected=%h",i,bgdata,bgsample,8'(expected));
  @(negedge pclk);
 end
 re=0;
 if(fault_expected&&!bgfault)$fatal(1,"bad RRESP not rejected");
 rvs=0;repeat(50)@(negedge pclk);
 end
endtask
integer reads_before_disable,live_before_disable;
initial begin
 repeat(8)@(negedge clk);reset=0;repeat(50)@(negedge clk);
 camera_frame(10,32);request_background();camera_frame(20,32);
 if(!dut.background_active||!bgbusy||bgvalid)$fatal(1,"capture did not start on complete boundary");
 camera_frame(60,32);
 if(!bgvalid||bgbusy||bgerror)$fatal(1,"background commit failed");
 for(integer i=0;i<128;i++)if(memory[4096+i]!=60)$fatal(1,"background frame torn");
 // The redirected background frame must never publish an unwritten live slot.
 if(dut.rc_wframe_index!=2||dut.r_wframe_index_last!=1)$fatal(1,"background capture advanced live ring");
 freeze=1;camera_frame(90,32);read_frame(60,0);
 if(bg_reads==0||live_reads==0)$fatal(1,"read scheduling starved a client");
 background_read_enabled=0;reads_before_disable=bg_reads;live_before_disable=live_reads;
 repeat(2)read_frame(60,0);
 if(bg_reads!=reads_before_disable||live_reads<=live_before_disable||!bgvalid||bgfault)
  $fatal(1,"white mode failed to stop background traffic while preserving live reads and stored reference");
 read_frame(60,0,1); // The mode can change after the falling VS edge.
 inject_read_error=1;read_frame(60,1);if(!bgerror)$fatal(1,"RRESP diagnostic not latched");inject_read_error=0;read_frame(60,0);
 request_background();camera_frame(100,32);camera_frame(120,16);
 if(bgvalid||bgbusy||!bgerror)$fatal(1,"partial camera frame became background");
 request_background();camera_frame(100,32);inject_write_error=1;camera_frame(130,32);inject_write_error=0;
 if(bgvalid||bgbusy||!bgerror)$fatal(1,"bad BRESP became background");
 request_background();camera_frame(100,32);camera_frame(140,32);read_frame(140,0);
 $display("PASS AXI background async-video=%0d: complete RAW capture, independent slot, live-ring preservation, backpressure, paired reads, white-mode reader stop/resume within blank, freeze, partial frame/BRESP/RRESP rejection and retry",ASYNC_VIDEO);$finish;
end
initial begin #2000000;$fatal(1,"background AXI timeout");end
endmodule
