`timescale 1ns / 1ps

//  by CrazyBird
module axi4_ctrl #(
	parameter 	C_ID_LEN      = 8, 
			C_DATA_LEN    = 128, 
			C_DATA_SIZE   = 4, 	//	C_DATA_LEN=8:0, 16:1, 32:2, 64:3, 128:4, 256:5, 512:6, 1024:7
			
			C_BURST_LEN   = 128,
			
			C_STRB_LEN    = C_DATA_LEN / 8, 
			C_ADDR_INC    = C_BURST_LEN * C_STRB_LEN,
			
			C_BASE_ADDR   = 32'h00000000, 	//	Start at 0x00000000 by default
			C_BUF_SIZE    = 22, 			//	Allocate 2^22 bytes (4MB) by default. The module takes 4*4MB by default. 
			// Live ring: 0x00000000..0x00ffffff. image3 alone restores the
            // independent RAW background at 0x01000000..0x013fffff.
			C_PHOTO0_BASE_ADDR = 32'h01400000,
			C_PHOTO1_BASE_ADDR = 32'h01500000,
			C_PHOTO_BYTES = 32'd1036800,
			C_RD_END_ADDR = 1280 * 720,
			
			C_W_WIDTH     = 64, 
			C_R_WIDTH     = 8,
            BACKGROUND_BUILD = 0,
            PHOTO_STREAM_BUILD = 1,
            C_BACKGROUND_BASE_ADDR = 32'h01000000
)(
    input  wire                 axi_clk         ,
    input  wire                 axi_reset       ,
    
    output       [C_ID_LEN-1:0]      axi_awid        ,
    output       [31:0]      axi_awaddr      ,
    output       [ 7:0]      axi_awlen       ,
    output       [ 2:0]      axi_awsize      ,
    output       [ 1:0]      axi_awburst     ,
    output                   axi_awlock      ,
    output       [ 3:0]      axi_awcache     ,
    output       [ 2:0]      axi_awprot      ,
    output       [ 3:0]      axi_awqos       ,
    output reg                  axi_awvalid     ,
    input  wire                 axi_awready     ,
    
    output       [C_DATA_LEN-1:0]      axi_wdata       ,
    output       [C_STRB_LEN-1:0]      axi_wstrb       ,
    output                   axi_wlast       ,
    output reg                  axi_wvalid      ,
    input  wire                 axi_wready      ,
    
    input  wire     [C_ID_LEN-1:0]      axi_bid         ,
    input  wire     [ 1:0]      axi_bresp       ,
    input  wire                 axi_bvalid      ,
    output                   axi_bready      ,
    
    output       [C_ID_LEN-1:0]      axi_arid        ,
    output       [31:0]      axi_araddr      ,
    output       [ 7:0]      axi_arlen       ,
    output       [ 2:0]      axi_arsize      ,
    output       [ 1:0]      axi_arburst     ,
    output                   axi_arlock      ,
    output       [ 3:0]      axi_arcache     ,
    output       [ 2:0]      axi_arprot      ,
    output       [ 3:0]      axi_arqos       ,
    output reg                  axi_arvalid     ,
    input  wire                 axi_arready     ,
    
    input  wire     [C_ID_LEN-1:0]      axi_rid         ,
    input  wire     [C_DATA_LEN-1:0]      axi_rdata       ,
    input  wire     [ 1:0]      axi_rresp       ,
    input  wire                 axi_rlast       ,
    input  wire                 axi_rvalid      ,
    output                   axi_rready      ,
    output wire              read_frame_flush,
    output wire              read_urgent,
    
    input  wire                 wframe_pclk     ,
    input  wire                 wframe_vsync    ,		//	Writter VSync. Flush on falling edge. Connect to EOF. 
    input  wire                 wframe_data_en  ,
    input  wire     [C_W_WIDTH-1:0]      wframe_data     ,
    
    input  wire                 rframe_pclk     ,
    input  wire                 rframe_vsync    ,		//	Reader VSync. Flush on falling edge. Connect to ~EOF. 
    input  wire                 rframe_data_en  ,
    output wire     [C_R_WIDTH-1:0]      rframe_data     ,
    input wire background_capture_i,
    input wire background_read_enable_i,
    output reg background_valid,
    output reg background_capture_busy,
    output reg background_error,
    output wire [C_R_WIDTH-1:0] background_rframe_data,
    output wire background_rframe_valid,
    output wire background_stream_fault,
    // Hold the currently displayed complete DDR frame while capture continues.
    // This input is synchronous to axi_clk and is applied at a read-frame
    // boundary, so a UART command cannot switch buffers halfway through a frame.
    input  wire                 freeze_i        ,

    // Gallery writer: the native SD reader provides byte-addressed RGB565
    // pixels in the AXI clock domain.  This controller remains the only AXI
    // master and packs each 16 adjacent bytes into one 128-bit write beat.
    input  wire                 photo_write_valid_i,
    input  wire                 photo_write_buffer_i,
    input  wire [19:0]          photo_write_offset_i,
    input  wire [7:0]           photo_write_data_i,
    input  wire                photo_load_start_i,
    input  wire                photo_load_end_i,
    output wire                photo_write_busy_o,
    output reg                 photo_word_commit_o,
    output wire                photo_write_error_o,

    // Gallery reader/display stream.  This independent FIFO keeps gallery
    // reads from disturbing the live camera display FIFO.
    input  wire                 photo_read_enable_i,
    input  wire                 photo_read_buffer_i,
    input  wire                 photo_rframe_pclk,
    input  wire                 photo_rframe_vsync,
    input  wire                 photo_rframe_data_en,
    output wire [7:0]           photo_rframe_data,
    output wire                 photo_rframe_valid,
    output wire                 photo_stream_reset_o,
    output reg photo_read_error_o,

    // Sticky diagnostics. They clear only with axi_reset so intermittent
    // camera/DDR faults remain observable after the affected frame is gone.
    output reg                  read_underflow_sticky,
    output reg      [31:0]      read_underflow_count,
    output reg                  bad_frame_sticky,
    output reg      [31:0]      bad_frame_count,

    output 		[31:0] 	tp_o
);
reg [1:0] r_rd_target;
always @(posedge axi_clk or posedge axi_reset)begin
    if(axi_reset)photo_read_error_o<=0;
    else if(photo_load_start_i)photo_read_error_o<=0;
    else if(axi_rvalid&&axi_rready&&r_rd_target==2&&axi_rresp!=0)photo_read_error_o<=1;
end
	reg r_write_source_photo = 1'b0;
	
	initial begin
		axi_awvalid <= 0; 
		axi_wvalid <= 0; 
		axi_arvalid <= 0; 
	end

	assign axi_awid    = {C_ID_LEN{1'b0}};
	assign axi_awlen   = r_write_source_photo ? 8'd0 : C_BURST_LEN - 1'b1;
	assign axi_awsize  = C_DATA_SIZE;
	assign axi_awburst = 2'b01;	//	INCR
	assign axi_awlock  = 1'b0;
	assign axi_awcache = 0;
	assign axi_awprot  = 3'b0;
	assign axi_awqos   = 4'b0;
	assign axi_wstrb   = {C_STRB_LEN{1'b1}};
	assign axi_bready  = 1'b1;
	    
	assign axi_arid    = {C_ID_LEN{1'b0}};
	assign axi_arlen   = C_BURST_LEN - 1'b1;
	assign axi_arsize  = C_DATA_SIZE;
	assign axi_arburst = 2'b01;	//	INCR
	assign axi_arlock  = 1'b0;
	assign axi_arcache = 0;
	assign axi_arprot  = 3'b0;
	assign axi_arqos   = 4'b0;
	assign axi_rready  = 1'b1;
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	R/W Schedule
    reg background_active;
    reg background_pending;
    reg background_write_error;
    wire background_bad_frame;

    // Capture redirects exactly one camera frame into its independent slot.
    // That frame MUST NOT be published into the live ring.
	reg	[1:0] 	rc_wframe_index;
	reg	[1:0] 	rc_rframe_index;

	//	Use 4 data buffers to simplify control. 
	wire 	[1:0] 	w_wframe_index_p1 = rc_wframe_index + 2'd1;
	wire 	[1:0] 	w_wframe_index_next = (w_wframe_index_p1 == rc_rframe_index) ? rc_wframe_index + 2'd2 : rc_wframe_index + 2'd1;

	reg 	[1:0] 	r_wframe_index_last = 0; 
	
	reg 			r_wframe_inc = 0, r_rframe_inc = 0;

	// Count packed camera words in their native clock domain. C_RD_END_ADDR
	// describes the number of output pixels for the configured frame; convert
	// that amount to C_W_WIDTH input words. A frame with missing/extra MIPI data
	// is written only into the current scratch buffer and is never published.
	localparam integer C_EXPECTED_WFRAME_WORDS =
		(C_RD_END_ADDR * C_R_WIDTH) / C_W_WIDTH;
	reg [C_BUF_SIZE-1:0] r_wframe_word_count = 0;
	reg                  r_wframe_vsync_d = 0;
	reg                  r_wframe_good = 0;
	always @(posedge wframe_pclk or posedge axi_reset) begin
		if(axi_reset) begin
			r_wframe_word_count <= 0;
			r_wframe_vsync_d    <= 0;
			r_wframe_good       <= 0;
		end else begin
			r_wframe_vsync_d <= wframe_vsync;
			if(!r_wframe_vsync_d && wframe_vsync)
				r_wframe_word_count <= 0;
			else if(wframe_vsync && wframe_data_en)
				r_wframe_word_count <= r_wframe_word_count + 1'b1;

			if(r_wframe_vsync_d && !wframe_vsync)
				r_wframe_good <=
					(r_wframe_word_count == C_EXPECTED_WFRAME_WORDS);
		end
	end
	// Declared before the AXI signal assignments because it also selects the
	// dynamic one-beat gallery AWLEN value.

	(* async_reg = "true" *) reg r_wframe_good_meta = 0;
	(* async_reg = "true" *) reg r_wframe_good_sync = 0;
	always @(posedge axi_clk or posedge axi_reset) begin
		if(axi_reset) begin
			r_wframe_good_meta <= 0;
			r_wframe_good_sync <= 0;
		end else begin
			r_wframe_good_meta <= r_wframe_good;
			r_wframe_good_sync <= r_wframe_good_meta;
		end
	end

	always @(posedge axi_clk) begin
		if(axi_reset) begin
			rc_wframe_index <= 2'b0;
			rc_rframe_index <= 2'd2;
			r_wframe_index_last <= 0;
            background_active <= 0; background_pending <= 0;
            background_valid <= 0; background_capture_busy <= 0;
            background_error <= 0; background_write_error <= 0;
			
		end else begin
			rc_wframe_index <= rc_wframe_index; 
			rc_rframe_index <= rc_rframe_index; 
			
			//	When wfifo_rd_rst_busy_neg, write pointer increments. When rfifo_wr_rst_busy_neg, read pointer increments. 
            if (BACKGROUND_BUILD) begin
                if (background_capture_i && !background_capture_busy) begin
                    background_pending <= 1; background_capture_busy <= 1;
                    background_valid <= 0; background_error <= 0;
                end
                if(axi_rvalid&&axi_rready&&r_rd_target==1&&axi_rresp!=0)background_error<=1;
                if (background_active && axi_bvalid && axi_bresp != 0)
                    background_write_error <= 1;
                if (background_active && background_bad_frame) begin
                    // A short/long camera frame never becomes a reference.
                    background_active<=0; background_capture_busy<=0;
                    background_valid<=0; background_error<=1;
                end else if (r_wframe_inc && background_active) begin
                    background_active <= 0; background_capture_busy <= 0;
                    background_valid <= !background_write_error;
                    background_error <= background_write_error;
                end else if (r_wframe_inc && background_pending) begin
                    background_pending <= 0; background_active <= 1;
                    background_valid <= 0; background_write_error <= 0;
                end
            end
			case ({r_rframe_inc, r_wframe_inc && !background_active})
				2'b01: begin
						//	Write increment only. 
						rc_wframe_index <= w_wframe_index_next; 	//	Use 4 buffers. 
						r_wframe_index_last <= rc_wframe_index; 
					end
				2'b10: begin
						//	Use r_wframe_index_last. 
						if (!freeze_i)
							rc_rframe_index <= r_wframe_index_last;
					end
				2'b11: begin
						//	Update write & read pointer simutaneously. 
						rc_wframe_index <= w_wframe_index_next; 	//	Use 4 buffers. 
						r_wframe_index_last <= rc_wframe_index;
						if (!freeze_i)
							rc_rframe_index <= rc_wframe_index;
					end
			endcase


		end
	end
	
	
	
	////////////////////////////////////////////////////////////////
	//	AXI Writter

	wire 				w_wfifo_pempty, w_wfifo_empty; 
	wire 				w_wfifo_ren; 
	wire 	[C_DATA_LEN-1:0] 	w_wfifo_rdata; 

	//	On EOF when ~empty, flush the last data then reset FIFO. 
	reg 	[3:0] 	rs_w = 0; 
	wire 	[3:0] 	ws_w_idle = 0; 
	wire 	[3:0] 	ws_w_wdata = 1; 
	wire 	[3:0] 	ws_w_winc = 2; 
	wire 	[3:0] 	ws_w_eof = 3; 
	wire [3:0] ws_w_resp = 4;

	//	Write Pointer. Burst bytes is always C_ADDR_INC. 
	reg 	[C_BUF_SIZE-1:0] 	rc_w_ptr = 0; 
	reg 	[0:0] 		rc_w_eof = 0; 
	reg 				r_w_rst = 1; 
	
	//	Burst Control
	reg 	[7:0] 	rc_burst = 0; 	//	Compare to C_BURST_LEN - 1. 
	reg [127:0]        photo_pending_data = 128'd0;
	reg [19:0]         photo_pending_offset = 20'd0;
	reg                photo_pending_buffer = 1'b0;
	wire photo_pending_valid,photo_pack_error,photo_word_take;
	wire [127:0] photo_queued_data;wire [19:0] photo_queued_offset;wire photo_queued_buffer,photo_queue_busy;
	assign photo_word_take=(rs_w==ws_w_idle)&&w_wfifo_pempty&&photo_pending_valid;
	assign photo_write_busy_o=photo_queue_busy||(r_write_source_photo&&rs_w!=ws_w_idle);
	assign photo_write_error_o=photo_pack_error||
		((rs_w==ws_w_resp)&&r_write_source_photo&&axi_bvalid&&axi_bresp!=0);
	generate if(PHOTO_STREAM_BUILD)begin : g_photo_writer
	gallery_word_fifo u_gallery_word_fifo(
		.clk(axi_clk),.rst_n(!axi_reset),.stream_start(photo_load_start_i),.stream_end(photo_load_end_i),
		.byte_valid(photo_write_valid_i),.byte_data(photo_write_data_i),.byte_offset(photo_write_offset_i),.byte_buffer(photo_write_buffer_i),
		.word_valid(photo_pending_valid),.word_take(photo_word_take),.word_data(photo_queued_data),
		.word_offset(photo_queued_offset),.word_buffer(photo_queued_buffer),.busy(photo_queue_busy),.error(photo_pack_error));
	end else begin : g_photo_writer_disabled
	 assign photo_pending_valid=0;assign photo_queued_data=0;assign photo_queued_offset=0;
	 assign photo_queued_buffer=0;assign photo_queue_busy=0;assign photo_pack_error=0;
	end endgenerate
	
	//	EOF Monitor. 
	reg 	[1:0] 	r_wframe_sync = 0; 	
	reg 			r_weof_pending = 0; 

	always @(posedge axi_clk or posedge axi_reset) begin
		if(axi_reset) begin
			rs_w <= 0; 
			rc_w_ptr <= 0; 
			rc_w_eof <= 0; 
			r_w_rst <= 1; 
			axi_awvalid <= 0; 
			axi_wvalid <= 0; 
			r_wframe_sync <= 0; 
			r_weof_pending <= 0; 
			r_wframe_inc <= 0; 
			r_write_source_photo <= 1'b0;
			photo_pending_data <= 128'd0;
			photo_pending_offset <= 20'd0;
			photo_pending_buffer <= 1'b0;
			photo_word_commit_o <= 1'b0;
			bad_frame_sticky <= 1'b0;
			bad_frame_count <= 32'd0;
			
		end else begin
			rc_w_eof <= 0; 
			r_wframe_inc <= 0; 
			photo_word_commit_o <= 1'b0;
			
			//	Raise EOF on falling edge of VSYNC. 
			r_wframe_sync <= {r_wframe_sync[0], wframe_vsync};
			if(r_wframe_sync == 2'b10) begin
				r_weof_pending <= 1; 
			end else begin
			end
			
			if(axi_awready) begin
				axi_awvalid <= 0; 
			end else begin
			end
			
			case (rs_w)
				ws_w_idle: begin
						rc_burst <= 0; 
						r_w_rst <= 0; 
						r_write_source_photo <= 1'b0;
						
						if(~w_wfifo_pempty) begin
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
						
						end else if(photo_pending_valid) begin
							axi_awvalid <= 1;
							axi_wvalid <= 1;
							r_write_source_photo <= 1'b1;
							photo_pending_data <= photo_queued_data;
							photo_pending_offset <= photo_queued_offset;
							photo_pending_buffer <= photo_queued_buffer;
							rs_w <= ws_w_wdata;
						end else if(r_weof_pending && (~w_wfifo_empty)) begin
							//	There's some data in the FIFO. write last. 
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
							
						end else if(r_weof_pending) begin
							//	EOF. Reset FIFO. Increment write pointer. 
							r_w_rst <= 1; 
							if(r_wframe_good_sync) begin
								r_wframe_inc <= 1;
							end else begin
								// Keep displaying the last known-complete frame.
								bad_frame_sticky <= 1'b1;
								if(bad_frame_count != 32'hffffffff)
									bad_frame_count <= bad_frame_count + 1'b1;
							end
							rs_w <= ws_w_eof; 
							
						end else begin
						end
					end
					
				ws_w_eof: begin
						//	Wait for some cycles to release reset. 
						r_weof_pending <= 0; 
						rc_w_ptr <= 0; 
						
						rc_w_eof <= rc_w_eof + 1'b1;
						if(&rc_w_eof)
							rs_w <= ws_w_idle; 
						else begin
						end
					end
					
				ws_w_wdata: begin
						rc_burst <= rc_burst + axi_wready; 
						
						//	On last transaction terminate write. 
						if(axi_wlast && axi_wready) begin
							axi_wvalid <= 0; 
								rs_w <= ws_w_resp;
						end else begin
						end
					end
				ws_w_resp: begin
					if(axi_bvalid)begin
						if(r_write_source_photo&&axi_bresp==0)photo_word_commit_o<=1'b1;
						rs_w<=ws_w_winc;
					end
				end
					
				ws_w_winc: begin
						if (!r_write_source_photo)
							rc_w_ptr <= rc_w_ptr + C_ADDR_INC[C_BUF_SIZE-1:0];
						rs_w <= ws_w_idle; 
					end
			endcase
		end
	end
	assign axi_awaddr = r_write_source_photo ?
			((photo_pending_buffer ? C_PHOTO1_BASE_ADDR : C_PHOTO0_BASE_ADDR) +
			 photo_pending_offset) :
			((BACKGROUND_BUILD && background_active) ?
             (C_BACKGROUND_BASE_ADDR + rc_w_ptr) :
             (C_BASE_ADDR + {rc_wframe_index, rc_w_ptr}));
	assign axi_wdata = r_write_source_photo ? photo_pending_data : w_wfifo_rdata;
	assign axi_wlast = r_write_source_photo ? 1'b1 :
							  (rc_burst >= C_BURST_LEN - 1);
	
	assign w_wfifo_ren = axi_wvalid && axi_wready && !r_write_source_photo;
	
	
	assign tp_o[1:0] = {rs_w[1:0]}; 
	assign tp_o[2] = axi_wvalid; 
	assign tp_o[3] = wframe_data_en; 
	
	
	generate
		if(C_W_WIDTH == 32) begin: Gen_FIFO_W32
			W0_FIFO_32 u_W0_FIFO_32
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end
	endgenerate




















reg                             rframe_vsync_dly;
reg                             photo_rframe_vsync_dly;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rframe_vsync_dly <= 1'b0;
    else
        rframe_vsync_dly <= rframe_vsync;
end

always @(posedge photo_rframe_pclk)
begin
    if(axi_reset == 1'b1)
        photo_rframe_vsync_dly <= 1'b0;
    else
        photo_rframe_vsync_dly <= photo_rframe_vsync;
end

wire                            rframe_vsync_neg;
assign rframe_vsync_neg =  rframe_vsync_dly & ~rframe_vsync;
wire                            photo_rframe_vsync_neg;
assign photo_rframe_vsync_neg = photo_rframe_vsync_dly & ~photo_rframe_vsync;

reg             [4:0]           rfifo_cnt;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_cnt <= 5'h1f;
    else
    begin
        if(rframe_vsync_neg == 1'b1)
            rfifo_cnt <= 5'h1f;
        else if(rfifo_cnt > 5'd0)
            rfifo_cnt <= rfifo_cnt - 1'b1;
        else
            rfifo_cnt <= 5'b0;
    end
end

reg                             rfifo_rst;
reg                             photo_rfifo_rst;
reg [4:0]                       photo_rfifo_cnt;
(* async_reg = "true" *) reg photo_read_enable_meta;
(* async_reg = "true" *) reg photo_read_enable_sync;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_rst <= 1'b1;
    else
    begin
        if(rfifo_cnt == 5'b0)
            rfifo_rst <= 1'b0;
        else
            rfifo_rst <= 1'b1;
    end
end


always @(posedge photo_rframe_pclk)
begin
    if(axi_reset == 1'b1)
        photo_rfifo_cnt <= 5'h1f;
    else if(photo_rframe_vsync_neg)
        photo_rfifo_cnt <= 5'h1f;
    else if(photo_rfifo_cnt > 5'd0)
        photo_rfifo_cnt <= photo_rfifo_cnt - 1'b1;
end

always @(posedge photo_rframe_pclk)
begin
    if(axi_reset == 1'b1)
        photo_rfifo_rst <= 1'b1;
    else
        photo_rfifo_rst <= (photo_rfifo_cnt != 5'd0);
end

wire 			w_rfifo_rst = axi_reset || rfifo_rst ||
                    (BACKGROUND_BUILD && photo_read_enable_sync && photo_rfifo_rst);
// image3's E timing trails RAW timing. Reset the E FIFO at BOTH frame
// boundaries: otherwise a read issued in between can survive the later E
// reset, lose its leading beats, and put an old response tail at byte zero.
// Legacy gallery images keep their original reset behavior.
wire            w_photo_rfifo_rst = axi_reset || photo_rfifo_rst ||
                    (BACKGROUND_BUILD && photo_read_enable_sync && rfifo_rst);
assign photo_stream_reset_o = w_photo_rfifo_rst || photo_rframe_vsync_neg;

reg                             rfifo_wenb;
reg             [C_DATA_LEN-1:0]          rfifo_wdata;
wire            [ 9:0]          rfifo_wcnt;
wire 					  rfifo_wfull; 
wire                            rfifo_wr_rst_busy;
wire 					w_rfifo_aempty; 
wire 					w_rfifo_empty; 
wire 		[C_R_WIDTH-1:0] w_rfifo_rdata;
reg r_read_frame_fault = 1'b0;
reg r_rfifo_rst = 0;

reg background_rfifo_wenb;
reg [C_DATA_LEN-1:0] background_rfifo_wdata;
wire background_rfifo_wfull, background_rfifo_empty, background_rfifo_aempty;
wire [C_R_WIDTH-1:0] background_rfifo_rdata;
(* async_reg = "true" *) reg bg_valid_meta, bg_valid_sync;
// The mode request is not an AXI-domain signal (image3 supplies a pixel-domain
// frame-boundary mode). Synchronize separately for scheduling and consumption.
(* async_reg = "true" *) reg bg_enable_axi_meta,bg_enable_axi_sync;
(* async_reg = "true" *) reg bg_enable_pixel_meta,bg_enable_pixel_sync;
always @(posedge axi_clk or posedge axi_reset)begin
    if(axi_reset)begin bg_enable_axi_meta<=0;bg_enable_axi_sync<=0;end
    else begin bg_enable_axi_meta<=background_read_enable_i;bg_enable_axi_sync<=bg_enable_axi_meta;end
end
reg bg_read_frame_fault;
reg bg_ready_for_frame;
reg bg_axi_read_error;
(* async_reg="true" *) reg bg_error_meta,bg_error_sync;
always @(posedge axi_clk or posedge r_rfifo_rst)begin
    if(r_rfifo_rst)bg_axi_read_error<=0;
    else if(axi_rvalid&&axi_rready&&r_rd_target==1&&axi_rresp!=0)bg_axi_read_error<=1;
end
always @(posedge rframe_pclk or posedge axi_reset) begin
    if (axi_reset) begin bg_valid_meta<=0; bg_valid_sync<=0; bg_read_frame_fault<=0;bg_error_meta<=0;bg_error_sync<=0;bg_ready_for_frame<=0;bg_enable_pixel_meta<=0;bg_enable_pixel_sync<=0;end
    else begin
        bg_valid_meta<=background_valid; bg_valid_sync<=bg_valid_meta;
        bg_enable_pixel_meta<=background_read_enable_i;bg_enable_pixel_sync<=bg_enable_pixel_meta;
        bg_error_meta<=bg_axi_read_error;bg_error_sync<=bg_error_meta;
        // The mode itself commits just after VS enters blank. Track readiness
        // throughout blank so the two sync clocks do not cost an extra frame.
        if (!rframe_vsync)begin bg_read_frame_fault<=0;bg_ready_for_frame<=bg_valid_sync&&bg_enable_pixel_sync;end
        else if (rframe_data_en && bg_valid_sync && bg_ready_for_frame && bg_enable_pixel_sync && background_rfifo_empty)
            bg_read_frame_fault<=1;
    end
end
assign background_stream_fault = bg_read_frame_fault || r_read_frame_fault || bg_error_sync;
assign background_rframe_valid = BACKGROUND_BUILD && rframe_data_en && bg_valid_sync && bg_ready_for_frame &&
    bg_enable_pixel_sync && !background_stream_fault && !background_rfifo_empty;
assign background_rframe_data = background_rframe_valid ? background_rfifo_rdata : 0;
generate if (BACKGROUND_BUILD) begin : g_background_fifo
    R0_FIFO_8 u_background_R0_FIFO_8 (
        .wr_clk_i(axi_clk), .wr_en_i(background_rfifo_wenb), .wdata(background_rfifo_wdata),
        .a_rst_i(w_rfifo_rst), .prog_full_o(background_rfifo_wfull),
        .rd_clk_i(rframe_pclk), .rd_en_i(background_rframe_valid), .rdata(background_rfifo_rdata),
        .empty_o(background_rfifo_empty), .almost_empty_o(background_rfifo_aempty)
    );
end else begin : g_background_fifo_disabled
    assign background_rfifo_wfull=1; assign background_rfifo_empty=1;
    assign background_rfifo_aempty=1; assign background_rfifo_rdata=0;
end endgenerate
reg                             photo_rfifo_wenb;
reg             [C_DATA_LEN-1:0] photo_rfifo_wdata;
wire                            photo_rfifo_wfull;
wire                            w_photo_rfifo_aempty;
wire                            w_photo_rfifo_empty;
wire        [C_R_WIDTH-1:0]     w_photo_rfifo_rdata;

// Once an active display read finds the FIFO empty, do not resume partway
// through the frame: doing so would shift the RAW Bayer phase and create
// colored horizontal bands. Black-fill the rest of the affected frame and
// recover at the next read-frame reset.
wire w_rfifo_pop = rframe_data_en && !r_read_frame_fault && !w_rfifo_empty;
assign rframe_data = (rframe_data_en && !r_read_frame_fault &&
						!w_rfifo_empty) ? w_rfifo_rdata : {C_R_WIDTH{1'b0}};

wire w_photo_rfifo_pop = photo_rframe_data_en && !w_photo_rfifo_empty;
assign photo_rframe_data = w_photo_rfifo_pop ? w_photo_rfifo_rdata :
                          {C_R_WIDTH{1'b0}};
assign photo_rframe_valid = !w_photo_rfifo_empty;

always @(posedge rframe_pclk or posedge axi_reset) begin
	if(axi_reset) begin
		r_read_frame_fault    <= 1'b0;
		read_underflow_sticky <= 1'b0;
		read_underflow_count  <= 32'd0;
	end else if(rframe_vsync_neg) begin
		r_read_frame_fault <= 1'b0;
	end else if(rframe_data_en && w_rfifo_empty && !r_read_frame_fault) begin
		r_read_frame_fault    <= 1'b1;
		read_underflow_sticky <= 1'b1;
		if(read_underflow_count != 32'hffffffff)
			read_underflow_count <= read_underflow_count + 1'b1;
	end
end


generate
	if(C_R_WIDTH == 8) begin: Gen_RFIFO_8
		R0_FIFO_8 u_R0_FIFO_8
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(w_rfifo_pop),
			.rdata			(w_rfifo_rdata),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
		if(PHOTO_STREAM_BUILD)begin : g_photo_reader
		R0_FIFO_8 u_photo_R0_FIFO_8
		(
			.wr_clk_i       (axi_clk),
			.wr_en_i        (photo_rfifo_wenb),
			.wdata          (photo_rfifo_wdata),
			.a_rst_i        (w_photo_rfifo_rst),
			.prog_full_o    (photo_rfifo_wfull),
			.rd_clk_i       (photo_rframe_pclk),
			.rd_en_i        (w_photo_rfifo_pop),
			.rdata          (w_photo_rfifo_rdata),
			.empty_o        (w_photo_rfifo_empty),
			.almost_empty_o (w_photo_rfifo_aempty)
		);
		end else begin : g_photo_reader_disabled
		 assign photo_rfifo_wfull=1;assign w_photo_rfifo_empty=1;
		 assign w_photo_rfifo_aempty=1;assign w_photo_rfifo_rdata=0;
		end
	end
endgenerate
		
always @(posedge axi_clk)
begin
	// The same reset must flush the external arbiter and reset our outstanding
	// owner/state, not only the destination FIFO/read-address counter.
	r_rfifo_rst <= w_rfifo_rst;
end

//assign tp_o[7:0] = {w_rfifo_empty, rfifo_wfull, rframe_data_en, rfifo_wenb, rfifo_rst, axi_reset, rframe_pclk, axi_clk}; 

reg             [15:0]               rfifo_wr_rst_busy_dly = 2'b0;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        rfifo_wr_rst_busy_dly <= 0;
    else
		rfifo_wr_rst_busy_dly <= {rfifo_wr_rst_busy_dly[14:0],1'b1};
end

wire                                rfifo_wr_rst_busy_neg;
assign rfifo_wr_rst_busy_neg = (rfifo_wr_rst_busy_dly[1:0] == 2'b01) ? 1'b1 : 1'b0;

reg             [4:0]               read_ddr_delay_cnt;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        read_ddr_delay_cnt <= 5'b0;
    else
    begin
        if(rfifo_wr_rst_busy_neg == 1'b1)
            read_ddr_delay_cnt <= 5'd31;
        else if(read_ddr_delay_cnt > 5'b0)
            read_ddr_delay_cnt <= read_ddr_delay_cnt - 1'b1;
        else
            read_ddr_delay_cnt <= 5'b0;
    end
end

always @(posedge axi_clk or posedge axi_reset) begin
	if(axi_reset)
		r_rframe_inc <= 0; 
	else
		r_rframe_inc <= rfifo_wr_rst_busy_neg; 
end


wire                                read_ddr_init_flag;
assign read_ddr_init_flag = (read_ddr_delay_cnt == 5'd1) ? 1'b1 : 1'b0;

//----------------------------------------------------------------------




//----------------------------------------------------------------------
localparam S_READ_IDLE = 2'd0;
localparam S_READ_ADDR = 2'd1;
localparam S_READ_DATA = 2'd2;

reg             [ 1:0]          rd_state;
reg             [ 8:0]          rdata_cnt;
reg             [C_BUF_SIZE-1:0]          araddr;
reg [C_BUF_SIZE-1:0] background_araddr;
reg bg_read_turn;
reg             [19:0]                    photo_araddr;
reg 					r_rd_pend = 0; 
assign background_bad_frame=(rs_w==ws_w_idle)&&r_weof_pending&&w_wfifo_empty&&!r_wframe_good_sync;
// Tell the shared DDR arbiter when an old frame must be drained/discarded,
// and when the selected display FIFO needs immediate refill.
assign read_frame_flush = r_rfifo_rst;
// Almost-empty flags belong to the pixel read clocks. Synchronize them before
// they can affect the shared AXI grant/READY decision.
(* async_reg = "true" *) reg urgent_live_meta,urgent_live_sync;
(* async_reg = "true" *) reg urgent_photo_meta,urgent_photo_sync;
always @(posedge axi_clk or posedge axi_reset)begin
 if(axi_reset)begin urgent_live_meta<=1;urgent_live_sync<=1;urgent_photo_meta<=1;urgent_photo_sync<=1;end
 else begin
  urgent_live_meta<=w_rfifo_aempty;urgent_live_sync<=urgent_live_meta;
  urgent_photo_meta<=w_photo_rfifo_aempty;urgent_photo_sync<=urgent_photo_meta;
 end
end
(* async_reg = "true" *) reg bg_urgent_meta, bg_urgent_sync;
always @(posedge axi_clk or posedge axi_reset) begin
 if(axi_reset)begin bg_urgent_meta<=1;bg_urgent_sync<=1;end
 else begin bg_urgent_meta<=background_rfifo_aempty;bg_urgent_sync<=bg_urgent_meta;end
end
assign read_urgent = !r_rfifo_rst &&
                    ((r_rd_target==2'd0 && urgent_live_sync) ||
                     (r_rd_target==2'd1 && bg_urgent_sync) ||
                     (r_rd_target==2'd2 && urgent_photo_sync));

(* async_reg = "true" *) reg photo_read_buffer_meta;
(* async_reg = "true" *) reg photo_read_buffer_sync;
(* async_reg = "true" *) reg photo_fifo_reset_meta,photo_fifo_reset_sync;
always @(posedge axi_clk or posedge axi_reset) begin
	if (axi_reset) begin
		photo_read_enable_meta <= 1'b0;
		photo_read_enable_sync <= 1'b0;
		photo_read_buffer_meta <= 1'b0;
		photo_read_buffer_sync <= 1'b0;
		photo_fifo_reset_meta <= 1'b1;photo_fifo_reset_sync <= 1'b1;
	end else begin
		photo_read_enable_meta <= photo_read_enable_i;
		photo_read_enable_sync <= photo_read_enable_meta;
		photo_read_buffer_meta <= photo_read_buffer_i;
		photo_read_buffer_sync <= photo_read_buffer_meta;
		photo_fifo_reset_meta <= w_photo_rfifo_rst;photo_fifo_reset_sync <= photo_fifo_reset_meta;
	end
end

wire background_read_ready = BACKGROUND_BUILD && background_valid && bg_enable_axi_sync &&
    rfifo_wr_rst_busy_dly[15] && (background_araddr < C_RD_END_ADDR) && !background_rfifo_wfull;
wire current_read_ready = rfifo_wr_rst_busy_dly[15] &&
                          (araddr < C_RD_END_ADDR) && !rfifo_wfull;
// E timing follows Canny and can reset this FIFO later than the RAW reader.
// Do not issue an AR while its destination FIFO is still discarding writes.
wire photo_read_ready = photo_read_enable_sync && !photo_fifo_reset_sync &&
                        (!BACKGROUND_BUILD || rfifo_wr_rst_busy_dly[15]) &&
                        (photo_araddr < C_PHOTO_BYTES) &&
                        !photo_rfifo_wfull;


always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst) begin
        rd_state <= S_READ_IDLE;
	  axi_arvalid <= 0; 
	  r_rd_pend <= 0; 
	  r_rd_target <= 2'd0; bg_read_turn<=0;
    end else
    begin
	
	
	
	if(axi_arready) begin
		axi_arvalid <= 0; 
	end else begin
	end
 if(axi_rvalid && axi_rlast) begin
		 r_rd_pend <= 0; 
	end else begin
	end
	
        case(rd_state)
            S_READ_IDLE : 
            begin
			// Live/background/gallery share one outstanding read. Alternate
            // live and background bursts; the other images omit the latter.
			// Only one read burst is outstanding, so response routing is explicit.
				if (photo_read_ready) begin
					r_rd_target <= 2'd2;
					rd_state <= S_READ_ADDR;
				end else if (current_read_ready && (!background_read_ready || !bg_read_turn)) begin
                    r_rd_target <= 2'd0; bg_read_turn<=1;
                    rd_state <= S_READ_ADDR;
                end else if (background_read_ready && (!current_read_ready || bg_read_turn)) begin
                    r_rd_target <= 2'd1; bg_read_turn<=0; rd_state<=S_READ_ADDR;
                end else
                    rd_state <= S_READ_IDLE;
            end
		
            S_READ_ADDR : 
            begin
				axi_arvalid <= 1; 
				r_rd_pend <= 1; 
                rd_state <= S_READ_DATA;
            end
            S_READ_DATA : 
            begin
			//	Return when ~arvalid && ~rd_pend. 
			if((~axi_arvalid) && (~r_rd_pend))
                //if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1)&&(rdata_cnt == C_BURST_LEN))
                    rd_state <= S_READ_IDLE;
                else
                    rd_state <= S_READ_DATA;
            end
            default : 
            begin
                rd_state <= S_READ_IDLE;
            end
        endcase
    end
end

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        araddr <= 0;
    else
    begin
		if((axi_arvalid == 1'b1)&&(axi_arready == 1'b1) &&
		   (r_rd_target == 2'd0))
			araddr <= araddr + C_ADDR_INC[C_BUF_SIZE-1:0];
        else
            araddr <= araddr;
    end
end

always @(posedge axi_clk or posedge w_photo_rfifo_rst)
begin
    if(w_photo_rfifo_rst == 1'b1)
        photo_araddr <= 20'd0;
    else if((axi_arvalid == 1'b1)&&(axi_arready == 1'b1) &&
            (r_rd_target == 2'd2))
        photo_araddr <= photo_araddr + C_ADDR_INC[19:0];
end

always @(posedge axi_clk or posedge r_rfifo_rst) begin
    if(r_rfifo_rst) background_araddr<=0;
    else if(axi_arvalid && axi_arready && r_rd_target==1)
        background_araddr<=background_araddr+C_ADDR_INC[C_BUF_SIZE-1:0];
end
assign axi_araddr = (r_rd_target == 2'd1) ? (C_BACKGROUND_BASE_ADDR+background_araddr) : (r_rd_target == 2'd2) ?
                    ((photo_read_buffer_sync ? C_PHOTO1_BASE_ADDR : C_PHOTO0_BASE_ADDR) + photo_araddr) :
                    (C_BASE_ADDR + {rc_rframe_index, araddr});


reg             [8:0]           rdata_cnt_dly;

always @(posedge axi_clk)
begin
    rdata_cnt_dly <= rdata_cnt;
end

always @(*)
begin
    if(rd_state == S_READ_DATA)
        begin
        if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1))
            rdata_cnt = rdata_cnt_dly + 1'b1;
        else
            rdata_cnt = rdata_cnt_dly;
        end
    else
        rdata_cnt = 9'b0;
end

assign axi_rready = 1; 

always @(posedge axi_clk)
begin
    if(axi_reset == 1'b1) begin
        rfifo_wenb <= 1'b0; background_rfifo_wenb<=0;
        photo_rfifo_wenb <= 1'b0;
    end else begin
        background_rfifo_wenb <= BACKGROUND_BUILD && axi_rvalid && axi_rready && r_rd_target==1;
        rfifo_wenb <= (axi_rvalid == 1'b1) && (axi_rready == 1'b1) &&
                      (r_rd_target == 2'd0);
		photo_rfifo_wenb <= (axi_rvalid == 1'b1) &&
							 (axi_rready == 1'b1) &&
							 (r_rd_target == 2'd2);
    end
end

always @(posedge axi_clk)
begin
    rfifo_wdata <= axi_rdata; background_rfifo_wdata<=axi_rdata;
	photo_rfifo_wdata <= axi_rdata;
end

endmodule
