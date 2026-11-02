`timescale 1ns/1ps
// Behavioral FIFO primitives for the REAL axi4_ctrl read scheduler. Only the
// DDR slave and physical FIFO primitives are modeled; both arbiters, video
// frame reset logic, photo capture/DMA, SD protocol and FAT writer are real RTL.
module W0_FIFO_32(input wr_clk_i,input wr_en_i,input [31:0] wdata,input a_rst_i,
 input rd_clk_i,input rd_en_i,output [127:0] rdata,output prog_empty_o,output empty_o);
 assign rdata=0;assign prog_empty_o=1;assign empty_o=1;
endmodule
module R0_FIFO_8(input wr_clk_i,input wr_en_i,input [127:0] wdata,input a_rst_i,
 output prog_full_o,input rd_clk_i,input rd_en_i,output [7:0] rdata,output empty_o,output almost_empty_o);
 reg [7:0] memory[0:4095];integer wp=0,rp=0;
 always @(posedge wr_clk_i or posedge a_rst_i)begin
  if(a_rst_i)wp=0;
  else if(wr_en_i)begin
   for(integer k=0;k<16;k=k+1)memory[(wp+k)%4096]=wdata[127-k*8 -:8];wp=wp+16;
  end
 end
 always @(posedge rd_clk_i or posedge a_rst_i)begin
  if(a_rst_i)rp=0;else if(rd_en_i&&wp!=rp)rp=rp+1;
 end
 assign prog_full_o=wp-rp>=3800;assign empty_o=wp==rp;assign almost_empty_o=wp-rp<256;
 assign rdata=memory[rp%4096];
endmodule

module photo_video_save_tb #(parameter GALLERY_TESTS=0, DELETE_TESTS=0,PROCESS_TESTS=0);
 reg clk=0,rst_n=0,b=0,q=0,vs=0,de=0,manual_vsync=0,block_read=0,del=0;
 integer confirm_count=0,delete_count=0,cancel_count=0,delete_fail_count=0,empty_count=0,fault_count=0,delete_busy_count=0;
 reg reject_card_write=0;
 string last_delete="";
 reg [7:0] red=0,green=0,blue=0;
 always #5 clk=~clk;
 integer cycles=0,visible=0,video_transactions=0,photo_transactions=0;
 reg check_display=0;
 wire vvs;
 localparam GALLERY_PERIOD=PROCESS_TESTS?8192:3200;
 localparam GALLERY_BLANK=PROCESS_TESTS?1024:180;
 wire vde=cycles%(PROCESS_TESTS?GALLERY_PERIOD:700)>=(PROCESS_TESTS?GALLERY_BLANK:180) &&
  cycles%(PROCESS_TESTS?GALLERY_PERIOD:700)<(PROCESS_TESTS?GALLERY_BLANK+400:580) && !manual_vsync;
 wire [7:0] video_byte;
 wire [31:0] va,vr,pa,pr,ma,mr;wire [7:0] val,vrl,pal,prl,mal,mrl;
 wire vav,vwv,vwl,vrv,vrr,vard,pav,pwv,pwl,prv,prr,pard;
 wire vawready,vwready,vbvalid,varready,vrvalid,vrlast;
 wire pawready,pwready,pbvalid,parready,prvalid,prlast;
 wire [127:0] vwd,vrd,pwd,prd,mwd,mrd;wire [15:0] vst,mst;
 wire [1:0] vbresp,vrresp,pbresp,prresp;
 wire m_av,m_awready,m_wv,m_wlast,m_wready,m_bvalid,m_bready,m_arv,m_arready,m_rv,m_rlast,m_rready;
 wire [1:0] m_bresp,m_rresp;
 wire vflush,vurgent,m_stalled;wire [3:0] m_debug;
 wire sdclk,cmdo,cmdoe,cmdi;wire [3:0] dato,datoe,dati;
 wire txvalid,txlast;wire [7:0] txdata;reg txaccept=0,txdone=0;
 reg gx=0,gprev=0,gnext=0,gtoggle=0,gvold=0,gactive=0;
 reg corrupt_gallery_read=0,fail_gallery_write=0;
 wire gmode,gbusy,gerror,gs,gbv,gd,ge;wire [7:0] gbyte;wire [19:0] goffset;wire [31:0] gnumber;
 wire stagebusy,stagefailed,stageabort,stageready,pwvbyte,pbuf,genable,displaybuf;
 wire [19:0] pwo;wire [7:0] pwbyte;
 wire writerbusy,wordcommit,writeerror,gstreamreset,gbytevalid,gbyteready;
 wire [7:0] gstreambyte,gr,gg,gb;wire frameerror,goutde;
 wire gvs=cycles%GALLERY_PERIOD<8;
 // Actual image2 uses the SAME LCD frame boundary for RAW and gallery FIFOs.
 // Keep enough blanking to prefill both FIFOs, as in the real 1080p timing.
 assign vvs=PROCESS_TESTS?~gvs:(GALLERY_TESTS&&gmode)?~gvs:(cycles%700<3 || manual_vsync);
 wire gde=cycles%GALLERY_PERIOD>=GALLERY_BLANK && cycles%GALLERY_PERIOD<GALLERY_BLANK+16*144 &&
  (cycles%GALLERY_PERIOD-GALLERY_BLANK)%144<128;
 always @(posedge clk)begin
  gvold<=gvs;
  if(!rst_n)begin gtoggle<=0;gactive<=0;end
  else begin if(gvs&&!gvold)gtoggle<=!gtoggle;if(gvs)gactive<=genable;end
 end
 photo_ddr_stage #(.PHOTO_BYTES(1024)) stage(.clk(clk),.rst_n(rst_n),
  .load_start(gs),.load_byte_valid(gbv),.load_byte(gbyte),.load_byte_offset(goffset),.load_done(gd),.load_error(ge),
  .gallery_mode(gmode),.display_vsync_toggle(gtoggle),.word_commit(wordcommit),.writer_busy(writerbusy),.write_error(writeerror),
  .load_busy(stagebusy),.load_failed(stagefailed),.load_abort(stageabort),.load_ready(stageready),
  .photo_write_valid(pwvbyte),.photo_write_buffer(pbuf),.photo_write_offset(pwo),.photo_write_data(pwbyte),
  .gallery_display_enable(genable),.display_buffer(displaybuf));
 photo_display_stream #(.DISPLAY_WIDTH(128),.DISPLAY_HEIGHT(16)) display(
  .clk(clk),.rst_n(rst_n),.gallery_enable(gactive),.photo_stream_reset(gstreamreset),
  .in_vsync(gvs),.in_hsync(1'b0),.in_href(gde),.photo_byte_valid(gbytevalid),.photo_byte(gstreambyte),.photo_byte_ready(gbyteready),
  .out_href(goutde),.out_red(gr),.out_green(gg),.out_blue(gb),.frame_error(frameerror));
 axi4_ctrl #(.C_W_WIDTH(32),.C_R_WIDTH(8),.C_BURST_LEN(8),.C_RD_END_ADDR(1024),.C_PHOTO_BYTES(1024)) video(
  .axi_clk(clk),.axi_reset(!rst_n),.axi_awaddr(va),.axi_awlen(val),.axi_awvalid(vav),.axi_awready(vawready),
  .axi_wdata(vwd),.axi_wstrb(vst),.axi_wlast(vwl),.axi_wvalid(vwv),.axi_wready(vwready),
  .axi_bid(8'd0),.axi_bresp(vbresp),.axi_bvalid(vbvalid),.axi_bready(),
  .axi_araddr(vr),.axi_arlen(vrl),.axi_arvalid(vard),.axi_arready(varready),
  .axi_rid(8'd0),.axi_rdata(vrd),.axi_rresp(vrresp),.axi_rlast(vrlast),.axi_rvalid(vrvalid),.axi_rready(vrr),
  .read_frame_flush(vflush),.read_urgent(vurgent),
  .wframe_pclk(clk),.wframe_vsync(1'b0),.wframe_data_en(1'b0),.wframe_data(32'd0),
  .rframe_pclk(clk),.rframe_vsync(vvs),.rframe_data_en(vde),.rframe_data(video_byte),
  .freeze_i(1'b0),
  .photo_write_valid_i(pwvbyte),.photo_write_buffer_i(pbuf),.photo_write_offset_i(pwo),.photo_write_data_i(pwbyte),
  .photo_load_start_i(gs),.photo_load_end_i(gd||ge||stagefailed||!gmode),
  .photo_write_busy_o(writerbusy),.photo_word_commit_o(wordcommit),.photo_write_error_o(writeerror),
  .photo_read_enable_i(genable),.photo_read_buffer_i(displaybuf),.photo_rframe_pclk(clk),.photo_rframe_vsync(~gvs),
  .photo_rframe_data_en(gbyteready),.photo_rframe_data(gstreambyte),.photo_rframe_valid(gbytevalid),.photo_stream_reset_o(gstreamreset));
 photo_native_pipeline #(.WIDTH(64),.HEIGHT(8),.ENABLE_DELETE(DELETE_TESTS),.DELETE_CONFIRM_CYCLES(50000),.ENABLE_PROCESSING(PROCESS_TESTS)) photo(
  .clk(clk),.rst_n(rst_n),.pclk(clk),.prst_n(rst_n),.capture_req(b),.query_req(q),.delete_req(del),.capture_accepted(),
  .capture_mode(2'd2),.median_enable(1'b1),.cleanup_level(2'd1),.min_pixels(11'd20),.high_threshold(11'd20),.low_threshold(11'd10),
  .axi_read_stalled(m_stalled),.axi_read_debug(m_debug),
  .gallery_ddr_busy(stagebusy||writerbusy),.gallery_ddr_failed(stagefailed),.gallery_abort(stageabort),.gallery_ready(stageready),
  .gallery_display_error(frameerror),
  .in_vsync(vs),.in_href(de),.red(red),.green(green),.blue(blue),
  .gallery_toggle_req(gx),.gallery_prev_req(gprev),.gallery_next_req(gnext),
  .gallery_mode(gmode),.gallery_busy(gbusy),.gallery_error(gerror),.gallery_file_number(gnumber),
  .gallery_load_start(gs),.gallery_load_byte_valid(gbv),.gallery_load_byte(gbyte),.gallery_load_byte_offset(goffset),.gallery_load_done(gd),.gallery_load_error(ge),
  .tx_valid(txvalid),.tx_data(txdata),.tx_last(txlast),.tx_accept(txaccept),.tx_done(txdone),
  .sd_clk(sdclk),.sd_cmd_o(cmdo),.sd_cmd_oe(cmdoe),.sd_cmd_i(cmdi),.sd_dat_i(dati),.sd_dat_o(dato),.sd_dat_oe(datoe),
  .awaddr(pa),.awlen(pal),.awvalid(pav),.awready(pawready),.wdata(pwd),.wlast(pwl),.wvalid(pwv),.wready(pwready),.bvalid(pbvalid),.bresp(pbresp),
  .araddr(pr),.arlen(prl),.arvalid(pard),.arready(parready),.rdata(prd),.rresp(prresp),.rlast(prlast),.rvalid(prvalid),.rready(prr));
 defparam photo.host.POWER_CYCLES=16;
 defparam photo.host.INIT_DIV=4;
 defparam photo.host.FAST_DIV=4;
 sd4_card_model_tb #(.SDSC(1),.LEGACY_CMD8(1),.BOOT_NOISE(GALLERY_TESTS)) card(sdclk,cmdo,cmdoe,cmdi,dato,datoe,dati,reject_card_write,corrupt_gallery_read);
 photo_axi_mux mux(.clk(clk),.rst_n(rst_n),.v_read_flush(vflush),.v_read_urgent(vurgent),.read_stalled(m_stalled),.read_debug(m_debug),
  .v_awaddr(va),.v_awlen(val),.v_awvalid(vav),.v_awready(vawready),.v_wdata(vwd),.v_wstrb(vst),.v_wlast(vwl),.v_wvalid(vwv),.v_wready(vwready),.v_bvalid(vbvalid),.v_bresp(vbresp),
  .v_araddr(vr),.v_arlen(vrl),.v_arvalid(vard),.v_arready(varready),.v_rdata(vrd),.v_rresp(vrresp),.v_rlast(vrlast),.v_rvalid(vrvalid),.v_rready(vrr),
  .p_awaddr(pa),.p_awlen(pal),.p_awvalid(pav),.p_awready(pawready),.p_wdata(pwd),.p_wlast(pwl),.p_wvalid(pwv),.p_wready(pwready),.p_bvalid(pbvalid),.p_bresp(pbresp),
  .p_araddr(pr),.p_arlen(prl),.p_arvalid(pard),.p_arready(parready),.p_rdata(prd),.p_rresp(prresp),.p_rlast(prlast),.p_rvalid(prvalid),.p_rready(prr),
  .m_awaddr(ma),.m_awlen(mal),.m_awvalid(m_av),.m_awready(m_awready),.m_wdata(mwd),.m_wstrb(mst),.m_wlast(m_wlast),.m_wvalid(m_wv),.m_wready(m_wready),
  .m_bvalid(m_bvalid),.m_bresp(m_bresp),.m_bready(m_bready),
  .m_araddr(mr),.m_arlen(mrl),.m_arvalid(m_arv),.m_arready(m_arready),.m_rdata(mrd),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rvalid(m_rv),.m_rready(m_rready));
 wire [31:0] native_addr;wire [7:0] native_len;wire native_type,native_valid,native_ready;
 AXI4_AWARMux bridge(.aclk_i(clk),.arst_i(!rst_n),
  .awid_i(8'd0),.awaddr_i(ma),.awlen_i(mal),.awvalid_i(m_av),.awready_o(m_awready),
  .arid_i(8'd0),.araddr_i(mr),.arlen_i(mrl),.arvalid_i(m_arv),.arready_o(m_arready),
  .aid_o(),.aaddr_o(native_addr),.alen_o(native_len),.atype_o(native_type),.avalid_o(native_valid),.aready_i(native_ready));
 reg [127:0] ram[0:383];integer wl=0,rl=0,wa=0,ra=0,bdelay=0,rdelay=0;
 reg [127:0] gallery_ram[0:127];reg reading_gallery=0,writing_gallery=0;
 reg bvalid=0,rvalid=0,rlast=0;reg [127:0] rdata=0;reg reading_photo=0;
 assign native_ready=rst_n&&cycles%5!=0&&(native_type?(wl==0&&bdelay==0&&!bvalid):(!block_read&&rl==0&&!rvalid));
 assign m_wready=wl>0&&cycles%3!=0;assign m_bvalid=bvalid;assign m_bresp=(writing_gallery&&fail_gallery_write)?2:0;
 assign m_rv=rvalid;assign m_rlast=rlast;assign mrd=rdata;assign m_rresp=0;
 function integer photo_index(input [31:0] a);
  if(PROCESS_TESTS&&a>=32'h01800000&&a<32'h01800400)photo_index=128+(a-32'h01800000)/16;
  else if(PROCESS_TESTS&&a>=32'h01900000&&a<32'h01900400)photo_index=192+(a-32'h01900000)/16;
  else if(PROCESS_TESTS&&a>=32'h01a00000&&a<32'h01a00800)photo_index=256+(a-32'h01a00000)/16;
  else photo_index={a[20],a[9:4]};
 endfunction
 reg pending_addr=0;reg [31:0] held_addr;reg [7:0] held_len;reg held_type;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(native_valid&&!native_ready)begin
   if(pending_addr&&(native_addr!==held_addr||native_len!==held_len||native_type!==held_type))
    $fatal(1,"DDR descriptor changed while VALID stalled across frame reset");
   pending_addr=1;held_addr=native_addr;held_len=native_len;held_type=native_type;
  end else pending_addr=0;
  if(native_valid&&native_ready)begin
   if(native_type)begin writing_gallery=native_addr<32'h01600000;wa=photo_index(native_addr);wl=native_len+1;end
   else begin
    reading_photo=native_addr>=32'h01600000;ra=photo_index(native_addr);rl=native_len+1;rdelay=12;
    reading_gallery=native_addr>=32'h01400000&&!reading_photo;
    if(reading_photo)begin
     if(native_len!=7&&!(PROCESS_TESTS&&native_len==0))$fatal(1,"unexpected photo burst");photo_transactions=photo_transactions+1;
    end else video_transactions=video_transactions+1;
   end
  end
  if(m_wv&&m_wready)begin if(writing_gallery)gallery_ram[wa]<=mwd;else ram[wa]<=mwd;wa=wa+1;wl=wl-1;
   if(m_wlast!=(wl==0))$fatal(1,"bad write last");if(wl==0)bdelay=10;end
  if(bvalid&&m_bready)bvalid<=0;
  if(bdelay>0)begin bdelay=bdelay-1;if(bdelay==0)bvalid<=1;end
  if(rvalid&&m_rready)begin rvalid<=0;rl=rl-1;ra=ra+1;end
  if(rdelay>0)rdelay=rdelay-1;
  else if(!rvalid&&rl>0)begin rvalid<=1;rlast<=rl==1;rdata<=reading_photo?ram[ra]:(reading_gallery?gallery_ram[ra]:{16{8'h5a}});end
  if(check_display&&vde)begin
   if(video_byte!==8'h5a)$fatal(1,"HDMI underflow cycle=%0d data=%h photo_state=%0d gallery=%b/%b fifo=%0d/%0d fault=%b rd=%0d target=%0d",cycles,
    video_byte,photo.state,gmode,genable,video.Gen_RFIFO_8.u_R0_FIFO_8.wp,video.Gen_RFIFO_8.u_R0_FIFO_8.rp,
    video.r_read_frame_fault,video.rd_state,video.r_rd_target);
   visible=visible+1;
  end
 end
 integer uart_delay=0,init_ok=0,tf_ok=0,ddr_ok=0;
 integer album_ready=0,album_exit=0,album_fail=0,gchecked=0;reg verify_gallery=0;integer tint_expected=5;
 reg [15:0] processed_expected[0:511];
 // Sample the raw timing before the controller advances its cycle counter.
 always @(negedge clk)begin
  if(verify_gallery&&gactive&&gde)begin
   automatic integer x=(cycles%GALLERY_PERIOD-GALLERY_BLANK)%144;
   automatic integer y=(cycles%GALLERY_PERIOD-GALLERY_BLANK)/144;
   automatic reg [15:0] expected=PROCESS_TESTS?processed_expected[(7-y/2)*64+x/2]:((x/8)<<11)|(((y/2)*2)<<5)|tint_expected;
   @(posedge clk);#1;
   if(frameerror||!goutde||{gr,gg,gb}!=={expected[15:11],3'b0,expected[10:5],2'b0,expected[4:0],3'b0})
    $fatal(1,"integrated gallery pixel x=%d y=%d got=%h expected=%h error=%b",x,y,{gr,gg,gb},expected,frameerror);
   gchecked=gchecked+1;
  end
 end
 string line="";
 always @(posedge clk)begin
  txaccept<=0;txdone<=0;
  if(uart_delay>0)begin uart_delay=uart_delay-1;if(uart_delay==0)txdone<=1;end
  else if(txvalid&&!txaccept)begin
   txaccept<=1;uart_delay=5;line={line,txdata};
   if(txlast)begin
    if(line==string'({"TF:INIT_OK",8'h0d,8'h0a}))init_ok=init_ok+1;
    else if(line==string'({"DDR_OK",8'h0d,8'h0a}))ddr_ok=ddr_ok+1;
    else if(line==string'({"tfOK",8'h0d,8'h0a}))tf_ok=tf_ok+1;
    else if(PROCESS_TESTS&&line==string'({"PROCESSING",8'h0d,8'h0a}))begin end
    else if(line==string'({"ALBUM:READY",8'h0d,8'h0a}))album_ready=album_ready+1;
    else if(line==string'({"ALBUM:EXIT",8'h0d,8'h0a}))album_exit=album_exit+1;
    else if(line==string'({"ALBUM:FAIL",8'h0d,8'h0a}))album_fail=album_fail+1;
    else if(line.substr(0,11)=="DEL_CONFIRM ")begin confirm_count=confirm_count+1;last_delete=line;end
    else if(line.substr(0,6)=="DEL_OK ")begin delete_count=delete_count+1;last_delete=line;end
    else if(line.substr(0,8)=="DEL_FAIL:")begin delete_fail_count=delete_fail_count+1;last_delete=line;end
    else if(line==string'({"DEL_CANCEL",8'h0d,8'h0a}))cancel_count=cancel_count+1;
    else if(line==string'({"ALBUM:EMPTY",8'h0d,8'h0a}))empty_count=empty_count+1;
    else if(line.substr(0,5)=="FAULT:")fault_count=fault_count+1;
    else if(DELETE_TESTS && line.substr(0,7)=="BUSY ST=")delete_busy_count=delete_busy_count+1;
    else $fatal(1,"save failed during HDMI integration: %s",line);
    line="";
   end
  end
 end
 task automatic capture(input [7:0] tint);
  begin
   @(negedge clk);b=1;@(negedge clk);b=0;repeat(8)@(negedge clk);
   vs=1;repeat(4)@(negedge clk);vs=0;repeat(4)@(negedge clk);
   for(integer y=0;y<16;y=y+1)begin
    for(integer x=0;x<128;x=x+1)begin de=1;red=x;green=y*4;blue=tint;@(negedge clk);end
    de=0;repeat(8)@(negedge clk);
   end
   vs=1;repeat(4)@(negedge clk);vs=0;
  end
 endtask
 task automatic gallery_command(input integer kind,input integer number,input integer tint);
  integer before_ready;
  begin
   verify_gallery=0;before_ready=album_ready;
   @(negedge clk);gx=kind==0;gprev=kind==1;gnext=kind==2;
   @(negedge clk);gx=0;gprev=0;gnext=0;
   wait(album_ready==before_ready+1);
   if(gnumber!=number||gerror||stagefailed)$fatal(1,"gallery selection/commit wrong number=%d",gnumber);
   tint_expected=tint;repeat(6400)@(negedge clk);verify_gallery=1;repeat(6400)@(negedge clk);verify_gallery=0;
  end
 endtask
 task automatic check_photo(input integer lba,input integer tint);
  integer x,y;reg [15:0] pixel;
  begin
   if(PROCESS_TESTS)$readmemh($sformatf("video_edge%0d.hex",tint*8),processed_expected);
   if(card.getbyte(lba,0)!="B"||card.getbyte(lba,1)!="M")$fatal(1,"bad BMP header");
   for(integer k=0;k<1024;k=k+1)begin
    x=(k/2)%64;y=7-k/128;pixel=PROCESS_TESTS?processed_expected[k/2]:((x>>2)<<11)|((y*2)<<5)|tint;
    if(card.getbyte(lba+1+k/512,k%512)!=(k%2?pixel[15:8]:pixel[7:0]))$fatal(1,"integrated photo mismatch");
   end
  end
 endtask
 task automatic delete_press;
  begin @(negedge clk);del=1;@(negedge clk);del=0;end
 endtask
 task automatic edit_card_byte(input integer lba,input integer byte_index,input [7:0] value);
  integer k,slot;
  begin
   slot=-1;for(k=0;k<card.slots;k=k+1)if(card.saved_lba[k]==lba)slot=k;
   if(slot<0)begin
    slot=card.slots;
    for(k=0;k<512;k=k+1)card.saved[slot][k]=card.getbyte(lba,k);
    card.saved_lba[slot]=lba;card.slots=card.slots+1;
   end
   card.saved[slot][byte_index]=value;
  end
 endtask
 function automatic [31:0] get_fat(input integer copy,input integer cluster);
  integer lba,ix;
  begin lba=32+copy*550+cluster/128;ix=(cluster%128)*4;
   get_fat={card.getbyte(lba,ix+3),card.getbyte(lba,ix+2),card.getbyte(lba,ix+1),card.getbyte(lba,ix)};
  end
 endfunction
 task automatic run_delete_tests;
  integer before_writes,before_ready,conf,failures,deleted;
  begin
   // A confirmation request alone MUST NOT write any sector.
   before_writes=card.writes;conf=confirm_count;delete_press();delete_press();wait(confirm_count==conf+1);
   if(photo.state!=0||delete_count!=0||photo.writer.deleting)$fatal(1,"Deletion started before confirmation message finished");
   wait(delete_busy_count>=1);
   if(last_delete!=string'({"DEL_CONFIRM IMG00002.BMP",8'h0d,8'h0a}))$fatal(1,"Wrong locked delete filename %s",last_delete);
   repeat(50100)@(negedge clk);wait(cancel_count==1);
   if(card.writes!=before_writes||delete_count!=0)$fatal(1,"Timeout confirmation wrote the card");
   conf=confirm_count;delete_press();wait(confirm_count==conf+1);
   gallery_command(1,1,5);wait(cancel_count==2);
   if(card.writes!=before_writes)$fatal(1,"Navigation cancellation wrote the card");
   gallery_command(2,2,10);
   conf=confirm_count;delete_press();wait(confirm_count==conf+1);
   @(negedge clk);gx=1;@(negedge clk);gx=0;wait(cancel_count==3);wait(!gmode);
   if(card.writes!=before_writes)$fatal(1,"Exit cancellation wrote the card");
   gallery_command(0,1,5);gallery_command(2,2,10);
   // Different mirrored FAT links must fail BEFORE directory or FAT mutation.
   edit_card_byte(582,6*4,9);failures=delete_fail_count;conf=confirm_count;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_fail_count==failures+1);
   if(last_delete!=string'({"DEL_FAIL:0B",8'h0d,8'h0a})||card.writes!=before_writes||photo.writer.delete_mutated)
    $fatal(1,"Broken mirrored chain was modified");
   edit_card_byte(582,6*4,7);wait(photo.state==0);gallery_command(1,1,5);gallery_command(2,2,10);
   // Preserve the reserved upper nibble independently in each FAT copy.
   for(integer k=6;k<=8;k=k+1)begin
    edit_card_byte(32,k*4+3,card.getbyte(32,k*4+3)|8'ha0);
    edit_card_byte(582,k*4+3,card.getbyte(582,k*4+3)|8'hb0);
   end
   deleted=delete_count;conf=confirm_count;before_ready=album_ready;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_count==deleted+1);
   if(last_delete!=string'({"DEL_OK IMG00002.BMP",8'h0d,8'h0a}))$fatal(1,"Wrong deletion result filename %s",last_delete);
   wait(album_ready==before_ready+1);
   if(gnumber!=1||card.getbyte(1132,32)!=8'he5||card.getbyte(1132,0)!="I")$fatal(1,"Last-file deletion did not select previous / preserve other entry");
   for(integer k=6;k<=8;k=k+1)
    if(get_fat(0,k)!=32'ha0000000||get_fat(1,k)!=32'hb0000000)$fatal(1,"FAT clearing lost reserved nibble");
   check_photo(1133,5);
   if((get_fat(0,3)&32'h0fffffff)!=4||(get_fat(1,3)&32'h0fffffff)!=4)$fatal(1,"Other photo FAT chain changed");
   for(integer k=488;k<496;k=k+1)
    if(card.getbyte(1,k)!=255||card.getbyte(7,k)!=255)$fatal(1,"FSInfo was not invalidated");
   // Saving after deletion must reuse freed space without changing IMG00001.
   capture(8'h78);delete_press();wait(tf_ok==3);check_photo(1136,15);
   if(card.getbyte(1132,7)!="1"||card.getbyte(1132,39)!="2")$fatal(1,"Existing photo was renumbered / freed space not reused");
   gallery_command(2,2,15);gallery_command(1,1,5);
   // A delete request during a new gallery load is rejected, not queued.
   before_ready=album_ready;before_writes=card.writes;
   @(negedge clk);gnext=1;@(negedge clk);gnext=0;wait(gbusy);
   delete_press();wait(album_ready==before_ready+1);
   if(card.writes!=before_writes)$fatal(1,"Busy gallery delete wrote the card");
   gallery_command(1,1,5);
   deleted=delete_count;conf=confirm_count;before_ready=album_fail;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();
   wait(photo.writer.delete_done);@(negedge clk);corrupt_gallery_read=1;
   wait(delete_count==deleted+1);wait(album_fail==before_ready+1);wait(!gbusy&&!stagebusy&&!writerbusy);
   if(photo.refresh_pending)$fatal(1,"Failed post-delete reload kept storage busy");
   corrupt_gallery_read=0;
   @(negedge clk);gx=1;@(negedge clk);gx=0;wait(!gmode);
   gallery_command(0,2,15);check_photo(1136,15);
   deleted=delete_count;conf=confirm_count;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_count==deleted+1);wait(empty_count==1);
   repeat(6400)@(negedge clk);
   if(gmode||genable||gactive||gbusy||stagebusy)$fatal(1,"Empty album did not return to live video");
   // Re-entering an empty album must also report EMPTY, not a failed load.
   @(negedge clk);gx=1;@(negedge clk);gx=0;wait(empty_count==2);
   // Unsupported attributes/header and cyclic links fail without writes.
   capture(8'hc8);wait(tf_ok==4);gallery_command(0,1,25);
   before_writes=card.writes;conf=confirm_count;failures=delete_fail_count;
   edit_card_byte(1132,11,8'h21);
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_fail_count==failures+1);
   if(card.writes!=before_writes||photo.writer.delete_mutated)$fatal(1,"Readonly entry was modified");
   edit_card_byte(1132,11,8'h20);wait(photo.state==0);gallery_command(2,1,25);
   conf=confirm_count;failures=delete_fail_count;edit_card_byte(1133,0,"X");
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_fail_count==failures+1);
   if(last_delete!=string'({"DEL_FAIL:0C",8'h0d,8'h0a})||card.writes!=before_writes)$fatal(1,"Bad BMP header was modified");
   edit_card_byte(1133,0,"B");wait(photo.state==0);gallery_command(2,1,25);
   conf=confirm_count;failures=delete_fail_count;edit_card_byte(32,3*4,3);edit_card_byte(582,3*4,3);
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_fail_count==failures+1);
   if(last_delete!=string'({"DEL_FAIL:0B",8'h0d,8'h0a})||card.writes!=before_writes)$fatal(1,"Cyclic chain was modified");
   edit_card_byte(32,3*4,4);edit_card_byte(582,3*4,4);wait(photo.state==0);gallery_command(2,1,25);
   // Fragmented (non-contiguous) valid chains must delete correctly as well.
   for(integer k=0;k<512;k=k+1)edit_card_byte(1139,k,card.getbyte(1134,k));
   for(integer copy=0;copy<2;copy=copy+1)begin
    edit_card_byte(32+copy*550,3*4,9);edit_card_byte(32+copy*550,9*4,5);
    edit_card_byte(32+copy*550,4*4,0);
   end
   conf=confirm_count;deleted=delete_count;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_count==deleted+1);wait(empty_count==3);
   for(integer copy=0;copy<2;copy=copy+1)
    if((get_fat(copy,3)&32'h0fffffff)!=0||(get_fat(copy,9)&32'h0fffffff)!=0||(get_fat(copy,5)&32'h0fffffff)!=0)
     $fatal(1,"Fragmented chain not freed");
   // Failure after a destructive command must NOT admit more file mutations.
   capture(8'ha0);wait(tf_ok==5);gallery_command(0,1,20);
   conf=confirm_count;failures=delete_fail_count;reject_card_write=1;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();wait(delete_fail_count==failures+1);
   if(last_delete!=string'({"DEL_FAIL:09 PARTIAL",8'h0d,8'h0a})||photo.state!=6||!photo.writer.delete_mutated)
    $fatal(1,"Directory write rejection did not lock deletion");
   if(card.getbyte(1132,0)!="I")$fatal(1,"Rejected directory write changed the file");
   before_writes=card.command_count[24];
   @(negedge clk);b=1;@(negedge clk);b=0;wait(fault_count==1);
   repeat(100)@(negedge clk);if(card.command_count[24]!=before_writes)$fatal(1,"Partial-failure lock admitted a write");
   reject_card_write=0;
   // Firmware reset clears the guard only after the operator has inspected
   // the card. Here the previous directory write was rejected, so it's intact.
   @(negedge clk);rst_n=0;repeat(20)@(negedge clk);rst_n=1;repeat(2100)@(negedge clk);
   gallery_command(0,1,20);conf=confirm_count;failures=delete_fail_count;
   delete_press();wait(confirm_count==conf+1);wait(photo.confirm_prompt_sent);delete_press();
   wait(photo.writer.state==15&&photo.writer.deleting&&photo.writer.fat_copy==1);
   @(negedge clk);reject_card_write=1;wait(delete_fail_count==failures+1);
   if(last_delete!=string'({"DEL_FAIL:09 PARTIAL",8'h0d,8'h0a})||photo.state!=6||card.getbyte(1132,0)!=8'he5)
    $fatal(1,"Mid-FAT failure did not preserve tombstone/lock");
   if((get_fat(0,photo.writer.file_cluster)&32'h0fffffff)!=0||
      (get_fat(1,photo.writer.file_cluster)&32'h0fffffff)==0)$fatal(1,"Fault injection did not interrupt FAT copies");
   before_writes=card.command_count[24];
   @(negedge clk);q=1;@(negedge clk);q=0;wait(fault_count==2);
   repeat(100)@(negedge clk);if(card.command_count[24]!=before_writes)$fatal(1,"Mid-FAT fault admitted more writes");
   $display("PASS confirmed native FAT32 deletion: timeout/navigation cancellation, chain preflight, both FATs/reserved bits, FSInfo, freed-space reuse, previous/next selection and empty exit");
   $display("PASS deletion safety: prompt completion gate, busy rejection, readonly/header/cycle preflight, fragmented chains, rejected directory and interrupted FAT writes lock storage");
  end
 endtask
 initial begin
  repeat(20)@(negedge clk);rst_n=1;repeat(2100)@(negedge clk);check_display=1;
  @(negedge clk);q=1;@(negedge clk);q=0;wait(init_ok==1);
  capture(8'h28);wait(tf_ok==1);check_photo(1133,5);
  if(PROCESS_TESTS)begin
   wait(album_ready==1);repeat(2*GALLERY_PERIOD)@(negedge clk);
   verify_gallery=1;repeat(2*GALLERY_PERIOD)@(negedge clk);verify_gallery=0;
   capture(8'h50);wait(tf_ok==2);check_photo(1136,10);wait(album_ready==2);
   repeat(2*GALLERY_PERIOD)@(negedge clk);verify_gallery=1;repeat(2*GALLERY_PERIOD)@(negedge clk);verify_gallery=0;
   if(ddr_ok!=2||visible<5000||video_transactions<40||photo_transactions<100||
      gnumber!=2||gchecked<5000||album_fail!=0)$fatal(1,"processed video/gallery coverage");
   $display("PASS complete Canny under real video DDR contention, both arbiters, saved BMP bytes and decoded gallery pixels");
   $finish;
  end
  // Stall a real video request, reset its producer's frame, and let the old
  // buffered address/data complete. Its descriptor must stay stable and its
  // old pixels must be discarded; normal display must resume next frames.
  check_display=0;block_read=1;wait(native_valid&&!native_type);repeat(3)@(negedge clk);
  manual_vsync=1;repeat(6)@(negedge clk);manual_vsync=0;repeat(40)@(negedge clk);block_read=0;
  repeat(1400)@(negedge clk);check_display=1;
  capture(8'h50);wait(tf_ok==2);check_photo(1136,10);repeat(1400)@(negedge clk);
  if(ddr_ok!=2||visible<5000||video_transactions<40||photo_transactions!=16)
   $fatal(1,"concurrent coverage incomplete video=%d photo=%d visible=%d",video_transactions,photo_transactions,visible);
  if(GALLERY_TESTS)begin
   check_display=0;
   gallery_command(0,1,5);gallery_command(2,2,10);gallery_command(2,1,5);gallery_command(1,2,10);
   @(negedge clk);gx=1;@(negedge clk);gx=0;wait(album_exit==1);repeat(3200)@(negedge clk);
   if(genable||gactive)$fatal(1,"gallery exit did not restore live display");
   gallery_command(0,1,5);
   if(album_fail!=0||gchecked<10000)$fatal(1,"gallery pixel coverage insufficient %d",gchecked);
   corrupt_gallery_read=1;
   @(negedge clk);gnext=1;@(negedge clk);gnext=0;wait(album_fail==1);
   repeat(6400)@(negedge clk);if(album_fail!=1||gbusy||stagebusy)$fatal(1,"CRC failure flooded UART / wedged reader");
   corrupt_gallery_read=0;gallery_command(2,2,10);
   fail_gallery_write=1;
   @(negedge clk);gprev=1;@(negedge clk);gprev=0;wait(album_fail==2);
   wait(!gbusy&&!stagebusy&&!writerbusy);repeat(3200)@(negedge clk);
   if(album_fail!=2||album_ready!=6)$fatal(1,"DDR failure falsely published / repeated status");
   fail_gallery_write=0;gallery_command(2,2,10);
   $display("PASS full native SD4 saved BMP -> FAT reader -> queued DDR/BRESP -> RGB565 HDMI, prev/next wrap, exit/re-enter");
   $display("PASS superfloppy boot-code bytes + SD CRC/DDR BRESP failure one-shot UART + retry recovery");
  end
  if(DELETE_TESTS)run_delete_tests();
  $display("PASS real video scheduler + both AXI arbiters + two photo saves + VSYNC/address stall + continuous HDMI pixels");
  $finish;
 end
 initial begin #100000000;$fatal(1,"video/save integration timeout");end
endmodule
