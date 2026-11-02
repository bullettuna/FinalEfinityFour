`timescale 1ns/1ps
module pose7_standalone_tb #(parameter WITH_VIDEO=0,PERF_ONLY=0,PERF_SAMPLES=4);
 reg clk=0,pclk=0,rst_n=0;always #5 clk=~clk;always #3.367 pclk=~pclk;
 reg [1:0] mode=0,resolution=0;reg run_n=0,txe=1;
 reg reconfig_request=0;wire reconfig_idle;
 reg menu_valid=0;reg [4:0] menu_addr=0;reg [11:0] menu_value=0;wire [15:0] menu_status;
 reg [7:0] uart=0;reg uart_valid=0;
 wire sdclk,co,ce,ci;wire [3:0] di,do_,de;
 wire [3:0] boot_status;wire [7:0] boot_error;
 wire [7:0] stable_check_feedback;wire usb_points_enabled;
 wire publish,result_valid;wire [527:0] result_points;
 wire [31:0] aw,ar;wire [7:0] awl,arl;wire awv,wv,wl,arv,rr;
 wire [127:0] wd;
 wire [31:0] law,lar;wire [7:0] lawl,larl;
 wire lawv,lawr,lwv,lwr,lwl,lbv,larv,larr,lrv,lrr,lrl;
 wire [127:0] lwd,lrd;wire [1:0] lbresp,lrresp;
 reg [7:0] memory[0:32'h23ffff],snapshot[0:460799],fixture[0:230399];
 integer cx=0,cy=0;
 always @(posedge pclk)if(!rst_n)begin cx<=0;cy<=0;end
 else if(cx==2199)begin cx<=0;cy<=cy==1124?0:cy+1;end else cx<=cx+1;
 wire vs=cy<1080,href=cy<1080&&cx>=8&&cx<1928;
 wire [7:0] pixel=href?fixture[(cy/3)*640+(cx-8)/3]:8'd0;
 integer cycle=0,live_count=0,delay_count=0,beat=0;
 reg [1:0] ws=0,rs=0;reg [31:0] wa=0,ra=0;
 reg [7:0] wlen=0,rlen=0,wb=0,rb=0;
 wire awr=ws==0&&cycle%5!=1,wr=ws==1&&cycle%7!=2,bv=ws==2;
 wire arr=rs==0&&cycle%6!=3,rv=rs==2&&cycle%9!=4;
 reg [127:0] rd;
 wire [7:0] ft_data;wire ft_wr;
 wire stopped;
 wire uart_tx_valid;wire [7:0] uart_tx_data;
`ifdef POSE7_USB_CANDIDATE
 image7_ft_link_usb #(
`elsif POSE7_STABLE_CANDIDATE
 image7_ft_link_stable #(
`elsif POSE7_LATEST_CANDIDATE
 image7_ft_link_latest #(
`elsif POSE7_PERF_CANDIDATE
 image7_ft_link_fast #(
`else
 image7_ft_link #(
`endif
 .AUTO_BOOT(1),.MENU_ENABLE(1),.MULTIBOOT_ENABLE(1)) dut(
  .sclk(clk),.rst_n(rst_n),.pclk(pclk),.run_n(run_n),.mode(mode),.resolution(resolution),.edge_packed(1'b1),.txe_n_async(txe),
  .gray_vs(vs),.gray_de(href),.gray_pixel(pixel),.edge_vs(vs),.edge_de(href),.edge_pixel(pixel),
  .uart_rx_data(uart),.uart_rx_valid(uart_valid),.uart_legacy_valid(),.uart_tx_valid(uart_tx_valid),.uart_tx_data(uart_tx_data),.uart_tx_accept(1'b1),
  .stop_for_reconfig(reconfig_request),.reconfig_idle(reconfig_idle),
  .menu_write_valid(menu_valid),.menu_write_addr(menu_addr),.menu_write_value(menu_value),.menu_status(menu_status),
`ifdef POSE7_STABLE_CANDIDATE
  .check_feedback(stable_check_feedback),
`endif
`ifdef POSE7_USB_CANDIDATE
  .usb_points_enabled(usb_points_enabled),
