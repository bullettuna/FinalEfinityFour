`timescale 1ns/1ps
`include "images/image2_video_guard/image2_menu_defs.vh"

//`include "ddr3_controller.vh"


module image2_platform #(
	// Legacy vision selector: 0 enables the saved Canny/shape chain.
	parameter MULTIBOOT_BUILD=1'b0,
	parameter PHOTO_TF_BUILD = 1'b0,
	// Actual photo/TF resource gate, independent of the vision selector.
	parameter ENABLE_PHOTO_TF = 1'b0,
	parameter ENABLE_KEY_UART = 1'b0,
	parameter ENABLE_ADC = 1'b0,
	// On-screen text menu.  Only the image1 profile enables it; the default
	// keeps every other image bit-for-bit on its existing control path.
	parameter MENU_BUILD = 1'b0,
	// Independent resource gates; defaults preserve image1/image2 behaviour.
	parameter SHAPE_BUILD = 1'b1,
	parameter COLOR_OVERLAY_BUILD = 1'b1,
	parameter GRAY_EDGE_SPLIT_BUILD = 1'b1,
	parameter CANNY_MEDIAN_BUILD = 1'b0,
    parameter PERSON_BUILD = 1'b0,
	parameter [1:0] DEFAULT_VIDEO_MODE = PHOTO_TF_BUILD ? 2'd0 : 2'd2
)
(
	////////////////////////////////////////////////////////////////
	//	External Clock & Reset
	input 			clk_24m,			//	24MHz Crystal
	
	
	////////////////////////////////////////////////////////////////
	//	System Clock
	output 			sys_pll_rstn_o, 		
	
	input 			clk_sys,			//	Sys PLL 96MHz 
	input 			clk_pixel,			//	Sys PLL 74.25MHz
	input 			clk_pixel_2x,		//	Sys PLL 148.5MHz
	input 			clk_pixel_10x,		//	Sys PLL 742.5MHz
	
	input 			sys_pll_lock,		//	Sys PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR Clock
	output 			ddr_pll_rstn_o, 
	
	input 			tdqss_clk,			
	input 			core_clk,			//	DDR PLL 200MHz
	input 			tac_clk,			
	input 			twd_clk,			
	
	input 			ddr_pll_lock,		//	DDR PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR PLL Phase Shift Interface
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,
	
	
	
	////////////////////////////////////////////////////////////////
	//	DDR Interface Ports
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	//	DQ I/O
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	//	DM O
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	//	DQS I/O
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
//	input 	[1:0] 	i_dqs_n_hi,
//	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
//	output 	[1:0] 	o_dqs_n_hi,
//	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	//	CK
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Ctl / I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,
	
	//	MIPI-CSI RXC 
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,
	
	//	MIPI-CSI RXD0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,
	
	//	MIPI-CSI RXD1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,
	
	//	MIPI-CSI RXD2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,
	
	//	MIPI-CSI RXD3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,
	
	//output 			csi_rxd0_fifo_rd_o, 
	//input 			csi_rxd0_fifo_empty_i, 
	//output 			csi_rxd1_fifo_rd_o, 
	//input 			csi_rxd1_fifo_empty_i, 
	//output 			csi_rxd2_fifo_rd_o, 
	//input 			csi_rxd2_fifo_empty_i, 
	//output 			csi_rxd3_fifo_rd_o, 
	//input 			csi_rxd3_fifo_empty_i, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	UART Interface
	input 		 	uart_rx_i,			//	115200-8-N-1 UART receive.
	output 		 	uart_tx_o, 
	
	
	output 	[5:0] 	led_o,			//	
	
	////////////////////////////////////////////////////////////////
	//	Extension Board (H1) Interface
	//	SPI (shared ADC + OLED), TF card (SD protocol) 4-bit, and KEY.
	input 			key,				//	KEY: board pull-up, pressed = 0

	input 			spi_miso,			//	MCP3202 DOUT
	output 			spi_sclk,			//	Shared SPI clock (ADC + OLED)
	output 			spi_mosi,			//	ADC DIN / OLED MOSI

	output 			cs_oled,			//	OLED CS, active low
	output 			oled_dc,			//	OLED DC, 0 = command, 1 = data
	output 			cs_adc,				//	MCP3202 CS/SHDN, active low

	output 			sd_clk,				//	SD clock
	input 			sd_cmd_i,			//	SD CMD input
	output 			sd_cmd_o,			//	SD CMD output
	output 			sd_cmd_oe,			//	SD CMD output enable, 0 = Hi-Z
	input 	[3:0]	sd_dat_i,			//	SD DAT[3:0] input
	output 	[3:0]	sd_dat_o,			//	SD DAT[3:0] output
	output 	[3:0]	sd_dat_oe,			//	SD DAT[3:0] output enable, 0 = Hi-Z

	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o,
 input cfg_ERROR,output [1:0] cfg_CBSEL,output cfg_CONFIG,cfg_ENA
);
	
    wire [1:0] w_boot_selected;wire [3:0] w_boot_status;wire w_boot_stop;
    wire w_boot_safe;
    assign w_boot_safe=1'b1;

	wire 			csi_rxd0_fifo_rd_o; 
	wire 			csi_rxd0_fifo_empty_i = 0;  
	wire 			csi_rxd1_fifo_rd_o;  
	wire 			csi_rxd1_fifo_empty_i = 0;  
	wire 			csi_rxd2_fifo_rd_o;  
	wire 			csi_rxd2_fifo_empty_i = 0;  
	wire 			csi_rxd3_fifo_rd_o;  
	wire 			csi_rxd3_fifo_empty_i = 0;  
	
	wire 	[1:0] 	i_dqs_n_hi;
	wire 	[1:0] 	i_dqs_n_lo;
	wire 	[1:0] 	o_dqs_n_hi;
	wire 	[1:0] 	o_dqs_n_lo;
	
	
	//	Hardware Configuration
	assign clk_p_hi = 1'b0;	//	DDR3 Clock requires 180 degree shifted. 
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	//	System Clock Tree Control
	assign sys_pll_rstn_o = 1'b1; 	//	nrst; 	//	Reset whole system when nrst (K2) is pressed. 
	
	assign ddr_pll_rstn_o = sys_pll_lock; 
	
	wire 			w_pll_lock = sys_pll_lock && ddr_pll_lock;
	
	//	Synchronize System Resets. 
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 
	
	//	Clock Gen
	always @(posedge clk_sys or negedge w_pll_lock) begin if(~w_pll_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel_2x or negedge w_pll_lock) begin if(~w_pll_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
	
	
	localparam 	CLOCK_MAIN 	= 96000000; 	//	System clock using 96MHz. 


	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	UART 115200-8-N-1 vision, Sobel, white-balance and Gamma control
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	wire 			w_uart_16x_tick;
	wire 	[7:0]	w_uart_rx_data;
	wire 			w_uart_rx_valid;
	wire 			w_uart_cmd_tx_done;
	wire 	[7:0]	w_uart_cmd_tx_data;
	wire 			w_uart_cmd_tx_start;
	wire 			w_uart_msg_tx_valid;
	wire 	[7:0]	w_uart_msg_tx_data;
	wire 			w_uart_msg_tx_last;
	wire 			w_uart_msg_tx_accept;
	wire 			w_uart_msg_tx_done;
	wire 			w_uart_msg2_tx_valid;
	wire 	[7:0]	w_uart_msg2_tx_data;
	wire 			w_uart_msg2_tx_last;
	wire 			w_uart_msg2_tx_accept;
	wire 			w_uart_msg2_tx_done;
	wire 			w_uart_sd_tx_valid;
	wire 	[7:0]	w_uart_sd_tx_data;
	wire 			w_uart_sd_tx_last;
	wire 			w_uart_sd_tx_accept;
	wire 			w_uart_sd_tx_done;
	wire 			w_uart_phy_tx_done;
	wire 	[7:0]	w_uart_phy_tx_data;
	wire 			w_uart_phy_tx_start;
	wire 	[1:0]	w_video_mode_request;
	wire 	[10:0]	w_edge_threshold_request;
	wire 	[10:0]	w_canny_low_threshold_request;
	wire w_uart_threshold_update;
	wire [10:0] w_edge_threshold_effective_request, w_canny_low_threshold_effective_request;

	// On-screen menu control and display record.  menu_ctrl lives in clk_sys;
	// the display record is synchronized and committed in vertical blanking.
	wire [3:0] ui_stage,ui_event;
    wire [7:0] ui_error;
    wire ui_event_valid,ui_sd_busy,ui_delete_confirm,ui_busy;
    wire [31:0] ui_file;
    wire [9:0] ui_sd_detail;
    // Declare before the nested g_adc.g_menu instance to prevent Verilog
    // from creating an undriven implicit net local to that generate scope.
    wire w_gallery_mode;
	wire [383:0] w_video_diagnostic_data;
    wire w_uart_legacy_valid;
	wire w_menu_open;
	wire w_menu_write_valid;
	wire [4:0] w_menu_write_addr;
	wire [11:0] w_menu_write_value;

    generate if(MULTIBOOT_BUILD)begin:g_flash_switch
    flash_image_switch #(.CURRENT_SLOT(1),.SELECT_ADDR(17),.LOAD_ADDR(18)) u_flash_image_switch(
      .clk(clk_sys),.rst_n(rstn_sys),.write_valid(w_menu_write_valid),.write_addr(w_menu_write_addr),.write_value(w_menu_write_value),
      .safe_to_switch(w_boot_safe),.cfg_error(cfg_ERROR),.selected_slot(w_boot_selected),.status(w_boot_status),
      .stop_request(w_boot_stop),.cfg_cbsel(cfg_CBSEL),.cfg_ena(cfg_ENA),.cfg_config(cfg_CONFIG));
    end else begin:g_no_flash_switch
      assign w_boot_selected=0;assign w_boot_status=0;assign w_boot_stop=0;
      assign cfg_CBSEL=0;assign cfg_ENA=0;assign cfg_CONFIG=0;
    end endgenerate

	wire [`MENU_DISP_WIDTH-1:0] w_menu_disp_sys;
	wire 	[10:0]	w_wb_red_gain_request;
	wire 	[10:0]	w_wb_green_gain_request;
	wire 	[10:0]	w_wb_blue_gain_request;
	wire 			w_gamma_enable_request;
	wire 	[8:0]	w_gamma_strength_request;
	wire 			w_median_enable_request;
	wire 			w_freeze_request;
	wire w_diagnostic_pattern_request;
	wire w_split_enable_request;
    wire w_background_capture_request,w_background_valid,w_background_busy,w_background_error;
    wire [7:0] w_background_data;
    wire w_background_sample_valid,w_background_stream_fault;
    wire [2:0] w_person_view_request;
    wire w_person_edge_source_request,w_person_edge_source_active;
    wire w_edge_bg_ready,w_edge_bg_busy,w_edge_bg_error,w_edge_reference_valid,w_edge_stream_fault;
    wire w_edge_writer_start,w_edge_writer_end,w_edge_writer_valid;
    wire [7:0] w_edge_writer_byte;wire [19:0] w_edge_writer_offset;
    wire w_edge_reader_request,w_edge_photo_read_error;
    wire w_edge_fg_vsync,w_edge_fg_hsync,w_edge_fg_href,w_edge_fg_pixel,w_edge_original_pixel;
    wire [64:0] w_edge_signature;
    (* async_reg="true" *)reg edge_ready_meta,edge_ready_sync;
    always @(posedge clk_sys or negedge rstn_sys)begin
     if(!rstn_sys)begin edge_ready_meta<=0;edge_ready_sync<=0;end
     else begin edge_ready_meta<=w_edge_reference_valid;edge_ready_sync<=edge_ready_meta;end
    end
    wire [7:0] w_difference_threshold_request;
    wire [1:0] w_person_noise_request;
    wire w_person_processing_error;
    (* async_reg="true" *) reg person_error_meta,person_error_sync;
    always @(posedge clk_sys or negedge rstn_sys)begin
        if(!rstn_sys)begin person_error_meta<=0;person_error_sync<=0;end
        else begin person_error_meta<=w_person_processing_error;person_error_sync<=person_error_meta;end
    end
	wire 			w_photo_capture_request;
	wire w_photo_delete_request;
    wire w_photo_uart_request,w_frame_tx_valid,w_frame_tx_last,w_frame_tx_accept,w_frame_tx_done;
    wire [7:0] w_frame_tx_data;
    wire [1:0] w_photo_cleanup_level;
    wire [10:0] w_photo_min_pixels;
	wire 			w_photo_gallery_toggle_request;
	wire 			w_sd_info_query_request;
	wire 			w_photo_gallery_prev_request;
	wire 			w_photo_gallery_next_request;
	wire 			w_gray_canny_enable_request;
	wire 			w_color_canny_enable_request;
	wire 			w_shape_enable_request;
	wire 			w_rect_line_fit_enable_request;
	wire 	[1:0]	w_line_support_level_request;
	wire 	[7:0]	w_black_threshold_request;
	wire 			w_shape_status_query_request;
	localparam [10:0]	DEFAULT_EDGE_THRESHOLD = PHOTO_TF_BUILD?11'd60:11'd25;
	localparam [10:0]	DEFAULT_CANNY_LOW_THRESHOLD = PHOTO_TF_BUILD?11'd30:11'd8;
	localparam [10:0]	DEFAULT_WB_RED_GAIN = PHOTO_TF_BUILD?11'd335:11'd496;
	localparam [10:0]	DEFAULT_WB_GREEN_GAIN = PHOTO_TF_BUILD?11'd248:11'd416;
	localparam [10:0]	DEFAULT_WB_BLUE_GAIN = PHOTO_TF_BUILD?11'd280:11'd313;
	localparam 		DEFAULT_GAMMA_ENABLE = 1'b1;
	localparam [8:0]	DEFAULT_GAMMA_STRENGTH = PHOTO_TF_BUILD?9'd42:9'd255;
	localparam 		DEFAULT_MEDIAN_ENABLE = 1'b1;
	localparam 		DEFAULT_GRAY_CANNY_ENABLE = 1'b1;
	localparam 		DEFAULT_COLOR_CANNY_ENABLE = 1'b1;
	localparam 		DEFAULT_SHAPE_ENABLE = 1'b0;
	localparam 		DEFAULT_RECT_LINE_FIT_ENABLE = 1'b1;
	localparam [1:0]	DEFAULT_LINE_SUPPORT_LEVEL = 2'd0;
	localparam [7:0]	DEFAULT_BLACK_THRESHOLD = 8'd96;
	// 96 MHz / 52 / 16 = 115384.6 baud (+0.16% from 115200 baud).
	integer_divider #(
		.DEVIDE_CNT	(16'd52)
	) u_uart_baud_divider (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.divide_clken	(w_uart_16x_tick)
	);

	uart_receiver u_uart_receiver (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.clken_16bps	(w_uart_16x_tick),
		.rxd			(uart_rx_i),
		.rxd_data		(w_uart_rx_data),
		.rxd_flag		(w_uart_rx_valid)
	);

	// ASCII commands: C=color, G=grayscale, E/S=edge, O=color overlay, T=cycle,
	// A/V confirm Canny; standalone Sobel remains disabled,
	// Hnumber/Lnumber + Enter independently set Canny high/low thresholds,
	// +/- and bare number adjust high; R resets both thresholds,
	// WR/WG/WB + number + Enter=set Q8.8 gains,
	// WD=reset white balance, Y=toggle Gamma, P0..P256=set strength,
	// M=gray display median; image2 also applies it to edge preview and photos,
	// F=toggle DDR frame freeze,
	// D=toggle black-on-white shape detection, Bnumber + Enter=set black
	// threshold (0..255), J=toggle legacy/line-fit rectangle detector,
	// K0..K3 + Enter=set line support to 1/2, 3/8, 1/4, or 1/8,
	// Q=query shape status, ?=query mode. Former game commands are rejected.
	// Gamma strength 256 is full Gamma 2.2.
	image2_vision_ctrl #(
		.SOBEL_AVAILABLE (1'b0),
        .PERSON_AVAILABLE(PERSON_BUILD),
		.PHOTO_AVAILABLE (ENABLE_PHOTO_TF),
		.VISION_AVAILABLE (1'b1),
        .PHOTO_EDGE_PROFILE(PHOTO_TF_BUILD),
		.SHAPE_AVAILABLE (!PHOTO_TF_BUILD && SHAPE_BUILD),
		.OVERLAY_AVAILABLE (!PHOTO_TF_BUILD && COLOR_OVERLAY_BUILD),
		.SPLIT_AVAILABLE (!PHOTO_TF_BUILD && GRAY_EDGE_SPLIT_BUILD),
		.DEFAULT_VIDEO_MODE		(DEFAULT_VIDEO_MODE),
		.DEFAULT_EDGE_THRESHOLD	(DEFAULT_EDGE_THRESHOLD),
		.DEFAULT_CANNY_LOW_THRESHOLD(DEFAULT_CANNY_LOW_THRESHOLD),
		.DEFAULT_WB_RED_GAIN		(DEFAULT_WB_RED_GAIN),
		.DEFAULT_WB_GREEN_GAIN	(DEFAULT_WB_GREEN_GAIN),
		.DEFAULT_WB_BLUE_GAIN	(DEFAULT_WB_BLUE_GAIN),
		.DEFAULT_GAMMA_ENABLE	(DEFAULT_GAMMA_ENABLE),
		.DEFAULT_GAMMA_STRENGTH(DEFAULT_GAMMA_STRENGTH),
		.DEFAULT_MEDIAN_ENABLE(DEFAULT_MEDIAN_ENABLE),
		.DEFAULT_GRAY_CANNY_ENABLE(DEFAULT_GRAY_CANNY_ENABLE),
		.DEFAULT_COLOR_CANNY_ENABLE(DEFAULT_COLOR_CANNY_ENABLE),
		.DEFAULT_SHAPE_ENABLE(DEFAULT_SHAPE_ENABLE),
		.DEFAULT_RECT_LINE_FIT_ENABLE(DEFAULT_RECT_LINE_FIT_ENABLE),
		.DEFAULT_LINE_SUPPORT_LEVEL(DEFAULT_LINE_SUPPORT_LEVEL),
		.DEFAULT_BLACK_THRESHOLD(DEFAULT_BLACK_THRESHOLD)
	) u_uart_vision_ctrl (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.rx_data		(w_uart_rx_data),
		.rx_valid		(w_uart_legacy_valid),
		.sd_info_query_req(w_sd_info_query_request),
		.tx_done		(w_uart_cmd_tx_done),
		.tx_data		(w_uart_cmd_tx_data),
		.tx_start		(w_uart_cmd_tx_start),
		.video_mode_req	(w_video_mode_request),
		.edge_threshold_req(w_edge_threshold_request),
		.canny_low_threshold_req(w_canny_low_threshold_request),
		.threshold_update(w_uart_threshold_update),
		.wb_red_gain_req	(w_wb_red_gain_request),
		.wb_green_gain_req(w_wb_green_gain_request),
		.wb_blue_gain_req	(w_wb_blue_gain_request),
		.gamma_enable_req	(w_gamma_enable_request),
		.gamma_strength_req	(w_gamma_strength_request),
		.median_enable_req	(w_median_enable_request),
		.freeze_req		(w_freeze_request),
		.diagnostic_pattern_req(w_diagnostic_pattern_request),
		.split_enable_req(w_split_enable_request),
		.background_capture_req(w_background_capture_request),
        .person_view_req(w_person_view_request),.person_edge_source_req(w_person_edge_source_request),.difference_threshold_req(w_difference_threshold_request),
        .person_noise_req(w_person_noise_request),.background_ready(w_person_edge_source_request?edge_ready_sync:w_background_valid),
        .background_busy(w_background_busy||w_edge_bg_busy),.background_fault((w_person_edge_source_request?w_edge_bg_error:w_background_error)||person_error_sync),
        .photo_capture_req	(w_photo_capture_request),
		.photo_delete_req(w_photo_delete_request),.photo_uart_req(w_photo_uart_request),
        .photo_cleanup_level_req(w_photo_cleanup_level),.photo_min_pixels_req(w_photo_min_pixels),
		.photo_gallery_toggle_req(w_photo_gallery_toggle_request),
		.photo_gallery_prev_req(w_photo_gallery_prev_request),
		.photo_gallery_next_req(w_photo_gallery_next_request),
		.gray_canny_enable_req(w_gray_canny_enable_request),
		.color_canny_enable_req(w_color_canny_enable_request),
		.shape_enable_req(w_shape_enable_request),
		.rect_line_fit_enable_req(w_rect_line_fit_enable_request),
		.line_support_level_req(w_line_support_level_request),
		.black_threshold_req(w_black_threshold_request),
		.status_query_req(w_shape_status_query_request),
		.menu_write_valid(w_menu_write_valid),
		.menu_write_addr(w_menu_write_addr),
		.menu_write_value(w_menu_write_value)
	);

	wire w_key_tx_valid, w_key_tx_last, w_key_tx_accept, w_key_tx_done;
	wire [7:0] w_key_tx_data;
	generate if (ENABLE_KEY_UART) begin : g_key_uart
		key_uart_reporter #(.DEBOUNCE_CYCLES(1920000)) u_key_uart_reporter (
			.clk(clk_sys), .rst_n(rstn_sys), .key_n(key),
			.tx_valid(w_key_tx_valid), .tx_data(w_key_tx_data),
			.tx_last(w_key_tx_last), .tx_accept(w_key_tx_accept),
			.tx_done(w_key_tx_done)
		);
	end else begin : g_no_key_uart
		assign w_key_tx_valid = 1'b0;
		assign w_key_tx_data = 8'd0;
		assign w_key_tx_last = 1'b0;
	end endgenerate

	wire w_adc_tx_valid, w_adc_tx_last, w_adc_tx_accept, w_adc_tx_done;
	wire [7:0] w_adc_tx_data;
	wire w_uart_aux_accept, w_uart_aux_done;
    // Photo builds reserve message4 for TF status. Their ADC knob is silent.
    localparam ADC_UART_REPORT = ENABLE_ADC && !PHOTO_TF_BUILD;
	assign w_adc_tx_accept = ADC_UART_REPORT ? w_uart_aux_accept : 1'b0;
	assign w_adc_tx_done = ADC_UART_REPORT ? w_uart_aux_done : 1'b0;
	assign w_uart_sd_tx_accept = ADC_UART_REPORT ? 1'b0 : w_uart_aux_accept;
	assign w_uart_sd_tx_done = ADC_UART_REPORT ? 1'b0 : w_uart_aux_done;
	assign w_key_tx_accept = PHOTO_TF_BUILD ? 1'b0 : w_frame_tx_accept;
    assign w_key_tx_done = PHOTO_TF_BUILD ? 1'b0 : w_frame_tx_done;
    uart_tx_arbiter u_uart_tx_arbiter (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.cmd_tx_start	(w_uart_cmd_tx_start),
		.cmd_tx_data	(w_uart_cmd_tx_data),
		.cmd_tx_done	(w_uart_cmd_tx_done),
		.msg_tx_valid	(w_uart_msg_tx_valid),
		.msg_tx_data	(w_uart_msg_tx_data),
		.msg_tx_last	(w_uart_msg_tx_last),
		.msg_tx_accept	(w_uart_msg_tx_accept),
		.msg_tx_done	(w_uart_msg_tx_done),
		.msg2_tx_valid	(w_uart_msg2_tx_valid),
		.msg2_tx_data	(w_uart_msg2_tx_data),
		.msg2_tx_last	(w_uart_msg2_tx_last),
		.msg2_tx_accept	(w_uart_msg2_tx_accept),
		.msg2_tx_done	(w_uart_msg2_tx_done),
		.msg3_tx_valid	(PHOTO_TF_BUILD ? w_frame_tx_valid : w_key_tx_valid),
		.msg3_tx_data	(PHOTO_TF_BUILD ? w_frame_tx_data : w_key_tx_data),
		.msg3_tx_last	(PHOTO_TF_BUILD ? w_frame_tx_last : w_key_tx_last),
		.msg3_tx_accept	(w_frame_tx_accept),
		.msg3_tx_done	(w_frame_tx_done),
		.msg4_tx_valid	(ADC_UART_REPORT ? w_adc_tx_valid : w_uart_sd_tx_valid),
		.msg4_tx_data	(ADC_UART_REPORT ? w_adc_tx_data : w_uart_sd_tx_data),
		.msg4_tx_last	(ADC_UART_REPORT ? w_adc_tx_last : w_uart_sd_tx_last),
		.msg4_tx_accept	(w_uart_aux_accept),
		.msg4_tx_done	(w_uart_aux_done),
		.uart_tx_done	(w_uart_phy_tx_done),
		.uart_tx_data	(w_uart_phy_tx_data),
		.uart_tx_start	(w_uart_phy_tx_start)
	);


	uart_transfer u_uart_transfer (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.clken_16bps	(w_uart_16x_tick),
		.txd			(uart_tx_o),
		.txd_en			(w_uart_phy_tx_start),
		.txd_data		(w_uart_phy_tx_data),
		.txd_flag		(w_uart_phy_tx_done)
	);
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	DDR3 Controller
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	//	General AXI Interface 
	wire	[7:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[7:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[7:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[7:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[7:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	//	AXI Interface Request
	wire 	[7:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	wire 	[2:0]	w_ddr3_cal_shift_val;
	wire 	[7:0]	w_ddr3_cal_fail_log;
	
	//	Do not issue DDR read / write when ~cal_done. 
	reg 			r_ddr_unlock = 0; 
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(),				//	o_dqs_n_oe),
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid),		//	Enable command only when unlocked. 
		.axi_aready		(w_ddr3_aready),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass),
		.cal_shift_val	(w_ddr3_cal_shift_val),
		.cal_fail_log	(w_ddr3_cal_fail_log)
	);
	//	The o_dqs_n_oe may not assert at negative edge. 
	assign o_dqs_n_oe = o_dqs_oe; 
	
	// BREADY is controlled by the transaction-owning DDR arbiter.
	assign shift_sel = 5'b00100; 		//	ddr_tac_clk always use PLLOUT[2]. 
	
	
	AXI4_AWARMux #(.AID_LEN(8), .AADDR_LEN(32)) axi4_awar_mux (
		.aclk_i			(w_ddr3_ui_clk), 
		.arst_i			(w_ddr3_ui_rst), 
		
		.awid_i			(w_ddr3_awid),
		.awaddr_i			(w_ddr3_awaddr),
		.awlen_i			(w_ddr3_awlen),
		.awvalid_i			(w_ddr3_awvalid && r_ddr_unlock),
		.awready_o			(w_ddr3_awready),
		
		.arid_i			(w_ddr3_arid),
		.araddr_i			(w_ddr3_araddr),
		.arlen_i			(w_ddr3_arlen),
		.arvalid_i			(w_ddr3_arvalid && r_ddr_unlock),
		.arready_o			(w_ddr3_arready),
		
		.aid_o			(w_ddr3_aid),
		.aaddr_o			(w_ddr3_aaddr),
		.alen_o			(w_ddr3_alen),
		.atype_o			(w_ddr3_atype),
		.avalid_o			(w_ddr3_avalid),
		.aready_i			(w_ddr3_aready)
	);
	
	assign w_ddr3_asize = 4; 		//	Fixed 128 bits (16 bytes, size = 4)
	assign w_ddr3_aburst = 1; 
	assign w_ddr3_alock = 0; 
	
	assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	I2C Config (SC130GS)
	
	//  i2c timing controller module of 16Bit
	wire            [ 8:0]          sc2210_i2c_config_index;
	wire            [23:0]          sc2210_i2c_config_data;
	wire            [ 8:0]          sc2210_i2c_config_size;
	wire                            sc2210_i2c_config_done;
	
	i2c_timing_ctrl_reg16_dat8_wronly
	#(
	    .CLK_FREQ           (CLOCK_MAIN),                              //  100 MHz
	    .I2C_FREQ           (50_000    )                               //  10 KHz(<= 400KHz)
	) u_i2c_timing_ctrl_16bit (
	    //  global clock
	    .clk                (clk_sys                 ),                          //  96MHz
	    .rst_n              (rstn_sys                ),                          //  system reset

	    //  i2c interface
	    .i2c_sclk           (csi_scl_o               ),                          //  i2c clock
	    .i2c_sdat_IN        (csi_sda_i               ),
	    .i2c_sdat_OUT       (csi_sda_o               ),
	    .i2c_sdat_OE        (csi_sda_oe              ),

	    //  i2c config data
	    .i2c_config_index   (sc2210_i2c_config_index        ),                          //  i2c config reg index, read 2 reg and write xx reg
	    .i2c_config_data    ({8'h60, sc2210_i2c_config_data}),                     //  i2c config data
	    .i2c_config_size    (sc2210_i2c_config_size         ),                          //  i2c config data counte
	    .i2c_config_done    (sc2210_i2c_config_done         )                          //  i2c config timing complete
	);
	assign csi_scl_oe = 1; 

	//  I2C Configure Data of SC2210
	I2C_SC2210_19201080_4Lanes_Config u_I2C_SC2210_19201080_4Lanes_Config
	(
	    .LUT_INDEX  (sc2210_i2c_config_index   ),
	    .LUT_DATA   (sc2210_i2c_config_data    ),
	    .LUT_SIZE   (sc2210_i2c_config_size    )
	);
		
	
		
	// UART activity indicator: toggle LED5 whenever a byte is received.
	reg r_uart_rx_activity = 1'b0;
	always @(posedge clk_sys or negedge rstn_sys) begin
		if(!rstn_sys)
			r_uart_rx_activity <= 1'b0;
		else if(w_uart_rx_valid)
			r_uart_rx_activity <= ~r_uart_rx_activity;
	end
	assign led_o[5] = r_uart_rx_activity;

	assign csi_ctl0_oe = 1'b0;
	assign csi_ctl1_oe = 1'b0;

	////////////////////////////////////////////////////////////////
	//	ADC owns shared SPI when enabled. OLED stays deselected.
	generate if (ENABLE_ADC) begin : g_adc
		wire sample_valid, sample_channel, knob_ready, knob_sample, key_event;
		wire [11:0] sample_data, raw_ch0, raw_ch1, knob_value, key_voltage;
		wire [1:0] key_code;
		mcp3202_spi u_mcp3202_spi (
			.clk(clk_sys), .rst_n(rstn_sys), .spi_miso(spi_miso),
			.spi_sclk(spi_sclk), .spi_mosi(spi_mosi), .cs_adc(cs_adc),
			.sample_valid(sample_valid), .sample_channel(sample_channel),
			.sample_data(sample_data)
		);
		adc_input_ctrl u_adc_input_ctrl (
			.clk(clk_sys), .rst_n(rstn_sys), .sample_valid(sample_valid),
			.sample_channel(sample_channel), .sample_data(sample_data),
			.raw_ch0(raw_ch0), .raw_ch1(raw_ch1), .knob_value(knob_value),
			.knob_ready(knob_ready), .knob_sample(knob_sample), .key_voltage(key_voltage),
			.key_event(key_event), .key_code(key_code)
		);
		adc_uart_reporter u_adc_uart_reporter (
			.clk(clk_sys), .rst_n(rstn_sys),
			.key_event(key_event), .key_code(key_code),
			.tx_valid(w_adc_tx_valid), .tx_data(w_adc_tx_data),
			.tx_last(w_adc_tx_last), .tx_accept(w_adc_tx_accept), .tx_done(w_adc_tx_done)
		);
		if (MENU_BUILD) begin : g_menu
			wire key1_short, key1_long;
			// KEY1: 20 ms debounce, 800 ms long press, one event per press.
			key_press_debounce #(
				.DEBOUNCE_CYCLES(1920000),
				.LONG_CYCLES(76800000)
			) u_key1_debounce (
				.clk(clk_sys), .rst_n(rstn_sys), .key_n(key),
				.short_press(key1_short), .long_press(key1_long)
			);
			image2_menu_ctrl u_menu_ctrl (
                .video_health({w_video_diagnostic_data[271:256],w_video_diagnostic_data[239:224],w_video_diagnostic_data[79:64],w_video_diagnostic_data[47:32]}),
                .cur_cleanup(w_photo_cleanup_level),.cur_minimum(w_photo_min_pixels),
                .ui_stage(ui_stage),.ui_event(ui_event),.ui_error(ui_error),.ui_event_valid(ui_event_valid),
                .ui_sd_busy(ui_sd_busy),.ui_delete_confirm(ui_delete_confirm),.ui_busy(ui_busy),
                .ui_gallery(w_gallery_mode),.ui_file(ui_file),.ui_sd_detail(ui_sd_detail),
				.clk(clk_sys), .rst_n(rstn_sys),
				.key1_short(key1_short), .key1_long(key1_long),
				.key_event(key_event), .key_code(key_code),
				.knob_value(knob_value), .knob_sample(knob_sample),
				.cur_view(w_video_mode_request),
				.cur_split(w_split_enable_request),
				.cur_shape(w_shape_enable_request),
				.cur_freeze(w_freeze_request),
				.cur_test(w_diagnostic_pattern_request),
				.cur_median(w_median_enable_request),
				.cur_gamma(w_gamma_enable_request),
				.cur_high(w_edge_threshold_effective_request),
				.cur_low(w_canny_low_threshold_effective_request),
				.cur_wb_r(w_wb_red_gain_request),
				.cur_wb_g(w_wb_green_gain_request),
				.cur_wb_b(w_wb_blue_gain_request),
				.cur_gamma_p(w_gamma_strength_request),
				.cur_black(w_black_threshold_request),
				.menu_open(w_menu_open),
				.write_valid(w_menu_write_valid),
				.write_addr(w_menu_write_addr),
				.write_value(w_menu_write_value),
				.disp(w_menu_disp_sys)
			);
		end else begin : g_menu_disabled
			assign w_menu_open        = 1'b0;
			assign w_menu_write_valid = 1'b0;
			assign w_menu_write_addr  = 5'd0;
			assign w_menu_write_value = 12'd0;
			assign w_menu_disp_sys    = {`MENU_DISP_WIDTH{1'b0}};
		end
		adc_threshold_ctrl #(.DEFAULT_HIGH(DEFAULT_EDGE_THRESHOLD),
			.DEFAULT_LOW(DEFAULT_CANNY_LOW_THRESHOLD),
			.KNOB_DIRECT(MENU_BUILD ? 1'b0 : 1'b1)) u_adc_threshold_ctrl (
			.clk(clk_sys), .rst_n(rstn_sys), .knob_value(knob_value), .knob_ready(knob_ready),
			.knob_enable(!w_menu_open),
			.uart_update(w_uart_threshold_update), .uart_high(w_edge_threshold_request),
			.uart_low(w_canny_low_threshold_request),
			.high_threshold(w_edge_threshold_effective_request),
			.low_threshold(w_canny_low_threshold_effective_request)
		);
	end else begin : g_no_adc
		assign spi_sclk = 1'b0;
		assign spi_mosi = 1'b0;
		assign cs_adc = 1'b1;
		assign w_adc_tx_valid = 1'b0;
		assign w_adc_tx_data = 8'd0;
		assign w_adc_tx_last = 1'b0;
		assign w_edge_threshold_effective_request = w_edge_threshold_request;
		assign w_canny_low_threshold_effective_request = w_canny_low_threshold_request;
		assign w_menu_open        = 1'b0;
		assign w_menu_write_valid = 1'b0;
		assign w_menu_write_addr  = 5'd0;
		assign w_menu_write_value = 12'd0;
		assign w_menu_disp_sys    = {`MENU_DISP_WIDTH{1'b0}};
	end endgenerate
	assign cs_oled  = 1'b1;
	assign oled_dc  = 1'b0;
	// SD pin drivers are generated only with ENABLE_PHOTO_TF=1;
	// otherwise clock stays low and CMD/DAT output enables stay off.

	////////////////////////////////////////////////////////////////
	//	MIPI CSI RX
	
	//	The CSI RXC shall not be inverted. Data can be inverted with swapped LP data and flipped HS data. 
	localparam 	CSI_RXD_INV 	= 4'b1111; 
	localparam 	CSI_DATA_WIDTH 	= 32; 			
	localparam 	CSI_STRB_WIDTH 	= CSI_DATA_WIDTH / 8; 

	//	Current implementation supports RAW8 only. 
	wire 			w_csi_rx_clk; 
	wire 	[3:0]	w_csi_rx_vsync, w_csi_rx_hsync;
	wire 			w_csi_rx_dvalid;
	wire 			w_csi_rx_vsync0 = w_csi_rx_vsync[0];
	wire 			w_csi_rx_hsync0 = w_csi_rx_hsync[0];
	wire 	[63:0] 	w_csi_rx_data; 
	wire 	[47:0] 	w_csi_rx_data_rel_raw; 
	wire 	[15:0]	w_csi_rx_index;
	
	wire 	[7:0] 	w_mipi_d0 = (CSI_RXD_INV[0] ? 8'hFF : 8'h00) ^ csi_rxd0_hs_i; 
	wire 	[7:0] 	w_mipi_d1 = (CSI_RXD_INV[1] ? 8'hFF : 8'h00) ^ csi_rxd1_hs_i; 
	wire 	[7:0] 	w_mipi_d2 = (CSI_RXD_INV[2] ? 8'hFF : 8'h00) ^ csi_rxd2_hs_i; 
	wire 	[7:0] 	w_mipi_d3 = (CSI_RXD_INV[3] ? 8'hFF : 8'h00) ^ csi_rxd3_hs_i; 
	MIPIRx4LaneFre mipi0_rx (
		.sclk_i			(clk_sys), 
		.srst_i			(rst_sys), 
		
		.mipi_rx_byteclk_i	(csi_rxc_i), 
		.mipi_rx_d0_i		({w_mipi_d0[0], w_mipi_d0[1], w_mipi_d0[2], w_mipi_d0[3], w_mipi_d0[4], w_mipi_d0[5], w_mipi_d0[6], w_mipi_d0[7]}), 
		.mipi_rx_d1_i		({w_mipi_d1[0], w_mipi_d1[1], w_mipi_d1[2], w_mipi_d1[3], w_mipi_d1[4], w_mipi_d1[5], w_mipi_d1[6], w_mipi_d1[7]}), 
		.mipi_rx_d2_i		({w_mipi_d2[0], w_mipi_d2[1], w_mipi_d2[2], w_mipi_d2[3], w_mipi_d2[4], w_mipi_d2[5], w_mipi_d2[6], w_mipi_d2[7]}), 
		.mipi_rx_d3_i		({w_mipi_d3[0], w_mipi_d3[1], w_mipi_d3[2], w_mipi_d3[3], w_mipi_d3[4], w_mipi_d3[5], w_mipi_d3[6], w_mipi_d3[7]}), 
		.mipi_rx_clk_lp_p_i	(csi_rxc_lp_p_i), 
		.mipi_rx_clk_lp_n_i	(csi_rxc_lp_n_i), 
		.mipi_rx_d0_lp_p_i	(CSI_RXD_INV[0] ? csi_rxd0_lp_n_i : csi_rxd0_lp_p_i), 
		.mipi_rx_d0_lp_n_i	(CSI_RXD_INV[0] ? csi_rxd0_lp_p_i : csi_rxd0_lp_n_i), 
		.mipi_rx_rst_o		(), 
		.mipi_rx_rst_n_o		(), 
		.mipi_rx_clk_hs_en_o	(csi_rxc_hs_en_o), 
		.mipi_rx_dat_hs_en_o	(csi_rxd0_hs_en_o), 
		.mipi_rx_clk_term_en_o	(csi_rxc_hs_term_en_o), 
		.mipi_rx_dat_term_en_o	(csi_rxd0_hs_term_en_o), 
		
		.CLK				(w_csi_rx_clk), 
		.VSYNC			(w_csi_rx_vsync),
		.HSYNC			(w_csi_rx_hsync),
		.DE				(w_csi_rx_dvalid), 
		.DAT				(w_csi_rx_data_rel_raw),
		.INDEX			(w_csi_rx_index)
	);
	assign w_csi_rx_data = {2{w_csi_rx_data_rel_raw[47:40], w_csi_rx_data_rel_raw[35:28], w_csi_rx_data_rel_raw[23:16], w_csi_rx_data_rel_raw[11:4]}}; 
	assign {csi_rxd3_hs_en_o, csi_rxd2_hs_en_o, csi_rxd1_hs_en_o} = {3{csi_rxd0_hs_en_o}}; 
	assign {csi_rxd3_hs_term_en_o, csi_rxd2_hs_term_en_o, csi_rxd1_hs_term_en_o} = {3{csi_rxd0_hs_term_en_o}}; 
	
	
	
	//	Output LED
	reg 	[5:0]		r_csi_fv_o = 0; 
	reg 	[1:0] 	r_csi_rx_vsync0_in = 0; 
	always @(posedge w_csi_rx_clk) begin
		r_csi_rx_vsync0_in <= {r_csi_rx_vsync0_in[0], w_csi_rx_vsync0};
		r_csi_fv_o <= r_csi_fv_o + ((r_csi_rx_vsync0_in == 2'b01) ? 6'd1 : 6'd0);
	end
	assign led_o[4] = r_csi_fv_o[5]; 
	
	
	
	//	Data Write Assignment
	wire			cmos_frame_vsync = w_csi_rx_vsync0;                     //  cmos frame data vsync valid signal
	wire			cmos_frame_href = w_csi_rx_hsync0 && w_csi_rx_dvalid;	 //  cmos frame data href vaild  signal
	wire	[63:0]	cmos_frame_Gray = {w_csi_rx_data[7:0], w_csi_rx_data[15:8], w_csi_rx_data[23:16], w_csi_rx_data[31:24], w_csi_rx_data[39:32], w_csi_rx_data[47:40], w_csi_rx_data[55:48], w_csi_rx_data[63:56]}; 

	












	////////////////////////////////////////////////////////////////
	//	DDR R/W Control
	

	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request; 
	wire            [7:0]           lcd_red, lcd_red2;
	wire            [7:0]           lcd_green, lcd_green2;
	wire            [7:0]           lcd_blue, lcd_blue2;
	wire            [7:0]           lcd_data;
	assign w_ddr3_wid = 8'b0;

	wire 	[31:0] 	w_axi_tp;
	wire 			w_read_underflow_sticky;
	wire 	[31:0]	w_read_underflow_count;
	wire 			w_bad_frame_sticky;
	wire 	[31:0]	w_bad_frame_count;
	wire 	[2:0]	w_axi_awsize_unused, w_axi_arsize_unused;
	wire 	[1:0]	w_axi_awburst_unused, w_axi_arburst_unused;
	wire 			w_axi_awlock_unused, w_axi_arlock_unused;
	wire 	[3:0]	w_axi_awcache_unused, w_axi_arcache_unused;
	wire 	[2:0]	w_axi_awprot_unused, w_axi_arprot_unused;
	wire 	[3:0]	w_axi_awqos_unused, w_axi_arqos_unused;
	wire 			w_axi_bready_unused;

	// TF gallery data path.  `photo_ddr_stage` keeps its buffer selection in
	// clk_sys; the AXI controller is still the only DDR master.
	wire        w_gallery_busy;
	wire        w_gallery_error;
	wire [31:0] w_gallery_file_number;
	wire        w_gallery_load_start;
	wire        w_gallery_load_byte_valid;
	wire [7:0]  w_gallery_load_byte;
	wire [19:0] w_gallery_load_byte_offset;
	wire        w_gallery_load_done;
	wire        w_gallery_load_error;
	wire        w_photo_write_valid;
	wire        w_photo_write_buffer;
	wire [19:0] w_photo_write_offset;
	wire [7:0]  w_photo_write_data;
	wire        w_gallery_display_enable_sys;
	wire        w_gallery_display_buffer_sys;
	wire        w_photo_rframe_data_en;
	wire [7:0]  w_photo_rframe_data;
	wire        w_photo_rframe_valid;
	wire w_photo_stream_reset, w_gallery_writer_busy, w_gallery_word_commit, w_gallery_write_error;
	wire w_gallery_stage_busy;
	wire w_gallery_stage_failed,w_gallery_abort,w_gallery_ready;
	wire w_gallery_frame_error;
	(* async_reg = "true" *) reg r_gallery_error_meta = 1'b0;
	(* async_reg = "true" *) reg r_gallery_error_sync = 1'b0;
	always @(posedge clk_sys or negedge rstn_sys) begin
		if (!rstn_sys) begin r_gallery_error_meta<=0;r_gallery_error_sync<=0;end
		else begin r_gallery_error_meta<=w_gallery_frame_error;r_gallery_error_sync<=r_gallery_error_meta;end
	end

	// VSYNC reaches the sys clock as a toggle: it is used only to commit an
	// already complete non-visible photo buffer.
	(* async_reg = "true" *) reg r_gallery_vs_meta = 1'b0;
	(* async_reg = "true" *) reg r_gallery_vs_sync = 1'b0;
	reg r_gallery_vs_seen = 1'b0;
	reg r_gallery_vsync_toggle_sys = 1'b0;
	always @(posedge clk_sys or negedge rstn_sys) begin
		if (!rstn_sys) begin
			r_gallery_vs_meta <= 1'b0;
			r_gallery_vs_sync <= 1'b0;
			r_gallery_vs_seen <= 1'b0;
			r_gallery_vsync_toggle_sys <= 1'b0;
		end else begin
			r_gallery_vs_meta <= lcd_vs;
			r_gallery_vs_sync <= r_gallery_vs_meta;
			if (r_gallery_vs_sync != r_gallery_vs_seen) begin
				r_gallery_vs_seen <= r_gallery_vs_sync;
				if (r_gallery_vs_sync) r_gallery_vsync_toggle_sys <= ~r_gallery_vsync_toggle_sys;
			end
		end
	end


	// Video AXI protection remains. The disabled photo client is tied inactive.
	wire [31:0] w_video_awaddr;
	wire [7:0] w_video_awlen;
	wire w_video_awvalid;
	wire w_video_awready;
	wire [127:0] w_video_wdata;
	wire [15:0] w_video_wstrb;
	wire w_video_wlast;
	wire w_video_wvalid;
	wire w_video_wready;
	wire [1:0] w_video_bresp;
	wire w_video_bvalid;
	wire [31:0] w_video_araddr;
	wire [7:0] w_video_arlen;
	wire w_video_arvalid;
	wire w_video_arready;
	wire [127:0] w_video_rdata;
	wire [1:0] w_video_rresp;
	wire w_video_rlast;
	wire w_video_rvalid;
	wire w_video_rready;
	wire w_video_read_flush,w_video_read_urgent,w_axi_read_stalled;
	wire [3:0] w_axi_read_debug;
	wire [31:0] w_capture_awaddr;
	wire [7:0] w_capture_awlen;
	wire w_capture_awvalid;
	wire w_capture_awready;
	wire [127:0] w_capture_wdata;
	wire w_capture_wlast;
	wire w_capture_wvalid;
	wire w_capture_wready;
	wire [1:0] w_capture_bresp;
	wire w_capture_bvalid;
	wire [31:0] w_capture_araddr;
	wire [7:0] w_capture_arlen;
	wire w_capture_arvalid;
	wire w_capture_arready;
	wire [127:0] w_capture_rdata;
	wire [1:0] w_capture_rresp;
	wire w_capture_rlast;
	wire w_capture_rvalid;
	wire w_capture_rready;
	wire [7:0] w_video_awid,w_video_arid;
	wire [7:0] w_video_bid = 8'd0, w_video_rid = 8'd0;
	assign w_ddr3_awid = 8'd0;
	assign w_ddr3_arid = 8'd0;

	photo_axi_mux u_photo_axi_mux (
		.clk(clk_sys), .rst_n(rstn_sys),
		.v_read_flush(w_video_read_flush),.v_read_urgent(w_video_read_urgent),
		.read_stalled(w_axi_read_stalled),.read_debug(w_axi_read_debug),
		.v_awaddr(w_video_awaddr),
		.v_awlen(w_video_awlen),
		.v_awvalid(w_video_awvalid),
		.v_awready(w_video_awready),
		.v_wdata(w_video_wdata),
		.v_wstrb(w_video_wstrb),
		.v_wlast(w_video_wlast),
		.v_wvalid(w_video_wvalid),
		.v_wready(w_video_wready),
		.v_bresp(w_video_bresp),
		.v_bvalid(w_video_bvalid),
		.v_araddr(w_video_araddr),
		.v_arlen(w_video_arlen),
		.v_arvalid(w_video_arvalid),
		.v_arready(w_video_arready),
		.v_rdata(w_video_rdata),
		.v_rresp(w_video_rresp),
		.v_rlast(w_video_rlast),
		.v_rvalid(w_video_rvalid),
		.v_rready(w_video_rready),
		.p_awaddr(w_capture_awaddr),
		.p_awlen(w_capture_awlen),
		.p_awvalid(w_capture_awvalid),
		.p_awready(w_capture_awready),
		.p_wdata(w_capture_wdata),
		.p_wlast(w_capture_wlast),
		.p_wvalid(w_capture_wvalid),
		.p_wready(w_capture_wready),
		.p_bresp(w_capture_bresp),
		.p_bvalid(w_capture_bvalid),
		.p_araddr(w_capture_araddr),
		.p_arlen(w_capture_arlen),
		.p_arvalid(w_capture_arvalid),
		.p_arready(w_capture_arready),
		.p_rdata(w_capture_rdata),
		.p_rresp(w_capture_rresp),
		.p_rlast(w_capture_rlast),
		.p_rvalid(w_capture_rvalid),
		.p_rready(w_capture_rready),
		.m_awaddr(w_ddr3_awaddr),
		.m_awlen(w_ddr3_awlen),
		.m_awvalid(w_ddr3_awvalid),
		.m_awready(w_ddr3_awready),
		.m_wdata(w_ddr3_wdata),
		.m_wstrb(w_ddr3_wstrb),
		.m_wlast(w_ddr3_wlast),
		.m_wvalid(w_ddr3_wvalid),
		.m_wready(w_ddr3_wready),
		.m_bresp(w_ddr3_bresp),
		.m_bvalid(w_ddr3_bvalid),
		.m_araddr(w_ddr3_araddr),
		.m_arlen(w_ddr3_arlen),
		.m_arvalid(w_ddr3_arvalid),
		.m_arready(w_ddr3_arready),
		.m_rdata(w_ddr3_rdata),
		.m_rresp(w_ddr3_rresp),
		.m_rlast(w_ddr3_rlast),
		.m_rvalid(w_ddr3_rvalid),
		.m_rready(w_ddr3_rready),
		.m_bready(w_ddr3_bready)
	);
	axi4_ctrl #(.C_PHOTO_BYTES(PERSON_BUILD?259200:1036800),.BACKGROUND_BUILD(PERSON_BUILD),.C_RD_END_ADDR(1920 * 1080), .C_W_WIDTH(CSI_DATA_WIDTH), .C_R_WIDTH(8), .C_ID_LEN(8)) u_axi4_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_video_awaddr       ),
		.axi_awid       (w_video_awid         ),
		.axi_awlen      (w_video_awlen        ),
		.axi_awsize     (w_axi_awsize_unused ),
		.axi_awburst    (w_axi_awburst_unused),
		.axi_awlock     (w_axi_awlock_unused ),
		.axi_awcache    (w_axi_awcache_unused),
		.axi_awprot     (w_axi_awprot_unused ),
		.axi_awqos      (w_axi_awqos_unused  ),
		.axi_awvalid    (w_video_awvalid      ),
		.axi_awready    (w_video_awready      ),

		.axi_wdata      (w_video_wdata        ),
		.axi_wstrb      (w_video_wstrb        ),
		.axi_wlast      (w_video_wlast        ),
		.axi_wvalid     (w_video_wvalid       ),
		.axi_wready     (w_video_wready       ),

		.axi_bid        (w_video_bid           ),
		.axi_bresp      (w_video_bresp         ),
		.axi_bvalid     (w_video_bvalid        ),
		.axi_bready     (w_axi_bready_unused  ),

		.axi_arid       (w_video_arid         ),
		.axi_araddr     (w_video_araddr       ),
		.axi_arlen      (w_video_arlen        ),
		.axi_arsize     (w_axi_arsize_unused ),
		.axi_arburst    (w_axi_arburst_unused),
		.axi_arlock     (w_axi_arlock_unused ),
		.axi_arcache    (w_axi_arcache_unused),
		.axi_arprot     (w_axi_arprot_unused ),
		.axi_arqos      (w_axi_arqos_unused  ),
		.axi_arvalid    (w_video_arvalid      ),
		.axi_arready    (w_video_arready      ),

		.axi_rid        (w_video_rid          ),
		.axi_rdata      (w_video_rdata        ),
		.axi_rresp      (w_video_rresp         ),
		.axi_rlast      (w_video_rlast        ),
		.axi_rvalid     (w_video_rvalid       ),
		.axi_rready     (w_video_rready       ),
		.read_frame_flush(w_video_read_flush),
		.read_urgent(w_video_read_urgent),

		.wframe_pclk    (w_csi_rx_clk          ),
		.wframe_vsync   (cmos_frame_vsync),		//	Writter VSync. Flush on rising edge. Connect to EOF.
		.wframe_data_en (cmos_frame_href   ),
		.wframe_data    (cmos_frame_Gray[31:0]),
		
		.rframe_pclk    (clk_pixel_2x            ),
		.rframe_vsync   (~lcd_vs             ),		//	Reader VSync. Flush on rising edge. Connect to ~EOF. 
		.rframe_data_en (lcd_request             ),
		.rframe_data    (lcd_data           ),

		.freeze_i       (w_freeze_request    ),
        .background_capture_i(w_background_capture_request&&!w_person_edge_source_request),.background_read_enable_i(PERSON_BUILD&&!w_person_edge_source_request),
        .background_valid(w_background_valid),.background_capture_busy(w_background_busy),.background_error(w_background_error),
        .background_rframe_data(w_background_data),.background_rframe_valid(w_background_sample_valid),
        .background_stream_fault(w_background_stream_fault),
		.photo_write_valid_i(w_photo_write_valid),
		.photo_write_buffer_i(w_photo_write_buffer),
		.photo_write_offset_i(w_photo_write_offset),
		.photo_write_data_i(w_photo_write_data),
		.photo_load_start_i(w_gallery_load_start),
		.photo_load_end_i(w_gallery_load_done || w_gallery_load_error || w_gallery_stage_failed || (!w_gallery_mode&&!PERSON_BUILD)),
		.photo_write_busy_o(w_gallery_writer_busy),
		.photo_word_commit_o(w_gallery_word_commit),
		.photo_write_error_o(w_gallery_write_error),
		.photo_read_enable_i(w_gallery_display_enable_sys),
		.photo_read_buffer_i(w_gallery_display_buffer_sys),
		.photo_rframe_pclk(clk_pixel_2x),
		.photo_rframe_vsync(PERSON_BUILD?~w_edge_fg_vsync:~lcd_vs),
		.photo_rframe_data_en(w_photo_rframe_data_en),
		.photo_rframe_data(w_photo_rframe_data),
		.photo_rframe_valid(w_photo_rframe_valid),
		.photo_stream_reset_o(w_photo_stream_reset),.photo_read_error_o(w_edge_photo_read_error),
		.read_underflow_sticky(w_read_underflow_sticky),
		.read_underflow_count(w_read_underflow_count),
		.bad_frame_sticky(w_bad_frame_sticky),
		.bad_frame_count(w_bad_frame_count),
		
		.tp_o 		(w_axi_tp)
	);
	// LED2 latches a display FIFO underflow; LED3 latches a rejected,
	// incomplete camera frame. Both clear on system reset.
	assign led_o[3:2] = {w_bad_frame_sticky, w_read_underflow_sticky};

	// Declare the shared video nets BEFORE the generated photo scope uses them.
	// Otherwise Verilog may create undriven local g_photo_tf.w_gamma_* nets.
	wire w_gamma_vsync, w_gamma_hsync, w_gamma_href;
	wire [7:0] w_gamma_r, w_gamma_g, w_gamma_b;

	generate if (ENABLE_PHOTO_TF) begin : g_photo_tf
	// Unified native SD session: initialization, save and gallery share one host.
	image2_photo_pipeline #(.CLK_HZ(CLOCK_MAIN),.ENABLE_DELETE(PHOTO_TF_BUILD),.ENABLE_PROCESSING(PHOTO_TF_BUILD),.ENABLE_UART_EXPORT(PHOTO_TF_BUILD)) u_photo_native_pipeline (
		.clk(clk_sys),
		.rst_n(rstn_sys),
		.pclk(clk_pixel_2x),
		.prst_n(rstn_pixel),
		.capture_req(w_photo_capture_request),.uart_capture_req(w_photo_uart_request),
        .frame_tx_valid(w_frame_tx_valid),.frame_tx_data(w_frame_tx_data),.frame_tx_last(w_frame_tx_last),
        .frame_tx_accept(w_frame_tx_accept),.frame_tx_done(w_frame_tx_done),
		.delete_req(w_photo_delete_request),
		.query_req(w_sd_info_query_request),
		.axi_read_stalled(w_axi_read_stalled),.axi_read_debug(w_axi_read_debug),
		.capture_accepted(),
        .ui_stage(ui_stage),.ui_event(ui_event),.ui_error(ui_error),.ui_event_valid(ui_event_valid),
        .ui_sd_busy(ui_sd_busy),.ui_delete_confirm(ui_delete_confirm),.ui_busy(ui_busy),.ui_file(ui_file),.ui_sd_detail(ui_sd_detail),
		// All photo modes start from aligned WB/Gamma RGB. The native controller
		// snapshots C/G/E and processes grayscale/edges before publishing to TF.
		.in_vsync(w_gamma_vsync),
		.in_href(w_gamma_href),
		.red(w_gamma_r),
		.green(w_gamma_g),
		.blue(w_gamma_b),
        .capture_mode(w_video_mode_request),.median_enable(w_median_enable_request),
        .cleanup_level(w_photo_cleanup_level),.min_pixels(w_photo_min_pixels),
        .high_threshold(w_edge_threshold_effective_request),.low_threshold(w_canny_low_threshold_effective_request),
		.gallery_toggle_req(w_photo_gallery_toggle_request),
		.gallery_prev_req(w_photo_gallery_prev_request),
		.gallery_next_req(w_photo_gallery_next_request),
		.gallery_mode(w_gallery_mode),
		.gallery_busy(w_gallery_busy),
		.gallery_error(w_gallery_error),
		.gallery_file_number(w_gallery_file_number),
		.gallery_load_start(w_gallery_load_start),
		.gallery_load_byte_valid(w_gallery_load_byte_valid),
		.gallery_load_byte(w_gallery_load_byte),
		.gallery_load_byte_offset(w_gallery_load_byte_offset),
		.gallery_load_done(w_gallery_load_done),
		.gallery_load_error(w_gallery_load_error),
		.gallery_ddr_busy(w_gallery_stage_busy || w_gallery_writer_busy),
		.gallery_ddr_failed(w_gallery_stage_failed),.gallery_abort(w_gallery_abort),.gallery_ready(w_gallery_ready),
		.gallery_display_error(r_gallery_error_sync),
		.tx_valid(w_uart_sd_tx_valid),
		.tx_data(w_uart_sd_tx_data),
		.tx_last(w_uart_sd_tx_last),
		.tx_accept(w_uart_sd_tx_accept),
		.tx_done(w_uart_sd_tx_done),
		.sd_clk(sd_clk),
		.sd_cmd_o(sd_cmd_o),
		.sd_cmd_oe(sd_cmd_oe),
		.sd_cmd_i(sd_cmd_i),
		.sd_dat_i(sd_dat_i),
		.sd_dat_o(sd_dat_o),
		.sd_dat_oe(sd_dat_oe),
		.awaddr(w_capture_awaddr),
		.awlen(w_capture_awlen),
		.awvalid(w_capture_awvalid),
		.awready(w_capture_awready),
		.wdata(w_capture_wdata),
		.wlast(w_capture_wlast),
		.wvalid(w_capture_wvalid),
		.wready(w_capture_wready),
		.bresp(w_capture_bresp),
		.bvalid(w_capture_bvalid),
		.araddr(w_capture_araddr),
		.arlen(w_capture_arlen),
		.arvalid(w_capture_arvalid),
		.arready(w_capture_arready),
		.rdata(w_capture_rdata),
		.rresp(w_capture_rresp),
		.rlast(w_capture_rlast),
		.rvalid(w_capture_rvalid),
		.rready(w_capture_rready)
	);

	photo_ddr_stage u_photo_ddr_stage (
		.clk				(clk_sys),
		.rst_n				(rstn_sys),
		.load_start		(w_gallery_load_start),
		.load_byte_valid	(w_gallery_load_byte_valid),
		.load_byte			(w_gallery_load_byte),
		.load_byte_offset	(w_gallery_load_byte_offset),
		.load_done			(w_gallery_load_done),
		.load_error			(w_gallery_load_error),
		.gallery_mode		(w_gallery_mode),
		.display_vsync_toggle(r_gallery_vsync_toggle_sys),
		.word_commit(w_gallery_word_commit),
		.writer_busy(w_gallery_writer_busy),
		.write_error(w_gallery_write_error),
		.load_busy			(w_gallery_stage_busy),
		.load_failed		(w_gallery_stage_failed),
		.load_abort(w_gallery_abort),.load_ready(w_gallery_ready),
		.loaded_byte_count	(),
		.photo_write_valid	(w_photo_write_valid),
		.photo_write_buffer	(w_photo_write_buffer),
		.photo_write_offset	(w_photo_write_offset),
		.photo_write_data	(w_photo_write_data),
		.gallery_display_enable(w_gallery_display_enable_sys),
		.display_buffer		(w_gallery_display_buffer_sys),
		.display_switch_toggle()
	);
	end else begin : g_photo_tf_disabled
		assign w_gallery_mode = 1'b0;
		assign w_gallery_busy = 1'b0;
		assign w_gallery_error = 1'b0;
		assign w_gallery_file_number = 32'd0;
		assign w_gallery_load_start = PERSON_BUILD?w_edge_writer_start:1'b0;
		assign w_gallery_load_byte_valid = 1'b0;
		assign w_gallery_load_byte = 8'd0;
		assign w_gallery_load_byte_offset = 20'd0;
		assign w_gallery_load_done = PERSON_BUILD?w_edge_writer_end:1'b0;
		assign w_gallery_load_error = 1'b0;
		assign w_gallery_stage_busy = 1'b0;
		assign w_gallery_stage_failed = 1'b0;
		assign w_gallery_abort = 1'b0;
		assign w_gallery_ready = 1'b0;
		assign w_photo_write_valid = PERSON_BUILD?w_edge_writer_valid:1'b0;
		assign w_photo_write_buffer = 1'b0;
		assign w_photo_write_offset = PERSON_BUILD?w_edge_writer_offset:20'd0;
		assign w_photo_write_data = PERSON_BUILD?w_edge_writer_byte:8'd0;
		assign w_gallery_display_enable_sys = PERSON_BUILD&&w_person_edge_source_request&&w_edge_bg_ready&&edge_ready_sync;
		assign w_gallery_display_buffer_sys = 1'b0;
		assign w_frame_tx_valid=1'b0;assign w_frame_tx_data=8'd0;assign w_frame_tx_last=1'b0;
		assign w_uart_sd_tx_valid = 1'b0;
		assign w_uart_sd_tx_data = 8'd0;
		assign w_uart_sd_tx_last = 1'b0;
		assign sd_clk = 1'b0;
		assign sd_cmd_o = 1'b1;
		assign sd_cmd_oe = 1'b0;
		assign sd_dat_o = 4'hf;
		assign sd_dat_oe = 4'h0;
		assign w_capture_awaddr = 32'd0;
		assign w_capture_awlen = 8'd0;
		assign w_capture_awvalid = 1'b0;
		assign w_capture_wdata = 128'd0;
		assign w_capture_wlast = 1'b0;
		assign w_capture_wvalid = 1'b0;
		assign w_capture_araddr = 32'd0;
		assign w_capture_arlen = 8'd0;
		assign w_capture_arvalid = 1'b0;
		assign w_capture_rready = 1'b1;
	end endgenerate

	
	
	
	////////////////////////////////////////////////////////////////
	//  LCD Timing Driver
	
	wire [11:0] lcd_xpos_unused, lcd_ypos_unused;

	lcd_driver u_lcd_driver
	(
	    //  global clock
	    .clk        (clk_pixel_2x   ),
	    .rst_n      (rstn_pixel), 
	    
	    //  lcd interface
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	//	Request data 1 cycle ahead. 
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_rgb    ({lcd_red2,lcd_green2,lcd_blue2, lcd_red,lcd_green,lcd_blue}),
	    .lcd_xpos   (lcd_xpos_unused),
	    .lcd_ypos   (lcd_ypos_unused),
	    
	    //  user interface
	    .lcd_data   ({6{lcd_data}}  )
	);
	
	
	

	wire 			w_rgb_vsync, w_rgb_hsync, w_rgb_href; 
	wire 	[7:0] 	w_rgb_r, w_rgb_g, w_rgb_b; 
	
	VIP_RAW8_RGB888 #(.IMG_HDISP(1920), .IMG_VDISP(1080)) bayer2rgb (
		.clk				(clk_pixel_2x),                //cmos video pixel clock
		.rst_n			(rstn_pixel),              //global reset
	    
		.mirror			(2'b00),

		    //CMOS YCbCr444 data output
		.per_frame_vsync		(lcd_vs),    //Prepared Image data vsync valid signal. Reset on falling edge. 
		.per_frame_href		(lcd_de),     //Prepared Image data href vaild  signal
		.per_frame_hsync		(lcd_hs),     //Prepared Image data href vaild  signal
		.per_img_RAW		(lcd_green),        //Prepared Image data 8 Bit RAW Data

		.post_frame_vsync		(w_rgb_vsync),   //Processed Image data vsync valid signal
		.post_frame_href		(w_rgb_href),    //Processed Image data href vaild  signal
		.post_frame_hsync		(w_rgb_hsync),    //Processed Image data href vaild  signal
		.post_img_red		(w_rgb_r),       //Prepared Image green data to be processed 
		.post_img_green		(w_rgb_g),     //Prepared Image green data to be processed
		.post_img_blue		(w_rgb_b)       //Prepared Image blue data to be processed
	);

	// Synchronize the slowly changing UART configuration into the video clock
	// domain, then apply it only at a frame boundary.  The request remains stable
	// for many pixel clocks before capture, so the complete bus has settled.
	(* async_reg = "true" *) reg [1:0] r_video_mode_meta = DEFAULT_VIDEO_MODE;
	(* async_reg = "true" *) reg [1:0] r_video_mode_sync = DEFAULT_VIDEO_MODE;
	(* async_reg = "true" *) reg [10:0] r_wb_red_gain_meta = DEFAULT_WB_RED_GAIN;
	(* async_reg = "true" *) reg [10:0] r_wb_red_gain_sync = DEFAULT_WB_RED_GAIN;
	(* async_reg = "true" *) reg [10:0] r_wb_green_gain_meta = DEFAULT_WB_GREEN_GAIN;
	(* async_reg = "true" *) reg [10:0] r_wb_green_gain_sync = DEFAULT_WB_GREEN_GAIN;
	(* async_reg = "true" *) reg [10:0] r_wb_blue_gain_meta = DEFAULT_WB_BLUE_GAIN;
	(* async_reg = "true" *) reg [10:0] r_wb_blue_gain_sync = DEFAULT_WB_BLUE_GAIN;
	(* async_reg = "true" *) reg r_gamma_enable_meta = DEFAULT_GAMMA_ENABLE;
	(* async_reg = "true" *) reg r_gamma_enable_sync = DEFAULT_GAMMA_ENABLE;
	(* async_reg = "true" *) reg [8:0] r_gamma_strength_meta = DEFAULT_GAMMA_STRENGTH;
	(* async_reg = "true" *) reg [8:0] r_gamma_strength_sync = DEFAULT_GAMMA_STRENGTH;
	(* async_reg = "true" *) reg r_median_enable_meta = DEFAULT_MEDIAN_ENABLE;
	(* async_reg = "true" *) reg r_median_enable_sync = DEFAULT_MEDIAN_ENABLE;
	(* async_reg = "true" *) reg r_gray_canny_enable_meta = DEFAULT_GRAY_CANNY_ENABLE;
	(* async_reg = "true" *) reg r_gray_canny_enable_sync = DEFAULT_GRAY_CANNY_ENABLE;
	(* async_reg = "true" *) reg r_color_canny_enable_meta = DEFAULT_COLOR_CANNY_ENABLE;
	(* async_reg = "true" *) reg r_color_canny_enable_sync = DEFAULT_COLOR_CANNY_ENABLE;
	(* async_reg = "true" *) reg r_shape_enable_meta = DEFAULT_SHAPE_ENABLE;
	(* async_reg = "true" *) reg r_shape_enable_sync = DEFAULT_SHAPE_ENABLE;
	(* async_reg = "true" *) reg r_rect_line_fit_enable_meta = DEFAULT_RECT_LINE_FIT_ENABLE;
	(* async_reg = "true" *) reg r_rect_line_fit_enable_sync = DEFAULT_RECT_LINE_FIT_ENABLE;
	(* async_reg = "true" *) reg [1:0] r_line_support_level_meta = DEFAULT_LINE_SUPPORT_LEVEL;
	(* async_reg = "true" *) reg [1:0] r_line_support_level_sync = DEFAULT_LINE_SUPPORT_LEVEL;
	(* async_reg = "true" *) reg [7:0] r_black_threshold_meta = DEFAULT_BLACK_THRESHOLD;
	(* async_reg = "true" *) reg [7:0] r_black_threshold_sync = DEFAULT_BLACK_THRESHOLD;
	reg [1:0] r_video_mode_active = DEFAULT_VIDEO_MODE;
	wire [10:0] r_edge_threshold_active, r_canny_low_threshold_active;
	edge_threshold_cdc #(.DEFAULT_HIGH(DEFAULT_EDGE_THRESHOLD),
		.DEFAULT_LOW(DEFAULT_CANNY_LOW_THRESHOLD)) u_edge_threshold_cdc (
		.clk(clk_sys), .rst_n(rstn_sys), .high_request(w_edge_threshold_effective_request),
		.low_request(w_canny_low_threshold_effective_request),
		.pclk(clk_pixel_2x), .prst_n(rstn_pixel), .frame_vsync(w_rgb_vsync),
		.high_active(r_edge_threshold_active), .low_active(r_canny_low_threshold_active)
	);
	reg [10:0] r_wb_red_gain_active = DEFAULT_WB_RED_GAIN;
	reg [10:0] r_wb_green_gain_active = DEFAULT_WB_GREEN_GAIN;
	reg [10:0] r_wb_blue_gain_active = DEFAULT_WB_BLUE_GAIN;
	reg r_gamma_enable_active = DEFAULT_GAMMA_ENABLE;
	reg [8:0] r_gamma_strength_active = DEFAULT_GAMMA_STRENGTH;
	reg r_median_enable_active = DEFAULT_MEDIAN_ENABLE;
	reg r_gray_canny_enable_active = DEFAULT_GRAY_CANNY_ENABLE;
	reg r_color_canny_enable_active = DEFAULT_COLOR_CANNY_ENABLE;
	reg r_shape_enable_active = DEFAULT_SHAPE_ENABLE;
	(* async_reg = "true" *) reg r_split_enable_meta = 1'b0;
	(* async_reg = "true" *) reg r_split_enable_sync = 1'b0;
	reg r_rect_line_fit_enable_active = DEFAULT_RECT_LINE_FIT_ENABLE;
	reg [1:0] r_line_support_level_active = DEFAULT_LINE_SUPPORT_LEVEL;
	reg [7:0] r_black_threshold_active = DEFAULT_BLACK_THRESHOLD;
	reg r_rgb_vsync_d = 1'b0;
	always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
		if(!rstn_pixel) begin
			r_video_mode_meta      <= DEFAULT_VIDEO_MODE;
			r_video_mode_sync      <= DEFAULT_VIDEO_MODE;
			r_wb_red_gain_meta      <= DEFAULT_WB_RED_GAIN;
			r_wb_red_gain_sync      <= DEFAULT_WB_RED_GAIN;
			r_wb_green_gain_meta    <= DEFAULT_WB_GREEN_GAIN;
			r_wb_green_gain_sync    <= DEFAULT_WB_GREEN_GAIN;
			r_wb_blue_gain_meta     <= DEFAULT_WB_BLUE_GAIN;
			r_wb_blue_gain_sync     <= DEFAULT_WB_BLUE_GAIN;
			r_gamma_enable_meta     <= DEFAULT_GAMMA_ENABLE;
			r_gamma_enable_sync     <= DEFAULT_GAMMA_ENABLE;
			r_gamma_strength_meta   <= DEFAULT_GAMMA_STRENGTH;
			r_gamma_strength_sync   <= DEFAULT_GAMMA_STRENGTH;
			r_median_enable_meta    <= DEFAULT_MEDIAN_ENABLE;
			r_median_enable_sync    <= DEFAULT_MEDIAN_ENABLE;
			r_gray_canny_enable_meta <= DEFAULT_GRAY_CANNY_ENABLE;
			r_gray_canny_enable_sync <= DEFAULT_GRAY_CANNY_ENABLE;
			r_color_canny_enable_meta <= DEFAULT_COLOR_CANNY_ENABLE;
			r_color_canny_enable_sync <= DEFAULT_COLOR_CANNY_ENABLE;
			r_shape_enable_meta     <= DEFAULT_SHAPE_ENABLE;
			r_shape_enable_sync     <= DEFAULT_SHAPE_ENABLE;
			r_rect_line_fit_enable_meta <= DEFAULT_RECT_LINE_FIT_ENABLE;
			r_rect_line_fit_enable_sync <= DEFAULT_RECT_LINE_FIT_ENABLE;
			r_line_support_level_meta <= DEFAULT_LINE_SUPPORT_LEVEL;
			r_line_support_level_sync <= DEFAULT_LINE_SUPPORT_LEVEL;
			r_black_threshold_meta  <= DEFAULT_BLACK_THRESHOLD;
			r_black_threshold_sync  <= DEFAULT_BLACK_THRESHOLD;
			r_video_mode_active    <= DEFAULT_VIDEO_MODE;
			r_wb_red_gain_active    <= DEFAULT_WB_RED_GAIN;
			r_wb_green_gain_active  <= DEFAULT_WB_GREEN_GAIN;
			r_wb_blue_gain_active   <= DEFAULT_WB_BLUE_GAIN;
			r_gamma_enable_active   <= DEFAULT_GAMMA_ENABLE;
			r_gamma_strength_active <= DEFAULT_GAMMA_STRENGTH;
			r_median_enable_active  <= DEFAULT_MEDIAN_ENABLE;
			r_gray_canny_enable_active <= DEFAULT_GRAY_CANNY_ENABLE;
			r_color_canny_enable_active <= DEFAULT_COLOR_CANNY_ENABLE;
			r_shape_enable_active   <= DEFAULT_SHAPE_ENABLE;
			r_rect_line_fit_enable_active <= DEFAULT_RECT_LINE_FIT_ENABLE;
			r_line_support_level_active <= DEFAULT_LINE_SUPPORT_LEVEL;
			r_black_threshold_active <= DEFAULT_BLACK_THRESHOLD;
			r_rgb_vsync_d          <= 1'b0;
			r_split_enable_meta <= 1'b0;
			r_split_enable_sync <= 1'b0;
		end else begin
			r_split_enable_meta <= w_split_enable_request;
			r_split_enable_sync <= r_split_enable_meta;
			r_video_mode_meta     <= w_video_mode_request;
			r_video_mode_sync     <= r_video_mode_meta;
			r_wb_red_gain_meta     <= w_wb_red_gain_request;
			r_wb_red_gain_sync     <= r_wb_red_gain_meta;
			r_wb_green_gain_meta   <= w_wb_green_gain_request;
			r_wb_green_gain_sync   <= r_wb_green_gain_meta;
			r_wb_blue_gain_meta    <= w_wb_blue_gain_request;
			r_wb_blue_gain_sync    <= r_wb_blue_gain_meta;
			r_gamma_enable_meta    <= w_gamma_enable_request;
			r_gamma_enable_sync    <= r_gamma_enable_meta;
			r_gamma_strength_meta  <= w_gamma_strength_request;
			r_gamma_strength_sync  <= r_gamma_strength_meta;
			r_median_enable_meta   <= w_median_enable_request;
			r_median_enable_sync   <= r_median_enable_meta;
			r_gray_canny_enable_meta <= w_gray_canny_enable_request;
			r_gray_canny_enable_sync <= r_gray_canny_enable_meta;
			r_color_canny_enable_meta <= w_color_canny_enable_request;
			r_color_canny_enable_sync <= r_color_canny_enable_meta;
			r_shape_enable_meta    <= w_shape_enable_request;
			r_shape_enable_sync    <= r_shape_enable_meta;
			r_rect_line_fit_enable_meta <= w_rect_line_fit_enable_request;
			r_rect_line_fit_enable_sync <= r_rect_line_fit_enable_meta;
			r_line_support_level_meta <= w_line_support_level_request;
			r_line_support_level_sync <= r_line_support_level_meta;
			r_black_threshold_meta <= w_black_threshold_request;
			r_black_threshold_sync <= r_black_threshold_meta;
			r_rgb_vsync_d         <= w_rgb_vsync;
			if(CANNY_MEDIAN_BUILD ? !w_rgb_vsync : (!r_rgb_vsync_d && w_rgb_vsync)) begin
				r_video_mode_active     <= r_video_mode_sync;
				r_wb_red_gain_active     <= r_wb_red_gain_sync;
				r_wb_green_gain_active   <= r_wb_green_gain_sync;
				r_wb_blue_gain_active    <= r_wb_blue_gain_sync;
				r_gamma_enable_active    <= r_gamma_enable_sync;
				r_gamma_strength_active  <= r_gamma_strength_sync;
				r_median_enable_active   <= r_median_enable_sync;
				r_gray_canny_enable_active <= r_gray_canny_enable_sync;
				r_color_canny_enable_active <= r_color_canny_enable_sync;
				r_shape_enable_active  <= r_shape_enable_sync;
				r_rect_line_fit_enable_active <= r_rect_line_fit_enable_sync;
				r_line_support_level_active <= r_line_support_level_sync;
				r_black_threshold_active <= r_black_threshold_sync;
			end
		end
	end

	wire 			w_wb_vsync, w_wb_hsync, w_wb_href;
	wire 	[7:0]	w_wb_r, w_wb_g, w_wb_b;
	rgb_white_balance u_rgb_white_balance (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		.per_frame_vsync	(w_rgb_vsync),
		.per_frame_href		(w_rgb_href),
		.per_frame_hsync	(w_rgb_hsync),
		.per_img_red		(w_rgb_r),
		.per_img_green		(w_rgb_g),
		.per_img_blue		(w_rgb_b),
		.red_gain			(r_wb_red_gain_active),
		.green_gain		(r_wb_green_gain_active),
		.blue_gain			(r_wb_blue_gain_active),
		.post_frame_vsync	(w_wb_vsync),
		.post_frame_href	(w_wb_href),
		.post_frame_hsync	(w_wb_hsync),
		.post_img_red		(w_wb_r),
		.post_img_green		(w_wb_g),
		.post_img_blue		(w_wb_b)
	);

	// Gamma is after white balance so the user first removes the color cast and
	// then adjusts overall tone. Corrected data and bypass data use the same
	// two-stage pipeline, preserving timing alignment when Gamma is toggled.
	gamma_correction u_gamma_correction (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		.gamma_enable		(r_gamma_enable_active),
		.gamma_strength		(r_gamma_strength_active),
		.per_frame_vsync	(w_wb_vsync),
		.per_frame_href		(w_wb_href),
		.per_frame_hsync	(w_wb_hsync),
		.per_img_red		(w_wb_r),
		.per_img_green		(w_wb_g),
		.per_img_blue		(w_wb_b),
		.post_frame_vsync	(w_gamma_vsync),
		.post_frame_href	(w_gamma_href),
		.post_frame_hsync	(w_gamma_hsync),
		.post_img_red		(w_gamma_r),
		.post_img_green		(w_gamma_g),
		.post_img_blue		(w_gamma_b)
	);

	wire 			w_gray_vsync, w_gray_hsync, w_gray_href;
	wire 	[7:0]	w_gray_pixel;
	wire 	[7:0]	w_gray_r, w_gray_g, w_gray_b;
	grey u_grey (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		// Overlay needs the always-valid gray sample for Sobel while retaining
		// the registered color outputs for the aligned background image.
		.gray_en			((r_video_mode_active == 2'd1) ||
						 (r_video_mode_active == 2'd2)),
		.per_frame_vsync	(w_gamma_vsync),
		.per_frame_href	(w_gamma_href),
		.per_frame_hsync	(w_gamma_hsync),
		.per_img_red		(w_gamma_r),
		.per_img_green		(w_gamma_g),
		.per_img_blue		(w_gamma_b),
		.post_frame_vsync	(w_gray_vsync),
		.post_frame_href	(w_gray_href),
		.post_frame_hsync	(w_gray_hsync),
		.post_img_gray		(w_gray_pixel),
		.post_img_red		(w_gray_r),
		.post_img_green		(w_gray_g),
		.post_img_blue		(w_gray_b)
	);

	// Image1 carries median-filtered luminance AND RGB into Canny. Its gray
	// modes replicate luminance into RGB upstream; color overlay keeps RGB.
	wire 			w_median_vsync, w_median_hsync, w_median_href;
	wire 	[7:0]	w_median_pixel;
	wire w_canny_in_vsync, w_canny_in_href, w_canny_in_hsync;
	wire [7:0] w_canny_in_gray, w_canny_in_r, w_canny_in_g, w_canny_in_b;
	wire [7:0] w_canny_original_gray;
	generate if (CANNY_MEDIAN_BUILD && !PHOTO_TF_BUILD) begin : g_canny_median_input
	image1_median_frontend #(
		.IMG_HDISP(14'd1920), .IMG_VDISP(14'd1080),
		.DEFAULT_MEDIAN_ENABLE(DEFAULT_MEDIAN_ENABLE)
	) u_median_frontend (
		.clk(clk_pixel_2x), .rst_n(rstn_pixel), .median_enable_req(r_median_enable_active),
		.per_frame_vsync(w_gray_vsync), .per_frame_href(w_gray_href), .per_frame_hsync(w_gray_hsync),
		.per_img_gray(w_gray_pixel), .per_img_red(w_gray_r), .per_img_green(w_gray_g), .per_img_blue(w_gray_b),
		.post_frame_vsync(w_median_vsync), .post_frame_href(w_median_href), .post_frame_hsync(w_median_hsync),
		.post_img_gray(w_median_pixel),
		.post_img_red(w_canny_in_r), .post_img_green(w_canny_in_g), .post_img_blue(w_canny_in_b),
		.post_original_gray(w_canny_original_gray), .median_active()
	);
	assign w_canny_in_vsync = w_median_vsync;
	assign w_canny_in_href = w_median_href;
	assign w_canny_in_hsync = w_median_hsync;
	assign w_canny_in_gray = w_median_pixel;
	end else begin : g_gray_median_vision
	median3x3_filter #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080)
	) u_median3x3_filter (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.median_enable		(r_median_enable_active),
		.per_frame_vsync	(w_gray_vsync),
		.per_frame_href	(w_gray_href),
		.per_frame_hsync	(w_gray_hsync),
		.per_img_gray		(w_gray_pixel),
		.post_frame_vsync	(w_median_vsync),
		.post_frame_href	(w_median_href),
		.post_frame_hsync	(w_median_hsync),
		.post_img_gray		(w_median_pixel)
	);
	assign w_canny_in_vsync = w_gray_vsync;
	assign w_canny_in_href = w_gray_href;
	assign w_canny_in_hsync = w_gray_hsync;
	assign w_canny_in_gray = w_gray_pixel;
	assign w_canny_in_r = w_gray_r;
	assign w_canny_in_g = w_gray_g;
	assign w_canny_in_b = w_gray_b;
	assign w_canny_original_gray = w_gray_pixel;
	end endgenerate

	// RGB median output is declared here because it is also the background
	// sideband for the grayscale Sobel recognition path. Its implementation is
	// shared with the existing color-overlay path below.
	wire 			w_rgb_median_vsync, w_rgb_median_hsync, w_rgb_median_href;
	wire 	[7:0]	w_rgb_median_r, w_rgb_median_g, w_rgb_median_b;

	// Shape results are derived from the selected Sobel/Canny edge stream below.
	// The result path runs continuously so it is stable before D enables display.
	wire 			w_shape_vsync, w_shape_hsync, w_shape_href;
	wire 	[7:0]	w_shape_r, w_shape_g, w_shape_b;
	wire 			w_shape_bbox_valid;
	wire 	[11:0]	w_shape_bbox_x_min, w_shape_bbox_x_max;
	wire 	[10:0]	w_shape_bbox_y_min, w_shape_bbox_y_max;
	wire 			w_shape_bbox2_valid;
	wire 	[11:0]	w_shape_bbox2_x_min, w_shape_bbox2_x_max;
	wire 	[10:0]	w_shape_bbox2_y_min, w_shape_bbox2_y_max;
	wire 	[21:0]	w_shape_object_area;
	wire 	[1:0]	w_shape_type;
	wire 	[1:0]	w_shape_type2;

	// Shape results change only once per frame. Synchronize them into the 96 MHz
	// UART domain, then require three matching frames before automatic reports.
	(* async_reg = "true" *) reg r_shape_vsync_meta, r_shape_vsync_sync;
	(* async_reg = "true" *) reg r_shape_valid_meta, r_shape_valid_sync;
	(* async_reg = "true" *) reg [1:0] r_shape_type_meta, r_shape_type_sync;
	(* async_reg = "true" *) reg r_shape2_valid_meta, r_shape2_valid_sync;
	(* async_reg = "true" *) reg [1:0] r_shape2_type_meta, r_shape2_type_sync;
	reg r_shape_vsync_previous;
	wire w_shape_frame_tick = r_shape_vsync_sync & ~r_shape_vsync_previous;
	wire w_shape_any_valid = r_shape_valid_sync || r_shape2_valid_sync;

	always @(posedge clk_sys or negedge rstn_sys) begin
		if (!rstn_sys) begin
			r_shape_vsync_meta     <= 1'b0;
			r_shape_vsync_sync     <= 1'b0;
			r_shape_vsync_previous <= 1'b0;
			r_shape_valid_meta     <= 1'b0;
			r_shape_valid_sync     <= 1'b0;
			r_shape_type_meta      <= 2'd0;
			r_shape_type_sync      <= 2'd0;
			r_shape2_valid_meta    <= 1'b0;
			r_shape2_valid_sync    <= 1'b0;
			r_shape2_type_meta     <= 2'd0;
			r_shape2_type_sync     <= 2'd0;
		end else begin
			r_shape_vsync_meta     <= w_shape_vsync;
			r_shape_vsync_sync     <= r_shape_vsync_meta;
			r_shape_vsync_previous <= r_shape_vsync_sync;
			r_shape_valid_meta     <= w_shape_bbox_valid;
			r_shape_valid_sync     <= r_shape_valid_meta;
			r_shape_type_meta      <= w_shape_type;
			r_shape_type_sync      <= r_shape_type_meta;
			r_shape2_valid_meta    <= w_shape_bbox2_valid;
			r_shape2_valid_sync    <= r_shape2_valid_meta;
			r_shape2_type_meta     <= w_shape_type2;
			r_shape2_type_sync     <= r_shape2_type_meta;
		end
	end

	generate if (!PHOTO_TF_BUILD && SHAPE_BUILD) begin : g_shape_reporters
	shape_uart_reporter #(
		.CLOCK_HZ		(CLOCK_MAIN),
		.REPORT_HZ		(2),
		.STABLE_FRAMES	(3),
		.OBJECT_INDEX	(1),
		.AUTO_ON_TRIGGER(1)
	) u_shape_uart_reporter (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.report_enable	(w_shape_enable_request),
		.auto_trigger	(w_shape_any_valid),
		.frame_tick		(w_shape_frame_tick),
		.shape_valid	(r_shape_valid_sync),
		.shape_type		(r_shape_type_sync),
		.query_pulse	(w_shape_status_query_request),
		.tx_valid		(w_uart_msg_tx_valid),
		.tx_data		(w_uart_msg_tx_data),
		.tx_last		(w_uart_msg_tx_last),
		.tx_accept		(w_uart_msg_tx_accept),
		.tx_done		(w_uart_msg_tx_done)
	);

	shape_uart_reporter #(
		.CLOCK_HZ		(CLOCK_MAIN),
		.REPORT_HZ		(2),
		.STABLE_FRAMES	(3),
		.OBJECT_INDEX	(2),
		.AUTO_ON_TRIGGER(1)
	) u_shape_uart_reporter_2 (
		.clk			(clk_sys),
		.rst_n			(rstn_sys),
		.report_enable	(w_shape_enable_request),
		.auto_trigger	(w_shape_any_valid),
		.frame_tick		(w_shape_frame_tick),
		.shape_valid	(r_shape2_valid_sync),
		.shape_type		(r_shape2_type_sync),
		.query_pulse	(w_shape_status_query_request),
		.tx_valid		(w_uart_msg2_tx_valid),
		.tx_data		(w_uart_msg2_tx_data),
		.tx_last		(w_uart_msg2_tx_last),
		.tx_accept		(w_uart_msg2_tx_accept),
		.tx_done		(w_uart_msg2_tx_done)
	);

	end else begin : g_shape_reporters_disabled
		assign w_uart_msg_tx_valid = 1'b0;
		assign w_uart_msg_tx_data = 8'd0;
		assign w_uart_msg_tx_last = 1'b0;
        image2_video_diagnostic u_image2_video_diagnostic(
         .clk(clk_sys),.cam_clk(w_csi_rx_clk),.pixel_clk(clk_pixel_2x),.rst_n(rstn_sys),
         .cam_vs(cmos_frame_vsync),.cam_de(cmos_frame_href),
         .underflow_count(w_read_underflow_count),.bad_frame_count(w_bad_frame_count),
         .status({28'd0,w_axi_read_stalled,w_ddr3_cal_pass,w_ddr3_cal_done,w_freeze_request}),
         .video_awaddr(w_video_awaddr),.video_araddr(w_video_araddr),
         .video_awvalid(w_video_awvalid),.video_awready(w_video_awready),.video_arvalid(w_video_arvalid),.video_arready(w_video_arready),
         .aux_awvalid(w_capture_awvalid),.aux_awready(w_capture_awready),.aux_arvalid(w_capture_arvalid),.aux_arready(w_capture_arready),
         .rx_valid(w_uart_rx_valid),.rx_data(w_uart_rx_data),.legacy_valid(w_uart_legacy_valid),
         .tx_valid(w_uart_msg2_tx_valid),.tx_data(w_uart_msg2_tx_data),.tx_last(w_uart_msg2_tx_last),
         .tx_accept(w_uart_msg2_tx_accept),.data(w_video_diagnostic_data));
	end endgenerate

	// Photo/TF configuration: keep the former Sobel hardware out of synthesis.
	// A runtime selector would still retain its line RAM and routing.
	generate if (1'b0) begin : g_sobel_removed_for_tf_photo
	wire 			w_sobel_edge_vsync, w_sobel_edge_hsync, w_sobel_edge_href;
	wire 	[7:0]	w_sobel_edge_pixel;
	sobel_edge #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080)
	) u_sobel_edge (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		.per_frame_vsync	(w_median_vsync),
		.per_frame_href	(w_median_href),
		.per_frame_hsync	(w_median_hsync),
		.per_img_gray		(w_median_pixel),
		.edge_threshold	(r_edge_threshold_active),
		.post_frame_vsync	(w_sobel_edge_vsync),
		.post_frame_href	(w_sobel_edge_href),
		.post_frame_hsync	(w_sobel_edge_hsync),
		.post_img_edge		(w_sobel_edge_pixel)
	);

	// Carry the gray/color background through a delay identical to the Sobel
	// window and its three pipeline stages. The preceding RGB median wrapper is
	// already cycle-aligned with the grayscale median wrapper.
	wire 			w_sobel_bg_vsync, w_sobel_bg_hsync, w_sobel_bg_href;
	wire 	[7:0]	w_sobel_bg_r, w_sobel_bg_g, w_sobel_bg_b;
	rgb_window_delay #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080)
	) u_sobel_shape_rgb_delay (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.delay_enable		(1'b1),
		.per_frame_vsync	(w_rgb_median_vsync),
		.per_frame_href	(w_rgb_median_href),
		.per_frame_hsync	(w_rgb_median_hsync),
		.per_img_red		(w_rgb_median_r),
		.per_img_green	(w_rgb_median_g),
		.per_img_blue		(w_rgb_median_b),
		.post_frame_vsync	(w_sobel_bg_vsync),
		.post_frame_href	(w_sobel_bg_href),
		.post_frame_hsync	(w_sobel_bg_hsync),
		.post_img_red		(w_sobel_bg_r),
		.post_img_green	(w_sobel_bg_g),
		.post_img_blue		(w_sobel_bg_b)
	);

	end endgenerate

	// Full streaming Canny path. Image1 M controls the aligned luminance/RGB
	// frontend; other build profiles keep their existing input behavior.
	wire 			w_canny_vsync, w_canny_hsync, w_canny_href;
	wire 	[7:0]	w_canny_edge_pixel;
	wire 	[7:0]	w_canny_r, w_canny_g, w_canny_b;
	generate if (!PHOTO_TF_BUILD) begin : g_canny_vision
	canny_edge #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080)
	) u_canny_edge (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		.per_frame_vsync	(w_canny_in_vsync),
		.per_frame_href	(w_canny_in_href),
		.per_frame_hsync	(w_canny_in_hsync),
		.per_img_gray		(w_canny_in_gray),
		.per_img_red		(PERSON_BUILD?w_canny_in_gray:w_canny_in_r),
		.per_img_green	(PERSON_BUILD?w_canny_in_gray:w_canny_in_g),
		.per_img_blue		(PERSON_BUILD?w_canny_in_gray:w_canny_in_b),
		.low_threshold		(r_canny_low_threshold_active),
		.high_threshold	(r_edge_threshold_active),
		.post_frame_vsync	(w_canny_vsync),
		.post_frame_href	(w_canny_href),
		.post_frame_hsync	(w_canny_hsync),
		.post_img_edge		(w_canny_edge_pixel),
		.post_img_red		(w_canny_r),
		.post_img_green	(w_canny_g),
		.post_img_blue		(w_canny_b)
	);
	end else begin : g_canny_photo_preview
        // Live local preview; saved photos use the independent complete-frame
        // grayscale engine, including exact hysteresis, at 960x540.
        canny_edge u_photo_preview(
         .clk(clk_pixel_2x),.rst_n(rstn_pixel),
         .per_frame_vsync(w_median_vsync),.per_frame_href(w_median_href),.per_frame_hsync(w_median_hsync),
         .per_img_gray(w_median_pixel),.per_img_red(w_median_pixel),.per_img_green(w_median_pixel),.per_img_blue(w_median_pixel),
         .low_threshold(r_canny_low_threshold_active),.high_threshold(r_edge_threshold_active),
         .post_frame_vsync(w_canny_vsync),.post_frame_href(w_canny_href),.post_frame_hsync(w_canny_hsync),
         .post_img_edge(w_canny_edge_pixel),.post_img_red(w_canny_r),.post_img_green(w_canny_g),.post_img_blue(w_canny_b));
    end endgenerate

	wire 			w_edge_vsync = w_canny_vsync;
	wire 			w_edge_hsync = w_canny_hsync;
	wire 			w_edge_href  = w_canny_href;
	wire 	[7:0]	w_edge_pixel = w_canny_edge_pixel;
	wire 	[7:0]	w_edge_bg_r = w_canny_r;
	wire 	[7:0]	w_edge_bg_g = w_canny_g;
	wire 	[7:0]	w_edge_bg_b = w_canny_b;

	// Competition-compliant recognition chain:
	// Sobel/Canny edge detection -> short-gap closing -> connected components
	// -> geometric features -> rectangle/circle/unknown.
	generate if (!PHOTO_TF_BUILD && SHAPE_BUILD) begin : g_shape_vision
	shape_recognition_pipeline #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080),
		.MIN_AREA	(22'd64),
		// Centered two-thirds of the 1920x1080 active picture (1280x720).
		.ROI_X_MIN	(12'd320),
		.ROI_X_MAX	(12'd1599),
		.ROI_Y_MIN	(11'd180),
		.ROI_Y_MAX	(11'd899)
	) u_shape_recognition_pipeline (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.per_frame_vsync	(w_edge_vsync),
		.per_frame_href	(w_edge_href),
		.per_frame_hsync	(w_edge_hsync),
		.per_img_edge		(w_edge_pixel),
		.per_img_red		(w_edge_bg_r),
		.per_img_green	(w_edge_bg_g),
		.per_img_blue		(w_edge_bg_b),
		.processing_enable(r_shape_enable_active),
		.rect_line_fit_enable(r_rect_line_fit_enable_active),
		.line_support_level(r_line_support_level_active),
		.post_frame_vsync	(w_shape_vsync),
		.post_frame_href	(w_shape_href),
		.post_frame_hsync	(w_shape_hsync),
		.post_img_red		(w_shape_r),
		.post_img_green	(w_shape_g),
		.post_img_blue		(w_shape_b),
		.bbox_valid		(w_shape_bbox_valid),
		.bbox_x_min		(w_shape_bbox_x_min),
		.bbox_x_max		(w_shape_bbox_x_max),
		.bbox_y_min		(w_shape_bbox_y_min),
		.bbox_y_max		(w_shape_bbox_y_max),
		.bbox2_valid		(w_shape_bbox2_valid),
		.bbox2_x_min		(w_shape_bbox2_x_min),
		.bbox2_x_max		(w_shape_bbox2_x_max),
		.bbox2_y_min		(w_shape_bbox2_y_min),
		.bbox2_y_max		(w_shape_bbox2_y_max),
		.object_area		(w_shape_object_area),
		.shape_type		(w_shape_type),
		.shape2_type		(w_shape_type2)
	);
	end else begin : g_shape_photo_bypass
		// In the photo build no recognizer state or line history is retained.
		assign w_shape_vsync       = w_gray_vsync;
		assign w_shape_hsync       = w_gray_hsync;
		assign w_shape_href        = w_gray_href;
		assign w_shape_r           = w_gray_r;
		assign w_shape_g           = w_gray_g;
		assign w_shape_b           = w_gray_b;
		assign w_shape_bbox_valid  = 1'b0;
		assign w_shape_bbox_x_min  = 12'd0;
		assign w_shape_bbox_x_max  = 12'd0;
		assign w_shape_bbox_y_min  = 11'd0;
		assign w_shape_bbox_y_max  = 11'd0;
		assign w_shape_bbox2_valid = 1'b0;
		assign w_shape_bbox2_x_min = 12'd0;
		assign w_shape_bbox2_x_max = 12'd0;
		assign w_shape_bbox2_y_min = 11'd0;
		assign w_shape_bbox2_y_max = 11'd0;
		assign w_shape_object_area = 22'd0;
		assign w_shape_type        = 2'd0;
		assign w_shape_type2       = 2'd0;
	end endgenerate

	// This RGB median/Sobel overlay branch is intentionally not synthesized in
	// the TF photo configuration. Canny overlay below remains available.
	generate if (1'b0) begin : g_rgb_sobel_removed_for_tf_photo
	// RGB median denoising uses one shared 24-bit window, avoiding three
	// independent line-buffer banks. UART command M controls this path together
	// with the grayscale median path, and the setting changes at a frame boundary.
	rgb_median3x3_filter #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080)
	) u_rgb_median3x3_filter (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.median_enable		(r_median_enable_active),
		.per_frame_vsync	(w_gray_vsync),
		.per_frame_href	(w_gray_href),
		.per_frame_hsync	(w_gray_hsync),
		.per_img_red		(w_gray_r),
		.per_img_green		(w_gray_g),
		.per_img_blue		(w_gray_b),
		.post_frame_vsync	(w_rgb_median_vsync),
		.post_frame_href	(w_rgb_median_href),
		.post_frame_hsync	(w_rgb_median_hsync),
		.post_img_red		(w_rgb_median_r),
		.post_img_green	(w_rgb_median_g),
		.post_img_blue		(w_rgb_median_b)
	);

	// RGB-aware color edges. One shared 24-bit window keeps all three channels
	// pixel-aligned after median denoising; each channel has its own Sobel decision. Edge colors are
	// white for black-involved boundaries, yellow for strong color differences,
	// and the center-pixel complement otherwise.
	wire 			w_sobel_overlay_vsync, w_sobel_overlay_hsync, w_sobel_overlay_href;
	wire 	[7:0]	w_sobel_overlay_r, w_sobel_overlay_g, w_sobel_overlay_b;
	rgb_color_edge_overlay #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080),
		.STRONG_DIFF	(10'd300),
		.BLACK_TH		(8'd20)
	) u_rgb_color_edge_overlay (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.overlay_enable		(1'b1),
		.per_frame_vsync	(w_rgb_median_vsync),
		.per_frame_href	(w_rgb_median_href),
		.per_frame_hsync	(w_rgb_median_hsync),
		.per_img_red		(w_rgb_median_r),
		.per_img_green		(w_rgb_median_g),
		.per_img_blue		(w_rgb_median_b),
		.edge_threshold	(r_edge_threshold_active),
		.post_frame_vsync	(w_sobel_overlay_vsync),
		.post_frame_href	(w_sobel_overlay_href),
		.post_frame_hsync	(w_sobel_overlay_hsync),
		.post_img_red		(w_sobel_overlay_r),
		.post_img_green	(w_sobel_overlay_g),
		.post_img_blue		(w_sobel_overlay_b)
	);

	end endgenerate

	// Apply the same white/yellow/centre-complement colour policy used by the
	// RGB-Sobel overlay to the luminance-Canny edge mask. No fixed red path remains.
	wire 			w_canny_overlay_vsync, w_canny_overlay_hsync, w_canny_overlay_href;
	wire 	[7:0]	w_canny_overlay_r, w_canny_overlay_g, w_canny_overlay_b;
	generate if (!PHOTO_TF_BUILD && COLOR_OVERLAY_BUILD) begin : g_canny_overlay_vision
	rgb_edge_colorizer #(
		.IMG_HDISP	(14'd1920),
		.IMG_VDISP	(14'd1080),
		.STRONG_DIFF	(10'd300),
		.BLACK_TH		(8'd20),
		.TOP_EDGE_GUARD (14'd8)
	) u_canny_color_overlay (
		.clk				(clk_pixel_2x),
		.rst_n			(rstn_pixel),
		.overlay_enable		(1'b1),
		.per_frame_vsync	(w_canny_vsync),
		.per_frame_href	(w_canny_href),
		.per_frame_hsync	(w_canny_hsync),
		.per_img_red		(w_canny_r),
		.per_img_green	(w_canny_g),
		.per_img_blue		(w_canny_b),
		.per_img_edge		(w_canny_edge_pixel),
		.post_frame_vsync	(w_canny_overlay_vsync),
		.post_frame_href	(w_canny_overlay_href),
		.post_frame_hsync	(w_canny_overlay_hsync),
		.post_img_red		(w_canny_overlay_r),
		.post_img_green	(w_canny_overlay_g),
		.post_img_blue		(w_canny_overlay_b)
	);
	end else begin : g_canny_overlay_photo_bypass
		assign w_canny_overlay_vsync = w_gray_vsync;
		assign w_canny_overlay_hsync = w_gray_hsync;
		assign w_canny_overlay_href  = w_gray_href;
		assign w_canny_overlay_r     = w_gray_r;
		assign w_canny_overlay_g     = w_gray_g;
		assign w_canny_overlay_b     = w_gray_b;
	end endgenerate

	wire 			w_overlay_vsync = w_canny_overlay_vsync;
	wire 			w_overlay_hsync = w_canny_overlay_hsync;
	wire 			w_overlay_href  = w_canny_overlay_href;
	wire 	[7:0]	w_overlay_r = w_canny_overlay_r;
	wire 	[7:0]	w_overlay_g = w_canny_overlay_g;
	wire 	[7:0]	w_overlay_b = w_canny_overlay_b;

	// 0=color, 1=gray, 2=binary edge, 3=color-edge overlay. UART A and V
	// independently select Sobel or Canny for modes 2 and 3.
	wire w_normal_video_vsync = (r_video_mode_active == 2'd3) ? w_overlay_vsync :
						 (r_video_mode_active == 2'd2) ? w_edge_vsync :
						 (r_video_mode_active == 2'd1) ? w_median_vsync : w_gray_vsync;
	wire w_normal_video_hsync = (r_video_mode_active == 2'd3) ? w_overlay_hsync :
						 (r_video_mode_active == 2'd2) ? w_edge_hsync :
						 (r_video_mode_active == 2'd1) ? w_median_hsync : w_gray_hsync;
	wire w_normal_video_href  = (r_video_mode_active == 2'd3) ? w_overlay_href :
						 (r_video_mode_active == 2'd2) ? w_edge_href :
						 (r_video_mode_active == 2'd1) ? w_median_href : w_gray_href;
	wire [23:0] w_normal_video_rgb = (r_video_mode_active == 2'd3) ?
								 {w_overlay_r, w_overlay_g, w_overlay_b} :
							 (r_video_mode_active == 2'd2) ?
								 {w_edge_pixel, w_edge_pixel, w_edge_pixel} :
							 (r_video_mode_active == 2'd1) ?
								 {w_median_pixel, w_median_pixel, w_median_pixel} :
								 {w_gray_r, w_gray_g, w_gray_b};

	// Match the original pre-Gaussian gray to Canny spatial/pipeline latency.
	// The legacy Canny RGB sideband itself is Gaussian-filtered, not original.
	wire w_split_active, w_split_vsync, w_split_hsync, w_split_href;
	wire [23:0] w_split_rgb;
	generate if (!PHOTO_TF_BUILD && GRAY_EDGE_SPLIT_BUILD) begin : g_gray_edge_split
		wire [7:0] original_gray_aligned;
		gray_canny_alignment u_original_gray_alignment (
			.clk(clk_pixel_2x), .rst_n(rstn_pixel),
			.in_vsync(w_canny_in_vsync), .in_hsync(w_canny_in_hsync), .in_href(w_canny_in_href),
			.in_gray(w_canny_original_gray), .out_gray(original_gray_aligned)
		);
		gray_edge_split u_gray_edge_split (
			.clk(clk_pixel_2x), .rst_n(rstn_pixel),
			.split_req(r_split_enable_sync && r_video_mode_active == 2'd2 && !r_shape_enable_active),
			.in_vsync(w_edge_vsync), .in_hsync(w_edge_hsync), .in_href(w_edge_href),
			.aligned_gray(original_gray_aligned), .aligned_edge(w_edge_pixel),
			.out_vsync(w_split_vsync), .out_hsync(w_split_hsync), .out_href(w_split_href),
			.out_rgb(w_split_rgb), .split_active(w_split_active)
		);
	end else begin : g_gray_edge_split_disabled
		assign w_split_active = 1'b0;
		assign w_split_vsync = 1'b0;
		assign w_split_hsync = 1'b0;
		assign w_split_href = 1'b0;
		assign w_split_rgb = 24'd0;
	end endgenerate

	// Comparison has its own matched timing; normal/shape paths are unchanged.
	wire w_shape_display_active = !PHOTO_TF_BUILD && SHAPE_BUILD && r_shape_enable_active;
	wire w_selected_video_vsync,w_selected_video_hsync,w_selected_video_href;
	wire [23:0] w_selected_video_rgb;
	generate if(CANNY_MEDIAN_BUILD && !PHOTO_TF_BUILD)begin : g_image1_video_output
		image1_video_mux #(.DEFAULT_SOURCE({1'b0,DEFAULT_VIDEO_MODE})) u_video_mux (
			.clk(clk_pixel_2x),.rst_n(rstn_pixel),
			.source_req(w_shape_display_active ? 3'd5 : w_split_active ? 3'd4 : {1'b0,r_video_mode_active}),
			.in_vsync({w_shape_vsync,w_split_vsync,w_overlay_vsync,w_edge_vsync,w_median_vsync,w_gray_vsync}),
			.in_hsync({w_shape_hsync,w_split_hsync,w_overlay_hsync,w_edge_hsync,w_median_hsync,w_gray_hsync}),
			.in_href({w_shape_href,w_split_href,w_overlay_href,w_edge_href,w_median_href,w_gray_href}),
			.in_rgb({w_shape_r,w_shape_g,w_shape_b,w_split_rgb,w_overlay_r,w_overlay_g,w_overlay_b,
			         w_edge_pixel,w_edge_pixel,w_edge_pixel,w_median_pixel,w_median_pixel,w_median_pixel,
			         w_gray_r,w_gray_g,w_gray_b}),
			.out_vsync(w_selected_video_vsync),.out_hsync(w_selected_video_hsync),.out_href(w_selected_video_href),
			.out_rgb(w_selected_video_rgb),.source_active()
		);
	end else begin : g_legacy_video_output
	assign w_selected_video_vsync = w_split_active ? w_split_vsync : w_shape_display_active ? w_shape_vsync : w_normal_video_vsync;
	assign w_selected_video_hsync = w_split_active ? w_split_hsync : w_shape_display_active ? w_shape_hsync : w_normal_video_hsync;
	assign w_selected_video_href = w_split_active ? w_split_href : w_shape_display_active ? w_shape_href : w_normal_video_href;
	assign w_selected_video_rgb = w_split_active ? w_split_rgb : w_shape_display_active ? {w_shape_r,w_shape_g,w_shape_b} : w_normal_video_rgb;
	end endgenerate

    // Match the RAW FIFO's one-clock request lead to the real LCD RGB/DE.
	// The dedicated mask stream has its own delayed timing; its display request
	// is committed in that stream's vertical blank.
    wire person_vsync,person_hsync,person_href,person_display_active;
    wire [23:0] person_rgb;
    generate if(PERSON_BUILD)begin : g_person_vision
        assign w_edge_signature={r_edge_threshold_active,r_canny_low_threshold_active,
         r_wb_red_gain_active,r_wb_green_gain_active,r_wb_blue_gain_active,r_gamma_enable_active,r_gamma_strength_active};
        edge_background_capture #(.CHECK_INPUT_FAULT(1)) u_edge_background_capture(
         .clk(clk_sys),.rst_n(rstn_sys),.pclk(clk_pixel_2x),.prst_n(rstn_pixel),
         .capture_req(w_background_capture_request&&w_person_edge_source_request),
         .in_vsync(w_edge_vsync),.in_hsync(w_edge_hsync),.in_href(w_edge_href),.in_edge(w_edge_pixel!=0),
         .config_signature(w_edge_signature),.input_frame_fault(w_background_stream_fault),.ready(w_edge_bg_ready),.busy(w_edge_bg_busy),.error(w_edge_bg_error),
         .writer_start(w_edge_writer_start),.writer_end(w_edge_writer_end),.writer_byte_valid(w_edge_writer_valid),
         .writer_byte(w_edge_writer_byte),.writer_offset(w_edge_writer_offset),
         .writer_busy(w_gallery_writer_busy),.writer_commit(w_gallery_word_commit),.writer_error(w_gallery_write_error),.reader_error(w_edge_photo_read_error),
         .reader_request(w_edge_reader_request),.reader_byte(w_photo_rframe_data),.reader_valid(w_photo_rframe_valid),
         .out_vsync(w_edge_fg_vsync),.out_hsync(w_edge_fg_hsync),.out_href(w_edge_fg_href),
         .out_edge(w_edge_original_pixel),.out_foreground(w_edge_fg_pixel),.reference_valid(w_edge_reference_valid),.frame_fault(w_edge_stream_fault)
        );
        reg [7:0] aligned_background;
        reg aligned_sample_valid;
        always @(posedge clk_pixel_2x)begin
            aligned_background<=w_background_data;
            aligned_sample_valid<=w_background_sample_valid;
        end
        person_roi_pipeline #(.DUAL_SOURCE(1)) u_person_roi_pipeline(
            .clk(clk_pixel_2x),.rst_n(rstn_pixel),.background_valid(w_background_valid),
            .sample_valid(aligned_sample_valid),.stream_fault(w_background_stream_fault),
            .in_vsync(lcd_vs),.in_hsync(lcd_hs),.in_href(lcd_de),.current_raw(lcd_red),.background_raw(aligned_background),
            .threshold_req(w_difference_threshold_request),.noise_req(w_person_noise_request),.view_req(w_person_view_request),
            .edge_source_req(w_person_edge_source_request),.edge_source_active(w_person_edge_source_active),
            .edge_vsync(w_edge_fg_vsync),.edge_hsync(w_edge_fg_hsync),.edge_href(w_edge_fg_href),
            .edge_foreground(w_edge_fg_pixel),.edge_pixel(w_edge_original_pixel),.edge_reference_valid(w_edge_reference_valid),.edge_stream_fault(w_edge_stream_fault),
            .out_vsync(person_vsync),.out_hsync(person_hsync),.out_href(person_href),.out_rgb(person_rgb),
            .display_active(person_display_active),.candidate_valid(),.analysis_busy(),.processing_error(w_person_processing_error)
        );
    end else begin : g_person_vision_disabled
        assign person_vsync=0;assign person_hsync=0;assign person_href=0;assign person_rgb=0;
        assign person_display_active=0;assign w_person_processing_error=0;
        assign w_edge_signature=0;assign w_edge_bg_ready=0;assign w_edge_bg_busy=0;assign w_edge_bg_error=0;
        assign w_edge_reference_valid=0;assign w_edge_stream_fault=0;assign w_edge_writer_start=0;assign w_edge_writer_end=0;
        assign w_edge_writer_valid=0;assign w_edge_writer_byte=0;assign w_edge_writer_offset=0;
        assign w_edge_reader_request=0;assign w_edge_fg_vsync=0;assign w_edge_fg_hsync=0;assign w_edge_fg_href=0;
        assign w_edge_fg_pixel=0;assign w_edge_original_pixel=0;assign w_person_edge_source_active=0;
    end endgenerate

	// Game rendering is removed. Keep timing and RGB together at the HDMI mux.
	wire w_video_vsync = person_display_active ? person_vsync : w_selected_video_vsync;
	wire w_video_hsync = person_display_active ? person_hsync : w_selected_video_hsync;
	wire w_video_href  = person_display_active ? person_href : w_selected_video_href;
	wire [23:0] w_video_rgb = person_display_active ? person_rgb : w_selected_video_rgb;

	// The gallery is selected only at the final HDMI source mux.  All live
	// camera and Sobel/Canny pipelines continue to run
	// unchanged underneath and become visible again immediately after X exits.
	(* async_reg = "true" *) reg r_gallery_enable_pixel_meta = 1'b0;
	(* async_reg = "true" *) reg r_gallery_enable_pixel_sync = 1'b0;
	reg r_gallery_enable_pixel_active = 1'b0;
	always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
		if (!rstn_pixel) begin
			r_gallery_enable_pixel_meta <= 1'b0;
			r_gallery_enable_pixel_sync <= 1'b0;
			r_gallery_enable_pixel_active <= 1'b0;
		end else begin
			r_gallery_enable_pixel_meta <= w_gallery_display_enable_sys;
			r_gallery_enable_pixel_sync <= r_gallery_enable_pixel_meta;
			if (lcd_vs) r_gallery_enable_pixel_active <= r_gallery_enable_pixel_sync;
		end
	end

	wire w_photo_video_vsync, w_photo_video_hsync, w_photo_video_href;
	wire [7:0] w_photo_video_r, w_photo_video_g, w_photo_video_b;
	generate if (ENABLE_PHOTO_TF) begin : g_photo_display
	photo_display_stream u_photo_display_stream (
		.clk				(clk_pixel_2x),
		.rst_n				(rstn_pixel),
		.gallery_enable		(r_gallery_enable_pixel_active),
		.photo_stream_reset(w_photo_stream_reset),
		.in_vsync			(lcd_vs),
		.in_hsync			(lcd_hs),
		.in_href			(lcd_de),
		.photo_byte_valid	(w_photo_rframe_valid),
		.photo_byte			(w_photo_rframe_data),
		.photo_byte_ready	(w_photo_rframe_data_en),
		.out_vsync			(w_photo_video_vsync),
		.out_hsync			(w_photo_video_hsync),
		.out_href			(w_photo_video_href),
		.out_red			(w_photo_video_r),
		.out_green			(w_photo_video_g),
		.out_blue			(w_photo_video_b),
		.frame_error(w_gallery_frame_error)
	);
	end else begin : g_photo_display_disabled
		assign w_photo_rframe_data_en = PERSON_BUILD?w_edge_reader_request:1'b0;
		assign w_gallery_frame_error = 1'b0;
		assign w_photo_video_vsync = 1'b0;
		assign w_photo_video_hsync = 1'b0;
		assign w_photo_video_href = 1'b0;
		assign w_photo_video_r = 8'd0;
		assign w_photo_video_g = 8'd0;
		assign w_photo_video_b = 8'd0;
	end endgenerate

	wire w_live_hdmi_vsync = !PERSON_BUILD&&r_gallery_enable_pixel_active ? w_photo_video_vsync : w_video_vsync;
	wire w_live_hdmi_hsync = !PERSON_BUILD&&r_gallery_enable_pixel_active ? w_photo_video_hsync : w_video_hsync;
	wire w_live_hdmi_href  = !PERSON_BUILD&&r_gallery_enable_pixel_active ? w_photo_video_href  : w_video_href;
	wire [23:0] w_live_hdmi_rgb = !PERSON_BUILD&&r_gallery_enable_pixel_active ?
			{w_photo_video_r, w_photo_video_g, w_photo_video_b} : w_video_rgb;

	// Z substitutes independently generated RGB AND sync immediately before
	// TMDS. Camera/DDR/vision keep running but cannot affect the test picture.
	wire w_hdmi_vsync, w_hdmi_hsync, w_hdmi_href;
	wire [23:0] w_hdmi_rgb;
	video_diagnostic_mux u_video_diagnostic_mux (
		.clk(clk_pixel_2x), .rst_n(rstn_pixel),
		.diagnostic_req(w_diagnostic_pattern_request),
		.live_vsync(w_live_hdmi_vsync), .live_hsync(w_live_hdmi_hsync),
		.live_href(w_live_hdmi_href), .live_rgb(w_live_hdmi_rgb),
		.out_vsync(w_hdmi_vsync), .out_hsync(w_hdmi_hsync),
		.out_href(w_hdmi_href), .out_rgb(w_hdmi_rgb), .diagnostic_active()
	);

	// Text menu overlay.  VS, HS, DE and RGB all pass through exactly three
	// registers, so line width, frame period and polarity are unchanged.  The
	// display record is committed only during vertical blanking.
	wire w_ui_vsync, w_ui_hsync, w_ui_href;
	wire [23:0] w_ui_rgb;
	generate if (MENU_BUILD) begin : g_menu_overlay
		(* async_reg = "true" *) reg [`MENU_DISP_WIDTH-1:0] r_menu_disp_meta;
		(* async_reg = "true" *) reg [`MENU_DISP_WIDTH-1:0] r_menu_disp_sync;
		reg [`MENU_DISP_WIDTH-1:0] r_menu_disp_active;
		always @(posedge clk_pixel_2x or negedge rstn_pixel) begin
			if (!rstn_pixel) begin
				r_menu_disp_meta   <= {`MENU_DISP_WIDTH{1'b0}};
				r_menu_disp_sync   <= {`MENU_DISP_WIDTH{1'b0}};
				r_menu_disp_active <= {`MENU_DISP_WIDTH{1'b0}};
			end else begin
				r_menu_disp_meta <= w_menu_disp_sys;
				r_menu_disp_sync <= r_menu_disp_meta;
				if (!w_hdmi_vsync)
					r_menu_disp_active <= r_menu_disp_sync;
			end
		end

		image2_menu_render #(.H_DISP(1920), .V_DISP(1080)) u_menu_text_render (
			.clk(clk_pixel_2x), .rst_n(rstn_pixel),
			.in_vsync(w_hdmi_vsync), .in_hsync(w_hdmi_hsync),
			.in_href(w_hdmi_href), .in_rgb(w_hdmi_rgb),
			.disp(r_menu_disp_active),
			.out_vsync(w_ui_vsync), .out_hsync(w_ui_hsync),
			.out_href(w_ui_href), .out_rgb(w_ui_rgb)
		);
	end else begin : g_no_menu_overlay
		assign w_ui_vsync = w_hdmi_vsync;
		assign w_ui_hsync = w_hdmi_hsync;
		assign w_ui_href  = w_hdmi_href;
		assign w_ui_rgb   = w_hdmi_rgb;
	end endgenerate

	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	LVDS Output 
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	HDMI requires specific timing, thus is not compatible with LCD & LVDS & DSI. Must implement standalone. 
	
	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	
	//-------------------------------------
	//Digilent HDMI-TX IP Modified by CB elec.
	rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi 
	(
		.oe_i 		(1'b1), 			//	Always enable output
		.bitflip_i 		(4'b0000), 		//	Reverse clock & data lanes. 
		
		.aRst			(1'b0), 
		.aRst_n		(1'b1), 
		
		.PixelClk		(clk_pixel_2x        ),//pixel clk = 148.5M
		
		.vid_pVSync		(w_ui_vsync),
		.vid_pHSync		(w_ui_hsync),
		.vid_pVDE		(w_ui_href),
		.vid_pData		(w_ui_rgb),
		
		.txc_o		(hdmi_txc_o), 
		.txd0_o		(hdmi_txd0_o), 
		.txd1_o		(hdmi_txd1_o), 
		.txd2_o		(hdmi_txd2_o)
	); 
			
	
	
endmodule

`include "src/uart/integer_divider.v"
`include "src/uart/uart_receiver.v"
`include "src/uart/uart_transfer.v"
`include "src/uart/uart_tx_arbiter.v"
`include "src/uart/key_uart_reporter.v"
`include "src/adc/mcp3202_spi.v"
`include "src/adc/adc_input_ctrl.v"
`include "src/adc/adc_uart_reporter.v"
`include "src/adc/adc_threshold_ctrl.v"
`include "src/vision/edge_threshold_cdc.v"
`include "images/image2_video_guard/image2_vision_ctrl.v"
`include "src/vision/video_diagnostic_mux.v"
`include "src/vision/gray_edge_split.v"
`include "src/vision/background_mask_pipeline.v"
`include "src/vision/person_snapshot_selector.v"
`include "src/vision/person_roi_pipeline.v"
`include "src/vision/edge_background_capture.v"
`include "src/vision/gray_canny_alignment.v"
`include "src/photo/photo_capture_2x_rgb565.v"
`include "src/photo/photo_capture_modes.v"
`include "src/storage/photo_work_memory.v"
`include "src/photo/photo_frame_process.v"
`include "src/storage/fat32_bmp_reader.v"
`include "src/storage/photo_ddr_stage.v"
`include "src/storage/gallery_word_fifo.v"
`include "src/storage/photo_display_stream.v"
`include "src/vision/rgb_white_balance.v"
`include "src/vision/gamma_correction.v"
`include "src/vision/grey.v"
`include "src/vision/median3x3_sort3.v"
`include "src/vision/median3x3_kernel.v"
`include "src/vision/median3x3_filter.v"
`include "src/vision/black_threshold.v"
`include "src/vision/binary_morph3x3.v"
`include "src/vision/linkruncca_core.v"
`include "src/vision/shape_hough_rectangle_detector.v"
`include "src/vision/shape_frame_analyzer.v"
`include "src/vision/shape_object_classifier.v"
`include "src/vision/shape_overlay.v"
`include "src/vision/shape_chinese_font.v"
`include "src/vision/shape_label_overlay.v"
`include "src/vision/shape_recognition_pipeline.v"
`include "src/vision/shape_uart_reporter.v"
`include "src/vision/rgb_median3x3_filter.v"
`include "src/vision/image1_median_frontend.v"
`include "src/vision/image1_video_mux.v"
`include "src/vision/sobel_edge.v"
`include "src/vision/gaussian3x3_filter.v"
`include "src/vision/canny_gradient.v"
`include "src/vision/canny_nms.v"
`include "src/vision/canny_double_threshold.v"
`include "src/vision/canny_hysteresis.v"
`include "src/vision/canny_edge.v"
`include "src/vision/rgb_window_delay.v"
`include "src/vision/color_edge_overlay.v"
`include "src/vision/rgb_color_edge_overlay.v"
`include "src/vision/rgb_edge_colorizer.v"
`include "src/storage/photo_async_fifo.v"
`include "src/storage/photo_axi_mux.v"
`include "src/storage/photo_ddr_dma.v"
`include "src/storage/sd4_command.v"
`include "src/storage/sd4_host.v"
`include "src/storage/fat32_photo_writer.v"
`include "src/storage/photo_event_uart.v"
`include "src/storage/photo_uart_export.v"
`include "images/image2_video_guard/image2_photo_pipeline.v"

`include "src/ui/key_press_debounce.v"
`include "src/ui/menu_font_8x8.v"
`include "images/image2_video_guard/image2_menu_rom.v"
`include "images/image2_video_guard/image2_menu_ctrl.v"
`include "images/image2_video_guard/image2_menu_render.v"

`include "src/ui/flash_image_switch.v"

`include "images/image2_video_guard/image2_video_diagnostic.v"
