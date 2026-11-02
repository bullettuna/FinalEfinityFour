`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Serialize a FAT32 photo writer and reader onto one SD block host.
//
// A transaction owner is latched from its start pulse and remains fixed until
// the block completes.  This prevents a newly asserted save request from
// redirecting the response bytes of a partially completed gallery read.  Save
// wins every idle arbitration point; a read can never start while save_active
// is high.  The block byte stream is forwarded only to its latched owner, so a
// single sector buffer can be shared by the two FAT engines.
//////////////////////////////////////////////////////////////////////////////////
module sd_storage_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    // Save client: priority client.
    input  wire        save_active,
    input  wire        save_init_start,
    output wire        save_init_busy,
    output wire        save_init_done,
    output wire        save_init_error,
    input  wire        save_block_start,
    input  wire        save_block_write,
    input  wire [31:0] save_block_lba,
    input  wire [7:0]  save_block_tx_byte,
    output wire        save_block_busy,
    output wire        save_block_done,
    output wire        save_block_error,
    output wire        save_block_rx_valid,
    output wire [7:0]  save_block_rx_data,
    output wire [8:0]  save_block_byte_index,

    // Gallery reader: admitted only while the save side is idle.
    input  wire        read_active,
    input  wire        read_init_start,
    output wire        read_init_busy,
    output wire        read_init_done,
    output wire        read_init_error,
    input  wire        read_block_start,
    input  wire        read_block_write,
    input  wire [31:0] read_block_lba,
    input  wire [7:0]  read_block_tx_byte,
    output wire        read_block_busy,
    output wire        read_block_done,
    output wire        read_block_error,
    output wire        read_block_rx_valid,
    output wire [7:0]  read_block_rx_data,
    output wire [8:0]  read_block_byte_index,

    // Shared physical host.
    output wire        host_init_start,
    input  wire        host_init_busy,
    input  wire        host_init_done,
    input  wire        host_init_error,
    output wire        host_block_start,
    output wire        host_block_write,
    output wire [31:0] host_block_lba,
    output wire [7:0]  host_block_tx_byte,
    input  wire        host_block_busy,
    input  wire        host_block_done,
    input  wire        host_block_error,
    input  wire        host_block_rx_valid,
    input  wire [7:0]  host_block_rx_data,
    input  wire [8:0]  host_block_byte_index
);

    localparam OWNER_SAVE = 1'b0;
    localparam OWNER_READ = 1'b1;

    reg block_owner_valid;
    reg block_owner;
    reg init_owner_valid;
    reg init_owner;
    reg save_init_pending;
    reg read_init_pending;

    // Start pulses from the FAT engines must not be lost when the other side
    // is finishing a sector.  Latch exactly one pending request per client;
    // the save queue is always selected first once the physical host is idle.
    reg save_pending, read_pending;
    reg save_pending_write, read_pending_write;
    reg [31:0] save_pending_lba, read_pending_lba;
    reg [7:0] save_pending_tx, read_pending_tx;

    // A save already in progress reserves the card before its next block
    // request arrives.  If a read block is currently active it is allowed to
    // finish, but no further read block can start.
    wire select_save_idle = save_pending;
    wire select_read_idle = !select_save_idle && read_pending;
    wire selected_owner = block_owner_valid ? block_owner :
                          (select_save_idle ? OWNER_SAVE : OWNER_READ);

    wire selected_start = !block_owner_valid && !host_block_busy &&
                          (select_save_idle || select_read_idle);

    assign host_block_start   = selected_start;
    assign host_block_write   = (selected_owner == OWNER_SAVE) ?
                                save_pending_write : read_pending_write;
    assign host_block_lba     = (selected_owner == OWNER_SAVE) ?
                                save_pending_lba : read_pending_lba;
    // TX bytes are indexed by the currently running SD block transfer and
    // therefore remain live; only the start metadata is queued.
    assign host_block_tx_byte = (selected_owner == OWNER_SAVE) ?
                                save_block_tx_byte : read_block_tx_byte;

    assign save_block_busy       = host_block_busy && block_owner_valid &&
                                   (block_owner == OWNER_SAVE);
    assign save_block_done       = host_block_done && block_owner_valid &&
                                   (block_owner == OWNER_SAVE);
    assign save_block_error      = host_block_error && block_owner_valid &&
                                   (block_owner == OWNER_SAVE);
    assign save_block_rx_valid   = host_block_rx_valid && block_owner_valid &&
                                   (block_owner == OWNER_SAVE);
    assign save_block_rx_data    = host_block_rx_data;
    assign save_block_byte_index = host_block_byte_index;

    assign read_block_busy       = host_block_busy && block_owner_valid &&
                                   (block_owner == OWNER_READ);
    assign read_block_done       = host_block_done && block_owner_valid &&
                                   (block_owner == OWNER_READ);
    assign read_block_error      = host_block_error && block_owner_valid &&
                                   (block_owner == OWNER_READ);
    assign read_block_rx_valid   = host_block_rx_valid && block_owner_valid &&
                                   (block_owner == OWNER_READ);
    assign read_block_rx_data    = host_block_rx_data;
    assign read_block_byte_index = host_block_byte_index;

    // Initialization is also serialized.  The writer has the same priority
    // rule as data blocks, and the done/error indication returns only to the
    // client that actually issued the successful start pulse.
    // Init requests are pulses too.  Queue them exactly like data requests so
    // an "i" probe or gallery request cannot disappear while a previous save
    // is completing its FAT update.
    wire select_save_init = save_init_pending;
    wire select_read_init = !select_save_init && !save_active && read_init_pending;
    wire init_selected_owner = init_owner_valid ? init_owner :
                              (select_save_init ? OWNER_SAVE : OWNER_READ);
    // sd_spi_host advertises init_busy while it waits in reset for its first
    // start pulse, so do not use host_init_busy as an admission condition.
    assign host_init_start = !init_owner_valid &&
                             (select_save_init || select_read_init);
    assign save_init_busy  = host_init_busy && init_owner_valid &&
                             (init_owner == OWNER_SAVE);
    assign save_init_done  = host_init_done && init_owner_valid &&
                             (init_owner == OWNER_SAVE);
    assign save_init_error = host_init_error && init_owner_valid &&
                             (init_owner == OWNER_SAVE);
    assign read_init_busy  = host_init_busy && init_owner_valid &&
                             (init_owner == OWNER_READ);
    assign read_init_done  = host_init_done && init_owner_valid &&
                             (init_owner == OWNER_READ);
    assign read_init_error = host_init_error && init_owner_valid &&
                             (init_owner == OWNER_READ);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            block_owner_valid <= 1'b0;
            block_owner       <= OWNER_SAVE;
            init_owner_valid  <= 1'b0;
            init_owner        <= OWNER_SAVE;
			save_init_pending <= 1'b0;
			read_init_pending <= 1'b0;
			save_pending <= 1'b0;
			read_pending <= 1'b0;
			save_pending_write <= 1'b0;
			read_pending_write <= 1'b0;
			save_pending_lba <= 32'd0;
			read_pending_lba <= 32'd0;
			save_pending_tx <= 8'hff;
			read_pending_tx <= 8'hff;
        end else begin
			if (save_init_start && !save_init_pending)
				save_init_pending <= 1'b1;
			if (read_init_start && !read_init_pending)
				read_init_pending <= 1'b1;
			if (save_block_start && !save_pending) begin
				save_pending <= 1'b1;
				save_pending_write <= save_block_write;
				save_pending_lba <= save_block_lba;
				save_pending_tx <= save_block_tx_byte;
			end
			if (read_block_start && !read_pending) begin
				read_pending <= 1'b1;
				read_pending_write <= read_block_write;
				read_pending_lba <= read_block_lba;
				read_pending_tx <= read_block_tx_byte;
			end
            if (!block_owner_valid && selected_start) begin
                block_owner_valid <= 1'b1;
                block_owner       <= selected_owner;
				if (selected_owner == OWNER_SAVE)
					save_pending <= 1'b0;
				else
					read_pending <= 1'b0;
            end else if (block_owner_valid &&
                         (host_block_done || host_block_error)) begin
                block_owner_valid <= 1'b0;
            end

            if (!init_owner_valid && host_init_start) begin
                init_owner_valid <= 1'b1;
                init_owner       <= init_selected_owner;
				if (init_selected_owner == OWNER_SAVE)
					save_init_pending <= 1'b0;
				else
					read_init_pending <= 1'b0;
            end else if (init_owner_valid && (host_init_done || host_init_error)) begin
                init_owner_valid <= 1'b0;
            end
        end
    end

endmodule
