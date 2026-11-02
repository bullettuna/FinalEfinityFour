`timescale 1ns/1ps
// Integrate E capture with the real gallery byte packer, video AXI controller,
// width-converting FIFO models and a byte DDR memory. Pixel/AXI clocks differ.
module axi4_edge_background_tb #(parameter TOLERANCE=0);
reg clk=0,pclk=0,reset=1,prst=0,capture=0,wvs=0,we=0,vs=0,hs=0,de=0,edge_bit=0,raw_capture=0,raw_read_vs=1;
reg [31:0] wd=0;always #5 clk=~clk;always #3 pclk=~pclk;
wire [31:0] awaddr,araddr;wire [7:0] awlen,arlen;wire awvalid,wvalid,wlast,arvalid,rready;
wire [127:0] wdata;wire bgvalid,bgbusy,bgerror;
reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
reg [1:0] bresp=0,rresp=0;reg [127:0] rdata=0;
reg [7:0] memory[0:16383];
integer cycle=0,wa=0,wl=0,ra=0,rl=0;
reg inject_write_error=0,inject_read_error=0;
reg tolerance_enable=TOLERANCE;
wire ready,busy,error,start,finish,byte_valid,request,ov,oh,oe,original,foreground,reference_valid,fault;
wire [7:0] byte_data,read_byte;wire [19:0] offset;
wire writer_busy,commit,writer_error,reader_error,read_valid;
edge_background_capture #(.WIDTH(64),.HEIGHT(32),.H_TOTAL(80),.TIMEOUT(100000),.TOLERANCE_AVAILABLE(TOLERANCE)) cap(
 .clk(clk),.rst_n(!reset),.pclk(pclk),.prst_n(prst),.capture_req(capture),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_edge(edge_bit),.config_signature(65'd0),
 .tolerance_enable(tolerance_enable),
 .ready(ready),.busy(busy),.error(error),.writer_start(start),.writer_end(finish),
 .writer_byte_valid(byte_valid),.writer_byte(byte_data),.writer_offset(offset),
 .writer_busy(writer_busy),.writer_commit(commit),.writer_error(writer_error),.reader_error(reader_error),
 .reader_request(request),.reader_byte(read_byte),.reader_valid(read_valid),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_edge(original),.out_foreground(foreground),
 .reference_valid(reference_valid),.frame_fault(fault));
axi4_ctrl #(.C_W_WIDTH(32),.C_R_WIDTH(8),.C_RD_END_ADDR(128),.C_BURST_LEN(4),.C_BUF_SIZE(8),
 .BACKGROUND_BUILD(1),.C_BACKGROUND_BASE_ADDR(32'h1000),.C_PHOTO0_BASE_ADDR(32'h2000),.C_PHOTO_BYTES(TOLERANCE?512:256)) video(
 .axi_clk(clk),.axi_reset(reset),.axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
 .axi_wdata(wdata),.axi_wvalid(wvalid),.axi_wready(wready),.axi_wlast(wlast),.axi_bvalid(bvalid),.axi_bresp(bresp),
 .axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
 .axi_rdata(rdata),.axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rresp(rresp),.axi_rready(rready),
 .wframe_pclk(clk),.wframe_vsync(wvs),.wframe_data_en(we),.wframe_data(wd),
 .rframe_pclk(pclk),.rframe_vsync(raw_read_vs),.rframe_data_en(1'b0),.freeze_i(1'b0),
 .background_capture_i(raw_capture),.background_read_enable_i(1'b0),.background_valid(bgvalid),
 .background_capture_busy(bgbusy),.background_error(bgerror),
 .photo_write_valid_i(byte_valid),.photo_write_buffer_i(1'b0),.photo_write_offset_i(offset),.photo_write_data_i(byte_data),
 .photo_load_start_i(start),.photo_load_end_i(finish),.photo_write_busy_o(writer_busy),
 .photo_word_commit_o(commit),.photo_write_error_o(writer_error),
 .photo_read_enable_i(ready),.photo_read_buffer_i(1'b0),.photo_rframe_pclk(pclk),
 .photo_rframe_vsync(~ov),.photo_rframe_data_en(request),.photo_rframe_data(read_byte),.photo_rframe_valid(read_valid),
 .photo_read_error_o(reader_error));
always @(posedge clk)begin
 if(reset)begin awready<=0;wready<=0;bvalid<=0;arready<=0;rvalid<=0;cycle<=0;end
 else begin
  cycle<=cycle+1;awready<=wl==0&&!bvalid&&cycle%3!=0;wready<=wl!=0&&cycle%4!=0;arready<=rl==0&&!rvalid&&cycle%3!=0;
  if(awvalid&&awready)begin wa=awaddr;wl=awlen+1;awready<=0;end
  if(wvalid&&wready)begin
   if(wlast!==(wl==1))$fatal(1,"WLAST mismatch");
   for(integer b=0;b<16;b++)memory[wa+b]<=wdata[(15-b)*8+:8];
   wa=wa+16;wl--;
   if(wl==0)begin bvalid<=1;bresp<=inject_write_error&&wa>=8192?2:0;wready<=0;end
  end
  if(bvalid)bvalid<=0;
  if(arvalid&&arready)begin ra=araddr;rl=arlen+1;arready<=0;end
  if(rvalid&&rready)begin rvalid<=0;ra=ra+16;rl--;end
  if(!rvalid&&rl>0&&cycle%4!=0)begin
   for(integer b=0;b<16;b++)rdata[(15-b)*8+:8]<=memory[ra+b];
   rvalid<=1;rlast<=rl==1;rresp<=inject_read_error&&ra>=8192?2:0;
  end
 end
end
function automatic bit a(input integer x,y);a=x==8||(y==4&&x>=8&&x<=18);endfunction
function automatic bit expanded_a(input integer x,y);
 begin
  expanded_a=0;
  for(integer dy=-1;dy<=1;dy++)for(integer dx=-1;dx<=1;dx++)
   if(x+dx>=0&&x+dx<64&&y+dy>=0&&y+dy<32)expanded_a|=a(x+dx,y+dy);
 end
endfunction
function automatic bit b(input integer x,y);b=(a(x,y)&&y<16)||((x==32||x==47)&&y>=8&&y<28)||((y==8||y==27)&&x>=32&&x<=47);endfunction
task camera_frame(input integer value);
 begin @(negedge clk);wvs=1;we=0;@(negedge clk);for(integer i=0;i<32;i++)begin we=1;wd={4{8'(value)}};@(negedge clk);end
 we=0;wvs=0;repeat(180)@(negedge clk);end
endtask
task frame(input bit current_b,check);
 begin
 @(negedge pclk);vs=0;de=0;raw_read_vs=1;repeat(5*80-20)@(negedge pclk);
 raw_read_vs=0;repeat(20)@(negedge pclk);vs=1;repeat(36*80)@(negedge pclk);
 for(integer y=0;y<32;y++)begin
  for(integer x=0;x<64;x++)begin
   de=1;edge_bit=current_b?b(x,y):a(x,y);@(posedge pclk);#1;
   if(check&&(foreground!==(b(x,y)&&!(tolerance_enable?expanded_a(x,y):a(x,y)))||fault))$fatal(1,"DDR E foreground mismatch x=%0d y=%0d got=%b fault=%b",x,y,foreground,fault);
   @(negedge pclk);
  end
  de=0;repeat(16)@(negedge pclk);
 end
 repeat(4*80)@(negedge pclk);vs=0;de=0;repeat(5*80)@(negedge pclk);
 end
endtask
task capture_edges;
 begin @(negedge clk);capture=1;@(negedge clk);capture=0;frame(0,0);wait(!busy);@(negedge clk);end
endtask
reg [1:0] saved_ring;
initial begin
 for(integer i=0;i<16384;i++)memory[i]=0;
 repeat(8)@(negedge clk);reset=0;prst=1;repeat(50)@(negedge clk);
 camera_frame(10);raw_capture=1;@(negedge clk);raw_capture=0;camera_frame(11);camera_frame(42);
 if(!bgvalid||bgerror)$fatal(1,"RAW reference not captured");saved_ring=video.rc_wframe_index;
 capture_edges();if(!ready||error)$fatal(1,"DDR E capture failed ready=%b error=%b commits=%0d pixel_failed=%b failed=%b end=%b offset=%0d pack_failed=%b packed=%0d",ready,error,cap.commits,cap.pixel_failed,cap.failed,cap.end_seen,cap.offset,video.g_photo_writer.u_gallery_word_fifo.failed,video.g_photo_writer.u_gallery_word_fifo.packed_count);
 for(integer y=0;y<32;y++)for(integer x=0;x<64;x++)begin
  if(TOLERANCE)begin
   if(memory[8192+y*16+x/4][7-2*(x%4)]!==a(x,y)||memory[8192+y*16+x/4][6-2*(x%4)]!==expanded_a(x,y))$fatal(1,"DDR paired reference mismatch x=%0d y=%0d",x,y);
  end else if(memory[8192+y*8+x/8][7-x%8]!==a(x,y))$fatal(1,"DDR packed bit order mismatch");
 end
 for(integer i=0;i<128;i++)if(memory[4096+i]!=42)$fatal(1,"E capture overwrote RAW reference");
 if(video.rc_wframe_index!=saved_ring)$fatal(1,"E capture advanced camera ring");
 frame(1,1);frame(1,1);
 if(TOLERANCE)begin tolerance_enable=0;frame(1,1);tolerance_enable=1;frame(1,1);end
 inject_read_error=1;frame(1,0);repeat(20)@(negedge clk);if(ready||!error)$fatal(1,"DDR RRESP reference invalidation missing");inject_read_error=0;
 capture_edges();if(!ready||error)$fatal(1,"DDR error recovery failed");frame(1,1);
 inject_write_error=1;capture_edges();if(ready||!error)$fatal(1,"BRESP failure published E reference");inject_write_error=0;
 capture_edges();if(!ready||error)$fatal(1,"BRESP recovery failed");frame(1,1);
 $display("PASS real AXI dual backgrounds tolerance=%0d: asynchronous E pack/gallery FIFO/BRESP/DDR/byte read, exact and paired 3x3 reference, RAW reference and live ring preserved, AR/W backpressure and BRESP/RRESP recovery",TOLERANCE);$finish;
end
initial begin #10000000;$fatal(1,"E DDR timeout");end
endmodule
