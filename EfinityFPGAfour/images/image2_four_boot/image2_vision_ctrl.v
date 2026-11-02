`timescale 1ns / 1ps
`include "images/image2_four_boot/image2_menu_defs.vh"

//////////////////////////////////////////////////////////////////////////////////
// UART command decoder for video mode, edge algorithm and image controls.
//
// Commands (ASCII, case-insensitive where applicable unless noted):
//   C      : color bypass
//   G      : grayscale
//   E or S : binary edge image (Sobel/Canny selected by A)
//   O      : color edge overlay (RGB-Sobel/luminance-Canny selected by V)
//   T      : cycle color -> grayscale -> edge -> overlay -> color
//   A      : toggle grayscale edge algorithm; reply 'S'=Sobel, 'C'=Canny
//   V      : toggle color-overlay algorithm; reply 'S'=Sobel, 'C'=Canny
//   With SOBEL_AVAILABLE=0, A/V always select Canny and reply 'C'.
//   Hnumber + Enter : set Sobel/Canny high threshold (0..2047)
//   Lnumber + Enter : set Canny low threshold independently (0..high)
//   + / -  : raise / lower the high threshold by 1
//   number + Enter : backward-compatible high-threshold setting
//   R      : restore both threshold defaults
//   WRnumber + Enter : set red white-balance gain (Q8.8, 256 = 1.0)
//   WGnumber + Enter : set green white-balance gain
//   WBnumber + Enter : set blue white-balance gain
//   WD     : restore all white-balance gains to their defaults
//   Y      : toggle Gamma 2.2 correction; reply '1'=enabled, '0'=disabled
//   Pnumber + Enter : set Gamma strength (0..256; 256 = full Gamma 2.2)
//   M      : toggle the 3x3 grayscale/RGB median pre-filters; reply '1'/'0'
//   F      : toggle DDR frame freeze; reply '1'=frozen, '0'=live
//   Z/z    : toggle independent HDMI diagnostic pattern; reply '1'/'0'
//   |      : toggle gray-left/Canny-right comparison when SPLIT_AVAILABLE;
//            selects E, disables shape overlay; C/G/E/S/O/T/D exit comparison.
//   b      : capture one RGB565 DDR photo and save it to TF; live video stays on
//   image3 PERSON_AVAILABLE: b captures independent RAW background (K=request
//   accepted, Q: B=busy/0=not ready/1=ready/!=DDR error); U cycles 1 raw mask,
//   2 cleaned, 3 selected, 4 contour, 5 selected+ROI, 0 normal. Nnumber+Enter
//   sets RAW difference threshold (0..255); X toggles RAW/E analysis (R/E reply).
//   D cycles 0 bypass/1 opening/2 gentle.
//   Other profiles continue rejecting U/N.
//   X      : enter/leave the TF gallery; it does not alter Q state
//   I/i    : initialize SD card and report type/capacity/CID/CSD
//   < / >  : select previous/next TF photo for gallery playback
//   With PHOTO_AVAILABLE=0, b/I/i/X/x/</> reply '!' and emit no requests.
//   D      : toggle RGB/gray-background shape overlay; reply '1'/'0'
//   J      : toggle rectangle detector; reply '0'=legacy, '1'=line fitting
//   K0..K3 + Enter : set line support to 1/2, 3/8, 1/4, or 1/8
//   Bnumber + Enter : set black threshold (0..255; upper-case B)
//   Q      : request a full shape-status message from the UART reporter
//   ?      : report the requested display mode ('0', '1', '2', or '3')
//   game / video / @x,y + Enter : retired; consumed and rejected with '!'
//
// Decimal digits are buffered without replies. Enter applies the complete value
// and returns 'K'. General values above 2047 saturate at 2047; Gamma strength
// additionally clamps at 256. Prefix bytes are accepted silently. An
// unsupported command returns '!'.
//////////////////////////////////////////////////////////////////////////////////

module image2_vision_ctrl
#(
    parameter        SOBEL_AVAILABLE = 1'b1,
    parameter        PHOTO_AVAILABLE = 1'b1,
    parameter        VISION_AVAILABLE = 1'b1,
    parameter        SHAPE_AVAILABLE = 1'b1,
    parameter        OVERLAY_AVAILABLE = 1'b1,
    parameter        SPLIT_AVAILABLE = 1'b0,
    parameter        PERSON_AVAILABLE = 1'b0,
    parameter        PERSON_EDGE_AVAILABLE = 1'b1,
    parameter        PERSON_EXTRA_VIEW = 1'b0,
    parameter        LIGHTING_AVAILABLE = 1'b0,
    parameter        WHITE_AVAILABLE = 1'b0,
    parameter [7:0]  PERSON_VERSION = "6",
    parameter        MEDIAN_AVAILABLE = 1'b1,
    parameter        EDGE_TEST_PROFILE = 1'b0,
    parameter        PHOTO_EDGE_PROFILE = 1'b0,
    parameter [1:0]  DEFAULT_VIDEO_MODE     = 2'd1,
    parameter [10:0] DEFAULT_EDGE_THRESHOLD = 11'd160,
    parameter [10:0] DEFAULT_CANNY_LOW_THRESHOLD = 11'd80,
    parameter [10:0] DEFAULT_WB_RED_GAIN     = 11'd256,
    parameter [10:0] DEFAULT_WB_GREEN_GAIN   = 11'd256,
    parameter [10:0] DEFAULT_WB_BLUE_GAIN    = 11'd256,
    parameter        DEFAULT_GAMMA_ENABLE    = 1'b0,
    parameter [8:0]  DEFAULT_GAMMA_STRENGTH  = 9'd64,
    parameter        DEFAULT_MEDIAN_ENABLE   = 1'b0,
    parameter        DEFAULT_GRAY_CANNY_ENABLE  = 1'b0,
    parameter        DEFAULT_COLOR_CANNY_ENABLE = 1'b0,
    parameter        DEFAULT_SHAPE_ENABLE       = 1'b0,
    parameter        DEFAULT_RECT_LINE_FIT_ENABLE = 1'b1,
    parameter [1:0]  DEFAULT_LINE_SUPPORT_LEVEL   = 2'd0,
    parameter [7:0]  DEFAULT_BLACK_THRESHOLD    = 8'd96
)
(
    input               clk,
    input               rst_n,

    input       [7:0]   rx_data,
    input               rx_valid,

    input               tx_done,
    output reg  [7:0]   tx_data,
    output reg          tx_start,

    // Stable configuration levels. The top level synchronizes and applies
    // these values only at a frame boundary in the pixel-clock domain.
    output reg  [1:0]   video_mode_req,
    output reg  [10:0]  edge_threshold_req,
    output reg  [10:0]  canny_low_threshold_req,
    output reg  [10:0]  wb_red_gain_req,
    output reg  [10:0]  wb_green_gain_req,
    output reg  [10:0]  wb_blue_gain_req,
    output reg          gamma_enable_req,
    output reg  [8:0]   gamma_strength_req,
    output reg          median_enable_req,
    output reg          edge_cleanup_req,
    output reg [1:0]    photo_cleanup_level_req,
    output reg [10:0]   photo_min_pixels_req,
    output reg          freeze_req,
    output reg          diagnostic_pattern_req,
    output reg          split_enable_req,
    output reg background_capture_req,
    output reg [2:0] person_view_req,
    output reg person_edge_source_req,
    output reg person_edge_tolerance_req,
    output reg person_stats_query_req,input person_stats_busy,
    input person_edge_source_active,
    input person_edge_foreground_present,
    input person_edge_frame_fault,
    output reg [7:0] difference_threshold_req,
    output reg [1:0] person_noise_req,
    output reg lighting_suppress_req,
    output reg white_background_req,
    input background_ready, input background_busy, input background_fault,
    output reg          photo_uart_req,
    output reg          photo_capture_req,
    output reg          photo_delete_req,
    output reg          photo_gallery_toggle_req,
    output reg          sd_info_query_req,
    output reg          photo_gallery_prev_req,
    output reg          photo_gallery_next_req,
    output reg          gray_canny_enable_req,
    output reg          color_canny_enable_req,
    output reg          shape_enable_req,
    output reg          rect_line_fit_enable_req,
    output reg  [1:0]   line_support_level_req,
    output reg  [7:0]   black_threshold_req,
    output reg          status_query_req,
    output reg          threshold_update,

    // On-screen menu write port.  The menu sets absolute values in the same
    // registers the serial commands own, so there is one source of truth.
    // Addresses are defined in images/image2_four_boot/image2_menu_defs.vh.
    input               menu_write_valid,
    input       [4:0]   menu_write_addr,
    input       [11:0]  menu_write_value
);

