`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Shared-TF-card integration wrapper for BMP save and gallery read paths.
//////////////////////////////////////////////////////////////////////////////////
module photo_bmp_sd #(
    parameter integer CLK_HZ      = 96000000,
    parameter integer INIT_DIV    = 120,
    parameter integer FAST_DIV    = 8,
    parameter integer PHOTO_WIDTH = 960,
    parameter integer PHOTO_HEIGHT= 540,
    parameter integer BAND_ROWS   = 16
) (
    input  wire        clk_sys,
    input  wire        rst_n_sys,
    input  wire        clk_pixel,
    input  wire        rst_n_pixel,

    input  wire        lcd_vs,
    input  wire        lcd_de,
    input  wire [7:0]  raw8,

    output wire        save_busy,
    output wire        save_done,
    output wire        save_error,
    output wire [7:0]  save_error_code,
    output wire [31:0] file_number,
    output wire [31:0] bytes_written,
    output wire [7:0]  state_debug,

    // Legacy gallery controls (the active project uses photo_native_pipeline).
    input  wire        gallery_toggle_req,
    input  wire        gallery_prev_req,
    input  wire        gallery_next_req,
    output wire        gallery_mode,
    output wire        gallery_busy,
    output wire        gallery_error,
    output wire [31:0] gallery_file_number,
    output wire        gallery_load_start,
    output wire        gallery_load_byte_valid,
    output wire [7:0]  gallery_load_byte,
    output wire [19:0] gallery_load_byte_offset,
    output wire        gallery_load_done,
    output wire        gallery_load_error,

    output wire        sd_clk,
    output wire        sd_cmd_o,
    output wire        sd_cmd_oe,
    input  wire        sd_cmd_i,
    input  wire [3:0]  sd_dat_i,
    output wire [3:0]  sd_dat_o,
    output wire [3:0]  sd_dat_oe
);

    wire        read_sd_init_start;
    wire        read_sd_init_busy;
    wire        read_sd_init_done;
    wire        read_sd_init_error;
    wire        read_block_start;
    wire        read_block_write;
    wire [31:0] read_block_lba;
    wire        read_block_busy;
    wire        read_block_done;
    wire        read_block_error;
    wire        read_block_rx_valid;
    wire [7:0]  read_block_rx_data;
    wire [8:0]  read_block_byte_index;
    wire [7:0]  read_block_tx_byte;
    wire        host_init_start, host_init_busy, host_init_done, host_init_error;
    wire        host_block_start, host_block_write, host_block_busy, host_block_done, host_block_error;
    wire [31:0] host_block_lba;
    wire        host_block_rx_valid;
    wire [7:0]  host_block_rx_data, host_block_tx_byte;
    wire [8:0]  host_block_byte_index;

    // The b command still drives the independent photo capture block in the
    // top level.  This wrapper no longer contains any post-capture writer.
    assign save_busy            = 1'b0;
    assign save_done            = 1'b0;
    assign save_error           = 1'b0;
    assign save_error_code      = 8'd0;
    assign file_number          = 32'd0;
    assign bytes_written        = 32'd0;
    assign state_debug          = 8'd0;

    fat32_bmp_reader #(
        .PHOTO_WIDTH(PHOTO_WIDTH),
        .PHOTO_HEIGHT(PHOTO_HEIGHT)
    ) u_fat_reader (
        .clk                   (clk_sys),
        .rst_n                 (rst_n_sys),
        .gallery_toggle_req    (gallery_toggle_req),
        .gallery_prev_req      (gallery_prev_req),
        .gallery_next_req      (gallery_next_req),
        .gallery_mode          (gallery_mode),
        .read_active           (),
        .read_busy             (gallery_busy),
        .read_error            (gallery_error),
        .current_file_number   (gallery_file_number),
        .load_start            (gallery_load_start),
        .load_byte_valid       (gallery_load_byte_valid),
        .load_byte             (gallery_load_byte),
        .load_byte_offset      (gallery_load_byte_offset),
        .load_done             (gallery_load_done),
        .load_error            (gallery_load_error),
        .sd_init_start         (read_sd_init_start),
        .sd_init_busy          (read_sd_init_busy),
        .sd_init_done          (read_sd_init_done),
        .sd_init_error         (read_sd_init_error),
        .block_start           (read_block_start),
        .block_write           (read_block_write),
        .block_lba             (read_block_lba),
        .block_busy            (read_block_busy),
        .block_done            (read_block_done),
        .block_error           (read_block_error),
        .block_rx_valid        (read_block_rx_valid),
        .block_rx_data         (read_block_rx_data),
        .block_byte_index      (read_block_byte_index),
        .block_tx_byte         (read_block_tx_byte)
    );

    sd_storage_arbiter u_sd_arbiter (
        .clk                   (clk_sys), .rst_n(rst_n_sys),
        .save_active           (1'b0),
        .save_init_start       (1'b0),
        .save_init_busy        (),
        .save_init_done        (),
        .save_init_error       (),
        .save_block_start      (1'b0),
        .save_block_write      (1'b0),
        .save_block_lba        (32'd0),
        .save_block_tx_byte    (8'hff),
        .save_block_busy       (),
        .save_block_done       (),
        .save_block_error      (),
        .save_block_rx_valid   (),
        .save_block_rx_data    (),
        .save_block_byte_index (),
        .read_active           (gallery_mode || gallery_busy),
        .read_init_start       (read_sd_init_start),
        .read_init_busy        (read_sd_init_busy),
        .read_init_done        (read_sd_init_done),
        .read_init_error       (read_sd_init_error),
        .read_block_start      (read_block_start),
        .read_block_write      (read_block_write),
        .read_block_lba        (read_block_lba),
        .read_block_tx_byte    (read_block_tx_byte),
        .read_block_busy       (read_block_busy),
        .read_block_done       (read_block_done),
        .read_block_error      (read_block_error),
        .read_block_rx_valid   (read_block_rx_valid),
        .read_block_rx_data    (read_block_rx_data),
        .read_block_byte_index (read_block_byte_index),
        .host_init_start       (host_init_start),
        .host_init_busy        (host_init_busy),
        .host_init_done        (host_init_done),
        .host_init_error       (host_init_error),
        .host_block_start      (host_block_start),
        .host_block_write      (host_block_write),
        .host_block_lba        (host_block_lba),
        .host_block_tx_byte    (host_block_tx_byte),
        .host_block_busy       (host_block_busy),
        .host_block_done       (host_block_done),
        .host_block_error      (host_block_error),
        .host_block_rx_valid   (host_block_rx_valid),
        .host_block_rx_data    (host_block_rx_data),
        .host_block_byte_index (host_block_byte_index)
    );

    sd_spi_host #(
        .CLK_HZ(CLK_HZ),
        .INIT_DIV(INIT_DIV),
        .FAST_DIV(FAST_DIV)
    ) u_sd_host (
        .clk                   (clk_sys),
        .rst_n                 (rst_n_sys),
        .sd_clk                (sd_clk),
        .sd_cmd_o              (sd_cmd_o),
        .sd_cmd_oe             (sd_cmd_oe),
        .sd_cmd_i              (sd_cmd_i),
        .sd_dat_i              (sd_dat_i),
        .sd_dat_o              (sd_dat_o),
        .sd_dat_oe             (sd_dat_oe),
        .init_start            (host_init_start),
        .init_busy             (host_init_busy),
        .init_done             (host_init_done),
        .init_error            (host_init_error),
        .high_capacity         (sd_high_capacity),
        .block_start           (host_block_start),
        .block_write           (host_block_write),
        .block_lba             (host_block_lba),
        .block_busy            (host_block_busy),
        .block_done            (host_block_done),
        .block_error           (host_block_error),
        .block_rx_valid        (host_block_rx_valid),
        .block_rx_data         (host_block_rx_data),
        .block_byte_index      (host_block_byte_index),
        .block_tx_byte         (host_block_tx_byte)
    );

endmodule
