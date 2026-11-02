`timescale 1ns/1ps
module photo_native_pipeline_tb #(parameter SDSC=0, LEGACY_CMD8=0,FAULT_TESTS=0,PROCESS_TESTS=0,AUTO_OPEN_RACE=0,UART_TESTS=0,ADC_TESTS=0);
 reg clk=0,pclk=0,rst_n=0;always #5 clk=~clk;always #3.5 pclk=~pclk;
 reg uart_req=0;
 wire frame_valid,frame_last;wire [7:0] frame_data;reg frame_accept=0,frame_done=0;
 integer frame_fd=0,frame_delay=0,frame_bytes=0,frame_count=0;
 reg b=0,q=0,vs=0,de=0;reg [7:0] red=0,green=0,blue=0;
 wire accepted,txvalid,txlast;wire [7:0] txdata;reg txaccept=0,txdone=0;
 wire sdclk,cmdo,cmdoe,cmdi;wire [3:0] dato,datoe,dati;
 reg reject_write=0,corrupt_read=0,inject_bresp=0;
 reg stall_ar=0,stall_r=0,omit_last=0,late_end=0;
 wire [31:0] awaddr,araddr;wire [7:0] awlen,arlen;
 wire awvalid,wvalid,wlast,arvalid,rready;reg awready=0,wready=0,arready=0,bvalid=0,rvalid=0,rlast=0;
 wire [127:0] wdata;reg [127:0] rdata=0;reg [1:0] bresp=0;
 wire gallery_busy;
 reg [1:0] capture_mode=0;
 reg knob_ready=0;reg [11:0] knob_value=120;
 wire [10:0] effective_high,effective_low;
 generate if(ADC_TESTS)begin : g_adc_threshold
 adc_threshold_ctrl #(.DEFAULT_HIGH(60),.DEFAULT_LOW(30)) threshold_ctrl(
  .clk(clk),.rst_n(rst_n),.knob_value(knob_value),.knob_ready(knob_ready),
  .knob_enable(1'b1),
  .uart_update(1'b0),.uart_high(11'd60),.uart_low(11'd30),
  .high_threshold(effective_high),.low_threshold(effective_low));
 end else begin : g_fixed_threshold
 assign effective_high=60;assign effective_low=30;
 end endgenerate
 reg inject_process_fault=0;
 reg delete_req=0;
 wire gallery_mode,gallery_done,gallery_byte_valid;
 wire [7:0] gallery_byte;wire [19:0] gallery_offset;wire [31:0] gallery_number;
 integer album_ready=0,processing_lines=0,process_failures=0,delete_confirm=0,delete_ok=0;
 reg [15:0] processed_expected[0:511];
 photo_native_pipeline #(.WIDTH(64),.HEIGHT(8),.DDR_TIMEOUT(FAULT_TESTS?2000:4800000),
  .DDR_RECOVERY_TIMEOUT(FAULT_TESTS?20000:48000000),.RECOVERY_TIMEOUT(FAULT_TESTS?40000:96000000),.ENABLE_PROCESSING(PROCESS_TESTS),.ENABLE_DELETE(PROCESS_TESTS),.ENABLE_UART_EXPORT(PROCESS_TESTS||UART_TESTS)) dut(
  .clk(clk),.rst_n(rst_n),.pclk(pclk),.prst_n(rst_n),.capture_req(b),.query_req(q),.capture_accepted(accepted),
  .delete_req(delete_req),.uart_capture_req(uart_req),
  .frame_tx_valid(frame_valid),.frame_tx_data(frame_data),.frame_tx_last(frame_last),.frame_tx_accept(frame_accept),.frame_tx_done(frame_done),
  .axi_read_stalled(1'b0),.axi_read_debug(4'd0),
  .gallery_ddr_busy(1'b0),.gallery_ddr_failed(1'b0),.gallery_abort(1'b0),.gallery_ready(PROCESS_TESTS&&gallery_done),
  .gallery_display_error(1'b0),
  .in_vsync(vs),.in_href(de),.red(red),.green(green),.blue(blue),
  .capture_mode(capture_mode),.median_enable(1'b1),.cleanup_level(2'd1),.min_pixels(11'd20),.high_threshold(effective_high),.low_threshold(effective_low),
  .gallery_toggle_req(1'b0),.gallery_prev_req(1'b0),.gallery_next_req(1'b0),.gallery_mode(gallery_mode),.gallery_busy(gallery_busy),.gallery_error(),.gallery_file_number(gallery_number),
  .gallery_load_start(),.gallery_load_byte_valid(gallery_byte_valid),.gallery_load_byte(gallery_byte),.gallery_load_byte_offset(gallery_offset),.gallery_load_done(gallery_done),.gallery_load_error(),
  .tx_valid(txvalid),.tx_data(txdata),.tx_last(txlast),.tx_accept(txaccept),.tx_done(txdone),
  .sd_clk(sdclk),.sd_cmd_o(cmdo),.sd_cmd_oe(cmdoe),.sd_cmd_i(cmdi),.sd_dat_i(dati),.sd_dat_o(dato),.sd_dat_oe(datoe),
  .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rresp(PROCESS_TESTS&&inject_process_fault&&dut.state==7?2'b10:2'b00),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 defparam dut.host.POWER_CYCLES=16;
 defparam dut.host.INIT_DIV=4;
 defparam dut.host.FAST_DIV=4;
 defparam dut.host.DATA_TIMEOUT=200000;
 sd4_card_model_tb #(.SDSC(SDSC),.LEGACY_CMD8(LEGACY_CMD8)) card(sdclk,cmdo,cmdoe,cmdi,dato,datoe,dati,reject_write,corrupt_read);
 reg [127:0] ram[0:383];integer wa,ra,wb_left=0,rb_left=0,delay_b=0,cycles=0;
 function integer addr_index(input [31:0] a);
  begin
   if(PROCESS_TESTS&&a>=32'h01800000&&a<32'h01800400)addr_index=128+(a-32'h01800000)/16;
   else if(PROCESS_TESTS&&a>=32'h01900000&&a<32'h01900400)addr_index=192+(a-32'h01900000)/16;
   else if(PROCESS_TESTS&&a>=32'h01a00000&&a<32'h01a00800)addr_index=256+(a-32'h01a00000)/16;
   else begin
    if((a&32'hffeffc00)!=32'h01600000)$fatal(1,"DDR address outside private buffers %h",a);
    addr_index={a[20],a[9:4]};
   end
  end
 endfunction
 always @(posedge clk)begin
  cycles<=cycles+1;
  awready<=wb_left==0&&delay_b==0&&!bvalid;
  wready<=wb_left!=0&&cycles%3!=0;
  arready<=!stall_ar&&rb_left==0&&!rvalid;
  bvalid<=0;
  if(awvalid&&awready)begin wa=addr_index(awaddr);wb_left=awlen+1;awready<=0;end
  if(wvalid&&wready)begin
   ram[wa]<=wdata;wa=wa+1;wb_left=wb_left-1;
   if(wlast!=(wb_left==0))$fatal(1,"WLAST mismatch");
   if(wb_left==0)begin delay_b=15;wready<=0;end
  end
  if(delay_b>0)begin delay_b=delay_b-1;
   if(delay_b==0)begin bvalid<=1;bresp<=inject_bresp?2:0;end
  end
  if(arvalid&&arready)begin ra=addr_index(araddr);rb_left=arlen+1;arready<=0;end
  if(rvalid&&rready)begin rvalid<=0;if(rb_left>0)begin ra=ra+1;rb_left=rb_left-1;end else late_end<=0;end
  if(!rvalid&&rb_left>0&&!stall_r&&cycles%4!=0)begin rdata<=ram[ra];rvalid<=1;rlast<=rb_left==1&&!omit_last;end
  if(!rvalid&&rb_left==0&&late_end)begin rvalid<=1;rlast<=1;rdata<=0;end
 end
 always @(posedge clk)begin
  frame_accept<=0;frame_done<=0;
  if(frame_delay>0)begin frame_delay=frame_delay-1;if(frame_delay==0)frame_done<=1;end
  else if(frame_valid&&!frame_accept)begin
   frame_accept<=1;frame_delay=5;$fwrite(frame_fd,"%c",frame_data);frame_bytes=frame_bytes+1;
   if(frame_last)frame_count=frame_count+1;
  end
 end
 integer uart_delay=0,ddr_ok=0,tf_ok=0,tf_fail=0,ddr_fail=0,init_ok=0,busy_lines=0,cap_count=0,reset_lines=0;
 string last_failure="";
 string line="";
 always @(posedge clk)begin
  txaccept<=0;txdone<=0;
  if(accepted)cap_count=cap_count+1;
  if(uart_delay!=0)begin uart_delay=uart_delay-1;if(uart_delay==0)txdone<=1;end
  else if(txvalid&&!txaccept)begin
   txaccept<=1;uart_delay=5;line={line,txdata};
   if(txlast)begin
    $display("UART %s",line);
    if(line.getc(line.len()-2)!=13||line.getc(line.len()-1)!=10)$fatal(1,"UART missing CR/LF");
    if(line==string'({"DDR_OK",8'h0d,8'h0a}))begin
     ddr_ok=ddr_ok+1;if(wb_left!=0||delay_b!=0)$fatal(1,"early DDR_OK");
    end else if(line==string'({"tfOK",8'h0d,8'h0a}))tf_ok=tf_ok+1;
    else if(line==string'({"DDR_FAIL",8'h0d,8'h0a}))ddr_fail=ddr_fail+1;
    else if(line==string'({"TF:INIT_OK",8'h0d,8'h0a}))init_ok=init_ok+1;
    else if(line.substr(0,7)=="BUSY ST=")busy_lines=busy_lines+1;
    else if(line.substr(0,7)=="TF_FAIL:")begin tf_fail=tf_fail+1;last_failure=line;end
    else if(line.substr(0,5)=="FAULT:")reset_lines=reset_lines+1;
    else if(PROCESS_TESTS&&line==string'({"PROCESSING",8'h0d,8'h0a}))processing_lines=processing_lines+1;
    else if(PROCESS_TESTS&&line==string'({"ALBUM:READY",8'h0d,8'h0a}))album_ready=album_ready+1;
    else if(PROCESS_TESTS&&line==string'({"PROCESS_FAIL:RESET_REQUIRED",8'h0d,8'h0a}))process_failures=process_failures+1;
    else if(PROCESS_TESTS&&line.substr(0,11)=="DEL_CONFIRM ")delete_confirm=delete_confirm+1;
    else if(PROCESS_TESTS&&line.substr(0,6)=="DEL_OK ")delete_ok=delete_ok+1;
    else $fatal(1,"unexpected status %s",line);
    line="";
   end
  end
 end
 task automatic command_b;begin @(negedge clk);b=1;@(negedge clk);b=0;end endtask
 task automatic frame(input [7:0] tint);
  integer x,y;
  begin
   repeat(8)@(negedge pclk);vs=1;repeat(4)@(negedge pclk);vs=0;
   repeat(4)@(negedge pclk);
   for(y=0;y<16;y=y+1)begin
    for(x=0;x<128;x=x+1)begin de=1;red=x;green=y*4;blue=tint;
     if(PROCESS_TESTS&&capture_mode!=0)begin red=(x>=32&&x<96&&y>=4&&y<12)?200:30;green=red;blue=red;end
     @(negedge pclk);end
    de=0;repeat(8)@(negedge pclk);
   end
   vs=1;repeat(4)@(negedge pclk);vs=0;
  end
 endtask
 task automatic check_processed(input integer lba,input integer edge_mode);
  if(edge_mode)$readmemh("integration_edge.hex",processed_expected);else $readmemh("integration_gray.hex",processed_expected);
  if(card.getbyte(lba,0)!="B"||card.getbyte(lba,1)!="M")$fatal(1,"processed BMP header");
  for(integer k=0;k<1024;k=k+1)
   if(card.getbyte(lba+1+k/512,k%512)!=(k%2?processed_expected[k/2][15:8]:processed_expected[k/2][7:0]))
    $fatal(1,"processed TF byte %d mismatch",k);
 endtask
 task automatic check_photo(input integer lba,input integer tint);
  integer k,x,y;reg [15:0] pixel;
  begin
   if(card.getbyte(lba,0)!="B"||card.getbyte(lba,1)!="M")$fatal(1,"bad BMP header");
   for(k=0;k<1024;k=k+1)begin
    x=(k/2)%64;y=7-(k/128);pixel=((x>>2)<<11)|((y*2)<<5)|tint;
    if(card.getbyte(lba+1+k/512,k%512)!=(k%2?pixel[15:8]:pixel[7:0]))
     $fatal(1,"photo byte mismatch %d got %h expected %h",k,card.getbyte(lba+1+k/512,k%512),(k%2?pixel[15:8]:pixel[7:0]));
   end
  end
 endtask
 initial begin
  repeat(20)@(negedge clk);rst_n=1;
  if(UART_TESTS)begin
   knob_ready=ADC_TESTS;repeat(10)@(negedge clk);
   capture_mode=1;frame_fd=$fopen("integration_gray_packet.bin","wb");
   @(negedge clk);uart_req=1;@(negedge clk);uart_req=0;frame(8'h50);
   wait(dut.state==8);
   if(ADC_TESTS)begin
    knob_value=4095;repeat(10)@(negedge clk);
    if(effective_high!=2047||dut.photo_high!=60||dut.photo_low!=30)$fatal(1,"Gray capture threshold snapshot changed with ADC");
   end
   if(dut.retained||dut.save_start||dut.host.initialized)$fatal(1,"UART capture depends on TF or publishes TF ownership");
   // Busy requests cannot trigger another capture or change the active frame.
   capture_mode=0;command_b();
   wait(frame_count==1);wait(dut.state==0);$fclose(frame_fd);
   if(frame_bytes!=552||cap_count!=1||busy_lines!=1)$fatal(1,"gray UART size/admission");
   knob_value=120;repeat(10)@(negedge clk);
   capture_mode=2;frame_bytes=0;frame_fd=$fopen("integration_edge_packet.bin","wb");
   @(negedge clk);uart_req=1;@(negedge clk);uart_req=0;frame(8'h78);
   if(ADC_TESTS)begin
    knob_value=4095;repeat(10)@(negedge clk);
    if(effective_high!=2047||dut.photo_high!=60||dut.photo_low!=30)$fatal(1,"Canny capture threshold snapshot changed with ADC");
   end
   wait(frame_count==2);wait(dut.state==0);$fclose(frame_fd);
   if(frame_bytes!=104||cap_count!=2||tf_ok!=0||dut.retained||dut.host.initialized)$fatal(1,"edge UART size/lifecycle");
   $display("PASS image2 camera sampler/DMA/full-frame Canny/UART without TF, repeated capture and BUSY ownership");$finish;
  end
  @(negedge clk);q=1;@(negedge clk);q=0;
  wait(init_ok==1);
  if(dut.host.high_capacity==SDSC || dut.host.capacity_mb!=(SDSC?1888:128))$fatal(1,"card type/capacity wrong");
  if(card.cmd16_count!=(SDSC?1:0))$fatal(1,"SDSC CMD16 branch not exercised");
  if(PROCESS_TESTS)begin
   command_b();frame(8'h28);wait(tf_ok==1);check_photo(1133,5);
   capture_mode=1;
   fork
    begin
     if(AUTO_OPEN_RACE)begin
      wait(dut.open_saved_photo);@(negedge clk);q=1;@(negedge clk);q=0;
     end
    end
    begin command_b();frame(8'h50);wait(tf_ok==2);end
   join
   if(AUTO_OPEN_RACE)begin
    for(integer k=0;k<2000000&&album_ready!=1;k=k+1)@(negedge clk);
    if(album_ready!=1)$fatal(1,"automatic preview request lost when i query coincides with save completion");
    if(init_ok!=2)$fatal(1,"preview race did not exercise an accepted i query");
   end else wait(album_ready==1);
   check_processed(1136,0);if(gallery_number!=2)$fatal(1,"auto-preview selected old file");
   capture_mode=2;command_b();frame(8'h78);wait(tf_ok==3);wait(album_ready==2);
   check_processed(1139,1);if(gallery_number!=3)$fatal(1,"auto-preview edge selected old file");
   reject_write=1;command_b();frame(8'ha0);wait(tf_fail==1);reject_write=0;
   wait(dut.state==0);
   // A UART-only capture must not replace the retained failed TF photo.
   capture_mode=2;@(negedge clk);uart_req=1;@(negedge clk);uart_req=0;
   repeat(100)@(negedge clk);
   if(cap_count!=4||dut.state!=0||!dut.retained||dut.retained_saved)$fatal(1,"UART overwrote failed TF photo");
   capture_mode=0;command_b();wait(tf_ok==4);wait(album_ready==3);
   check_processed(1142,1);
   if(cap_count!=4||processing_lines!=3||gallery_number!=4)$fatal(1,"retry recaptured/reprocessed or lost mode");
   @(negedge clk);delete_req=1;@(negedge clk);delete_req=0;wait(delete_confirm==1);wait(dut.confirm_prompt_sent);
   @(negedge clk);delete_req=1;@(negedge clk);delete_req=0;wait(delete_ok==1);wait(album_ready==4);
   if(gallery_number!=3||card.getbyte(1132,96)!=8'he5)$fatal(1,"processed-photo delete/reload selected wrong file");
   check_processed(1139,1);
   capture_mode=2;inject_process_fault=1;command_b();frame(8'hc8);wait(process_failures==1);
   repeat(100)@(negedge clk);
   if(tf_ok!=4||dut.state!=3||dut.retained_slot!=1)$fatal(1,"failed processing published or overwrote retained photo");
   $display("PASS real C/G/E sampler -> DDR processor -> SD4/FAT32 BMP -> exact saved-file auto-preview; failed-save retry and processing fault gate");$finish;
  end
  command_b();frame(8'h28);wait(ddr_ok==1);
  command_b();wait(tf_ok==1);
  if(cap_count!=1||busy_lines!=1||!dut.retained_saved||dut.retained_slot!=0)$fatal(1,"first lifecycle wrong");
  check_photo(1133,5);
  if(card.getbyte(1132,7)!="1")$fatal(1,"directory publication wrong");
  command_b();repeat(20)@(negedge clk);
  if(dut.retained_slot!=0||!dut.retained_saved)$fatal(1,"previous frame released early");
  frame(8'h50);wait(tf_ok==2);check_photo(1136,10);
  if(dut.retained_slot!=1||!dut.retained_saved)$fatal(1,"buffer did not alternate");
  reject_write=1;command_b();frame(8'h78);wait(tf_fail==1);
  if(tf_ok!=2||dut.retained_saved||dut.retained_slot!=0)$fatal(1,"failed image not retained");
  reject_write=0;command_b();wait(tf_ok==3);check_photo(1139,15);
  if(cap_count!=3)$fatal(1,"retry captured a different image");
  inject_bresp=1;command_b();frame(8'ha0);wait(ddr_fail==1);repeat(30)@(negedge clk);
  if(ddr_ok!=3||tf_ok!=3||dut.retained_slot!=0)$fatal(1,"AXI error falsely published");
  inject_bresp=0;corrupt_read=1;command_b();frame(8'ha0);wait(tf_fail==2);
  if(tf_ok!=3)$fatal(1,"read CRC error reported success");
  if(FAULT_TESTS)begin
   corrupt_read=0;stall_ar=1;command_b();wait(dut.photo_read_debug==1);
   @(negedge clk);q=1;@(negedge clk);q=0;wait(tf_fail==3);
   if(last_failure!=string'({"TF_FAIL:DDR_ADDR_TIMEOUT",8'h0d,8'h0a})||dut.retained_saved||tf_ok!=3)
    $fatal(1,"DDR address timeout diagnostic/retention wrong");
   stall_ar=0;wait(dut.state==0);command_b();wait(tf_ok==4);check_photo(1142,20);
   if(cap_count!=5)$fatal(1,"DDR timeout retry recaptured");
   stall_r=1;command_b();frame(8'hc8);wait(tf_fail==4);wait(reset_lines==1);
   if(last_failure!=string'({"TF_FAIL:DDR_DATA_TIMEOUT",8'h0d,8'h0a})||dut.state!=3||dut.retained_saved)
    $fatal(1,"permanent stall did not enter explicit fault");
   @(negedge clk);q=1;@(negedge clk);q=0;wait(reset_lines==2);
   if(init_ok!=1)$fatal(1,"i started a new SD transaction while DDR was blocked");
   stall_r=0;wait(dut.state==0);command_b();wait(tf_ok==5);check_photo(1145,25);
   omit_last=1;command_b();frame(8'he0);wait(tf_fail==5);
   if(last_failure!=string'({"TF_FAIL:DDR_RLAST",8'h0d,8'h0a})||tf_ok!=5)$fatal(1,"missing RLAST falsely succeeded");
   omit_last=0;late_end=1;wait(dut.state==0);command_b();wait(tf_ok==6);check_photo(1148,28);
   if(cap_count!=7||busy_lines!=2)$fatal(1,"recovery/busy snapshot lifecycle wrong");
  end
  $display("PASS native SD4 SDSC=%0d LEGACY_CMD8=%0d + RGB565 DDR + FAT32 BMP + UART + double-buffer lifecycle + retries/error paths",SDSC,LEGACY_CMD8);
  $finish;
 end
 initial begin #100000000;$fatal(1,"timeout state=%d host=%d cmd=%d data=%d fat=%d",dut.state,dut.host.state,dut.host.cmd.state,dut.host.ds,dut.writer.state);end
endmodule