localparam [1:0] MODE_COLOR = 2'd0;
localparam [1:0] MODE_GRAY  = 2'd1;
localparam [1:0] MODE_EDGE  = 2'd2;
localparam [1:0] MODE_OVERLAY = 2'd3;
localparam [2:0] PERSON_LAST_VIEW=PERSON_EXTRA_VIEW?3'd6:3'd5;

localparam [3:0] WORD_IDLE    = 4'd0;
localparam [3:0] WORD_GAME_A  = 4'd1;
localparam [3:0] WORD_GAME_M  = 4'd2;
localparam [3:0] WORD_GAME_E  = 4'd3;
localparam [3:0] WORD_VIDEO_I = 4'd4;
localparam [3:0] WORD_VIDEO_D = 4'd5;
localparam [3:0] WORD_VIDEO_E = 4'd6;
localparam [3:0] WORD_VIDEO_O = 4'd7;
localparam [3:0] WORD_HIT_X   = 4'd8;
localparam [3:0] WORD_HIT_Y   = 4'd9;

localparam [3:0] TARGET_THRESHOLD      = 4'd0;
localparam [3:0] TARGET_WB_RED         = 4'd1;
localparam [3:0] TARGET_WB_GREEN       = 4'd2;
localparam [3:0] TARGET_WB_BLUE        = 4'd3;
localparam [3:0] TARGET_GAMMA_STRENGTH = 4'd4;
localparam [3:0] TARGET_CANNY_LOW       = 4'd5;
localparam [3:0] TARGET_BLACK_THRESHOLD = 4'd6;
localparam [3:0] TARGET_LINE_SUPPORT     = 4'd7;
localparam [3:0] TARGET_REJECTED_NUMBER = 4'd8;
localparam [3:0] TARGET_DIFFERENCE = 4'd9;
localparam [3:0] TARGET_PERSON_VIEW = 4'd10;
localparam [3:0] TARGET_PERSON_VIEW_DONE = 4'd11;
localparam [3:0] TARGET_PERSON_TOLERANCE = 4'd12;
localparam [3:0] TARGET_PHOTO_MINIMUM = 4'd13;

reg        command_updates_mode;
reg        command_updates_threshold;
reg        command_updates_canny_low;
reg        command_updates_wb_red;
reg        command_updates_wb_green;
reg        command_updates_wb_blue;
reg        command_updates_gamma;
reg        command_updates_median;
reg        command_updates_freeze;
reg        command_updates_diagnostic;
reg        command_updates_split;
reg        command_updates_gray_algorithm;
reg        command_updates_color_algorithm;
reg        command_updates_shape;
reg        command_updates_rect_line_fit;
reg        command_updates_line_support;
reg        command_updates_black_threshold;
reg        command_updates_status_query;
reg        command_updates_word_state;
reg [3:0]  command_next_word_state;
reg        command_updates_number;
reg        command_updates_target;
reg        command_updates_wb_prefix;
reg        command_has_response;
reg [10:0] command_next_wb_red;
reg [10:0] command_next_wb_green;
reg [10:0] command_next_wb_blue;
reg        command_next_number_valid;
reg [10:0] command_next_number;
reg [3:0]  command_next_target;
reg        command_next_wb_prefix;
reg [7:0]  command_response;

