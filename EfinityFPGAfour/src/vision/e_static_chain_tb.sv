`timescale 1ns/1ps
// Integrate E capture with the real gallery byte packer, video AXI controller,
// width-converting FIFO models and a byte DDR memory. Pixel/AXI clocks differ.
module e_static_chain_tb #(parameter BURST=4); localparam TOLERANCE=1;
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
wire cvs,chs,cde; wire [7:0] cedge; reg [7:0] gray=0; wire ready,busy,error,start,finish,byte_valid,request,ov,oh,oe,original,foreground,reference_valid,fault;
wire [7:0] byte_data,read_byte;wire [19:0] offset;
wire writer_busy,commit,writer_error,reader_error,read_valid;
wire background_bit,expanded_bit;wire [31:0] captured_crc;
edge_background_capture #(.WIDTH(64),.HEIGHT(32),.H_TOTAL(80),.TIMEOUT(100000),.TOLERANCE_AVAILABLE(TOLERANCE)) cap(
 .clk(clk),.rst_n(!reset),.pclk(pclk),.prst_n(prst),.capture_req(capture),
 .in_vsync(cvs),.in_hsync(chs),.in_href(cde),.in_edge(cedge!=0),.config_signature(65'd0),
 .tolerance_enable(tolerance_enable),
 .ready(ready),.busy(busy),.error(error),.writer_start(start),.writer_end(finish),
 .writer_byte_valid(byte_valid),.writer_byte(byte_data),.writer_offset(offset),
 .writer_busy(writer_busy),.writer_commit(commit),.writer_error(writer_error),.reader_error(reader_error),
 .reader_request(request),.reader_byte(read_byte),.reader_valid(read_valid),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_edge(original),.out_foreground(foreground),
 .reference_valid(reference_valid),.frame_fault(fault),.captured_crc(captured_crc),
 .out_reference_edge(background_bit),.out_reference_expanded(expanded_bit));
axi4_ctrl #(.C_W_WIDTH(32),.C_R_WIDTH(8),.C_RD_END_ADDR(128),.C_BURST_LEN(BURST),.C_BUF_SIZE(8),
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
canny_edge #(.IMG_HDISP(64),.IMG_VDISP(32)) canny(
 .clk(pclk),.rst_n(prst),.per_frame_vsync(vs),.per_frame_hsync(hs),.per_frame_href(de),
 .per_img_gray(gray),.per_img_red(gray),.per_img_green(gray),.per_img_blue(gray),
 .low_threshold(11'd22),.high_threshold(11'd45),
 .post_frame_vsync(cvs),.post_frame_hsync(chs),.post_frame_href(cde),.post_img_edge(cedge));
reg canonical[0:2047];
reg ov_d=0;
integer output_frame=0,index=0,differences=0,foreground_pixels=0,edges=0;
always @(posedge pclk)begin
 #1;
 if(!prst)begin ov_d=0;index=0;output_frame=0;end
 else begin
  if(ov&&!ov_d)begin output_frame++;index=0;differences=0;foreground_pixels=0;edges=0;end
  if(oe)begin
   if(index>=2048)$fatal(1,"too many output pixels");
   if(output_frame==2)canonical[index]=original;
   if(output_frame>=3&&original!==canonical[index])differences++;
   if(original)edges++;
   if(foreground)foreground_pixels++;
   if(output_frame>=4&&(fault||foreground!==0))$fatal(1,"same frozen Canny image became foreground frame=%0d index=%0d fg=%b fault=%b",output_frame,index,foreground,fault);
   if(output_frame>=4&&background_bit!==canonical[index])$fatal(1,"read-back reference differs from static Canny at index=%0d",index);
   index++;
  end
  if(!ov&&ov_d)begin
   $display("STATIC frame=%0d pixels=%0d edges=%0d current_vs_canonical_diff=%0d foreground=%0d tolerance=%b",output_frame,index,edges,differences,foreground_pixels,tolerance_enable);
   if(index!=2048)$fatal(1,"wrong Canny output frame size");
   if(output_frame>=3&&differences)$fatal(1,"constant grayscale input produced different E frames");
  end
  ov_d=ov;
 end
end
function automatic [7:0] image(input integer x,y);
 image=8'((x*13+y*19+((x/9+y/7)%2)*151)%256);
endfunction
function automatic bit expanded(input integer x,y);
 begin
  expanded=0;
  for(integer dy=-1;dy<=1;dy++)for(integer dx=-1;dx<=1;dx++)
   if(x+dx>=0&&x+dx<64&&y+dy>=0&&y+dy<32)expanded|=canonical[(y+dy)*64+x+dx];
 end
endfunction
task static_frame;
 begin
  @(negedge pclk);vs=0;de=0;raw_read_vs=1;repeat(5*80)@(negedge pclk);
  raw_read_vs=0;vs=1;repeat(36*80)@(negedge pclk);
  for(integer y=0;y<32;y++)begin
   for(integer x=0;x<64;x++)begin de=1;gray=image(x,y);@(negedge pclk);end
   de=0;gray=0;repeat(16)@(negedge pclk);
  end
  repeat(4*80)@(negedge pclk);vs=0;de=0;repeat(5*80)@(negedge pclk);
 end
endtask
initial begin
 for(integer i=0;i<16384;i++)memory[i]=0;
 repeat(8)@(negedge clk);reset=0;prst=1;repeat(50)@(negedge clk);
 static_frame();static_frame();
 if(!edges)$fatal(1,"fixture has no Canny edges");
 @(negedge clk);capture=1;@(negedge clk);capture=0;static_frame();wait(!busy);
 if(!ready||error)$fatal(1,"static reference not ready");
 begin : check_capture_crc
  reg [31:0] crc;
  crc=32'hffffffff;
  for(integer i=0;i<2048;i++)crc=(crc<<1)^((crc[31]^canonical[i])?32'h04c11db7:32'd0);
  if(captured_crc!==~crc)$fatal(1,"captured E CRC mismatch");
 end
 for(integer y=0;y<32;y++)for(integer x=0;x<64;x++)
  if(memory[8192+y*16+x/4][7-2*(x%4)]!==canonical[y*64+x]||memory[8192+y*16+x/4][6-2*(x%4)]!==expanded(x,y))
   $fatal(1,"actual Canny reference pack/dilation mismatch x=%0d y=%0d",x,y);
 static_frame();static_frame();tolerance_enable=0;static_frame();static_frame();
 $display("PASS actual Canny and AXI with modeled FWFT FIFO: repeated frozen grayscale produces identical E frames, exact/3x3 DDR references match every pixel, both difference modes remain zero");$finish;
end
initial begin #10000000;$fatal(1,"static Canny chain timeout");end
endmodule
