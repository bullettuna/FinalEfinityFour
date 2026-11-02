`timescale 1ns/1ps
module image7_ft_link_latest #(parameter WIDTH=1920,HEIGHT=1080,AUTO_BOOT=0,MENU_ENABLE=0,MULTIBOOT_ENABLE=0)(
 input sclk,input rst_n,input pclk,input run_n,input [1:0] mode,resolution,input edge_packed,input txe_n_async,
 input gray_vs,gray_de,input [7:0] gray_pixel,input edge_vs,edge_de,input [7:0] edge_pixel,
 input [7:0] uart_rx_data,input uart_rx_valid,output uart_legacy_valid,
 output uart_tx_last,
 input stop_for_reconfig,output reconfig_idle,
 input menu_write_valid,input [4:0] menu_write_addr,input [11:0] menu_write_value,
 output [15:0] menu_status,
 output uart_tx_valid,output [7:0] uart_tx_data,input uart_tx_accept,
 input [383:0] video_diagnostic_data,
 input ddr_ready,
 output sd_clk,sd_cmd_o,sd_cmd_oe,input sd_cmd_i,
 input [3:0] sd_dat_i,output [3:0] sd_dat_o,sd_dat_oe,
 output reg result_strobe,output reg [527:0] result_points,output reg result_valid,
 output [3:0] boot_status,output [7:0] boot_error,
 output link_ready,output stopped,output [7:0] data_o,output [7:0] data_oe,output wr_n,output wr_oe,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 `include "images/image7_mocap11_a/pose7_model_identity.vh"
 `include "images/image7_mocap11_a/pose7_boot_identity.vh"
 localparam IDLE=0,POOLSTART=1,POOLWAIT=2,NETSTART=3,NETWAIT=4,DECSTART=5,DECWAIT=6,SEND=7;
 wire reconfig_stopping=MULTIBOOT_ENABLE && stop_for_reconfig;
 reg [2:0] state;
 reg [31:0] cycles,result_cycles,result_input_crc;
 reg deterministic,point_available;
 reg [527:0] packet_points;
 reg [31:0] packet_cycles,packet_input_crc,packet_heatmap_crc;
 reg [7:0] packet_flags;
 reg auto_run,control_prefix,boot_testing,sd_start;
 reg [1:0] menu_check_state;reg menu_restore;
 wire menu_request=MENU_ENABLE && menu_write_valid && !reconfig_stopping;
 wire menu_check=menu_request && (menu_write_addr==16 || menu_write_addr==17);
 reg model_enabled;reg [31:0] live_results;
 reg [3:0] boot_state;reg [7:0] boot_failure;
 wire sd_busy,sd_done,sd_ready,sd_error;
 wire [7:0] sd_failure;
 wire sd_initialized,sd_fat_valid,sd_file_found,sd_header_valid,sd_crc_valid;
 wire [31:0] sd_file_size,sd_read_bytes;wire [5:0] sd_command;wire [3:0] sd_reason;
 wire sv,sw;wire [31:0] saddr;wire [127:0] sdata;
 reg [2:0] init;
 always @(posedge sclk or negedge rst_n)if(!rst_n)init<=0;else init<={init[1:0],1'b1};
 assign link_ready=init[2];
 wire model_ready,uart_model_ready,input_ready,test_start;
 wire [31:0] model_crc,uart_model_crc,uploaded_input_crc,pool_input_crc,heatmap_crc;
 assign model_ready=uart_model_ready||boot_state==3;
 assign model_crc=uart_model_ready?uart_model_crc:POSE6_MODEL_CRC;
 assign boot_status=AUTO_BOOT?boot_state:(model_ready?4'd3:4'd0);
 assign boot_error=boot_failure;
 wire [527:0] points;
 wire [31:0] snapshot_read_base;
 wire snapshot_available,snapshot_release,ddr_stopped,snapshot_fault,snapshot_valid;
 wire [20:0] snapshot_address;wire [7:0] snap_data;wire [15:0] width,height;
 wire [31:0] sa,sa_r;wire [7:0] sl,sl_r;wire sav,sar,srv,srr,swv,swr,swlast,sbv;
 wire [127:0] swdata,srdata;wire [1:0] sbresp,srresp;wire srlast;
 wire pose_mode=model_ready&&((AUTO_BOOT&&auto_run)||mode==3&&resolution==1);
 wire infer_enable=!reconfig_stopping&&menu_check_state==0&&model_enabled&&model_ready&&((AUTO_BOOT&&auto_run)||run_n&&mode==3&&resolution==1);
 wire packet_release,legacy_release;
 wire s_rvalid,s_rready;
 pose7_latest_snapshot #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_snapshot(
  .clk(sclk),.rst_n(rst_n),.pclk(pclk),.enable(!reconfig_stopping&&(infer_enable||run_n&&mode>1)),.edge_mode(pose_mode||mode==3),.resolution(pose_mode?2'd1:resolution),
  .vs(pose_mode||mode==3?edge_vs:gray_vs),.de(pose_mode||mode==3?edge_de:gray_de),.pixel(pose_mode||mode==3?edge_pixel:gray_pixel),
  .latest_mode(pose_mode),.acquire_frame(state==POOLSTART),.read_base(snapshot_read_base),
  .available(snapshot_available),.release_frame(snapshot_release),.stopped(ddr_stopped),.fault(snapshot_fault),
  .address(snapshot_address),.byte_data(snap_data),.byte_valid(snapshot_valid),.frame_width(width),.frame_height(height),
  .awaddr(sa),.awlen(sl),.awvalid(sav),.awready(sar),.wdata(swdata),.wlast(swlast),.wvalid(swv),.wready(swr),.bvalid(sbv),.bresp(sbresp),
  .araddr(sa_r),.arlen(sl_r),.arvalid(srv),.arready(srr),.rdata(srdata),.rresp(srresp),.rlast(srlast),.rvalid(s_rvalid),.rready(s_rready));
 wire pool_done,net_done,decode_done,net_fault,master_fault;
 wire lv,lw,pv,pw,nv,nw,dv,dw;
 wire [31:0] la,pa,na,da;wire [127:0] ld,pd,nd,dd;
 wire mv,mready,mwrite,response_valid;wire [31:0] ma;wire [127:0] md,response_data;
 wire pooling=state==POOLSTART||state==POOLWAIT;
 wire networking=state==NETSTART||state==NETWAIT;
 wire decoding=state==DECSTART||state==DECWAIT;
 wire loading=state==IDLE;
 wire sd_owner=sd_busy||sd_start;
 generate if(AUTO_BOOT)begin:g_sd_boot
  pose7_sd_boot u_sd_boot(.clk(sclk),.rst_n(rst_n),.start(sd_start),.busy(sd_busy),.done(sd_done),.ready(sd_ready),.error(sd_error),
   .error_code(sd_failure),.error_command(sd_command),.sd_error_reason(sd_reason),
   .sd_clk(sd_clk),.sd_cmd_o(sd_cmd_o),.sd_cmd_oe(sd_cmd_oe),.sd_cmd_i(sd_cmd_i),.sd_dat_i(sd_dat_i),.sd_dat_o(sd_dat_o),.sd_dat_oe(sd_dat_oe),
   .command_valid(sv),.command_ready(mready&&sd_owner),.command_write(sw),.command_address(saddr),.command_data(sdata),
   .response_valid(response_valid&&sd_owner),.memory_fault(master_fault),
   .card_initialized(sd_initialized),.fat_valid(sd_fat_valid),.file_found(sd_file_found),
   .header_valid(sd_header_valid),.crc_valid(sd_crc_valid),.file_size(sd_file_size),.read_bytes(sd_read_bytes));
 end else begin:g_no_sd_boot
  assign sd_busy=0;assign sd_done=0;assign sd_ready=0;assign sd_error=0;assign sd_failure=0;
  assign sv=0;assign sw=0;assign saddr=0;assign sdata=0;
  assign sd_initialized=0;assign sd_fat_valid=0;assign sd_file_found=0;assign sd_header_valid=0;assign sd_crc_valid=0;
  assign sd_file_size=0;assign sd_read_bytes=0;assign sd_command=0;assign sd_reason=0;
  assign sd_clk=0;assign sd_cmd_o=1;assign sd_cmd_oe=0;assign sd_dat_o=4'hf;assign sd_dat_oe=0;
 end endgenerate
 wire loader_tx_valid,loader_busy,diagnostic_valid,diagnostic_busy,diagnostic_start;
 wire [7:0] loader_tx_data,diagnostic_byte;
 wire debug_start,debug_busy,debug_valid;wire [7:0] debug_opcode,debug_byte;
 wire [1:0] reload_reply=!AUTO_BOOT?2'd3:reconfig_stopping?2'd2:model_enabled?2'd1:
    (!ddr_ready||state!=IDLE||sd_owner||boot_state==1||boot_state==2||!mready)?2'd2:2'd0;
 wire menu_reload=menu_check_state==1 && reload_reply==0 && !diagnostic_busy && !debug_busy && !loader_busy;
 wire reload_accept=(debug_start&&debug_opcode=="R"&&reload_reply==0)||menu_reload;
 assign menu_status={boot_failure,(menu_check_state!=0||sd_owner||boot_state==2),model_enabled,
                     (AUTO_BOOT&&boot_state==3),sd_crc_valid,sd_header_valid,sd_file_found,sd_fat_valid,sd_initialized};
 wire diagnostic_last,debug_last;
 assign uart_tx_last=diagnostic_valid?diagnostic_last:debug_valid?debug_last:1'b1;
 assign uart_tx_valid=loader_tx_valid||diagnostic_valid||debug_valid;
 assign uart_tx_data=diagnostic_valid?diagnostic_byte:debug_valid?debug_byte:loader_tx_data;
 pose7_diag_packet u_diagnostic(.clk(sclk),.rst_n(rst_n),.start(diagnostic_start),.data(video_diagnostic_data),
  .busy(diagnostic_busy),.last(diagnostic_last),.valid(diagnostic_valid),.byte_data(diagnostic_byte),.ready(uart_tx_accept));
 pose7_debug_uart u_debug(.clk(sclk),.rst_n(rst_n),.start(debug_start),.opcode(debug_opcode),.reload_reply(reload_reply),
  .card_initialized(sd_initialized),.fat_valid(sd_fat_valid),.file_found(sd_file_found),.header_valid(sd_header_valid),.crc_valid(sd_crc_valid),
  .model_ready(model_ready&&menu_check_state==0&&!reconfig_stopping),.self_test_pass(AUTO_BOOT&&boot_state==3),.enabled(model_enabled),.model_busy(state!=IDLE||sd_owner||menu_check_state!=0),
  .boot_stage(boot_status),.error_code(boot_failure),.sd_command(sd_command),.sd_reason(sd_reason),
  .file_size(sd_file_size),.read_bytes(sd_read_bytes),.runs(live_results),
  .busy(debug_busy),.last(debug_last),.valid(debug_valid),.data(debug_byte),.ready(uart_tx_accept&&!diagnostic_valid));
 pose7_uart_loader #(.MODEL_BYTES(POSE6_MODEL_BYTES),.EXPECTED_MODEL_CRC(POSE6_MODEL_CRC)) u_loader(
  .clk(sclk),.rst_n(rst_n),.rx_data(uart_rx_data),.rx_valid(uart_rx_valid&&!reconfig_stopping),.legacy_rx_valid(uart_legacy_valid),
  .busy(loader_busy),.can_load(!reconfig_stopping&&menu_check_state==0&&loading&&!sd_owner&&!run_n&&!point_available&&!diagnostic_busy&&(!AUTO_BOOT||boot_state>=3)&&!auto_run),.clear_input(state==POOLSTART),
  .model_ready(uart_model_ready),.input_ready(input_ready),.test_start(test_start),.model_crc(uart_model_crc),.input_crc(uploaded_input_crc),
  .tx_valid(loader_tx_valid),.tx_data(loader_tx_data),.tx_accept(uart_tx_accept&&!diagnostic_valid&&!debug_valid),
  .command_valid(lv),.command_ready(mready&&loading),.command_write(lw),.command_address(la),.command_data(ld),
  .response_valid(response_valid&&loading),.memory_fault(master_fault),
  .diagnostic_busy(diagnostic_busy),.diagnostic_start(diagnostic_start),.external_model_ready(boot_state==3),
  .debug_busy(debug_busy),.invalidate_model(reload_accept),.debug_start(debug_start),.debug_opcode(debug_opcode));
 pose7_input_pool_latest u_pool(.source_base(snapshot_read_base),.clk(sclk),.rst_n(rst_n),.start(state==POOLSTART),.busy(),.done(pool_done),.input_crc(pool_input_crc),
  .command_valid(pv),.command_ready(mready&&pooling),.command_write(pw),.command_address(pa),.command_data(pd),
  .response_valid(response_valid&&pooling),.response_data(response_data));
 pose7_network_fast u_network(.clk(sclk),.rst_n(rst_n),.start(state==NETSTART),.busy(),.done(net_done),.fault(net_fault),
  .command_valid(nv),.command_ready(mready&&networking),.command_write(nw),.command_address(na),.command_data(nd),
  .response_valid(response_valid&&networking),.response_data(response_data));
 pose7_decode u_decode(.clk(sclk),.rst_n(rst_n),.start(state==DECSTART),.busy(),.done(decode_done),.points(points),.heatmap_crc(heatmap_crc),
  .command_valid(dv),.command_ready(mready&&decoding),.command_write(dw),.command_address(da),.command_data(dd),
  .response_valid(response_valid&&decoding),.response_data(response_data));
 assign mv=sd_owner?sv:pooling?pv:networking?nv:decoding?dv:loading?lv:1'b0;
 assign mwrite=sd_owner?sw:pooling?pw:networking?nw:decoding?dw:lw;
 assign ma=sd_owner?saddr:pooling?pa:networking?na:decoding?da:la;
 assign md=sd_owner?sdata:pooling?pd:networking?nd:decoding?dd:ld;
 wire [31:0] ma_w,ma_r;wire [7:0] ml_w,ml_r;wire mav_w,mar_w,mav_r,mar_r;
 wire [127:0] mwdata,mrdata;wire mwlast,mwv,mwr,mbv,mrv,mrr,mrlast;wire [1:0] mbresp,mrresp;
 pose7_axi_master u_master(.clk(sclk),.rst_n(rst_n),.command_valid(mv),.command_ready(mready),.command_write(mwrite),
  .command_address(ma),.command_data(md),.response_valid(response_valid),.response_data(response_data),.fault(master_fault),
  .awaddr(ma_w),.awlen(ml_w),.awvalid(mav_w),.awready(mar_w),.wdata(mwdata),.wlast(mwlast),.wvalid(mwv),.wready(mwr),.bvalid(mbv),.bresp(mbresp),
  .araddr(ma_r),.arlen(ml_r),.arvalid(mav_r),.arready(mar_r),.rdata(mrdata),.rresp(mrresp),.rlast(mrlast),.rvalid(mrv),.rready(mrr));
 photo_axi_mux u_pose_axi_mux(.clk(sclk),.rst_n(rst_n),.v_read_flush(1'b0),.v_read_urgent(1'b0),.read_stalled(),.read_debug(),
  .v_awaddr(sa),.v_awlen(sl),.v_awvalid(sav),.v_awready(sar),.v_wdata(swdata),.v_wstrb(16'hffff),.v_wlast(swlast),.v_wvalid(swv),.v_wready(swr),.v_bvalid(sbv),.v_bresp(sbresp),
  .v_araddr(sa_r),.v_arlen(sl_r),.v_arvalid(srv),.v_arready(srr),.v_rdata(srdata),.v_rresp(srresp),.v_rlast(srlast),.v_rvalid(s_rvalid),.v_rready(s_rready),
  .p_awaddr(ma_w),.p_awlen(ml_w),.p_awvalid(mav_w),.p_awready(mar_w),.p_wdata(mwdata),.p_wlast(mwlast),.p_wvalid(mwv),.p_wready(mwr),.p_bvalid(mbv),.p_bresp(mbresp),
  .p_araddr(ma_r),.p_arlen(ml_r),.p_arvalid(mav_r),.p_arready(mar_r),.p_rdata(mrdata),.p_rresp(mrresp),.p_rlast(mrlast),.p_rvalid(mrv),.p_rready(mrr),
  .m_awaddr(awaddr),.m_awlen(awlen),.m_awvalid(awvalid),.m_awready(awready),.m_wdata(wdata),.m_wstrb(),.m_wlast(wlast),.m_wvalid(wvalid),.m_wready(wready),.m_bvalid(bvalid),.m_bresp(bresp),.m_bready(),
  .m_araddr(araddr),.m_arlen(arlen),.m_arvalid(arvalid),.m_arready(arready),.m_rdata(rdata),.m_rresp(rresp),.m_rlast(rlast),.m_rvalid(rvalid),.m_rready(rready));
 assign snapshot_release=pool_done||(!pose_mode&&!pooling&&legacy_release);
 wire legacy_valid,legacy_ready;wire [7:0] legacy_data,packed_data;wire packed_valid;
 wire [20:0] payload_address;
 ft_edge_pack u_pack(.clk(sclk),.rst_n(rst_n&&run_n&&!pose_mode),.enable(mode==3&&edge_packed),.byte_address(payload_address),
  .pixel_address(snapshot_address),.pixel_data(snap_data),.pixel_valid(snapshot_valid),.packed_data(packed_data),.packed_valid(packed_valid));
 ft_packet_source u_legacy_packet(.clk(sclk),.rst_n(rst_n&&run_n&&!pose_mode),.mode(mode),.edge_packed(edge_packed),.frame_width(width),.frame_height(height),
  .snapshot_available(snapshot_available&&!pose_mode),.snapshot_valid(packed_valid),.snapshot_release(legacy_release),
  .snapshot_address(payload_address),.snapshot_data(packed_data),.valid(legacy_valid),.data(legacy_data),.ready(legacy_ready));
 wire point_valid,tx_ready;wire [7:0] point_data;
 pose7_packet u_packet(.clk(sclk),.rst_n(rst_n),.available(point_available),.release_result(packet_release),.points(packet_points),
  .cycles(packet_cycles),.model_crc(model_crc),.input_crc(packet_input_crc),.heatmap_crc(packet_heatmap_crc),.flags(packet_flags),
  .valid(point_valid),.data(point_data),.ready(tx_ready));
 wire tx_stopped;
 assign legacy_ready=tx_ready&&!point_valid;
 ft245_async_tx u_tx(.clk(sclk),.rst_n(rst_n),.run_enable(run_n||point_available),.txe_n_async(txe_n_async),
  .valid(point_valid||legacy_valid),.data(point_valid?point_data:legacy_data),.ready(tx_ready),.data_o(data_o),.data_oe(data_oe),.wr_n(wr_n),.wr_oe(wr_oe),.stopped(tx_stopped));
 assign reconfig_idle=state==IDLE&&mready&&!sd_owner&&ddr_stopped&&menu_check_state==0&&!loader_busy&&!debug_busy&&!diagnostic_busy&&(!AUTO_BOOT||boot_state>=3);
 // In autonomous pose mode, USB settings do not own the capture/model DDR
 // clients. A host mode change only waits for its physical packet to finish.
 // Flash reconfiguration still uses the stricter reconfig_idle above.
 assign stopped=tx_stopped&&!point_available&&
   ((AUTO_BOOT&&auto_run&&model_ready)?!legacy_valid:
    (ddr_stopped&&state==IDLE&&mready&&!sd_owner&&(!AUTO_BOOT||boot_state>=3)));
 always @(posedge sclk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;cycles<=0;result_cycles<=0;result_input_crc<=0;deterministic<=0;point_available<=0;
   packet_points<=0;packet_cycles<=0;packet_input_crc<=0;packet_heatmap_crc<=0;packet_flags<=0;
   auto_run<=AUTO_BOOT!=0;control_prefix<=0;boot_testing<=0;sd_start<=0;boot_state<=0;boot_failure<=0;
   menu_check_state<=0;menu_restore<=0;
   model_enabled<=1;live_results<=0;
   result_strobe<=0;result_points<=0;result_valid<=0;end
  else begin
   sd_start<=0;result_strobe<=!model_enabled;
   // Repeat OFF invalidation until ON, so an occupied display CDC mailbox
   // cannot lose the one-shot clear and leave a stale skeleton visible.
   if(!model_enabled)result_valid<=0;
   if(packet_release)point_available<=0;
   // Explicit FT mode commands take manual ownership; Z/C/G/E remain views.
   if(uart_legacy_valid)begin
    if(control_prefix)begin control_prefix<=0;if(uart_rx_data>="0"&&uart_rx_data<="7")auto_run<=0;end
    else if(uart_rx_data=="!")control_prefix<=1;
   end
   if(AUTO_BOOT&&boot_state==0&&ddr_ready)begin sd_start<=1;boot_state<=1;end
   if(AUTO_BOOT&&boot_state==1&&!sd_start&&sd_error)begin boot_state<=4;boot_failure<=sd_failure;end
   if(state!=IDLE)cycles<=cycles+1'b1;
   case(state)
    IDLE:if(AUTO_BOOT&&boot_state==1&&sd_done)begin
      boot_testing<=1;boot_state<=2;deterministic<=1;cycles<=0;result_input_crc<=POSE6_TEST_INPUT_CRC;state<=NETSTART;
     end else if(test_start&&!reconfig_stopping)begin deterministic<=1;cycles<=0;result_input_crc<=uploaded_input_crc;state<=NETSTART;end
     else if(infer_enable&&snapshot_available)begin deterministic<=0;cycles<=0;state<=POOLSTART;end
    POOLSTART:state<=POOLWAIT;
    POOLWAIT:if(pool_done)begin result_input_crc<=pool_input_crc;state<=NETSTART;end
    NETSTART:state<=NETWAIT;
    NETWAIT:if(net_done)state<=DECSTART;
    DECSTART:state<=DECWAIT;
    DECWAIT:if(decode_done)begin
     result_cycles<=cycles;state<=IDLE;
     if(boot_testing)begin
      boot_testing<=0;
      if(points==POSE6_TEST_POINTS&&heatmap_crc==POSE6_TEST_HEATMAP_CRC&&!net_fault&&!master_fault)boot_state<=3;
      else begin boot_state<=4;boot_failure<=8'h30;end
     end else begin
      if(!deterministic)begin
       live_results<=live_results+1'b1;
       if(model_enabled)begin result_strobe<=1;result_points<=points;result_valid<=model_ready&&!net_fault&&!master_fault;end
      end
      // A stalled USB packet owns its own immutable copy. Drop intermediate
      // USB results instead of making the network wait for a USB receiver.
      if(!point_available&&!packet_release&&(deterministic||model_enabled&&run_n&&pose_mode))begin
       point_available<=1;packet_points<=points;packet_cycles<=cycles;
       packet_input_crc<=result_input_crc;packet_heatmap_crc<=heatmap_crc;
       packet_flags<={4'd0,deterministic,(master_fault||net_fault),1'b1,model_ready};
      end
     end
    end
   endcase
   // Stop inhibits new work immediately; an in-flight DDR operation drains.
   // The final assignment also invalidates the displayed points on the command cycle.
   if(debug_start&&debug_opcode=="-")begin model_enabled<=0;result_strobe<=1;result_valid<=0;end
   if(debug_start&&debug_opcode=="+"&&model_ready&&menu_check_state==0)begin model_enabled<=1;if(AUTO_BOOT)auto_run<=1;end
   // Check actions drain the current inference, reload the actual file, verify
   // CRC and run the frozen integer self-test. Restore ON only after success.
   if(menu_check && menu_check_state==0)begin
    menu_check_state<=1;menu_restore<=model_enabled;model_enabled<=0;
    result_strobe<=1;result_valid<=0;
   end
   if(menu_reload)menu_check_state<=2;
   if(menu_check_state==2 && (boot_state==3||boot_state==4))begin
    menu_check_state<=0;
    if(boot_state==3 && menu_restore)begin model_enabled<=1;auto_run<=1;end
   end
   if(menu_request && menu_write_addr==1)begin
    if(!menu_write_value[0])begin model_enabled<=0;menu_restore<=0;result_strobe<=1;result_valid<=0;end
    else if(model_ready && menu_check_state==0)begin model_enabled<=1;auto_run<=1;end
   end
   if(debug_start&&debug_opcode=="-")menu_restore<=0;
   if(reload_accept)begin boot_state<=0;boot_failure<=0;result_strobe<=1;result_valid<=0;end
   if(reconfig_stopping)begin model_enabled<=0;result_strobe<=1;result_valid<=0;end

  end
 end
endmodule
