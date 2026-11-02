`timescale 1ns/1ps
// Real full-size sampler/DMA with the same pre-gray Gamma RGB tap as image 2.
// The synthesized TOP is checked separately by check-image-netlist.ps1.
module photo_capture_full_hd_tb;
localparam IW=1920,IH=1080,W=960,H=540,ROW_BYTES=W*2,WORDS=W*H/8;
reg clk=0,pclk=0,rst_n=0,vs=0,de=0,hs=0,start=0,request=0,gray_mode=0;
reg [7:0] red=0,green=0,blue=8'ha0;
always #5.208 clk=~clk;
always #3.360 pclk=~pclk;
wire gvs,gde,ghs;wire [7:0] gr,gg,gb;
gamma_correction gamma(.clk(pclk),.rst_n(rst_n),.gamma_enable(1'b0),.gamma_strength(9'd42),
 .per_frame_vsync(vs),.per_frame_href(de),.per_frame_hsync(hs),
 .per_img_red(red),.per_img_green(green),.per_img_blue(blue),
 .post_frame_vsync(gvs),.post_frame_href(gde),.post_frame_hsync(ghs),
 .post_img_red(gr),.post_img_green(gg),.post_img_blue(gb));
// Display mode changes do not feed the capture input.
grey display_gray(.clk(pclk),.rst_n(rst_n),.gray_en(gray_mode),
 .per_frame_vsync(gvs),.per_frame_href(gde),.per_frame_hsync(ghs),
 .per_img_red(gr),.per_img_green(gg),.per_img_blue(gb));
reg req1=0,req2=0;
always @(posedge pclk)begin req1<=request;req2<=req1;end
wire active,finished,valid;wire [15:0] pixel;
photo_capture_2x_rgb565 sampler(.clk(pclk),.rst_n(rst_n),.capture_toggle(req2),
 .in_vsync(gvs),.in_href(gde),.in_red(gr),.in_green(gg),.in_blue(gb),
 .capture_active(active),.capture_done_toggle(finished),.pixel_valid(valid),.pixel_rgb565(pixel));
wire busy,done,error,av,wv,wl;wire [31:0] addr;wire [7:0] len;wire [127:0] data;
reg bvalid=0;integer outstanding=0,beat=0,bdelay=0,cycles=0,writes=0,bursts=0;
reg [31:0] burst_addr=0;
reg ardy=0,wrdy=0;
// Slave READY is stable before the DUT's rising edge, avoiding TB/DUT races.
always @(negedge clk)begin
 ardy=rst_n && outstanding==0 && !bvalid && bdelay==0 && cycles%257<128;
 wrdy=rst_n && outstanding>0 && cycles%7!=0;
end
photo_ddr_dma dma(.clk(clk),.rst_n(rst_n),.pclk(pclk),.prst_n(rst_n),.start(start),.buffer_select(1'b0),
 .busy(busy),.done(done),.error(error),.pixel_valid(valid),.pixel_data(pixel),
 .pixel_active(active),.pixel_done_toggle(finished),.read_start(1'b0),.read_buffer(1'b0),.read_offset(20'd0),
 .awaddr(addr),.awlen(len),.awvalid(av),.awready(ardy),.wdata(data),.wlast(wl),.wvalid(wv),.wready(wrdy),
 .bvalid(bvalid),.bresp(2'd0),.arready(1'b0),.rdata(128'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0));
function automatic [15:0] expected(input integer offset,input integer lane);
 integer sx,sy;reg [7:0] rr,gv;
 begin sx=2*((offset%ROW_BYTES)/2+lane);sy=2*(H-1-offset/ROW_BYTES);
 rr=sx;gv=sy;expected={rr[7:3],gv[7:2],5'b10100};end
endfunction
integer offset;
always @(posedge clk)begin
 if(rst_n)begin
  cycles=cycles+1;
  if(error)$fatal(1,"Capture DMA error, overflow=%0d count=%0d written=%0d",dma.o2,dma.n2,dma.words_written);
  if(bvalid)bvalid<=0;
  if(bdelay>0)begin bdelay=bdelay-1;if(bdelay==0)bvalid<=1;end
  if(av&&ardy)begin
   if(len!==7||addr!==32'h01600000+(H-1-bursts/15)*ROW_BYTES+(bursts%15)*128)
    $fatal(1,"Bad bottom-up burst address/count: %08x burst=%0d",addr,bursts);
   burst_addr=addr;outstanding=8;beat=0;bursts=bursts+1;
  end
  if(wv&&wrdy)begin
   if(wl!==(outstanding==1))$fatal(1,"WLAST mismatch");
   offset=burst_addr-32'h01600000+beat*16;
   for(integer lane=0;lane<8;lane=lane+1)
    if(data[lane*16+:16]!==expected(offset,lane))$fatal(1,"RGB565 mismatch offset=%0d lane=%0d",offset,lane);
   outstanding=outstanding-1;beat=beat+1;writes=writes+1;
   if(outstanding==0)bdelay=4;
  end
 end
end
task automatic frame;
 begin
  vs=0;de=0;repeat(5*2200)@(negedge pclk);
  vs=1;repeat(36*2200)@(negedge pclk);
  for(integer y=0;y<IH;y=y+1)begin
   gray_mode=y[0];
   for(integer x=0;x<IW;x=x+1)begin de=1;red=x;green=y;@(negedge pclk);end
   de=0;repeat(280)@(negedge pclk);
  end
  repeat(4*2200)@(negedge pclk);
 end
endtask
initial begin
 repeat(10)@(negedge clk);rst_n=1;
 @(negedge clk);start=1;request=1;@(negedge clk);start=0;
 fork
  begin frame();frame();end
  begin wait(done);#1;
   if(writes!=WORDS||bursts!=WORDS/8||dma.n2!=W*H||busy||bvalid||bdelay)
    $fatal(1,"Incomplete full-size photo writes=%0d bursts=%0d pixels=%0d",writes,bursts,dma.n2);
   $display("PASS 1080p Gamma colour -> 960x540 sampler -> 64800 DDR words / 8100 bursts, exact RGB565 and frame completion at 148.8/96MHz; gray display independent");
   $finish;
  end
 join
end
initial begin #100000000;$fatal(1,"Full-HD timeout active=%0d source_finished=%0d ws=%0d",active,dma.source_finished,dma.ws);end
endmodule