`endif
  .video_diagnostic_data(384'd0),.ddr_ready(1'b1),
  .sd_clk(sdclk),.sd_cmd_o(co),.sd_cmd_oe(ce),.sd_cmd_i(ci),.sd_dat_i(di),.sd_dat_o(do_),.sd_dat_oe(de),
  .result_strobe(publish),.result_points(result_points),.result_valid(result_valid),.boot_status(boot_status),.boot_error(boot_error),
  .link_ready(),.stopped(stopped),.data_o(ft_data),.data_oe(),.wr_n(ft_wr),.wr_oe(),
  .awaddr(law),.awlen(lawl),.awvalid(lawv),.awready(lawr),.wdata(lwd),.wlast(lwl),.wvalid(lwv),.wready(lwr),.bvalid(lbv),.bresp(lbresp),
  .araddr(lar),.arlen(larl),.arvalid(larv),.arready(larr),.rdata(lrd),.rresp(lrresp),.rlast(lrl),.rvalid(lrv),.rready(lrr));
 // Production outer arbiter: synthetic 153.6/76.8 MB/s video read/write
 // demand at 96 MHz, above the active 1080p60 RAW8 pixel rate. These are
 // AXI traffic/service checks, not a substitute for a physical FIFO/PHY test.
 reg [1:0] vwstate=0,vrstate=0;
 reg [31:0] vwa=0,vra=32'h00800000;
 reg [7:0] vwbeat=0,vrbeat=0;
 integer next_write=0,next_read=0,write_started=0,read_started=0;
 integer video_reads=0,video_writes=0,max_read_service=0,max_write_service=0;
 wire vawv=WITH_VIDEO&&vwstate==1,vwv=WITH_VIDEO&&vwstate==2,varv=WITH_VIDEO&&vrstate==1;
 wire vawr,vwr,vbv,varr,vrv,vrl;wire [1:0] vbresp,vrresp;wire [127:0] vrd;wire br;
 function [127:0] video_pattern(input [31:0] a);
  video_pattern={a,a^32'h13579bdf,a+32'd1,~a};
 endfunction
 photo_axi_mux outer_mux(
  .clk(clk),.rst_n(rst_n),.v_read_flush(1'b0),.v_read_urgent(varv),.read_stalled(),.read_debug(),
  .v_awaddr(vwa),.v_awlen(8'd127),.v_awvalid(vawv),.v_awready(vawr),.v_wdata(video_pattern(vwa+vwbeat*16)),.v_wstrb(16'hffff),.v_wlast(vwbeat==127),.v_wvalid(vwv),.v_wready(vwr),.v_bvalid(vbv),.v_bresp(vbresp),
  .v_araddr(vra),.v_arlen(8'd127),.v_arvalid(varv),.v_arready(varr),.v_rdata(vrd),.v_rresp(vrresp),.v_rlast(vrl),.v_rvalid(vrv),.v_rready(1'b1),
  .p_awaddr(law),.p_awlen(lawl),.p_awvalid(lawv),.p_awready(lawr),.p_wdata(lwd),.p_wlast(lwl),.p_wvalid(lwv),.p_wready(lwr),.p_bvalid(lbv),.p_bresp(lbresp),
  .p_araddr(lar),.p_arlen(larl),.p_arvalid(larv),.p_arready(larr),.p_rdata(lrd),.p_rresp(lrresp),.p_rlast(lrl),.p_rvalid(lrv),.p_rready(lrr),
  .m_awaddr(aw),.m_awlen(awl),.m_awvalid(awv),.m_awready(awr),.m_wdata(wd),.m_wstrb(),.m_wlast(wl),.m_wvalid(wv),.m_wready(wr),.m_bvalid(bv),.m_bresp(2'd0),.m_bready(br),
  .m_araddr(ar),.m_arlen(arl),.m_arvalid(arv),.m_arready(arr),.m_rdata(rd),.m_rresp(2'd0),.m_rlast(rb==rlen),.m_rvalid(rv),.m_rready(rr));
 always @(posedge clk)if(rst_n&&WITH_VIDEO)begin
  if(vwstate==0&&cycle>=next_write)begin vwstate<=1;write_started<=cycle;end
  if(vawv&&vawr)begin vwstate<=2;vwbeat<=0;end
  if(vwv&&vwr)begin vwbeat<=vwbeat+1'b1;if(vwbeat==127)vwstate<=3;end
  if(vbv)begin
   if(vwstate!=3||vbresp!=0)$fatal(1,"Video write ownership");
   vwstate<=0;next_write<=write_started+2560;video_writes<=video_writes+1;
   vwa<=vwa[23:0]==24'hfff800 ? 0 : vwa+2048;
   if(cycle-write_started>max_write_service)max_write_service<=cycle-write_started;
  end
  if(vrstate==0&&cycle>=next_read)begin vrstate<=1;read_started<=cycle;end
  if(varv&&varr)begin vrstate<=2;vrbeat<=0;end
  if(vrv)begin
   if(vrstate!=2||vrresp!=0||vrl!==(vrbeat==127)||vrd!==video_pattern(vra+vrbeat*16))$fatal(1,"Video read data/ownership");
   vrbeat<=vrbeat+1'b1;
   if(vrl)begin
    vrstate<=0;next_read<=read_started+1280;video_reads<=video_reads+1;
    vra<=vra[23:0]==24'hfff800 ? 32'h00800000 : vra+2048;
    if(cycle-read_started>max_read_service)max_read_service<=cycle-read_started;
   end
  end
  if((vrstate!=0&&cycle-read_started>1000)||(vwstate!=0&&cycle-write_started>1000))$fatal(1,"Video service deadline exceeded");
 end
 pose7_sd_card_tb #(.SDSC(1),.VOLUME_LBA(2048)) card(sdclk,co,ce,ci,do_,de,di,1'b0,1'b0);
 reg [527:0] expected_points;reg [31:0] expected_icrc,expected_hcrc;
 integer j;
 function [7:0] read_byte(input [31:0] address);
  begin
   if(address>=32'h02000000&&address<32'h02240000)read_byte=memory[address-32'h02000000];
   else if(address>=32'h01800000&&address<32'h01838400)read_byte=snapshot[address-32'h01800000];
   else if(address>=32'h01a00000&&address<32'h01a38400)read_byte=snapshot[230400+address-32'h01a00000];
   else if(address<32'h01000000)begin
    reg [127:0] pattern;
    pattern=video_pattern({address[31:4],4'b0});read_byte=pattern[address[3:0]*8+:8];
   end else begin $fatal(1,"DDR read out of range %h",address);read_byte=0;end
  end
 endfunction
 always @*begin
  rd=0;
  if(rs==1||rs==2)for(integer q=0;q<16;q=q+1)rd[q*8+:8]=read_byte(ra+rb*16+q);
 end
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;
  if(awv&&awr)begin
   if(aw[3:0]!=0||(awl!=0&&awl!=7&&awl!=127))$fatal(1,"write descriptor");
   wa<=aw;wlen<=awl;wb<=0;ws<=1;
  end
  if(wv&&wr)begin
   if(wl!==(wb==wlen))$fatal(1,"write last");
   for(j=0;j<16;j=j+1)begin
    if(wa>=32'h02000000&&wa+wb*16+j<32'h02240000)memory[wa-32'h02000000+wb*16+j]<=wd[j*8+:8];
    else if(wa>=32'h01800000&&wa+wb*16+j<32'h01838400)snapshot[wa-32'h01800000+wb*16+j]<=wd[j*8+:8];
    else if(wa>=32'h01a00000&&wa+wb*16+j<32'h01a38400)snapshot[230400+wa-32'h01a00000+wb*16+j]<=wd[j*8+:8];
    else if(wa<32'h01000000)begin
     if(wd!==video_pattern(wa+wb*16))$fatal(1,"Video DDR write corrupted");
    end else $fatal(1,"write range %h",wa);
   end
   wb<=wb+1'b1;if(wl)ws<=2;
  end
  if(bv&&br)ws<=0;
  if(arv&&arr)begin
   if(ar[3:0]!=0||(arl!=0&&arl!=7&&arl!=127))$fatal(1,"read descriptor");
   ra<=ar;rlen<=arl;rb<=0;rs<=1;delay_count<=cycle%3+1;
  end
  if(rs==1)begin if(delay_count!=0)delay_count<=delay_count-1;else rs<=2;end
  if(rv&&rr)begin rb<=rb+1'b1;if(rb==rlen)rs<=0;end
  if(publish&&result_valid)begin
   if(!result_valid||result_points!==expected_points||dut.heatmap_crc!==expected_hcrc||dut.result_input_crc!==expected_icrc)
    $fatal(1,"Live result differs from frozen integer oracle points=%h heat=%h input=%h",result_points,dut.heatmap_crc,dut.result_input_crc);
   live_count<=live_count+1;
   $display("PASS standalone live result %0d exact points/heatmap/input CRC cycle=%0d USB_blocked=%0d",live_count+1,cycle,txe);
  end
 end

 integer bank_capture_cycle[0:1];
 integer capture_start_cycle=0,input_capture_cycle=0,last_live_cycle=0;
 reg capturing_d=0;
 always @(posedge clk)begin
  capturing_d<=dut.u_snapshot.capturing;
`ifdef POSE7_LATEST_CANDIDATE
  if(dut.u_snapshot.capturing&&!capturing_d)bank_capture_cycle[dut.u_snapshot.write_bank]<=cycle;
  if(dut.state==1)input_capture_cycle<=bank_capture_cycle[dut.snapshot_read_base[21]];
  if(arv&&arr&&ar>=32'h01800000&&ar<32'h01c00000)begin
   if(!dut.u_snapshot.locked_valid||ar[21]!=dut.u_snapshot.locked_bank)$fatal(1,"pool read not protected by acquired bank");
  end