reg        number_valid;
reg [10:0] number_value;
reg [3:0]  number_target;
reg        wb_prefix;
reg [3:0]  word_state;
always @(*) begin
    command_updates_mode      = 1'b0;
    command_updates_threshold = 1'b0;
    command_updates_canny_low = 1'b0;
    command_updates_wb_red    = 1'b0;
    command_updates_wb_green  = 1'b0;
    command_updates_wb_blue   = 1'b0;
    command_updates_gamma     = 1'b0;
    command_updates_median    = 1'b0;
    command_updates_freeze    = 1'b0;
    command_updates_diagnostic = 1'b0;
    command_updates_split = 1'b0;
    command_updates_gray_algorithm  = 1'b0;
    command_updates_color_algorithm = 1'b0;
    command_updates_shape     = 1'b0;
    command_updates_rect_line_fit = 1'b0;
    command_updates_line_support = 1'b0;
    command_updates_black_threshold = 1'b0;
    command_updates_status_query = 1'b0;
    command_updates_word_state = 1'b0;
    command_next_word_state = word_state;
    command_updates_number    = 1'b0;
    command_updates_target    = 1'b0;
    command_updates_wb_prefix = 1'b0;
    command_has_response      = 1'b1;
    command_next_wb_red       = wb_red_gain_req;
    command_next_wb_green     = wb_green_gain_req;
    command_next_wb_blue      = wb_blue_gain_req;
    command_next_number_valid = number_valid;
    command_next_number       = number_value;
    command_next_target       = number_target;
    command_next_wb_prefix    = wb_prefix;
    command_response          = 8'h21; // '!': unsupported command

    // Consume retired game packets so their letters/digits cannot change
    // edge algorithms, thresholds, or trigger SD commands.
    if ((word_state != WORD_IDLE) || (rx_data == 8'h67) ||
        (rx_data == 8'h76) || ((rx_data == 8'h40) && !PHOTO_EDGE_PROFILE)) begin
        command_has_response      = 1'b0;
        command_updates_word_state = 1'b1;
        command_updates_number    = 1'b1;
        command_next_number_valid = 1'b0;
        command_next_number       = 11'd0;
        command_updates_target    = 1'b1;
        command_next_target       = TARGET_THRESHOLD;
        command_updates_wb_prefix = 1'b1;
        command_next_wb_prefix    = 1'b0;

        case (word_state)
            WORD_IDLE: begin
            if (rx_data == 8'h67)       // 'g'
                command_next_word_state = WORD_GAME_A;
            else if (rx_data == 8'h76)  // 'v'
                command_next_word_state = WORD_VIDEO_I;
            else                        // '@': retired coordinate packet
                command_next_word_state = WORD_HIT_X;
            end
            WORD_GAME_A: begin
                if (rx_data == 8'h61)       // 'a'
                    command_next_word_state = WORD_GAME_M;
                else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            WORD_GAME_M: begin
                if (rx_data == 8'h6d)       // 'm'
                    command_next_word_state = WORD_GAME_E;
                else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            WORD_GAME_E: begin
                command_next_word_state = WORD_IDLE;
                command_has_response = 1'b1;
            end
            WORD_VIDEO_I: begin
                if (rx_data == 8'h69)       // 'i'
                    command_next_word_state = WORD_VIDEO_D;
                else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            WORD_VIDEO_D: begin
                if (rx_data == 8'h64)       // 'd'
                    command_next_word_state = WORD_VIDEO_E;
                else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            WORD_VIDEO_E: begin
                if (rx_data == 8'h65)       // 'e'
                    command_next_word_state = WORD_VIDEO_O;
                else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            WORD_VIDEO_O: begin
                command_next_word_state = WORD_IDLE;
                command_has_response = 1'b1;
            end
            WORD_HIT_X, WORD_HIT_Y: begin
                // No coordinate storage or arithmetic remains. Reject once
                // at Enter; consume digits/comma without touching thresholds.
                if ((rx_data >= 8'h30) && (rx_data <= 8'h39)) begin
                    command_has_response = 1'b0;
                end else if (rx_data == 8'h2c) begin
                    command_next_word_state = WORD_HIT_Y;
                end else begin
                    command_next_word_state = WORD_IDLE;
                    command_has_response = 1'b1;
                end
            end
            default: begin
                command_next_word_state = WORD_IDLE;
                command_has_response = 1'b1;
            end
        endcase
    // A W prefix reserves the next byte for choosing a white-balance channel.
    // This keeps the existing single-byte R/G commands backward compatible.
    end else if (wb_prefix) begin
        command_updates_wb_prefix = 1'b1;
        command_next_wb_prefix    = 1'b0;
        command_updates_number    = 1'b1;
        command_next_number_valid = 1'b0;
        command_next_number       = 11'd0;
        command_updates_target    = 1'b1;
        command_next_target       = TARGET_THRESHOLD;

        case (rx_data)
            8'h52, 8'h72: begin       // 'R', 'r'
                command_next_target  = TARGET_WB_RED;
                command_has_response = 1'b0;
            end

            8'h47, 8'h67: begin       // 'G', 'g'
                command_next_target  = TARGET_WB_GREEN;
                command_has_response = 1'b0;
            end

            8'h42, 8'h62: begin       // 'B', 'b'
                command_next_target  = TARGET_WB_BLUE;
                command_has_response = 1'b0;
            end

            8'h44, 8'h64: begin       // 'D', 'd': defaults
                command_updates_wb_red   = 1'b1;
                command_updates_wb_green = 1'b1;
                command_updates_wb_blue  = 1'b1;
                command_next_wb_red      = DEFAULT_WB_RED_GAIN;
                command_next_wb_green    = DEFAULT_WB_GREEN_GAIN;
                command_next_wb_blue     = DEFAULT_WB_BLUE_GAIN;
                command_response         = 8'h57; // 'W'
            end

            8'h57, 8'h77: begin       // repeated 'W', 'w'
                command_next_wb_prefix = 1'b1;
                command_has_response   = 1'b0;
            end

            8'h0D, 8'h0A: begin       // cancel an incomplete prefix
                command_has_response = 1'b0;
            end

            default: begin
                command_response = 8'h21;
            end
        endcase
    end else begin
        case (rx_data)
            8'h7C: begin             // '|': image1 gray/edge comparison
                if (SPLIT_AVAILABLE && VISION_AVAILABLE) begin
                    command_updates_split = 1'b1;
                    command_updates_number = 1'b1;
                    command_next_number_valid = 1'b0;
                    command_next_number = 11'd0;
                    command_updates_target = 1'b1;
                    command_next_target = TARGET_THRESHOLD;
                    command_response = split_enable_req ? "0" : "1";
                end
            end
            8'h43, 8'h63: begin       // 'C', 'c'
                command_updates_mode      = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response          = 8'h30;
            end

            8'h47, 8'h67: begin       // 'G', 'g'
                command_updates_mode      = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response          = 8'h31;
            end

            8'h45, 8'h65,             // 'E', 'e'
            8'h53, 8'h73: begin       // 'S', 's'
                command_updates_mode      = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response          = 8'h32;
            end

            8'h4F, 8'h6F: begin       // 'O', 'o': color edge overlay
                command_updates_mode      = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response          = 8'h33;
            end

            8'h54, 8'h74: begin       // 'T', 't'
                command_updates_mode      = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                case (video_mode_req)
                    MODE_COLOR: command_response = 8'h31;
                    MODE_GRAY:  command_response = VISION_AVAILABLE ? 8'h32 : 8'h30;
                    MODE_EDGE:  command_response = OVERLAY_AVAILABLE ? 8'h33 : 8'h30;
                    default:    command_response = 8'h30;
                endcase
            end

            8'h57, 8'h77: begin       // 'W', 'w': WB command prefix
                command_updates_wb_prefix = 1'b1;
                command_next_wb_prefix    = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_next_number       = 11'd0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_has_response      = 1'b0;
            end

            8'h59, 8'h79: begin       // 'Y', 'y': toggle Gamma 2.2
                command_updates_gamma      = 1'b1;
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = gamma_enable_req ? 8'h30 : 8'h31;
            end

            8'h50, 8'h70: begin       // 'P', 'p': Gamma-strength number prefix
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_GAMMA_STRENGTH;
                command_has_response       = 1'b0;
            end

            8'h48, 8'h68: begin       // 'H', 'h': high-threshold number prefix
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_has_response       = 1'b0;
            end

            8'h4C, 8'h6C: begin       // 'L', 'l': Canny low-threshold prefix
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_CANNY_LOW;
                command_has_response       = 1'b0;
            end

            8'h42: begin               // 'B': black-threshold number prefix
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_BLACK_THRESHOLD;
                command_has_response       = 1'b1;
                command_response           = 8'h42;
            end

            8'h62: begin               // b: one-shot DDR photo capture/save
                // Keep the numeric parser in a neutral state.  Capture itself
                // is strobed below in the sequential block so it is a single
                // clock request even if the UART stream continues immediately.
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                // The command is acknowledged only after the requested DDR
                // frame has been completely committed.
                command_has_response       = !PHOTO_AVAILABLE;
                if (!PHOTO_AVAILABLE) command_response = "!";
            end

            8'h3C: begin               // '<': previous TF gallery item
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = PHOTO_AVAILABLE ? 8'h3C : "!";
            end

            8'h3E: begin               // '>': next TF gallery item
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = PHOTO_AVAILABLE ? 8'h3E : "!";
            end

            8'h58, 8'h78: begin       // 'X', 'x': enter/leave TF gallery
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = PHOTO_AVAILABLE ? 8'h58 : "!";
            end

            8'h49, 8'h69: begin       // 'I'/'i': standalone SD information report
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_has_response       = !PHOTO_AVAILABLE;
                if (!PHOTO_AVAILABLE) command_response = "!";
            end

            8'h4D, 8'h6D: begin       // 'M', 'm': toggle gray and RGB median pre-filters
                command_updates_median     = 1'b1;
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = median_enable_req ? 8'h30 : 8'h31;
            end

            8'h46, 8'h66: begin       // 'F', 'f': toggle DDR frame freeze
                command_updates_freeze     = 1'b1;
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = freeze_req ? 8'h30 : 8'h31;
            end

            8'h44, 8'h64: begin       // 'D', 'd': toggle shape detection
                command_updates_shape      = 1'b1;
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_THRESHOLD;
                command_response           = shape_enable_req ? 8'h30 : 8'h31;
            end

            8'h55, 8'h75: begin // U cycles; an optional single 0..5 selects an exact view.
                command_updates_number=1'b1;command_next_number_valid=1'b0;command_next_number=0;
                command_updates_target=1'b1;command_next_target=PERSON_AVAILABLE ? TARGET_PERSON_VIEW : TARGET_REJECTED_NUMBER;
                command_response=PERSON_AVAILABLE ? (person_view_req==PERSON_LAST_VIEW ? "0" : "1"+person_view_req) : "!";
            end
            8'h4e, 8'h6e: begin // Consume retired N<number> safely, never change the edge threshold.
                command_updates_number=1'b1;command_next_number_valid=1'b0;command_next_number=0;
                command_updates_target=1'b1;command_next_target=PERSON_AVAILABLE ? TARGET_DIFFERENCE : TARGET_REJECTED_NUMBER;command_has_response=1'b0;
            end

            8'h4A, 8'h6A: begin       // 'J', 'j': legacy/line-fit rectangle detector
                command_updates_rect_line_fit = 1'b1;
                command_updates_number        = 1'b1;
                command_next_number_valid     = 1'b0;
                command_next_number           = 11'd0;
                command_updates_target        = 1'b1;
                command_next_target           = TARGET_THRESHOLD;
                command_response = rect_line_fit_enable_req ? 8'h30 : 8'h31;
            end

            8'h4B, 8'h6B: begin       // 'K', 'k': line-support level prefix
                command_updates_number     = 1'b1;
                command_next_number_valid  = 1'b0;
                command_next_number        = 11'd0;
                command_updates_target     = 1'b1;
                command_next_target        = TARGET_LINE_SUPPORT;
                command_has_response       = 1'b0;
            end

            8'h5A, 8'h7A: begin       // 'Z', 'z': independent HDMI test
                command_updates_diagnostic = 1'b1;
                command_updates_number = 1'b1;
                command_next_number_valid = 1'b0;
                command_next_number = 11'd0;
                command_updates_target = 1'b1;
                command_next_target = TARGET_THRESHOLD;
                command_response = diagnostic_pattern_req ? "0" : "1";
            end

            8'h51, 8'h71: begin       // 'Q', 'q': query shape status
                command_updates_status_query = 1'b1;
                command_updates_number       = 1'b1;
                command_next_number_valid    = 1'b0;
                command_next_number          = 11'd0;
                command_updates_target       = 1'b1;
                command_next_target          = TARGET_THRESHOLD;
                command_has_response         = 1'b0;
            end

            8'h41, 8'h61: begin       // 'A', 'a': gray edge Sobel/Canny
                command_updates_gray_algorithm = 1'b1;
                command_updates_number         = 1'b1;
                command_next_number_valid      = 1'b0;
                command_next_number            = 11'd0;
                command_updates_target         = 1'b1;
                command_next_target            = TARGET_THRESHOLD;
                command_response = !SOBEL_AVAILABLE ? 8'h43 :
                                   (gray_canny_enable_req ? 8'h53 : 8'h43);
            end

            8'h56, 8'h76: begin       // 'V', 'v': color overlay Sobel/Canny
                command_updates_color_algorithm = 1'b1;
                command_updates_number          = 1'b1;
                command_next_number_valid       = 1'b0;
                command_next_number             = 11'd0;
                command_updates_target          = 1'b1;
                command_next_target             = TARGET_THRESHOLD;
                command_response = !SOBEL_AVAILABLE ? 8'h43 :
                                   (color_canny_enable_req ? 8'h53 : 8'h43);
            end

            8'h2B: begin               // '+'
                command_updates_threshold = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response = 8'h2B;
            end

            8'h2D: begin               // '-'
                command_updates_threshold = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response = 8'h2D;
            end

            8'h52, 8'h72: begin        // 'R', 'r'
                command_updates_threshold = 1'b1;
                command_updates_canny_low = 1'b1;
                command_updates_number    = 1'b1;
                command_next_number_valid = 1'b0;
                command_updates_target    = 1'b1;
                command_next_target       = TARGET_THRESHOLD;
                command_response          = 8'h52;
            end

            8'h3F: begin               // '?'
                case (video_mode_req)
                    MODE_COLOR: command_response = 8'h30;
                    MODE_GRAY:  command_response = 8'h31;
                    MODE_EDGE:  command_response = 8'h32;
                    default:    command_response = 8'h33;
                endcase
            end

            8'h0D, 8'h0A: begin        // apply a pending decimal value
                if (number_valid) begin
                    case (number_target)
                        TARGET_WB_RED: begin
                            command_updates_wb_red = 1'b1;
                            command_next_wb_red    = number_value;
                        end
                        TARGET_WB_GREEN: begin
                            command_updates_wb_green = 1'b1;
                            command_next_wb_green    = number_value;
                        end
                        TARGET_WB_BLUE: begin
                            command_updates_wb_blue = 1'b1;
                            command_next_wb_blue    = number_value;
                        end
                        TARGET_GAMMA_STRENGTH: begin
                            // Applied directly in the sequential block below.
                        end
                        TARGET_CANNY_LOW: begin
                            command_updates_canny_low = 1'b1;
                        end
                        TARGET_BLACK_THRESHOLD: begin
                            command_updates_black_threshold = 1'b1;
                        end
                        TARGET_LINE_SUPPORT: begin
                            command_updates_line_support = 1'b1;
                        end
                        TARGET_DIFFERENCE: begin end
                        TARGET_PHOTO_MINIMUM: begin end
                        TARGET_REJECTED_NUMBER: begin end
                        default: begin
                            command_updates_threshold = 1'b1;
                        end
                    endcase
                    command_updates_number    = 1'b1;
                    command_next_number_valid = 1'b0;
                    command_next_number       = 11'd0;
                    command_updates_target    = 1'b1;
                    command_next_target       = TARGET_THRESHOLD;
                    command_response = number_target==TARGET_REJECTED_NUMBER?"!":8'h4B; // K: accepted
                end else if(number_target==TARGET_PERSON_VIEW || number_target==TARGET_PERSON_VIEW_DONE || number_target==TARGET_PERSON_TOLERANCE)begin
                    // U and U<n> are immediate commands; Enter only terminates
                    // their optional argument, never commits a Canny threshold.
                    command_updates_target=1'b1;command_next_target=TARGET_THRESHOLD;
                    command_has_response=1'b0;
                end else if(number_target==TARGET_REJECTED_NUMBER)begin
                    command_updates_target=1'b1;command_next_target=TARGET_THRESHOLD;
                    command_response="!";
                end else begin
                    command_has_response = 1'b0;
                end
            end

            default: begin
                if ((rx_data >= 8'h30) && (rx_data <= 8'h39)) begin
                    command_updates_number    = 1'b1;
                    command_next_number_valid = 1'b1;
                    command_has_response      = 1'b0;

                    if(number_target==TARGET_PERSON_VIEW || number_target==TARGET_PERSON_VIEW_DONE || number_target==TARGET_PERSON_TOLERANCE)begin
                        command_next_number_valid=1'b0;
                        command_next_number=0;
                        command_updates_target=1'b1;
                        command_has_response=1'b1;
                        if(PERSON_AVAILABLE && ((number_target==TARGET_PERSON_VIEW && rx_data<="0"+PERSON_LAST_VIEW) ||
                           (number_target==TARGET_PERSON_TOLERANCE && rx_data<="1")))begin
                            command_next_target=TARGET_PERSON_VIEW_DONE;
                            command_response=rx_data;
                        end else begin
                            command_next_target=TARGET_REJECTED_NUMBER;
                            command_response="!";
                        end
                    end else if(number_target==TARGET_REJECTED_NUMBER)begin
                        // Keep consuming malformed/unsupported command tails
                        // through Enter without storing a threshold value.
                        command_next_number_valid=1'b0;
                        command_next_number=0;
                    end else if (!number_valid)
                        command_next_number = {3'd0, rx_data} - 11'h030;
                    else if ((number_value > 11'd204) ||
                        ((number_value == 11'd204) && ((rx_data - 8'h30) > 8'd7)))
                        command_next_number = 11'd2047;
                    else
                        command_next_number = number_value * 4'd10 +
                                              ({3'd0, rx_data} - 11'h030);
                end else begin
                    command_updates_number    = 1'b1;
                    command_next_number_valid = 1'b0;
                    command_updates_target    = 1'b1;
                    command_next_target       = TARGET_THRESHOLD;
                    command_response          = 8'h21;
                end
            end
        endcase
        // image3 keeps Canny but omits shape classification and colour overlay.
        // Reject their controls without changing the active display or leaking
        // rejected B/K numbers into the shared edge-threshold parser.
        if (!SHAPE_AVAILABLE) begin
            case (rx_data)
                "D","d","Q","q","J","j": begin
                    command_updates_shape = 1'b0;
                    command_updates_status_query = 1'b0;
                    command_updates_rect_line_fit = 1'b0;
                    command_response = "!";
                    command_has_response = 1'b1;
                end
                "B","K","k": begin
                    command_next_target = TARGET_REJECTED_NUMBER;
                    command_has_response = 1'b0;
                end
            endcase
        end
        if (!OVERLAY_AVAILABLE) begin
            case (rx_data)
                "O","o","V": begin
                    command_updates_mode = 1'b0;
                    command_updates_color_algorithm = 1'b0;
                    command_response = "!";
                    command_has_response = 1'b1;
                end
            endcase
        end
        // The photo image has only colour/gray display, not a hidden edge or
        // recognition mode. Consume unsupported numeric prefixes to Enter.
        if (!VISION_AVAILABLE) begin
            case (rx_data)
                "E","e","S","s","O","o","A","a","V","M","m",
                "D","d","Q","q","J","j": begin
                    command_updates_mode = 1'b0;
                    command_updates_gray_algorithm = 1'b0;
                    command_updates_color_algorithm = 1'b0;
                    command_updates_median = 1'b0;
                    command_updates_shape = 1'b0;
                    command_updates_status_query = 1'b0;
                    command_updates_rect_line_fit = 1'b0;
                    command_response = "!";
                    command_has_response = 1'b1;
                end
                "H","h","L","l","K","k","B": begin
                    command_next_target = TARGET_REJECTED_NUMBER;
                    command_has_response = 1'b0;
                end
            endcase
            if (command_updates_threshold || command_updates_canny_low ||
                command_updates_line_support || command_updates_black_threshold) begin
                command_updates_threshold = 1'b0;
                command_updates_canny_low = 1'b0;
                command_updates_line_support = 1'b0;
                command_updates_black_threshold = 1'b0;
                command_response = "!";
                command_has_response = 1'b1;
            end
            // Lowercase d belongs to photo deletion only in the photo image.
            // The native controller owns confirmation/result messages.
            if(PHOTO_AVAILABLE && rx_data=="d")command_has_response=1'b0;
        end
        if (PERSON_AVAILABLE) begin
            case(rx_data)
                "V": begin command_response=PERSON_VERSION;end
                "~": begin command_response=LIGHTING_AVAILABLE?(lighting_suppress_req?"0":"1"):"!";end
                "%": begin command_response=WHITE_AVAILABLE?(white_background_req?"0":"1"):"!";end
                "S","s": begin
                    command_updates_mode=0;command_updates_gray_algorithm=0;
                    command_updates_number=1;command_next_number_valid=0;command_next_number=0;
                    command_updates_target=1;command_next_target=TARGET_PERSON_VIEW_DONE;
                    command_has_response=person_stats_busy;command_response="!";
                end
                "O","o": begin
                    command_updates_mode=0;command_updates_color_algorithm=0;
                    command_updates_number=1;command_next_number_valid=0;command_next_number=0;
                    command_updates_target=1;command_next_target=TARGET_PERSON_TOLERANCE;
                    command_has_response=1;command_response=person_edge_tolerance_req?"0":"1";
                end
                "I","i": begin command_response=white_background_req?"W":person_edge_source_active?"E":"R";end
                "J","j": begin command_response=white_background_req?"W":!person_edge_source_active?"R":person_edge_frame_fault?"!":person_edge_foreground_present?"1":"0";end
                "X","x":begin command_response=background_busy ? "!" : person_edge_source_req ? "R" : "E";end
                "b": begin command_has_response=1; command_response=background_busy||white_background_req ? "!" : "K"; end
                "D","d": begin command_response=person_noise_req==2 ? "0" : "1"+person_noise_req; end
                "Q","q": begin command_response=background_busy ? "B" : background_fault ? "!" : background_ready ? "1" : "0"; end
            endcase
            if(!PERSON_EDGE_AVAILABLE)case(rx_data)
                "X","x","O","o","S","s":begin
                    command_updates_mode=0;command_updates_gray_algorithm=0;
                    command_updates_color_algorithm=0;
                    command_updates_number=1;command_next_number_valid=0;command_next_number=0;
                    command_updates_target=1;command_next_target=TARGET_REJECTED_NUMBER;
                    command_has_response=1;command_response="!";
                end
                "I","i","J","j":begin command_response=white_background_req?"W":"R";end
            endcase
        end
        if(!MEDIAN_AVAILABLE&&(rx_data=="M"||rx_data=="m"))begin
            command_updates_median=0;command_response="!";command_has_response=1;
        end
        if(EDGE_TEST_PROFILE)case(rx_data)
            "V":begin command_response="5";command_has_response=1;end
            "D","d":begin
                command_updates_shape=0;command_response=edge_cleanup_req?"0":"1";command_has_response=1;
            end
        endcase
        if(PHOTO_EDGE_PROFILE)case(rx_data)
            ":":begin command_has_response=1;command_response="U";end
            "@":begin command_has_response=video_mode_req!=1&&video_mode_req!=2;command_response="!";end
            "V":begin command_response="2";command_has_response=1;end
            "D":begin command_updates_shape=0;command_response=photo_cleanup_level_req==2?"0":"1"+photo_cleanup_level_req;command_has_response=1;end
            "d":begin command_updates_shape=0;command_has_response=0;end
            "N","n":begin command_next_target=TARGET_PHOTO_MINIMUM;command_has_response=0;end
            "A","a":begin command_updates_gray_algorithm=0;command_response="C";command_has_response=1;end
        endcase
    end
end

reg       tx_busy;
reg       pending_valid;
reg [7:0] pending_data;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        background_capture_req<=0; person_view_req<=0;person_edge_source_req<=0;
        lighting_suppress_req<=LIGHTING_AVAILABLE;
        white_background_req<=0;
        person_edge_tolerance_req<=1;
        person_stats_query_req<=0;
        difference_threshold_req<=24; person_noise_req<=2;
        video_mode_req     <= DEFAULT_VIDEO_MODE;
        edge_threshold_req <= DEFAULT_EDGE_THRESHOLD;
        canny_low_threshold_req <= DEFAULT_CANNY_LOW_THRESHOLD;
        threshold_update <= 1'b0;
        wb_red_gain_req    <= DEFAULT_WB_RED_GAIN;
        wb_green_gain_req  <= DEFAULT_WB_GREEN_GAIN;
        wb_blue_gain_req   <= DEFAULT_WB_BLUE_GAIN;
        gamma_enable_req   <= DEFAULT_GAMMA_ENABLE;
        gamma_strength_req <= DEFAULT_GAMMA_STRENGTH;
        median_enable_req  <= DEFAULT_MEDIAN_ENABLE;
        edge_cleanup_req <= EDGE_TEST_PROFILE;
        photo_cleanup_level_req<=1;photo_min_pixels_req<=20;
        freeze_req         <= 1'b0;
        diagnostic_pattern_req <= 1'b0;
        split_enable_req <= 1'b0;
        photo_uart_req <= 1'b0;
        photo_capture_req  <= 1'b0;
        photo_delete_req <= 1'b0;
        photo_gallery_toggle_req <= 1'b0;
        sd_info_query_req  <= 1'b0;
        photo_gallery_prev_req <= 1'b0;
        photo_gallery_next_req <= 1'b0;
        gray_canny_enable_req  <= SOBEL_AVAILABLE ? DEFAULT_GRAY_CANNY_ENABLE : 1'b1;
        color_canny_enable_req <= SOBEL_AVAILABLE ? DEFAULT_COLOR_CANNY_ENABLE : 1'b1;
        shape_enable_req       <= VISION_AVAILABLE && SHAPE_AVAILABLE && DEFAULT_SHAPE_ENABLE;
        rect_line_fit_enable_req <= DEFAULT_RECT_LINE_FIT_ENABLE;
        line_support_level_req <= DEFAULT_LINE_SUPPORT_LEVEL;
        black_threshold_req    <= DEFAULT_BLACK_THRESHOLD;
        status_query_req       <= 1'b0;
        number_valid       <= 1'b0;
        number_value       <= 11'd0;
        number_target      <= TARGET_THRESHOLD;
        wb_prefix          <= 1'b0;
        word_state         <= WORD_IDLE;
        tx_data            <= 8'h00;
        tx_start           <= 1'b0;
        tx_busy            <= 1'b0;
        pending_valid      <= 1'b0;
        pending_data       <= 8'h00;
    end else begin
        tx_start <= 1'b0;
        threshold_update <= rx_valid && (command_updates_threshold || command_updates_canny_low);
        background_capture_req<=0;
        person_stats_query_req<=0;
        if(EDGE_TEST_PROFILE&&rx_valid&&!wb_prefix&&word_state==WORD_IDLE&&(rx_data=="D"||rx_data=="d"))
            edge_cleanup_req<=!edge_cleanup_req;
        if(PERSON_AVAILABLE && rx_valid && !wb_prefix && word_state==WORD_IDLE) begin
            if(LIGHTING_AVAILABLE&&rx_data=="~")lighting_suppress_req<=!lighting_suppress_req;
            if(WHITE_AVAILABLE&&rx_data=="%")white_background_req<=!white_background_req;
            if(PERSON_EDGE_AVAILABLE&&(rx_data=="X"||rx_data=="x")&&!background_busy) person_edge_source_req<=!person_edge_source_req;
            if(PERSON_EDGE_AVAILABLE&&(rx_data=="O"||rx_data=="o"))person_edge_tolerance_req<=!person_edge_tolerance_req;
            if(PERSON_EDGE_AVAILABLE&&(rx_data=="S"||rx_data=="s")&&!person_stats_busy)person_stats_query_req<=1;
            if(PERSON_EDGE_AVAILABLE&&number_target==TARGET_PERSON_TOLERANCE && rx_data>="0" && rx_data<="1")
                person_edge_tolerance_req<=rx_data[0];
            if(rx_data=="b" && !background_busy && !white_background_req) background_capture_req<=1;
            if(rx_data=="U" || rx_data=="u") person_view_req<=person_view_req==PERSON_LAST_VIEW ? 0 : person_view_req+1'b1;
            if(number_target==TARGET_PERSON_VIEW && rx_data>="0" && rx_data<="0"+PERSON_LAST_VIEW)
                person_view_req<=rx_data-8'h30;
            if(rx_data=="D" || rx_data=="d") person_noise_req<=person_noise_req==2 ? 0 : person_noise_req+1'b1;
            if(command_updates_mode) person_view_req<=0;
            if((rx_data==13 || rx_data==10) && number_valid && number_target==TARGET_DIFFERENCE)
                difference_threshold_req<=number_value>255 ? 255 : number_value[7:0];
        end
        if (rx_valid && command_updates_diagnostic)
            diagnostic_pattern_req <= !diagnostic_pattern_req;
        status_query_req <= 1'b0;
        photo_uart_req <= PHOTO_EDGE_PROFILE && PHOTO_AVAILABLE && rx_valid && !wb_prefix &&
            word_state==WORD_IDLE && rx_data=="@" && (video_mode_req==1||video_mode_req==2);
        photo_capture_req <= 1'b0;
        photo_delete_req <= 1'b0;
        if(PHOTO_AVAILABLE && (!VISION_AVAILABLE||PHOTO_EDGE_PROFILE) && !wb_prefix && rx_valid &&
           word_state==WORD_IDLE && rx_data=="d")photo_delete_req<=1'b1;
        if(PHOTO_EDGE_PROFILE&&rx_valid&&!wb_prefix&&word_state==WORD_IDLE)begin
            if(rx_data=="D")photo_cleanup_level_req<=photo_cleanup_level_req==2?0:photo_cleanup_level_req+1'b1;
            if((rx_data==13||rx_data==10)&&number_valid&&number_target==TARGET_PHOTO_MINIMUM)
                photo_min_pixels_req<=number_value;
        end
        photo_gallery_toggle_req <= 1'b0;
        sd_info_query_req  <= 1'b0;
        photo_gallery_prev_req <= 1'b0;
        photo_gallery_next_req <= 1'b0;

        // Lower-case b requests RGB565 DDR capture/save only.
        // It does not change freeze_req: F alone controls live/frozen display.
        // Upper-case B remains reserved for the B<number> black threshold.
        if (PHOTO_AVAILABLE && !wb_prefix && rx_valid && (word_state == WORD_IDLE) && (rx_data == 8'h62)) begin
            photo_capture_req <= 1'b1;
        end
        if (PHOTO_AVAILABLE && !wb_prefix && rx_valid && (word_state == WORD_IDLE) && ((rx_data == 8'h58) || (rx_data == 8'h78)))
            photo_gallery_toggle_req <= 1'b1;
        // I/i is handled by the shared native SD session. It owns
        // its own rising-edge query latch and reports one complete message.
        if (PHOTO_AVAILABLE && !wb_prefix && rx_valid && (word_state == WORD_IDLE) && ((rx_data == 8'h49) || (rx_data == 8'h69)))
            sd_info_query_req <= 1'b1;
        if (PHOTO_AVAILABLE && !wb_prefix && rx_valid && (word_state == WORD_IDLE) && (rx_data == 8'h3C))
            photo_gallery_prev_req <= 1'b1;
        if (PHOTO_AVAILABLE && !wb_prefix && rx_valid && (word_state == WORD_IDLE) && (rx_data == 8'h3E))
            photo_gallery_next_req <= 1'b1;

        if (rx_valid && command_updates_status_query)
            status_query_req <= 1'b1;

        if (rx_valid && command_updates_word_state)
            word_state <= command_next_word_state;

        if (rx_valid && command_updates_mode) begin
            case (rx_data)
                8'h43, 8'h63: video_mode_req <= MODE_COLOR;
                8'h47, 8'h67: video_mode_req <= MODE_GRAY;
                8'h45, 8'h65,
                8'h53, 8'h73: video_mode_req <= MODE_EDGE;
                8'h4F, 8'h6F: video_mode_req <= MODE_OVERLAY;
                default: begin
                    case (video_mode_req)
                        MODE_COLOR: video_mode_req <= MODE_GRAY;
                        MODE_GRAY:  video_mode_req <= VISION_AVAILABLE ? MODE_EDGE : MODE_COLOR;
                        MODE_EDGE:  video_mode_req <= OVERLAY_AVAILABLE ? MODE_OVERLAY : MODE_COLOR;
                        default:    video_mode_req <= MODE_COLOR;
                    endcase
                end
            endcase
        end
        if (rx_valid && command_updates_threshold) begin
            case (rx_data)
                8'h2B: begin
                    if (edge_threshold_req != 11'd2047)
                        edge_threshold_req <= edge_threshold_req + 11'd1;
                end
                8'h2D: begin
                    if (edge_threshold_req != 11'd0) begin
                        edge_threshold_req <= edge_threshold_req - 11'd1;
                        if (canny_low_threshold_req >= edge_threshold_req)
                            canny_low_threshold_req <= edge_threshold_req - 11'd1;
                    end
                end
                8'h52, 8'h72: edge_threshold_req <= DEFAULT_EDGE_THRESHOLD;
                default: begin
                    edge_threshold_req <= number_value;
                    if (canny_low_threshold_req > number_value)
                        canny_low_threshold_req <= number_value;
                end
            endcase
        end
        if (rx_valid && command_updates_canny_low) begin
            if ((rx_data == 8'h52) || (rx_data == 8'h72))
                canny_low_threshold_req <= DEFAULT_CANNY_LOW_THRESHOLD;
            else if (number_value > edge_threshold_req)
                canny_low_threshold_req <= edge_threshold_req;
            else
                canny_low_threshold_req <= number_value;
        end
        if (rx_valid && command_updates_wb_red)
            wb_red_gain_req <= command_next_wb_red;
        if (rx_valid && command_updates_wb_green)
            wb_green_gain_req <= command_next_wb_green;
        if (rx_valid && command_updates_wb_blue)
            wb_blue_gain_req <= command_next_wb_blue;
        if (rx_valid && command_updates_gamma)
            gamma_enable_req <= ~gamma_enable_req;
        if (rx_valid && command_updates_median)
            median_enable_req <= ~median_enable_req;
        if (rx_valid && command_updates_freeze)
            freeze_req <= ~freeze_req;
        if (rx_valid && command_updates_gray_algorithm)
            gray_canny_enable_req <= SOBEL_AVAILABLE ? ~gray_canny_enable_req : 1'b1;
        if (rx_valid && command_updates_color_algorithm)
            color_canny_enable_req <= SOBEL_AVAILABLE ? ~color_canny_enable_req : 1'b1;
        if (rx_valid && command_updates_shape)
            shape_enable_req <= ~shape_enable_req;
        // A separate flag preserves the existing two-bit display protocol.
        // Selecting any ordinary display/recognition mode exits comparison.
        if (rx_valid && (command_updates_mode || command_updates_shape))
            split_enable_req <= 1'b0;
        if (rx_valid && command_updates_split) begin
            split_enable_req <= ~split_enable_req;
            video_mode_req <= MODE_EDGE;
            shape_enable_req <= 1'b0;
        end
        if (rx_valid && command_updates_rect_line_fit)
            rect_line_fit_enable_req <= ~rect_line_fit_enable_req;
        if (rx_valid && command_updates_line_support) begin
            if (number_value > 11'd3)
                line_support_level_req <= 2'd3;
            else
                line_support_level_req <= number_value[1:0];
        end
        if (rx_valid && command_updates_black_threshold) begin
            if (number_value > 11'd255)
                black_threshold_req <= 8'd255;
            else
                black_threshold_req <= number_value[7:0];
        end
        if (rx_valid && ((rx_data == 8'h0D) || (rx_data == 8'h0A)) &&
            number_valid && (number_target == TARGET_GAMMA_STRENGTH)) begin
            if (number_value > 11'd256)
                gamma_strength_req <= 9'd256;
            else
                gamma_strength_req <= number_value[8:0];
        end
        if (rx_valid && command_updates_number) begin
            number_valid <= command_next_number_valid;
            number_value <= command_next_number;
        end
        if (rx_valid && command_updates_target)
            number_target <= command_next_target;
        if (rx_valid && command_updates_wb_prefix)
            wb_prefix <= command_next_wb_prefix;

        // Absolute menu writes.  Placed after the serial command assignments:
        // if a menu write and a serial byte ever coincide, the explicitly
        // selected menu target wins.  The menu never toggles state, it always
        // writes the state it wants, so a missed UART reply cannot desync it.
        if (menu_write_valid) begin
            case (menu_write_addr)
                `MENU_ITEM_VIEW: begin
                    video_mode_req   <= menu_write_value[1:0]>2 ? MODE_COLOR : menu_write_value[1:0];
                    split_enable_req <= 1'b0;
                end
                `MENU_ITEM_CAPTURE: if(PHOTO_AVAILABLE) photo_capture_req<=1;
                `MENU_ITEM_GALLERY: if(PHOTO_AVAILABLE) photo_gallery_toggle_req<=1;
                `MENU_ITEM_FREEZE: freeze_req <= menu_write_value[0];
                `MENU_ITEM_TEST:   diagnostic_pattern_req <= menu_write_value[0];
                `MENU_ITEM_CANNY: begin
                    edge_threshold_req      <= menu_write_value[10:0];
                    canny_low_threshold_req <= {1'b0, menu_write_value[10:1]};
                    threshold_update        <= 1'b1;
                end
                `MENU_ITEM_CANNY_H: begin
                    edge_threshold_req <= menu_write_value[10:0];
                    if (canny_low_threshold_req > menu_write_value[10:0])
                        canny_low_threshold_req <= menu_write_value[10:0];
                    threshold_update <= 1'b1;
                end
                `MENU_ITEM_CANNY_L: begin
                    canny_low_threshold_req <=
                        (menu_write_value[10:0] > edge_threshold_req) ?
                        edge_threshold_req : menu_write_value[10:0];
                    threshold_update <= 1'b1;
                end
                `MENU_ITEM_CANNY_RST: begin
                    edge_threshold_req      <= DEFAULT_EDGE_THRESHOLD;
                    canny_low_threshold_req <= DEFAULT_CANNY_LOW_THRESHOLD;
                    threshold_update        <= 1'b1;
                end
                `MENU_ITEM_MEDIAN: median_enable_req <= menu_write_value[0];
                `MENU_ITEM_WB_R:   wb_red_gain_req   <= menu_write_value[10:0];
                `MENU_ITEM_WB_G:   wb_green_gain_req <= menu_write_value[10:0];
                `MENU_ITEM_WB_B:   wb_blue_gain_req  <= menu_write_value[10:0];
                `MENU_ITEM_WB_RST: begin
                    wb_red_gain_req   <= DEFAULT_WB_RED_GAIN;
                    wb_green_gain_req <= DEFAULT_WB_GREEN_GAIN;
                    wb_blue_gain_req  <= DEFAULT_WB_BLUE_GAIN;
                end
                `MENU_ITEM_GAMMA: gamma_enable_req <= menu_write_value[0];
                `MENU_ITEM_GAMMA_P: gamma_strength_req <=
                    (menu_write_value > 12'd256) ? 9'd256 : menu_write_value[8:0];
                `MENU_ITEM_CLEANUP: photo_cleanup_level_req <= menu_write_value>2 ? 2 : menu_write_value[1:0];
                `MENU_ITEM_MINIMUM: photo_min_pixels_req <= menu_write_value>2047 ? 2047 : menu_write_value[10:0];
                `MENU_ITEM_SD: if(PHOTO_AVAILABLE) sd_info_query_req<=1;
                `MENU_ITEM_PREV: if(PHOTO_AVAILABLE) photo_gallery_prev_req<=1;
                `MENU_ITEM_NEXT: if(PHOTO_AVAILABLE) photo_gallery_next_req<=1;
                `MENU_ITEM_DELETE: if(PHOTO_AVAILABLE) photo_delete_req<=1;
                default: ;
            endcase
        end

        if (tx_done)
            tx_busy <= 1'b0;

        if (!tx_busy) begin
            if (pending_valid) begin
                tx_data       <= pending_data;
                tx_start      <= 1'b1;
                tx_busy       <= 1'b1;
                pending_valid <= 1'b0;

                if (rx_valid && command_has_response) begin
                    pending_data  <= command_response;
                    pending_valid <= 1'b1;
                end
            end else if (rx_valid && command_has_response) begin
                tx_data  <= command_response;
                tx_start <= 1'b1;
                tx_busy  <= 1'b1;
            end
        end else if (rx_valid && command_has_response) begin
            pending_data  <= command_response;
            pending_valid <= 1'b1;
        end
    end
end

endmodule
