`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Small SPI-mode TF-card host.  A TF card uses the SD SPI protocol, hence the
// SD command names and sd_* pins retained by this RTL interface.
//
// The controller deliberately exposes a block-oriented interface.  FAT and
// file-system policy live above this module so the SPI engine stays independent
// from the particular card format.  Only DAT[0] (MISO) and DAT[3] (CS) are
// driven; DAT[1:2] remain high-Z.
//////////////////////////////////////////////////////////////////////////////////
module sd_spi_host #(
    parameter integer CLK_HZ       = 96000000,
    // The byte engine changes SCK on every half_tick, so the actual SPI
    // frequency is CLK_HZ / (2 * DIV).  Keep initialization within the SD
    // SPI-mode 400 kHz limit and use 6 MHz only after OCR says ready.
    parameter integer INIT_DIV     = 120, // 96 MHz / (2 * 120) = 400 kHz
    parameter integer FAST_DIV     = 8,   // 96 MHz / (2 * 8)   =   6 MHz
    // response_timeout is 16 bits.  Do not use 65536 here: it truncates to
    // zero and makes the very first 0xff response look like a timeout.
    // 8192 byte-times is about 164 ms at the 400 kHz init clock.
    parameter integer RESP_TIMEOUT = 8192
) (
    input  wire        clk,
    input  wire        rst_n,

    output reg         sd_clk,
    output reg         sd_cmd_o,
    output reg         sd_cmd_oe,
    input  wire        sd_cmd_i,
    input  wire [3:0]  sd_dat_i,
    output reg  [3:0]  sd_dat_o,
    output reg  [3:0]  sd_dat_oe,

    input  wire        init_start,
    output reg         init_busy,
    output reg         init_done,
    output reg         init_error,
    output reg         high_capacity,

    input  wire        block_start,
    input  wire        block_write,
    input  wire [31:0] block_lba,
    output reg         block_busy,
    output reg         block_done,
    output reg         block_error,

    output reg         block_rx_valid,
    output reg  [7:0]  block_rx_data,

    output reg  [8:0]  block_byte_index,
    input  wire [7:0]  block_tx_byte
);

    localparam [3:0] B_IDLE = 4'd0;
    localparam [3:0] B_SETUP = 4'd1;
    localparam [3:0] B_RISE = 4'd2;
    localparam [3:0] B_FALL = 4'd3;
    localparam [3:0] B_DONE = 4'd4;

    localparam [6:0] H_RESET = 7'd0;
    localparam [6:0] H_CMD_SEND = 7'd1;
    localparam [6:0] H_RESP_WAIT = 7'd2;
    localparam [6:0] H_RESP_CMD0 = 7'd3;
    localparam [6:0] H_RESP_CMD8 = 7'd4;
    localparam [6:0] H_R7 = 7'd5;
    localparam [6:0] H_RESP_CMD55 = 7'd6;
    localparam [6:0] H_RESP_CMD41 = 7'd7;
    localparam [6:0] H_RESP_CMD58 = 7'd8;
    localparam [6:0] H_OCR = 7'd9;
    localparam [6:0] H_READY = 7'd10;
    localparam [6:0] H_RESP_CMD17 = 7'd11;
    localparam [6:0] H_RESP_CMD24 = 7'd12;
    localparam [6:0] H_READ_TOKEN = 7'd13;
    localparam [6:0] H_READ_DATA = 7'd14;
    localparam [6:0] H_READ_CRC = 7'd15;
    localparam [6:0] H_WRITE_GAP = 7'd16;
    localparam [6:0] H_WRITE_TOKEN = 7'd17;
    localparam [6:0] H_WRITE_DATA = 7'd18;
    localparam [6:0] H_WRITE_CRC = 7'd19;
    localparam [6:0] H_WRITE_RESP = 7'd20;
    localparam [6:0] H_WRITE_BUSY = 7'd21;
    localparam [6:0] H_BLOCK_DONE = 7'd22;
    localparam [6:0] H_ERROR = 7'd23;
    localparam [6:0] H_RESET_CLOCKS = 7'd24;
    localparam [6:0] H_RESP_CMD16 = 7'd25;

    reg [7:0]  div_setting;
    reg [15:0] div_count;
    reg        half_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_count <= 16'd0;
            half_tick <= 1'b0;
        end else begin
            if (div_count >= div_setting - 1'b1) begin
                div_count <= 16'd0;
                half_tick <= 1'b1;
            end else begin
                div_count <= div_count + 1'b1;
                half_tick <= 1'b0;
            end
        end
    end

    reg [3:0] byte_state;
    reg [2:0] byte_bit;
    reg [7:0] byte_tx;
    reg [7:0] byte_tx_data;
    reg [7:0] byte_rx;
    reg       byte_start;
    reg       byte_busy;
    reg       byte_done;
    reg       sd_clk_idle_high;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_state <= B_IDLE;
            byte_bit   <= 3'd7;
            byte_tx    <= 8'hff;
            byte_rx    <= 8'hff;
            byte_busy  <= 1'b0;
            byte_done  <= 1'b0;
            sd_clk     <= 1'b0;
            sd_cmd_o   <= 1'b1;
            sd_cmd_oe  <= 1'b1;
        end else begin
            byte_done <= 1'b0;
            case (byte_state)
                B_IDLE: begin
                    sd_clk <= 1'b0;
                    sd_cmd_o <= 1'b1;
                    byte_busy <= 1'b0;
                    if (byte_start) begin
                        byte_tx   <= byte_tx_data;
                        byte_rx   <= 8'h00;
                        byte_bit  <= 3'd7;
                        byte_busy <= 1'b1;
                        byte_state <= B_SETUP;
                    end
                end
                B_SETUP: begin
                    // SPI sends bytes MSB first.  byte_bit starts at 7 and
                    // decrements after each SCK rising edge; selecting the
                    // current bit here is therefore essential.  Driving
                    // byte_tx[7] on every cycle corrupts CMD0/CMD8 and all
                    // subsequent TF-card commands.
                    sd_cmd_o <= byte_tx[byte_bit];
                    sd_clk   <= 1'b0;
                    if (half_tick)
                        byte_state <= B_RISE;
                end
                B_RISE: begin
                    sd_clk <= 1'b1;
                    if (half_tick) begin
                        byte_rx[byte_bit] <= sd_dat_i[0];
                        byte_state <= B_FALL;
                    end
                end
                B_FALL: begin
                    sd_clk <= 1'b0;
                    if (half_tick) begin
                        if (byte_bit == 3'd0)
                            byte_state <= B_DONE;
                        else begin
                            byte_bit <= byte_bit - 1'b1;
                            byte_state <= B_SETUP;
                        end
                    end
                end
                B_DONE: begin
                    byte_done <= 1'b1;
                    byte_busy <= 1'b0;
                    byte_state <= B_IDLE;
                end
                default: byte_state <= B_IDLE;
            endcase
        end
    end

    function [6:0] crc7_cmd;
        input [39:0] data;
        integer i;
        reg [6:0] c;
        begin
            c = 7'd0;
            for (i = 39; i >= 0; i = i - 1)
                c = c[6] ^ data[i] ? ((c << 1) ^ 7'h09) : (c << 1);
            crc7_cmd = c;
        end
    endfunction

    reg [6:0]  host_state;
    reg [6:0]  host_after_send;
    reg [6:0]  host_after_resp;
    reg [5:0]  command_index;
    reg [31:0] command_argument;
    reg [39:0] command_word;
    reg [2:0]  command_byte_count;
    reg [15:0] response_timeout;
    reg [7:0]  response_r1;
    reg [31:0] r7_value;
    reg [31:0] ocr_value;
    reg [1:0]  r7_byte_count;
    reg [1:0]  ocr_byte_count;
    reg [7:0]  reset_byte_count;

    // At 400 kHz, a card can legally need far longer than 255 ACMD41
    // attempts after power-up.  4096 attempts provides a practical startup
    // window without an unbounded state-machine wait.
    reg [11:0] acmd41_retry;
    reg [2:0]  cmd0_retry;
    reg        card_v2;
    reg [1:0]  crc_byte_count;
    reg [8:0]  data_byte_count;
    reg [3:0]  write_wait_count;
    reg [19:0] write_busy_count;
    reg [3:0]  write_prepare_count;
    reg [7:0]  write_status;

    reg        block_write_latched;
    reg [31:0] block_lba_latched;

    wire [39:0] command_base = {2'b01, command_index, command_argument};
    wire [39:0] command_frame = {
        command_base[39:8],
        crc7_cmd(command_base),
        // SD SPI command packets end with a mandatory logic-1 stop bit.
        // A zero here makes the standalone I-reader work while the legacy
        // FAT32 save path fails during CMD0/CMD8 initialization.
        1'b1
    };
    wire [31:0] command_lba_arg = high_capacity ?
        block_lba_latched : {block_lba_latched[22:0], 9'b0};
    wire [31:0] next_ocr_value = {ocr_value[23:0], byte_rx};
    wire [31:0] next_r7_value  = {r7_value[23:0], byte_rx};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_state <= H_RESET;
            host_after_send <= H_RESET;
            host_after_resp <= H_RESET;
            command_index <= 6'd0;
            command_argument <= 32'd0;
            command_word <= 40'd0;
            command_byte_count <= 3'd0;
            response_timeout <= 16'd0;
            response_r1 <= 8'hff;
            r7_value <= 32'd0;
            ocr_value <= 32'd0;
            r7_byte_count <= 2'd0;
            ocr_byte_count <= 2'd0;
            reset_byte_count <= 8'd0;
            acmd41_retry <= 12'd0;
            cmd0_retry <= 3'd0;
            card_v2 <= 1'b0;
            crc_byte_count <= 2'd0;
            data_byte_count <= 9'd0;
            write_wait_count <= 4'd0;
            write_busy_count <= 20'd0;
            write_prepare_count <= 4'd0;

            byte_start <= 1'b0;
            init_busy <= 1'b0;
            init_done <= 1'b0;
            init_error <= 1'b0;
            high_capacity <= 1'b0;
            block_busy <= 1'b0;
            block_done <= 1'b0;
            block_error <= 1'b0;
            block_rx_valid <= 1'b0;
            block_rx_data <= 8'h00;
            block_byte_index <= 9'd0;
            block_write_latched <= 1'b0;
            block_lba_latched <= 32'd0;
            div_setting <= INIT_DIV[7:0];
            byte_tx_data <= 8'hff;
            sd_dat_o <= 4'b0000;
            sd_dat_oe <= 4'b0000;
        end else begin
            byte_start <= 1'b0;
            block_done <= 1'b0;
            block_error <= 1'b0;
            block_rx_valid <= 1'b0;

            // DAT3 is SPI chip-select.  Drive it actively so operation does
            // not depend on an external card-socket pull-up.  DAT0 is input-
            // only; DAT1/DAT2 remain released in SPI mode.
            sd_dat_o[3] <= sd_clk_idle_high;
            sd_dat_oe[3] <= 1'b1;
            sd_dat_o[2:0] <= 3'b000;
            sd_dat_oe[2:0] <= 3'b000;

            case (host_state)
                H_RESET: begin
                    init_busy <= 1'b1;
                    init_done <= 1'b0;
                    init_error <= 1'b0;
                    div_setting <= INIT_DIV[7:0];
                    if (init_start) begin
                        reset_byte_count <= 8'd16;
                        host_state <= H_RESET_CLOCKS;
                        command_index <= 6'd0;
                        command_argument <= 32'd0;
                        command_byte_count <= 3'd0;
                        host_after_send <= H_RESP_CMD0;
                        acmd41_retry <= 12'd0;
                        cmd0_retry <= 3'd0;
                        card_v2 <= 1'b0;
                        high_capacity <= 1'b0;
                        r7_value <= 32'd0;
                        ocr_value <= 32'd0;
                    end
                end

                H_RESET_CLOCKS: begin
                    if (!byte_busy && !byte_done) begin
                        if (reset_byte_count != 8'd0) begin
                            byte_tx_data <= 8'hff;
                            byte_start <= 1'b1;
                            reset_byte_count <= reset_byte_count - 1'b1;
                        end else begin
                            host_state <= H_CMD_SEND;
                        end
                    end
                end

                H_CMD_SEND: begin
                    if (command_byte_count == 3'd0) begin
                        command_word <= {
                            command_base[39:8],
                            crc7_cmd(command_base),
                            1'b1
                        };
                        byte_tx_data <= command_frame[39:32];
                    end else begin
                        byte_tx_data <= command_word[39:32];
                    end
                    if (!byte_busy && !byte_done) begin
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        if (command_byte_count == 3'd5) begin
                            command_byte_count <= 3'd0;
                            response_timeout <= 16'd0;
                            // Every SD/TF command is followed by an R1
                            // response.  The old implementation jumped
                            // directly to the response-decoding state, so
                            // response_r1 stayed at its reset value (8'hff)
                            // and CMD0 could never succeed.
                            host_after_resp <= host_after_send;
                            host_state <= H_RESP_WAIT;
                        end else begin
                            command_byte_count <= command_byte_count + 1'b1;
                            command_word <= {command_word[31:0], 8'hff};
                        end
                    end
                end

                H_RESP_WAIT: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        response_timeout <= response_timeout + 1'b1;
                        response_r1 <= byte_rx;
                        if (byte_rx[7] == 1'b0) begin
                            response_timeout <= 16'd0;
                            host_state <= host_after_resp;
                        end else if (response_timeout == RESP_TIMEOUT[15:0]) begin
                            host_state <= H_ERROR;
                        end
                    end
                end

                H_RESP_CMD0: begin
                    if (response_r1 == 8'h01) begin
                        command_index <= 6'd8;
                        command_argument <= 32'h000001aa;
                        host_after_send <= H_RESP_CMD8;
                        host_state <= H_CMD_SEND;
                    end else if (cmd0_retry != 3'd7) begin
                        // A card may still be leaving power-up reset.  Retry
                        // CMD0 a bounded number of times before declaring it
                        // absent, rather than accepting an arbitrary R1.
                        cmd0_retry <= cmd0_retry + 1'b1;
                        command_index <= 6'd0;
                        command_argument <= 32'd0;
                        host_after_send <= H_RESP_CMD0;
                        host_state <= H_CMD_SEND;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_RESP_CMD8: begin
                    if (response_r1 == 8'h01) begin
                        card_v2 <= 1'b1;
                        r7_value <= 32'd0;
                        r7_byte_count <= 2'd0;
                        host_state <= H_R7;
                    end else if (response_r1[2]) begin
                        // In SPI mode SDv1 responds to CMD8 with the illegal
                        // command bit (normally R1=0x05).  Do not mistake a
                        // timeout or another error for a legacy card.
                        card_v2 <= 1'b0;
                        high_capacity <= 1'b0;
                        command_index <= 6'd55;
                        command_argument <= 32'd0;
                        host_after_send <= H_RESP_CMD55;
                        host_state <= H_CMD_SEND;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_R7: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        r7_value <= {r7_value[23:0], byte_rx};
                        if (r7_byte_count == 2'd3) begin
                            // CMD8 R7 must echo the requested 3.3 V range and
                            // check pattern (0x1AA).  Without this check a
                            // floating MISO line can be misidentified as a card.
                            if ((next_r7_value[11:8] == 4'h1) &&
                                (next_r7_value[7:0] == 8'haa)) begin
                                command_index <= 6'd55;
                                command_argument <= 32'd0;
                                host_after_send <= H_RESP_CMD55;
                                host_state <= H_CMD_SEND;
                            end else begin
                                host_state <= H_ERROR;
                            end
                        end else begin
                            r7_byte_count <= r7_byte_count + 1'b1;
                        end
                    end
                end

                H_RESP_CMD55: begin
                    if ((response_r1 == 8'h01) || (response_r1 == 8'h00)) begin
                        command_index <= 6'd41;
                        command_argument <= card_v2 ? 32'h40000000 : 32'd0;
                        host_after_send <= H_RESP_CMD41;
                        host_state <= H_CMD_SEND;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_RESP_CMD41: begin
                    if (response_r1 == 8'h00) begin
                        command_index <= 6'd58;
                        command_argument <= 32'd0;
                        host_after_send <= H_RESP_CMD58;
                        host_state <= H_CMD_SEND;
                    end else if (response_r1 == 8'h01) begin
                        if (acmd41_retry == 12'hfff) begin
                            host_state <= H_ERROR;
                        end else begin
                            acmd41_retry <= acmd41_retry + 1'b1;
                            command_index <= 6'd55;
                            command_argument <= 32'd0;
                            host_after_send <= H_RESP_CMD55;
                            host_state <= H_CMD_SEND;
                        end
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_RESP_CMD58: begin
                    if (response_r1 == 8'h00) begin
                        ocr_value <= 32'd0;
                        ocr_byte_count <= 2'd0;
                        host_state <= H_OCR;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_OCR: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        ocr_value <= {ocr_value[23:0], byte_rx};
                        if (ocr_byte_count == 2'd3) begin
                            // OCR[31] is the power-up-status bit.  Never
                            // accept a card that still reports itself busy.
                            if (!next_ocr_value[31]) begin
                                host_state <= H_ERROR;
                            end else if (card_v2 && next_ocr_value[30]) begin
                                high_capacity <= 1'b1;
                                div_setting <= FAST_DIV[7:0];
                                init_busy <= 1'b0;
                                init_done <= 1'b1;
                                host_state <= H_READY;
                            end else begin
                                // SDSC cards use byte addresses.  Explicitly
                                // select the 512-byte block length required by
                                // the FAT32 sector engine before reporting
                                // initialization complete.
                                high_capacity <= 1'b0;
                                command_index <= 6'd16;
                                command_argument <= 32'd512;
                                host_after_send <= H_RESP_CMD16;
                                host_state <= H_CMD_SEND;
                            end
                        end else begin
                            ocr_byte_count <= ocr_byte_count + 1'b1;
                        end
                    end
                end

                H_RESP_CMD16: begin
                    if (response_r1 == 8'h00) begin
                        div_setting <= FAST_DIV[7:0];
                        init_busy <= 1'b0;
                        init_done <= 1'b1;
                        host_state <= H_READY;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_READY: begin
                    init_busy <= 1'b0;
                    if (init_start) begin
                        init_busy <= 1'b1;
                        init_done <= 1'b0;
                        init_error <= 1'b0;
                        div_setting <= INIT_DIV[7:0];
                        reset_byte_count <= 8'd16;
                        command_index <= 6'd0;
                        command_argument <= 32'd0;
                        command_byte_count <= 3'd0;
                        host_after_send <= H_RESP_CMD0;
                        acmd41_retry <= 12'd0;
                        cmd0_retry <= 3'd0;
                        card_v2 <= 1'b0;
                        high_capacity <= 1'b0;
                        r7_value <= 32'd0;
                        ocr_value <= 32'd0;
                        host_state <= H_RESET_CLOCKS;
                    end else if (block_start) begin
                        block_write_latched <= block_write;
                        block_lba_latched <= block_lba;
                        block_busy <= 1'b1;
                        data_byte_count <= 9'd0;
                        crc_byte_count <= 2'd0;
                        if (block_write) begin
                            command_index <= 6'd24;
                            command_argument <= high_capacity ?
                                block_lba : {block_lba[22:0], 9'b0};
                            host_after_send <= H_RESP_CMD24;
                        end else begin
                            command_index <= 6'd17;
                            command_argument <= high_capacity ?
                                block_lba : {block_lba[22:0], 9'b0};
                            host_after_send <= H_RESP_CMD17;
                        end
                        host_state <= H_CMD_SEND;
                    end
                end

                H_RESP_CMD17: begin
                    if (response_r1 == 8'h00) begin
                        response_timeout <= 16'd0;
                        host_state <= H_READ_TOKEN;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_RESP_CMD24: begin
                    if (response_r1 == 8'h00) begin
                        host_state <= H_WRITE_GAP;
                    end else begin
                        host_state <= H_ERROR;
                    end
                end

                H_READ_TOKEN: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        response_timeout <= response_timeout + 1'b1;
                        if (byte_rx == 8'hfe) begin
                            data_byte_count <= 9'd0;
                            host_state <= H_READ_DATA;
                        end else if (byte_rx != 8'hff) begin
                            host_state <= H_ERROR;
                        end else if (response_timeout == RESP_TIMEOUT[15:0]) begin
                            host_state <= H_ERROR;
                        end
                    end
                end

                H_READ_DATA: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        block_rx_valid <= 1'b1;
                        block_rx_data <= byte_rx;
                        if (data_byte_count == 9'd511) begin
                            crc_byte_count <= 2'd0;
                            host_state <= H_READ_CRC;
                        end else begin
                            data_byte_count <= data_byte_count + 1'b1;
                        end
                    end
                end

                H_READ_CRC: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        if (crc_byte_count == 2'd1) begin
                            host_state <= H_BLOCK_DONE;
                        end else begin
                            crc_byte_count <= crc_byte_count + 1'b1;
                        end
                    end
                end

                H_WRITE_GAP: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        host_state <= H_WRITE_TOKEN;
                    end
                end

                H_WRITE_TOKEN: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hfe;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        data_byte_count <= 9'd0;
                        block_byte_index <= 9'd0;
                        write_prepare_count <= 4'd0;
                        host_state <= H_WRITE_DATA;
                    end
                end

                H_WRITE_DATA: begin
                    // sector_ram has a registered read port.  Hold the index
                    // stable for several system clocks before launching SPI.
                    if (!byte_busy && !byte_done) begin
                        block_byte_index <= data_byte_count;
                        if (write_prepare_count != 4'd4) begin
                            write_prepare_count <= write_prepare_count + 1'b1;
                        end else begin
                            byte_tx_data <= block_tx_byte;
                            byte_start <= 1'b1;
                        end
                    end else if (byte_done) begin
                        write_prepare_count <= 4'd0;
                        if (data_byte_count == 9'd511) begin
                            crc_byte_count <= 2'd0;
                            host_state <= H_WRITE_CRC;
                        end else begin
                            data_byte_count <= data_byte_count + 1'b1;
                        end
                    end
                end

                H_WRITE_CRC: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        if (crc_byte_count == 2'd1) begin
                            host_state <= H_WRITE_RESP;
                        end else begin
                            crc_byte_count <= crc_byte_count + 1'b1;
                        end
                    end
                end

                H_WRITE_RESP: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done) begin
                        write_status <= byte_rx;
                        if (byte_rx[4:0] == 5'b00101) begin
                            write_wait_count <= 4'd0;
                            write_busy_count <= 20'd0;
                            host_state <= H_WRITE_BUSY;
                        end else begin
                            host_state <= H_ERROR;
                        end
                    end
                end

                H_WRITE_BUSY: begin
                    if (!byte_busy && !byte_done) begin
                        byte_tx_data <= 8'hff;
                        byte_start <= 1'b1;
                    end else if (byte_done && byte_rx == 8'hff) begin
                        host_state <= H_BLOCK_DONE;
                    end else if (byte_done && write_busy_count == 20'hfffff) begin
                        host_state <= H_ERROR;
                    end else if (byte_done) begin
                        write_busy_count <= write_busy_count + 1'b1;
                    end
                end

                H_BLOCK_DONE: begin
                    block_busy <= 1'b0;
                    block_done <= 1'b1;
                    host_state <= H_READY;
                end

                H_ERROR: begin
                    if (init_busy) begin
                        init_busy <= 1'b0;
                        init_error <= 1'b1;
                    end
                    block_busy <= 1'b0;
                    block_error <= 1'b1;
                    host_state <= H_READY;
                end

                default: host_state <= H_RESET;
            endcase
        end
    end

    // DAT3 is high while the card is deselected and low while selected.  The
    // byte engine leaves it low for all command/data transfers.
    always @* begin
        sd_clk_idle_high = (host_state == H_RESET) ||
                           (host_state == H_RESET_CLOCKS) ||
                           (host_state == H_READY) ||
                           (host_state == H_ERROR);
    end

endmodule
