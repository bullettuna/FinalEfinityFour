`timescale 1ns/1ps
// b -> complete DDR frame -> optional gray/Canny processing -> FAT32 BMP.
// Keep the saved frame until its successor has committed. Failed saves are
// retained; a subsequent b retries that same frame instead of overwriting it.
module photo_native_pipeline #(parameter CLK_HZ=96000000,WIDTH=960,HEIGHT=540,
 parameter DDR_TIMEOUT=CLK_HZ/20,DDR_RECOVERY_TIMEOUT=CLK_HZ/2,
 parameter SAVE_WAIT_TIMEOUT=CLK_HZ*2,RECOVERY_TIMEOUT=CLK_HZ,
 parameter ENABLE_DELETE=0,DELETE_CONFIRM_CYCLES=CLK_HZ*5,ENABLE_PROCESSING=0,ENABLE_UART_EXPORT=0)(
 input clk,input rst_n,input pclk,input prst_n,input capture_req,input query_req,
 input delete_req,input uart_capture_req,
 output frame_tx_valid,output [7:0] frame_tx_data,output frame_tx_last,input frame_tx_accept,input frame_tx_done,
 input axi_read_stalled,input [3:0] axi_read_debug,
 output reg capture_accepted,
 input in_vsync,input in_href,input [7:0] red,green,blue,
 input [1:0] capture_mode,input median_enable,input [1:0] cleanup_level,
 input [10:0] min_pixels,high_threshold,low_threshold,
 input gallery_toggle_req,input gallery_prev_req,input gallery_next_req,
 input gallery_ddr_busy,
 input gallery_ddr_failed,input gallery_abort,input gallery_ready,
 input gallery_display_error,
 output gallery_mode,output gallery_busy,output gallery_error,output [31:0] gallery_file_number,
 output gallery_load_start,output gallery_load_byte_valid,output [7:0] gallery_load_byte,
 output [19:0] gallery_load_byte_offset,output gallery_load_done,output gallery_load_error,
 output tx_valid,output [7:0] tx_data,output tx_last,input tx_accept,input tx_done,
 output sd_clk,output sd_cmd_o,output sd_cmd_oe,input sd_cmd_i,
 input [3:0] sd_dat_i,output [3:0] sd_dat_o,output [3:0] sd_dat_oe,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 localparam IDLE=0,CAPTURE=1,SAVE=2,FAULT=3,RECOVER=4,DELETE=5,DELETE_FAULT=6,PROCESS=7,EXPORT=8;
 reg [3:0] state;
 reg uart_capture,export_start;
 wire export_done,export_busy,export_error;
 wire uart_request=ENABLE_UART_EXPORT && uart_capture_req;
 wire capture_command=capture_req||uart_request;
 reg capture_toggle,dma_start,slot,retained,retained_slot,retained_saved;
 reg save_start,query_start,query_busy;
 reg [31:0] capture_timer;
 reg [1:0] photo_mode,photo_cleanup;
 reg photo_median,process_start,open_saved_photo;
 reg [31:0] open_saved_number;
 reg [10:0] photo_minimum,photo_high,photo_low;
 wire process_busy,process_done,process_error;
 wire dma_busy,dma_done,dma_error,save_busy,save_done,save_error;
 wire [7:0] save_error_code;wire [31:0] file_number;
 wire report_room;reg event_valid,event_critical;reg [3:0] event_kind;reg [7:0] event_code;
 reg [5:0] event_command;reg [3:0] event_reason;
 reg [3:0] event_stage,event_rd,event_axi;reg [5:0] event_beats;
 reg [31:0] recovery_timer;
 reg delete_armed,delete_start,reader_reload,gallery_visible_ready,refresh_pending;
 reg confirm_prompt_sent;
 wire confirmation_sent;wire [16:0] confirmation_file_number;
 reg [31:0] delete_target,confirm_timer;
 reg [16:0] event_file_number;
 wire delete_done,delete_error,delete_mutated,gallery_empty;
 wire delete_command=ENABLE_DELETE && delete_req;
 wire save_owner=state==CAPTURE||state==PROCESS||state==SAVE||state==RECOVER||state==DELETE||state==DELETE_FAULT;
 wire gallery_storage_busy=gallery_ddr_busy;
 reg gallery_failed_seen,gallery_mode_seen;
 reg display_failure_reported;
 wire gallery_admit=state==IDLE&&!query_busy&&!capture_command&&!query_req&&!gallery_storage_busy&&!delete_command&&!refresh_pending;
 wire gallery_navigation=gallery_toggle_req||gallery_prev_req||gallery_next_req;
 wire open_saved_admit=open_saved_photo&&gallery_admit&&!gallery_navigation;
 (* async_reg="true" *) reg cap1,cap2;
 reg cap3,cap4;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin cap1<=0;cap2<=0;cap3<=0;cap4<=0;end
  else begin cap1<=capture_toggle;cap2<=cap1;cap3<=cap2;cap4<=cap3;end
 end
 wire pixel_valid,pixel_active,pixel_done;
 wire [15:0] pixel_data;wire [9:0] pixel_x;wire [8:0] pixel_y;
 generate if(ENABLE_PROCESSING)begin : g_capture_modes
 assign pixel_x=0;assign pixel_y=0;
 photo_capture_modes #(.IN_WIDTH(WIDTH*2),.IN_HEIGHT(HEIGHT*2)) sampler(
  // The mode payload has two pixel-domain settling clocks before this request
  // can arm a frame, including a request coincident with a frame boundary.
  .clk(pclk),.rst_n(prst_n),.capture_toggle(cap4),.mode_req(photo_mode),
  .in_vsync(in_vsync),.in_href(in_href),.red(red),.green(green),.blue(blue),
  .capture_active(pixel_active),.capture_done_toggle(pixel_done),.pixel_valid(pixel_valid),.pixel_rgb565(pixel_data));
 end else begin : g_capture_legacy
 photo_capture_2x_rgb565 #(.IN_WIDTH(WIDTH*2),.IN_HEIGHT(HEIGHT*2)) sampler(
  .clk(pclk),.rst_n(prst_n),.capture_toggle(cap2),.in_vsync(in_vsync),.in_href(in_href),
  .in_red(red),.in_green(green),.in_blue(blue),.capture_active(pixel_active),
  .capture_done_toggle(pixel_done),.pixel_valid(pixel_valid),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_rgb565(pixel_data));
 end endgenerate
 wire photo_start,photo_done,photo_error,photo_valid;
 wire export_read_start;wire [19:0] export_read_offset;
 wire [19:0] photo_offset;
 wire [8:0] photo_index;wire [7:0] photo_byte;
 wire photo_read_busy,photo_reset_required;wire [3:0] photo_read_debug,photo_read_fault;
 wire [5:0] photo_read_beats;
 wire [31:0] d_awaddr,d_araddr,p_awaddr,p_araddr;
 wire [7:0] d_awlen,d_arlen,p_awlen,p_arlen;
 wire [127:0] d_wdata,p_wdata;
 wire d_awvalid,d_wvalid,d_wlast,d_arvalid,d_rready;
 wire p_awvalid,p_wvalid,p_wlast,p_arvalid,p_rready;
 generate if(ENABLE_UART_EXPORT)begin : g_uart_export
 photo_uart_export #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_export(
  .clk(clk),.rst_n(rst_n),.start(export_start),.mode(photo_mode),.median_enable(photo_median),
  .cleanup_level(photo_cleanup),.min_pixels(photo_minimum),.high_threshold(photo_high),.low_threshold(photo_low),
  .busy(export_busy),.done(export_done),.error(export_error),.read_start(export_read_start),.read_offset(export_read_offset),
  .read_done(photo_done),.read_error(photo_error),.read_valid(photo_valid),.read_index(photo_index),.read_byte(photo_byte),
  .tx_valid(frame_tx_valid),.tx_data(frame_tx_data),.tx_last(frame_tx_last),.tx_accept(frame_tx_accept),.tx_done(frame_tx_done));
 end else begin : g_no_uart_export
 assign export_busy=0;assign export_done=0;assign export_error=0;assign export_read_start=0;assign export_read_offset=0;
 assign frame_tx_valid=0;assign frame_tx_data=0;assign frame_tx_last=0;
 end endgenerate
 wire processing_owner=ENABLE_PROCESSING&&(state==PROCESS||process_busy);
 assign awaddr=processing_owner?p_awaddr:d_awaddr;assign awlen=processing_owner?p_awlen:d_awlen;
 assign awvalid=processing_owner?p_awvalid:d_awvalid;assign wdata=processing_owner?p_wdata:d_wdata;
 assign wvalid=processing_owner?p_wvalid:d_wvalid;assign wlast=processing_owner?p_wlast:d_wlast;
 assign araddr=processing_owner?p_araddr:d_araddr;assign arlen=processing_owner?p_arlen:d_arlen;
 assign arvalid=processing_owner?p_arvalid:d_arvalid;assign rready=processing_owner?p_rready:d_rready;
 generate if(ENABLE_PROCESSING)begin : g_frame_processing
 photo_frame_process #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.MEM_TIMEOUT(DDR_RECOVERY_TIMEOUT)) u_process(
  .clk(clk),.rst_n(rst_n),.start(process_start),.buffer_select(slot),.mode(photo_mode),
  .median_enable(photo_median),.cleanup_level(photo_cleanup),.min_pixels(photo_minimum),
  .high_threshold(photo_high),.low_threshold(photo_low),.busy(process_busy),.done(process_done),.error(process_error),.debug_stage(),
  .awaddr(p_awaddr),.awlen(p_awlen),.awvalid(p_awvalid),.awready(awready&&processing_owner),
  .wdata(p_wdata),.wlast(p_wlast),.wvalid(p_wvalid),.wready(wready&&processing_owner),
  .bvalid(bvalid&&processing_owner),.bresp(bresp),.araddr(p_araddr),.arlen(p_arlen),.arvalid(p_arvalid),
  .arready(arready&&processing_owner),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid&&processing_owner),.rready(p_rready));
 end else begin : g_no_frame_processing
 assign process_busy=0;assign process_done=0;assign process_error=0;
 assign p_awaddr=0;assign p_awlen=0;assign p_awvalid=0;assign p_wdata=0;assign p_wlast=0;assign p_wvalid=0;
 assign p_araddr=0;assign p_arlen=0;assign p_arvalid=0;assign p_rready=0;
 end endgenerate
 photo_ddr_dma #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.READ_TIMEOUT(DDR_TIMEOUT),.RECOVERY_TIMEOUT(DDR_RECOVERY_TIMEOUT)) dma(
  .clk(clk),.rst_n(rst_n),.pclk(pclk),.prst_n(prst_n),.start(dma_start),.buffer_select(slot),
  .busy(dma_busy),.done(dma_done),.error(dma_error),.pixel_valid(pixel_valid),.pixel_data(pixel_data),
  .pixel_active(pixel_active),.pixel_done_toggle(pixel_done),
  .read_start(state==EXPORT?export_read_start:photo_start),.read_buffer(state==EXPORT?slot:retained_slot),.read_offset(state==EXPORT?export_read_offset:photo_offset),.read_done(photo_done),
  .read_error(photo_error),.read_valid(photo_valid),.read_index(photo_index),.read_byte(photo_byte),
  .read_busy(photo_read_busy),.read_debug(photo_read_debug),.read_beats(photo_read_beats),
  .read_fault(photo_read_fault),.read_reset_required(photo_reset_required),
  .awaddr(d_awaddr),.awlen(d_awlen),.awvalid(d_awvalid),.awready(awready&&!processing_owner),
  .wdata(d_wdata),.wlast(d_wlast),.wvalid(d_wvalid),.wready(wready&&!processing_owner),.bvalid(bvalid&&!processing_owner),.bresp(bresp),
  .araddr(d_araddr),.arlen(d_arlen),.arvalid(d_arvalid),.arready(arready&&!processing_owner),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid&&!processing_owner),.rready(d_rready));
 wire wi,wb,ww,ri,rb,rw;wire [31:0] wl,rl;wire [7:0] wt,rt;
 wire hi_busy,hi_done,hi_error,hb_busy,hb_done,hb_error,hrvalid;
 wire [7:0] hrdata;wire [8:0] hindex;
 wire high_capacity,initialized;wire [31:0] capacity_mb;
 wire [5:0] host_error_command;wire [3:0] host_error_reason;
 sd4_host #(.CLK_HZ(CLK_HZ),.INIT_DIV(CLK_HZ/800000),.FAST_DIV(8),.POWER_CYCLES(CLK_HZ/100),.DATA_TIMEOUT(CLK_HZ/2)) host(
  .clk(clk),.rst_n(rst_n),.sd_clk(sd_clk),.sd_cmd_o(sd_cmd_o),.sd_cmd_oe(sd_cmd_oe),.sd_cmd_i(sd_cmd_i),
  .sd_dat_i(sd_dat_i),.sd_dat_o(sd_dat_o),.sd_dat_oe(sd_dat_oe),
  .init_start(query_start||(save_owner?wi:ri)),.init_busy(hi_busy),.init_done(hi_done),.init_error(hi_error),
  .error_command(host_error_command),.error_reason(host_error_reason),
  .high_capacity(high_capacity),.initialized(initialized),.capacity_mb(capacity_mb),
  .block_start(!query_busy&&(save_owner?wb:rb)),.block_write(save_owner?ww:rw),.block_lba(save_owner?wl:rl),
  .block_busy(hb_busy),.block_done(hb_done),.block_error(hb_error),.block_rx_valid(hrvalid),.block_rx_data(hrdata),
  .block_byte_index(hindex),.block_tx_byte(save_owner?wt:rt));
 wire [5:0] writer_state,writer_error_stage;wire [2:0] writer_purpose;
 fat32_photo_writer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.WAIT_TIMEOUT(SAVE_WAIT_TIMEOUT),.ENABLE_DELETE(ENABLE_DELETE)) writer(
  .clk(clk),.rst_n(rst_n),.start(save_start),.busy(save_busy),.done(save_done),.error(save_error),
  .delete_start(delete_start),.delete_number(delete_target),.delete_done(delete_done),.delete_error(delete_error),.delete_mutated(delete_mutated),
  .error_code(save_error_code),.file_number(file_number),.init_start(wi),
  .debug_state(writer_state),.debug_purpose(writer_purpose),.error_stage(writer_error_stage),
  .init_done(hi_done&&save_owner),.init_error(hi_error&&save_owner),.capacity_mb(capacity_mb),
  .block_start(wb),.block_write(ww),.block_lba(wl),.block_done(hb_done&&save_owner),.block_error(hb_error&&save_owner),
  .block_rx_valid(hrvalid&&save_owner),.block_rx_data(hrdata),.block_byte_index(hindex),.block_tx_byte(wt),
  .photo_start(photo_start),.photo_offset(photo_offset),.photo_done(photo_done),.photo_error(photo_error),
  .photo_valid(photo_valid),.photo_index(photo_index),.photo_byte(photo_byte));
 fat32_bmp_reader #(.PHOTO_WIDTH(WIDTH),.PHOTO_HEIGHT(HEIGHT),.PHOTO_BYTES(WIDTH*HEIGHT*2),.ENABLE_DELETE(ENABLE_DELETE),.OPEN_AVAILABLE(ENABLE_PROCESSING)) reader(
  .clk(clk),.rst_n(rst_n),.gallery_toggle_req(gallery_toggle_req&&gallery_admit),
  .open_file_req(open_saved_admit),.open_file_number(open_saved_number),
  .load_abort(gallery_abort),
  .reload_after_delete(reader_reload),.gallery_empty(gallery_empty),
  .gallery_prev_req(gallery_prev_req&&gallery_admit),.gallery_next_req(gallery_next_req&&gallery_admit),
  .gallery_mode(gallery_mode),.read_active(),.read_busy(gallery_busy),.read_error(gallery_error),.current_file_number(gallery_file_number),
  .load_start(gallery_load_start),.load_byte_valid(gallery_load_byte_valid),.load_byte(gallery_load_byte),
  .load_byte_offset(gallery_load_byte_offset),.load_done(gallery_load_done),.load_error(gallery_load_error),
  .sd_init_start(ri),.sd_init_busy(hi_busy&&!save_owner),.sd_init_done(hi_done&&!save_owner&&!query_busy),.sd_init_error(hi_error&&!save_owner&&!query_busy),
  .block_start(rb),.block_write(rw),.block_lba(rl),.block_busy(hb_busy&&!save_owner),
  .block_done(hb_done&&!save_owner),.block_error(hb_error&&!save_owner),.block_rx_valid(hrvalid&&!save_owner),
  .block_rx_data(hrdata),.block_byte_index(hindex),.block_tx_byte(rt));
 photo_event_uart #(.ENABLE_DELETE(ENABLE_DELETE)) reporter(.clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_critical(event_critical),.event_kind(event_kind),.event_code(event_code),
  .event_command(event_command),.event_reason(event_reason),
  .event_file_number(event_file_number),
  .event_stage(event_stage),.event_rd(event_rd),.event_axi(event_axi),.event_beats(event_beats),
  .room(report_room),.tx_valid(tx_valid),.tx_data(tx_data),.tx_last(tx_last),.tx_accept(tx_accept),.tx_done(tx_done),
  .confirmation_sent(confirmation_sent),.confirmation_file_number(confirmation_file_number));
 // Stage names used by the UART reporter: idle/capture/init/DDR/read/write/
 // directory/FAT scan/metadata/recovery/fault. Snapshot them with each event.
 wire [3:0] save_stage=writer_state==1?2:
  (writer_state==10||writer_state==11)?3:
  writer_state==28?(ww?5:(writer_purpose==1?6:(writer_purpose==2?7:4))):8;
 wire [3:0] current_stage=state==EXPORT?12:state==PROCESS?11:state==CAPTURE?1:state==SAVE?save_stage:
  state==RECOVER?9:(state==FAULT||state==DELETE_FAULT)?10:state==DELETE?8:query_busy?2:(gallery_busy||gallery_storage_busy)?4:0;
 wire channels_idle=!process_busy&&!dma_busy&&!photo_read_busy&&!hi_busy&&!hb_busy&&!save_busy&&!axi_read_stalled;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin state<=IDLE;capture_toggle<=0;dma_start<=0;slot<=0;retained<=0;retained_slot<=0;retained_saved<=0;
   save_start<=0;query_start<=0;query_busy<=0;capture_timer<=0;event_valid<=0;event_critical<=1;event_kind<=0;event_code<=0;
   event_command<=0;event_reason<=0;event_stage<=0;event_rd<=0;event_axi<=0;event_beats<=0;
   recovery_timer<=0;capture_accepted<=0;gallery_failed_seen<=0;gallery_mode_seen<=0;display_failure_reported<=0;
   delete_armed<=0;delete_start<=0;reader_reload<=0;gallery_visible_ready<=0;refresh_pending<=0;
   delete_target<=0;confirm_timer<=0;event_file_number<=0;confirm_prompt_sent<=0;
   uart_capture<=0;export_start<=0;photo_mode<=0;photo_cleanup<=1;photo_median<=1;photo_minimum<=20;photo_high<=60;photo_low<=30;process_start<=0;open_saved_photo<=0;open_saved_number<=0;end
  // Reset the optional deletion state in the same clock/reset domain.
  else begin
   dma_start<=0;save_start<=0;query_start<=0;event_valid<=0;capture_accepted<=0;delete_start<=0;reader_reload<=0;process_start<=0;export_start<=0;
   // Keep completion-triggered preview pending across an i query / host busy.
   // Explicit navigation or an accepted new capture supersedes the preview.
   if(open_saved_admit||gallery_navigation)open_saved_photo<=0;
   event_critical<=1;
   event_command<=0;event_reason<=0;
   event_stage<=current_stage;event_rd<=photo_read_debug;event_axi<=axi_read_debug;event_beats<=photo_read_beats;
   gallery_failed_seen<=gallery_error||gallery_ddr_failed;gallery_mode_seen<=gallery_mode;
   if(!gallery_mode||gallery_load_start)display_failure_reported<=0;
   // Do not report the previous frame's reset/underflow while a new album
   // picture is still loading. A committed display failure is still reported.
   if(gallery_mode&&gallery_visible_ready&&gallery_display_error&&!display_failure_reported)begin
    display_failure_reported<=1;event_valid<=1;event_kind<=13;
   end
   if(gallery_ready)begin event_valid<=1;event_kind<=10;end
   if((gallery_error||gallery_ddr_failed)&&!gallery_failed_seen)begin event_valid<=1;event_kind<=11;end
   if(gallery_mode_seen&&!gallery_mode&&!gallery_empty)begin event_valid<=1;event_kind<=12;end
   if(capture_command||query_req)begin
    event_critical<=0;
    if(state==FAULT||state==DELETE_FAULT)begin event_valid<=1;event_kind<=9;end
    else if(state!=IDLE||query_busy||gallery_busy||gallery_storage_busy||dma_busy||photo_read_busy||axi_read_stalled||!report_room)begin event_valid<=1;event_kind<=4;end
    else if(capture_command)begin
     open_saved_photo<=0;
     if(uart_request && (capture_req||query_req||(capture_mode!=1&&capture_mode!=2)||(retained&&!retained_saved)))begin
      event_valid<=1;event_kind<=4;
     end else if(retained&&!retained_saved)begin save_start<=1;state<=SAVE;end
     else begin
      uart_capture<=uart_request;slot<=retained?~retained_slot:1'b0;dma_start<=1;capture_toggle<=~capture_toggle;
      photo_mode<=ENABLE_PROCESSING?capture_mode:2'd0;photo_median<=median_enable;
      photo_cleanup<=cleanup_level;photo_minimum<=min_pixels;photo_high<=high_threshold;photo_low<=low_threshold;
      state<=CAPTURE;capture_timer<=0;capture_accepted<=1;
     end
    end else begin query_start<=1;query_busy<=1;end
   end
   if(query_busy&&(hi_done||hi_error))begin
    query_busy<=0;event_valid<=1;event_critical<=1;event_kind<=hi_error?6:5;
    event_command<=host_error_command;event_reason<=host_error_reason;
   end
   if(state==CAPTURE)begin
    capture_timer<=capture_timer+1'b1;
    if(dma_done)begin
     // This assignment publishes the new frame and frees the previous saved
     // slot. No DDR erasure is required; the old slot is reusable next time.
     if(ENABLE_PROCESSING&&photo_mode!=0)begin
      process_start<=1;state<=PROCESS;event_valid<=1;event_critical<=1;event_kind<=15;event_code<=0;
     end else begin
      retained<=1;retained_slot<=slot;retained_saved<=0;
      event_valid<=1;event_critical<=1;event_kind<=0;save_start<=1;state<=SAVE;
     end
    end else if(dma_error)begin event_valid<=1;event_critical<=1;event_kind<=2;state<=IDLE;end
    else if(capture_timer==CLK_HZ*2-1)begin event_valid<=1;event_critical<=1;event_kind<=2;state<=FAULT;end
   end
   if(state==PROCESS)begin
    if(process_done)begin
     if(uart_capture)begin export_start<=1;state<=EXPORT;end
     else begin
      retained<=1;retained_slot<=slot;retained_saved<=0;save_start<=1;state<=SAVE;
      event_valid<=1;event_critical<=1;event_kind<=0;
     end
    end else if(process_error)begin
     state<=FAULT;event_valid<=1;event_critical<=1;event_kind<=15;event_code<=2;
    end
   end
   if(state==EXPORT&&export_done)begin
    state<=photo_read_busy?FAULT:IDLE;
   end
   if(state==SAVE)begin
    if(save_done)begin retained_saved<=1;state<=IDLE;event_valid<=1;event_critical<=1;event_kind<=1;
     if(ENABLE_PROCESSING&&photo_mode!=0)begin open_saved_photo<=1;open_saved_number<=file_number;end
    end
    else if(save_error)begin
     state<=RECOVER;recovery_timer<=0;event_valid<=1;event_critical<=1;event_kind<=3;event_code<=save_error_code;
     if(save_error_code==8)begin event_kind<=7;event_code<={4'd0,photo_read_fault};end
     else if(save_error_code==10)begin event_kind<=8;event_code<={2'd0,writer_error_stage};end
     event_command<=host_error_command;event_reason<=host_error_reason;
    end
   end
   if(state==RECOVER)begin
    if(channels_idle)state<=IDLE;
    else if(photo_reset_required || recovery_timer>=RECOVERY_TIMEOUT)begin
     state<=FAULT;event_valid<=1;event_critical<=1;event_kind<=9;
    end else recovery_timer<=recovery_timer+1'b1;
   end
   // Late completion can safely recover the bus after a fault report. Until
   // then retain the photo, keep draining, and refuse a new transaction.
   if(state==FAULT && channels_idle)state<=IDLE;
   if(gallery_ready)gallery_visible_ready<=1;
   if(gallery_load_start||!gallery_mode||gallery_display_error)gallery_visible_ready<=0;
   if(ENABLE_DELETE)begin
    if(gallery_load_start||gallery_error||gallery_ddr_failed||!gallery_mode)refresh_pending<=0;
    if(delete_armed && confirmation_sent && confirmation_file_number==delete_target)confirm_prompt_sent<=1;
    if(delete_armed)begin
     if(confirm_prompt_sent && confirm_timer<DELETE_CONFIRM_CYCLES)confirm_timer<=confirm_timer+1'b1;
     if((confirm_prompt_sent&&confirm_timer>=DELETE_CONFIRM_CYCLES-1) || gallery_toggle_req || gallery_prev_req || gallery_next_req ||
        capture_command || query_req || !gallery_mode || gallery_file_number!=delete_target)begin
      delete_armed<=0;
      if(!(capture_command||query_req))begin event_valid<=1;event_critical<=1;event_kind<=14;event_code<=4;end
     end
    end
    if(delete_command && !(gallery_toggle_req||gallery_prev_req||gallery_next_req||capture_command||query_req))begin
     if(state!=IDLE || open_saved_photo || query_busy || gallery_busy || gallery_storage_busy || dma_busy || photo_read_busy ||
        axi_read_stalled || refresh_pending || !report_room)begin event_valid<=1;event_critical<=0;event_kind<=4;end
     else if(!gallery_mode || !gallery_visible_ready || gallery_file_number==0)begin
      event_valid<=1;event_kind<=14;event_code<=2;event_command<=1;delete_armed<=0;
     end else if(delete_armed && !confirm_prompt_sent)begin
      event_valid<=1;event_critical<=0;event_kind<=4;
     end else if(delete_armed && confirm_timer<DELETE_CONFIRM_CYCLES-1 && gallery_file_number==delete_target)begin
      delete_armed<=0;delete_start<=1;gallery_visible_ready<=0;state<=DELETE;
     end else begin
      delete_armed<=1;delete_target<=gallery_file_number;confirm_timer<=0;confirm_prompt_sent<=0;
      event_valid<=1;event_critical<=1;event_kind<=14;event_code<=0;event_file_number<=gallery_file_number[16:0];
     end
    end
    if((gallery_toggle_req||gallery_prev_req||gallery_next_req) && (state==DELETE||state==DELETE_FAULT))begin
     event_valid<=1;event_critical<=0;event_kind<=4;
    end
    if(state==DELETE && delete_done)begin
     state<=IDLE;refresh_pending<=1;reader_reload<=1;
     event_valid<=1;event_critical<=1;event_kind<=14;event_code<=1;event_file_number<=delete_target[16:0];
    end
    if(state==DELETE && delete_error)begin
     state<=delete_mutated?DELETE_FAULT:RECOVER;recovery_timer<=0;
     event_valid<=1;event_critical<=1;event_kind<=14;event_code<=2;
     event_command<=save_error_code[5:0];event_reason<=delete_mutated?15:0;
    end
    if(gallery_empty)begin refresh_pending<=0;event_valid<=1;event_critical<=1;event_kind<=14;event_code<=3;end
   end
  end
 end
endmodule
