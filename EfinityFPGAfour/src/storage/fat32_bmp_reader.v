`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Streaming FAT32 reader for IMGnnnnn.BMP.
//
// This deliberately has no 512-byte register-array sector cache.  BPB fields,
// directory entries and FAT links are decoded directly from the byte-indexed
// block response.  Only the selected BMP pixel stream is emitted, with its
// bottom-up BMP rows translated to top-down RGB565 DDR byte addresses.
//////////////////////////////////////////////////////////////////////////////////
module fat32_bmp_reader #(
    parameter [15:0] PHOTO_WIDTH  = 16'd960,
    parameter [15:0] PHOTO_HEIGHT = 16'd540,
    parameter [19:0] PHOTO_BYTES  = 20'd1036800,
    parameter ENABLE_DELETE = 0,
    parameter OPEN_AVAILABLE = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        gallery_toggle_req,
    input  wire        gallery_prev_req,
    input  wire        gallery_next_req,
    input  wire        reload_after_delete,
    input  wire        open_file_req,
    input  wire [31:0] open_file_number,
    output reg         gallery_empty,
    input  wire        load_abort,
    output reg         gallery_mode,
    output wire        read_active,
    output reg         read_busy,
    output reg         read_error,
    output reg  [31:0] current_file_number,

    output reg         load_start,
    output reg         load_byte_valid,
    output reg  [7:0]  load_byte,
    output reg  [19:0] load_byte_offset,
    output reg         load_done,
    output reg         load_error,

    output reg         sd_init_start,
    input  wire        sd_init_busy,
    input  wire        sd_init_done,
    input  wire        sd_init_error,
    output reg         block_start,
    output reg         block_write,
    output reg  [31:0] block_lba,
    input  wire        block_busy,
    input  wire        block_done,
    input  wire        block_error,
    input  wire        block_rx_valid,
    input  wire [7:0]  block_rx_data,
    input  wire [8:0]  block_byte_index,
    output wire [7:0]  block_tx_byte
);

    localparam [7:0] R_IDLE       = 8'd0;
    localparam [7:0] R_INIT       = 8'd1;
    localparam [7:0] R_INIT_WAIT  = 8'd2;
    localparam [7:0] R_MBR        = 8'd3;
    localparam [7:0] R_BPB        = 8'd4;
    localparam [7:0] R_PARSE_BPB  = 8'd5;
    localparam [7:0] R_DIR        = 8'd6;
    localparam [7:0] R_PICK       = 8'd7;
    localparam [7:0] R_FILE       = 8'd8;
    localparam [7:0] R_FILE_FAT   = 8'd9;
    localparam [7:0] R_DONE       = 8'd10;
    localparam [7:0] R_FAIL       = 8'd11;
    localparam [7:0] R_DIR_FAT    = 8'd12;

    localparam [27:0] FAT32_EOC   = 28'h0ffffff8;
    localparam [19:0] ROW_BYTES   = PHOTO_WIDTH * 2;
    localparam [19:0] LAST_ROW    = (PHOTO_HEIGHT-1) * ROW_BYTES;

    reg [7:0] state;
    reg abort_pending;
    reg [7:0] after_block;
    reg [31:0] volume_lba;
    reg [15:0] sector0_bps, sector0_root_entries, sector0_fat16;
    reg fallback_valid;
    reg [31:0] fallback_number;
    reg [27:0] fallback_cluster;
    reg [15:0] bytes_per_sector;
    reg [7:0] sectors_per_cluster;
    reg [15:0] reserved_sectors;
    reg [7:0] fat_count;
    reg [31:0] fat_sectors;
    reg [31:0] first_fat_lba;
    reg [31:0] first_data_lba;
    reg [27:0] root_cluster;
    reg [27:0] scan_cluster;
    reg [7:0] scan_sector;
    reg dir_end_seen;
    reg scan_previous;
    reg delete_reload;

    reg [7:0] n0, n1, n2, n3, n4, n5, n6, n7, n8, n9, n10;
    reg [7:0] entry_attr;
    reg [15:0] entry_cluster_hi, entry_cluster_lo;
    reg candidate_valid;
    reg [31:0] candidate_number;
    reg [27:0] candidate_cluster;
    reg [31:0] entry_number;

    reg [27:0] file_cluster;
    reg [7:0] file_sector;
    reg [19:0] pixel_count;
    reg pixel_stream_complete;
    reg [19:0] bmp_row_byte;
    reg [19:0] ddr_row_base;
    reg [31:0] file_byte_base;
    reg [31:0] bmp_pixel_offset;
    reg [31:0] bmp_width;
    reg [31:0] bmp_height;
    reg [15:0] bmp_bpp;
    reg [31:0] bmp_compression;
    reg bmp_magic_ok;
    reg [27:0] next_cluster;
    reg [7:0] fat_byte0, fat_byte1, fat_byte2, fat_byte3;
    reg [8:0] fat_entry_byte;

    assign read_active = gallery_mode || read_busy;
    assign block_tx_byte = 8'hff;

    wire entry_name_ok = (n0 == "I") && (n1 == "M") && (n2 == "G") &&
                         (n3 >= "0") && (n3 <= "9") &&
                         (n4 >= "0") && (n4 <= "9") &&
                         (n5 >= "0") && (n5 <= "9") &&
                         (n6 >= "0") && (n6 <= "9") &&
                         (n7 >= "0") && (n7 <= "9") &&
                         (n8 == "B") && (n9 == "M") && (n10 == "P");
    wire [31:0] entry_number_wire =
        ((n3 - "0") * 32'd10000) + ((n4 - "0") * 32'd1000) +
        ((n5 - "0") * 32'd100) + ((n6 - "0") * 32'd10) + (n7 - "0");
    wire entry_normal_file = (entry_attr != 8'h0f) && !entry_attr[4] &&
                             !entry_attr[3] && (n0 != 8'he5) && (n0 != 8'h00);
    wire [27:0] entry_cluster_wire = {entry_cluster_hi[11:0], entry_cluster_lo};
    reg direct_selection;
    reg [31:0] direct_number;
    wire candidate_matches_direction = direct_selection ? entry_number_wire==direct_number : scan_previous ?
        ((entry_number_wire < current_file_number) &&
         (!candidate_valid || (entry_number_wire > candidate_number))) :
        ((entry_number_wire > current_file_number) &&
         (!candidate_valid || (entry_number_wire < candidate_number)));

    wire header_ok = bmp_magic_ok && (bmp_pixel_offset == 32'd512) &&
                     (bmp_width == PHOTO_WIDTH) && (bmp_height == PHOTO_HEIGHT) &&
                     (bmp_bpp == 16'd16) && (bmp_compression == 32'd3);
    wire [31:0] fat_lba_wire = first_fat_lba + ({4'd0, file_cluster} >> 7);
    wire [8:0] fat_byte_wire = {file_cluster[6:0], 2'b00};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= R_IDLE;
            abort_pending<=0;
            after_block <= R_IDLE;
            gallery_mode <= 1'b0;
            read_busy <= 1'b0;
            read_error <= 1'b0;
            current_file_number <= 32'd0;
            load_start <= 1'b0;
            load_byte_valid <= 1'b0;
            load_byte <= 8'd0;
            load_byte_offset <= 20'd0;
            load_done <= 1'b0;
            load_error <= 1'b0;
            sd_init_start <= 1'b0;
            block_start <= 1'b0;
            block_write <= 1'b0;
            block_lba <= 32'd0;
            volume_lba <= 32'd0;
            sector0_bps<=0;sector0_root_entries<=0;sector0_fat16<=0;
            fallback_valid<=0;fallback_number<=0;fallback_cluster<=0;
            bytes_per_sector <= 16'd512;
            sectors_per_cluster <= 8'd1;
            reserved_sectors <= 16'd0;
            fat_count <= 8'd0;
            fat_sectors <= 32'd0;
            first_fat_lba <= 32'd0;
            first_data_lba <= 32'd0;
            root_cluster <= 28'd2;
            scan_cluster <= 28'd2;
            scan_sector <= 8'd0;
            dir_end_seen <= 1'b0;
            scan_previous <= 1'b0;
            delete_reload <= 1'b0;
            direct_selection<=0;direct_number<=0;
            gallery_empty <= 1'b0;
            candidate_valid <= 1'b0;
            candidate_number <= 32'd0;
            candidate_cluster <= 28'd0;
            file_cluster <= 28'd0;
            file_sector <= 8'd0;
            pixel_count <= 20'd0;
            pixel_stream_complete <= 1'b0;
            bmp_row_byte <= 20'd0;
            ddr_row_base <= LAST_ROW;
            file_byte_base <= 32'd0;
            bmp_pixel_offset <= 32'd0;
            bmp_width <= 32'd0;
            bmp_height <= 32'd0;
            bmp_bpp <= 16'd0;
            bmp_compression <= 32'd0;
            bmp_magic_ok <= 1'b0;
            next_cluster <= 28'd0;
            fat_byte0 <= 8'd0; fat_byte1 <= 8'd0;
            fat_byte2 <= 8'd0; fat_byte3 <= 8'd0;
            fat_entry_byte <= 9'd0;
            n0<=0;n1<=0;n2<=0;n3<=0;n4<=0;n5<=0;n6<=0;n7<=0;n8<=0;n9<=0;n10<=0;
            entry_attr <= 0; entry_cluster_hi <= 0; entry_cluster_lo <= 0;
        end else begin
            load_start <= 1'b0;
            load_byte_valid <= 1'b0;
            load_done <= 1'b0;
            load_error <= 1'b0;
            gallery_empty <= 1'b0;
            sd_init_start <= 1'b0;
            block_start <= 1'b0;

            // Stream parser; no complete sector is retained in registers.
            if (block_rx_valid) begin
                if (state == R_MBR) begin
                    case(block_byte_index)
                        11:sector0_bps[7:0]<=block_rx_data;
                        12:sector0_bps[15:8]<=block_rx_data;
                        17:sector0_root_entries[7:0]<=block_rx_data;
                        18:sector0_root_entries[15:8]<=block_rx_data;
                        22:sector0_fat16[7:0]<=block_rx_data;
                        23:sector0_fat16[15:8]<=block_rx_data;
                    endcase
                    if (block_byte_index == 9'd454) volume_lba[7:0] <= block_rx_data;
                    if (block_byte_index == 9'd455) volume_lba[15:8] <= block_rx_data;
                    if (block_byte_index == 9'd456) volume_lba[23:16] <= block_rx_data;
                    if (block_byte_index == 9'd457) volume_lba[31:24] <= block_rx_data;
                end else if (state == R_BPB) begin
                    case (block_byte_index)
                        9'd11: bytes_per_sector[7:0] <= block_rx_data;
                        9'd12: bytes_per_sector[15:8] <= block_rx_data;
                        9'd13: sectors_per_cluster <= block_rx_data;
                        9'd14: reserved_sectors[7:0] <= block_rx_data;
                        9'd15: reserved_sectors[15:8] <= block_rx_data;
                        9'd16: fat_count <= block_rx_data;
                        9'd36: fat_sectors[7:0] <= block_rx_data;
                        9'd37: fat_sectors[15:8] <= block_rx_data;
                        9'd38: fat_sectors[23:16] <= block_rx_data;
                        9'd39: fat_sectors[31:24] <= block_rx_data;
                        9'd44: root_cluster[7:0] <= block_rx_data;
                        9'd45: root_cluster[15:8] <= block_rx_data;
                        9'd46: root_cluster[23:16] <= block_rx_data;
                        9'd47: root_cluster[27:24] <= block_rx_data[3:0];
                    endcase
                end else if (state == R_DIR) begin
                    case (block_byte_index[4:0])
                        5'd0:  n0  <= block_rx_data;
                        5'd1:  n1  <= block_rx_data;
                        5'd2:  n2  <= block_rx_data;
                        5'd3:  n3  <= block_rx_data;
                        5'd4:  n4  <= block_rx_data;
                        5'd5:  n5  <= block_rx_data;
                        5'd6:  n6  <= block_rx_data;
                        5'd7:  n7  <= block_rx_data;
                        5'd8:  n8  <= block_rx_data;
                        5'd9:  n9  <= block_rx_data;
                        5'd10: n10 <= block_rx_data;
                        5'd11: entry_attr <= block_rx_data;
                        5'd20: entry_cluster_hi[7:0] <= block_rx_data;
                        5'd21: entry_cluster_hi[15:8] <= block_rx_data;
                        5'd26: entry_cluster_lo[7:0] <= block_rx_data;
                        5'd27: entry_cluster_lo[15:8] <= block_rx_data;
                        5'd31: begin
                            if (n0 == 8'h00) dir_end_seen <= 1'b1;
                            if (!dir_end_seen && entry_name_ok && entry_normal_file && entry_cluster_wire>=2 &&
                                (delete_reload ? (entry_number_wire<current_file_number &&
                                  (!fallback_valid || entry_number_wire>fallback_number)) :
                                  (!fallback_valid || (scan_previous ? entry_number_wire>fallback_number : entry_number_wire<fallback_number)))) begin
                                fallback_valid<=1;fallback_number<=entry_number_wire;fallback_cluster<=entry_cluster_wire;
                            end
                            if (entry_name_ok && entry_normal_file &&
                                !dir_end_seen && entry_cluster_wire>=2 && candidate_matches_direction) begin
                                candidate_valid <= 1'b1;
                                candidate_number <= entry_number_wire;
                                candidate_cluster <= entry_cluster_wire;
                            end
                        end
                    endcase
                end else if (state == R_FILE) begin
                    case (file_byte_base + block_byte_index)
                        32'd0: bmp_magic_ok <= (block_rx_data == "B");
                        32'd1: bmp_magic_ok <= bmp_magic_ok && (block_rx_data == "M");
                        32'd10: bmp_pixel_offset[7:0] <= block_rx_data;
                        32'd11: bmp_pixel_offset[15:8] <= block_rx_data;
                        32'd12: bmp_pixel_offset[23:16] <= block_rx_data;
                        32'd13: bmp_pixel_offset[31:24] <= block_rx_data;
                        32'd18: bmp_width[7:0] <= block_rx_data;
                        32'd19: bmp_width[15:8] <= block_rx_data;
                        32'd20: bmp_width[23:16] <= block_rx_data;
                        32'd21: bmp_width[31:24] <= block_rx_data;
                        32'd22: bmp_height[7:0] <= block_rx_data;
                        32'd23: bmp_height[15:8] <= block_rx_data;
                        32'd24: bmp_height[23:16] <= block_rx_data;
                        32'd25: bmp_height[31:24] <= block_rx_data;
                        32'd28: bmp_bpp[7:0] <= block_rx_data;
                        32'd29: bmp_bpp[15:8] <= block_rx_data;
                        32'd30: bmp_compression[7:0] <= block_rx_data;
                        32'd31: bmp_compression[15:8] <= block_rx_data;
                        32'd32: bmp_compression[23:16] <= block_rx_data;
                        32'd33: bmp_compression[31:24] <= block_rx_data;
                        default: begin end
                    endcase
                    if ((file_byte_base + block_byte_index >= 32'd512) &&
                        (pixel_count < PHOTO_BYTES) && header_ok) begin
                        load_byte_valid <= 1'b1;
                        load_byte <= block_rx_data;
                        load_byte_offset <= ddr_row_base + bmp_row_byte;
                        pixel_count <= pixel_count + 1'b1;
						if (pixel_count == PHOTO_BYTES - 1'b1)
							pixel_stream_complete <= 1'b1;
                        if (bmp_row_byte == ROW_BYTES - 1'b1) begin
                            bmp_row_byte <= 20'd0;
                            ddr_row_base <= ddr_row_base - ROW_BYTES;
                        end else begin
                            bmp_row_byte <= bmp_row_byte + 1'b1;
                        end
                    end
                end else if ((state == R_FILE_FAT) || (state == R_DIR_FAT)) begin
                    if (block_byte_index == fat_entry_byte) fat_byte0 <= block_rx_data;
                    if (block_byte_index == fat_entry_byte + 1'b1) fat_byte1 <= block_rx_data;
                    if (block_byte_index == fat_entry_byte + 2'd2) fat_byte2 <= block_rx_data;
                    if (block_byte_index == fat_entry_byte + 2'd3) fat_byte3 <= block_rx_data;
                end
            end

            if (block_error) begin
                state <= R_FAIL;
            end else if (block_done) begin
                state <= after_block;
            end

            case (state)
                R_IDLE: begin
                    read_busy <= 1'b0;
                    if(OPEN_AVAILABLE&&open_file_req)begin
                        gallery_mode<=1;read_error<=0;read_busy<=1;delete_reload<=0;
                        direct_selection<=1;direct_number<=open_file_number;state<=R_INIT;
                    end else if (gallery_toggle_req) begin
                        gallery_mode <= ~gallery_mode;
                        read_error <= 1'b0;
                        if (!gallery_mode) begin
                            current_file_number<=0;
                            direct_selection<=0;
                            delete_reload<=0;
                            scan_previous <= 1'b0;
                            state <= R_INIT;
                            read_busy <= 1'b1;
                        end
                    end
                end
                R_INIT: begin
                    abort_pending<=0;
                    volume_lba<=0;sector0_bps<=0;sector0_root_entries<=0;sector0_fat16<=0;
                    sd_init_start <= 1'b1;
                    state <= R_INIT_WAIT;
                end
                R_INIT_WAIT: begin
                    if (sd_init_done) begin
						block_lba <= 32'd0;
                        block_write <= 1'b0;
                        block_start <= 1'b1;
                        after_block <= R_BPB;
                        state <= R_MBR;
					end else if (sd_init_error) begin
                        state <= R_FAIL;
                    end
                end
                R_MBR: begin
                    // MBR partition LBA has been captured while receiving.
                    // FAT32 superfloppy cards naturally retain LBA 0 here.
                    if (block_done) begin
                        // A FAT32 boot sector is not an MBR: bytes 454..457
                        // can be boot code rather than a partition address.
                        if(sector0_bps==512 && sector0_root_entries==0 && sector0_fat16==0)begin
                            volume_lba<=0;block_lba<=0;
                        end else block_lba <= volume_lba;
                        block_write <= 1'b0;
                        block_start <= 1'b1;
                        after_block <= R_PARSE_BPB;
                        state <= R_BPB;
                    end
                end
                R_BPB: begin end
                R_PARSE_BPB: begin
                    if (bytes_per_sector != 16'd512 ||
                        sectors_per_cluster == 8'd0 || fat_count == 8'd0 ||
                        fat_sectors == 32'd0 || root_cluster < 28'd2) begin
                        state <= R_FAIL;
                    end else begin
                        first_fat_lba <= volume_lba + reserved_sectors;
                        first_data_lba <= volume_lba + reserved_sectors +
                                          (fat_sectors * fat_count);
                        scan_cluster <= root_cluster;
                        scan_sector <= 8'd0;
                        candidate_valid <= 1'b0;
                        fallback_valid<=0;
                        dir_end_seen <= 1'b0;
                        state <= R_DIR;
                    end
                end
                R_DIR: begin
                    if (!block_busy && !block_start && !block_done) begin
                        block_lba <= first_data_lba +
                                     (({4'd0, scan_cluster} - 32'd2) * sectors_per_cluster) +
                                     scan_sector;
                        block_write <= 1'b0;
                        block_start <= 1'b1;
                        after_block <= R_DIR;
                    end
                    if (block_done) begin
                        if (dir_end_seen) begin
                            state <= R_PICK;
						end else if (scan_sector + 1'b1 >= sectors_per_cluster) begin
							// The root directory can span a FAT chain.  Follow it
							// lazily, rather than creating an in-BRAM directory index.
							block_lba <= first_fat_lba + ({4'd0, scan_cluster} >> 7);
							block_write <= 1'b0;
							block_start <= 1'b1;
							fat_entry_byte <= {scan_cluster[6:0], 2'b00};
							after_block <= R_DIR_FAT;
							state <= R_DIR_FAT;
                        end else begin
                            scan_sector <= scan_sector + 1'b1;
                        end
                    end
                end
                R_PICK: begin
                    if(direct_selection&&!candidate_valid)begin state<=R_FAIL;end
                    else if (!candidate_valid && !fallback_valid) begin
                        if(ENABLE_DELETE)begin gallery_empty<=1;gallery_mode<=0;current_file_number<=0;read_busy<=0;state<=R_IDLE;end
                        else state <= R_FAIL;
                    end else begin
                        current_file_number <= candidate_valid?candidate_number:fallback_number;
                        file_cluster <= candidate_valid?candidate_cluster:fallback_cluster;
                        file_sector <= 8'd0;
                        file_byte_base <= 32'd0;
                        pixel_count <= 20'd0;
						pixel_stream_complete <= 1'b0;
                        bmp_row_byte <= 20'd0;
                        ddr_row_base <= LAST_ROW;
                        bmp_pixel_offset <= 32'd0;
                        bmp_width <= 32'd0;
                        bmp_height <= 32'd0;
                        bmp_bpp <= 16'd0;
                        bmp_compression <= 32'd0;
                        bmp_magic_ok <= 1'b0;
                        load_start <= 1'b1;
                        state <= R_FILE;
                    end
                end
                R_FILE: begin
                    if (!block_busy && !block_start && !block_done) begin
                        block_lba <= first_data_lba +
                                     (({4'd0, file_cluster} - 32'd2) * sectors_per_cluster) +
                                     file_sector;
                        block_write <= 1'b0;
                        block_start <= 1'b1;
                        after_block <= R_FILE;
                    end
                    if (block_done) begin
                        file_byte_base <= file_byte_base + 32'd512;
                        if(file_byte_base==0 && !header_ok)begin
                            state<=R_FAIL;
                        end else if (pixel_stream_complete || (pixel_count >= PHOTO_BYTES)) begin
                            load_done <= 1'b1;
                            read_busy <= 1'b0;
                            state <= R_DONE;
                        end else if (file_sector + 1'b1 < sectors_per_cluster) begin
                            file_sector <= file_sector + 1'b1;
                        end else begin
                            block_lba <= fat_lba_wire;
                            block_write <= 1'b0;
                            block_start <= 1'b1;
                            fat_entry_byte <= fat_byte_wire;
                            after_block <= R_FILE_FAT;
                            state <= R_FILE_FAT;
                        end
                    end
                end
                R_FILE_FAT: begin
                    if (block_done) begin
                        next_cluster <= {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
                        if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} >= FAT32_EOC || {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0}<2) begin
                            state <= R_FAIL;
                        end else begin
                            file_cluster <= {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
                            file_sector <= 8'd0;
                            state <= R_FILE;
                        end
                    end
                end
				R_DIR_FAT: begin
					if (block_done) begin
						if ({fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0} >= FAT32_EOC) begin
							state <= R_PICK;
						end else begin
							scan_cluster <= {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
							scan_sector <= 8'd0;
							state <= R_DIR;
						end
					end
				end
                R_DONE: begin
                    read_busy<=0;
                    if(OPEN_AVAILABLE&&open_file_req)begin
                        gallery_mode<=1;read_error<=0;read_busy<=1;delete_reload<=0;
                        direct_selection<=1;direct_number<=open_file_number;state<=R_INIT;
                    end else if (ENABLE_DELETE && reload_after_delete && gallery_mode) begin
                        direct_selection<=0;
                        delete_reload<=1;scan_previous<=0;read_error<=0;read_busy<=1;state<=R_INIT;
                    end else if (gallery_toggle_req) begin
                        gallery_mode <= 1'b0;
                        state <= R_IDLE;
                    end else if (gallery_prev_req || gallery_next_req) begin
                        direct_selection<=0;
                        delete_reload<=0;
                        read_error<=0;
                        scan_previous <= gallery_prev_req;
                        state <= R_INIT;
                        read_busy <= 1'b1;
                    end
                end
                R_FAIL: begin
                    read_busy <= 1'b0;
                    read_error <= 1'b1;
                    load_error <= 1'b1;
                    state <= R_DONE;
                    if (gallery_toggle_req) begin
                        gallery_mode <= 1'b0;
                        state <= R_IDLE;
                    end else if (gallery_prev_req || gallery_next_req) begin
                        direct_selection<=0;
                        scan_previous <= gallery_prev_req;
                        read_error <= 1'b0;
                        state <= R_INIT;
                        read_busy <= 1'b1;
                    end
                end
                default: state <= R_IDLE;
            endcase
            // Bus errors have priority over the state's normal completion.
            if(block_error && read_busy)begin block_start<=0;state<=R_FAIL;end
            if(load_abort && read_busy)abort_pending<=1;
            if(abort_pending)begin
                block_start<=0;load_byte_valid<=0;
                if(!block_busy && !sd_init_busy && !sd_init_start && !block_start)begin
                    abort_pending<=0;state<=R_FAIL;
                end
            end
        end
    end
endmodule