`else
  if(dut.u_snapshot.capturing&&!capturing_d)capture_start_cycle<=cycle;
  if(dut.state==1)input_capture_cycle<=capture_start_cycle;
`endif
  if(publish&&result_valid)begin
   if(input_capture_cycle<=0)$fatal(1,"missing acquired-frame timestamp");
   $display("PERF live cycle=%0d interval=%0d capture_to_result=%0d",cycle,cycle-last_live_cycle,cycle-input_capture_cycle);
   last_live_cycle<=cycle;
  end
 end

 integer packet_file,packet_bytes=0;
 always @(negedge ft_wr)if(rst_n)begin $fwrite(packet_file,"%c",ft_data);packet_bytes=packet_bytes+1;end
 task send(input [7:0] b);
  begin @(negedge clk);uart=b;uart_valid=1;@(negedge clk);uart_valid=0;repeat(5)@(negedge clk);end
 endtask
 reg [7:0] uart_reply[0:255];integer uart_count=0;
 always @(posedge clk)if(uart_tx_valid)begin uart_reply[uart_count]<=uart_tx_data;uart_count<=uart_count+1;end
 task query(input string command,input string expected);
  integer q;
  begin
   @(negedge clk);uart_count=0;
   for(q=0;q<command.len();q=q+1)send(command[q]);
   wait(!dut.debug_busy&&!dut.debug_start&&!uart_tx_valid);#1;
   if(uart_count!=expected.len())$fatal(1,"UART %s length got=%0d expected=%0d",command,uart_count,expected.len());
   for(q=0;q<uart_count;q=q+1)if(uart_reply[q]!==expected[q])$fatal(1,"UART %s byte=%0d got=%h expected=%h",command,q,uart_reply[q],expected[q]);
  end
 endtask
 task menu_command(input [4:0] address,input [11:0] value);
  begin @(negedge clk);menu_valid=1;menu_addr=address;menu_value=value;@(negedge clk);menu_valid=0;repeat(4)@(negedge clk);end
 endtask
 integer f,n,k,rc;
 initial begin
  for(k=0;k<32'h240000;k=k+1)memory[k]=8'ha5;
  f=$fopen("capture640.bin","rb");n=$fread(fixture,f);$fclose(f);if(n!=230400)$fatal(1,"fixture size");
  for(k=0;k<230400;k=k+1)snapshot[k]=8'h5a;
  f=$fopen("expected.vec","r");rc=$fscanf(f,"%h %h %h",expected_points,expected_icrc,expected_hcrc);$fclose(f);if(rc!=3)$fatal(1,"oracle file");
  packet_file=$fopen("standalone_points.bin","wb");
  #32;rst_n=1;
  wait(boot_status==1);@(negedge clk);reconfig_request=1;
  repeat(20)@(negedge clk);if(reconfig_idle)$fatal(1,"reconfiguration must wait for SD boot");
  wait(boot_status==3||boot_status==4);#1;
  if(boot_status!=3)$fatal(1,"Onboard self-test failed %h",boot_error);
  wait(reconfig_idle);#1;
  if(dut.sd_busy||dut.sd_start||dut.model_enabled||!dut.ddr_stopped)$fatal(1,"SD boot drain unsafe");
  @(negedge clk);reconfig_request=0;menu_command(1,1);
  $display("PASS image7 reconfiguration startup drain: request during actual SD read waits for SD completion, exact self-test and idle DDR/capture; model resumes explicitly");
  for(k=0;k<162592;k=k+1)if(memory[k]!==card.boot_file[128+k])$fatal(1,"SD-loaded model byte %0d",k);
  $display("PASS standalone SD4 -> DDR -> complete model -> onboard oracle self-test, no UART, no USB, cycle=%0d",cycle);
  if(PERF_ONLY)begin
   wait(live_count>=PERF_SAMPLES);repeat(10)@(negedge clk);
   if(packet_bytes!=0||boot_status!=3)$fatal(1,"live performance unexpectedly requires PC/USB");
   $display("PASS image7 live performance: four exact live results, SD startup, video contention and capture-to-result timestamps; no UART or USB");
   $finish;
  end
  query("~6S","SD INIT=1 FAT=1 STAGE=3 ERR=00 CMD=00 REASON=0\015\012");
  query("~6F","BIN FOUND=1 SIZE=00039BA0 HDR=1 CRC=1 BYTES=00039BA0\015\012");
  query("~6R","SD STOP_FIRST\015\012");
  wait(dut.state==4&&!dut.boot_testing);
  query("~6-","MODEL OFF\015\012");
  query("~6V","MODEL READY=1 TEST=1 ENABLE=0 BUSY=1 RUNS=00000000 ERR=00\015\012");
  query("~6R","SD BUSY\015\012");
  wait(dut.state==0);repeat(1000)@(negedge clk);
  if(dut.state!=0||dut.model_enabled||dut.infer_enable||live_count!=0)$fatal(1,"OFF did not quiesce/suppress pending result");
  query("~6V","MODEL READY=1 TEST=1 ENABLE=0 BUSY=0 RUNS=00000001 ERR=00\015\012");
  // A real file-missing retry must invalidate the old SD-ready and self-test.
  card.fault=1;query("~6R","SD RELOAD\015\012");wait(boot_status==4);#1;
  query("~6S","SD INIT=1 FAT=1 STAGE=4 ERR=04 CMD=00 REASON=0\015\012");
  query("~6F","BIN FOUND=0 SIZE=00000000 HDR=0 CRC=0 BYTES=00000000\015\012");
  query("~6+","MODEL NOT_READY\015\012");
  card.fault=0;query("~6R","SD RELOAD\015\012");wait(boot_status==3||boot_status==4);#1;
  if(boot_status!=3||dut.model_enabled||dut.infer_enable)$fatal(1,"Reload must run exact self-test but remain OFF");
  query("~6F","BIN FOUND=1 SIZE=00039BA0 HDR=1 CRC=1 BYTES=00039BA0\015\012");
  query("~6+","MODEL ON\015\012");
  $display("PASS integrated ASCII debug: actual SD/file milestones, OFF drains active network and hides results, reload rejects unsafe states, missing-file failure and recovery re-run exact self-test, ON resumes without USB");
  // Menu checks must perform real SD reads and numerical self-test, not
  // merely redisplay stale boot flags. Check under active network + DDR load.
  wait(dut.state==4&&!dut.boot_testing);
  card.fault=1;menu_command(16,0);
  if(dut.model_enabled||!menu_status[7])$fatal(1,"menu check did not stop/drain");
`ifdef POSE7_STABLE_CANDIDATE
  if(stable_check_feedback!=8'h12)$fatal(1,"SD CHECK did not acknowledge request");
`endif
  wait(boot_status==4 && dut.menu_check_state==0);#1;
  if(boot_error!=4||menu_status[6]||menu_status[2])$fatal(1,"menu missing BIN not reported");
  `ifdef POSE7_STABLE_CANDIDATE
  if(stable_check_feedback!=8'h14)$fatal(1,"SD should pass when FAT32 works but BIN is missing");
  menu_command(17,0);wait(dut.menu_check_state==0);#1;
  if(stable_check_feedback!=8'h2e||boot_error!=4)$fatal(1,"BIN CHECK must finish FAIL E04 with a new sequence");
`endif
  card.fault=0;menu_command(17,0);wait(boot_status==3 && dut.menu_check_state==0);#1;
  if(menu_status[6]||menu_status[7]||menu_status[5:0]!=6'h3f)$fatal(1,"menu recovery/self-test must stay OFF");
  menu_command(1,1);if(!dut.model_enabled)$fatal(1,"menu inference ON");
  wait(dut.state==4&&!dut.boot_testing);
  menu_command(17,0);wait(boot_status!=3);wait(boot_status==3 && dut.menu_check_state==0);#1;
  if(!menu_status[6]||!dut.infer_enable||menu_status[5:0]!=6'h3f)$fatal(1,"menu check did not restore ON");
  `ifdef POSE7_STABLE_CANDIDATE
  if(stable_check_feedback!=8'h4c)$fatal(1,"BIN completion feedback not sticky after repeated check");
  $display("PASS stable check feedback: accepted SD/BIN requests increment sequence, WAIT, independent SD PASS and BIN FAIL E04, recovery PASS, persistent completion");
`endif
  $display("PASS integrated menu: actual SD re-read, active inference drain, missing BIN fails OFF, valid BIN CRC and numerical self-test, preserve OFF, restore ON, real status flags");
  wait(live_count>=2);
  if(dut.point_available||packet_bytes!=0)$fatal(1,"Autonomous mode unexpectedly needs USB");
`ifdef POSE7_USB_CANDIDATE
  if(usb_points_enabled)$fatal(1,"USB stream not OFF at boot");
  menu_command(20,1);if(!usb_points_enabled)$fatal(1,"USB menu ON not applied");
  wait(live_count>=3);repeat(500)@(negedge clk);
  if(!dut.point_available||packet_bytes!=0)$fatal(1,"menu ON did not queue points without UART start");
  menu_command(20,0);repeat(500)@(negedge clk);
  if(usb_points_enabled||dut.point_available||!dut.tx_stopped||!dut.infer_enable)$fatal(1,"USB OFF blocked PHY or inference");
  wait(live_count>=4);if(packet_bytes||dut.point_available)$fatal(1,"OFF published or transmitted a new result");
  menu_command(20,1);
  $display("PASS USB menu runtime: boot OFF, menu ON without UART, backpressured queue OFF cancels, inference and HDMI point publication continue, ON resumes");
`endif
  send("!");send("3");@(negedge clk);mode=3;resolution=1;run_n=1;
`ifdef POSE7_USB_CANDIDATE
  wait(live_count>=6);
`else
  wait(live_count>=4);
`endif
  if(!dut.point_available||!txe)$fatal(1,"Missing backpressured USB test");
  @(negedge clk);reconfig_request=1;
  wait(reconfig_idle);repeat(200)@(negedge clk);
  if(dut.model_enabled||dut.infer_enable||result_valid||dut.sd_busy||dut.state!=0||!dut.ddr_stopped||!dut.mready)
   $fatal(1,"running inference did not drain before Flash CONFIG");
  if(!txe||!dut.point_available)$fatal(1,"missing blocked USB drain scenario");
  $display("PASS image7 reconfiguration live drain: in-flight inference, DDR and snapshot finish without AXI reset; blocked USB does not prevent safe Flash switch; stale skeleton cleared");
  txe=0;wait(packet_bytes>=114);#1;$fclose(packet_file);
  $display("PASS image7 standalone integration: full native SD4/SDSC, fragmented FAT32 boot, on-board numerical self-test, 1080p 3x3 and 640x360 input pool, repeated exact live inference with no PC and with blocked USB, resumed atomic USB packet");
  if(WITH_VIDEO)begin
   if(video_reads<1000||video_writes<1000)$fatal(1,"Insufficient video stress");
   $display("PASS contended DDR video: %0d reads/%0d writes of 128 beats; max request-to-completion %0d/%0d clocks; exact live model results preserved",video_reads,video_writes,max_read_service,max_write_service);
  end
  $finish;
 end
 initial begin #(64'd3000000000);$fatal(1,"Standalone integration timeout boot=%0d error=%h net=%0d count=%0d",boot_status,boot_error,dut.state,live_count);end
endmodule
