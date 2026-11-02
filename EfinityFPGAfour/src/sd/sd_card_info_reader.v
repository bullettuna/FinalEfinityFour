`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// One-shot SD-card information reader using the SD SPI transport.
//
// A query performs a fresh card initialization and then reads:
//   - OCR (capacity class)
//   - CID
//   - CSD (capacity and card generation)
//
// The module only exposes a byte-stream message for the existing UART message
// arbiter. It does not implement a filesystem or read user data.
//////////////////////////////////////////////////////////////////////////////////

module sd_card_info_reader #(
    parameter [15:0] SPI_HALF_PERIOD        = 16'd120,
    parameter [31:0] ACMD41_RETRY_LIMIT     = 32'd5000,
    parameter [15:0] DATA_TOKEN_RETRY_LIMIT = 16'hffff
)
(
    input               clk,
    input               rst_n,
    input               query,
    output              busy,

    output reg          tx_valid,
    output reg  [7:0]   tx_data,
    output reg          tx_last,
    input               tx_accept,

    output              sd_clk,
    output              sd_cmd_o,
    output reg          sd_cmd_oe,
    output      [3:0]   sd_dat_o,
    output      [3:0]   sd_dat_oe,
    input       [3:0]   sd_dat_i
);

localparam [5:0] S_IDLE              = 6'd0;
localparam [5:0] S_POWER             = 6'd1;
localparam [5:0] S_POWER_NEXT        = 6'd2;
localparam [5:0] S_CMD_SEND          = 6'd3;
localparam [5:0] S_CMD_NEXT          = 6'd4;
localparam [5:0] S_SPI_WAIT          = 6'd5;
localparam [5:0] S_R1_WAIT           = 6'd6;
localparam [5:0] S_R1_NEXT           = 6'd7;
localparam [5:0] S_CMD0_R1           = 6'd8;
localparam [5:0] S_CMD8_R1           = 6'd9;
localparam [5:0] S_CMD8_R7           = 6'd10;
localparam [5:0] S_CMD8_R7_NEXT      = 6'd11;
localparam [5:0] S_ACMD41_START      = 6'd12;
localparam [5:0] S_CMD55_R1          = 6'd13;
localparam [5:0] S_ACMD41_R1         = 6'd14;
localparam [5:0] S_CMD58_R1          = 6'd15;
localparam [5:0] S_CMD58_R4          = 6'd16;
localparam [5:0] S_CMD58_R4_NEXT     = 6'd17;
localparam [5:0] S_CMD10_R1          = 6'd18;
localparam [5:0] S_CMD9_R1           = 6'd19;
localparam [5:0] S_DATA_TOKEN        = 6'd20;
localparam [5:0] S_DATA_TOKEN_NEXT   = 6'd21;
localparam [5:0] S_DATA_BYTES        = 6'd22;
localparam [5:0] S_DATA_BYTES_NEXT   = 6'd23;
localparam [5:0] S_DATA_CRC          = 6'd24;
localparam [5:0] S_DATA_CRC_NEXT     = 6'd25;
localparam [5:0] S_DEASSERT          = 6'd26;
localparam [5:0] S_DEASSERT_NEXT     = 6'd27;
localparam [5:0] S_CAP_BCD_START     = 6'd28;
localparam [5:0] S_CAP_BCD           = 6'd29;
localparam [5:0] S_CAP_FINALIZE      = 6'd30;
localparam [5:0] S_REPORT_PREPARE    = 6'd31;
localparam [5:0] S_REPORT             = 6'd32;
localparam [5:0] S_FAIL_NOT_FOUND    = 6'd33;
localparam [5:0] S_FAIL_READ         = 6'd34;

localparam [1:0] CARD_SDSC = 2'd0;
localparam [1:0] CARD_SDHC = 2'd1;
localparam [1:0] CARD_SDXC = 2'd2;

reg  [5:0]  state;
reg  [5:0]  spi_return;
reg  [5:0]  r1_done_state;
reg         query_previous;

reg  [7:0]  power_bytes;
reg  [47:0] cmd_shift;
reg  [3:0]  cmd_bytes_left;
reg  [7:0]  response_bytes_left;
reg  [15:0] token_retry;
reg  [31:0] acmd41_retry;

reg  [31:0] response_shift;
reg  [127:0] cid_shift;
reg  [127:0] csd_shift;
reg  [127:0] data_shift;
reg  [7:0]  data_bytes_left;
reg  [7:0]  data_crc_bytes_left;
reg         read_target;             // 0 = CID, 1 = CSD

reg  [7:0]  r1;
reg         init_v2;
reg         high_capacity;
reg  [1:0]  card_type;
reg  [31:0] capacity_mb;
reg  [31:0] cap_work;
reg  [27:0] cap_bcd;
reg  [27:0] cap_bcd_adjusted;
reg  [5:0]  cap_iterations;
reg  [2:0]  cap_length;

reg  [1:0]  report_status;           // 0 = success, 1 = not found, 2 = read fail
reg  [7:0]  report_index;
reg  [7:0]  report_length;

reg         spi_start;
reg  [7:0]  spi_tx_data;
reg  [7:0]  spi_rx_byte;
reg  [7:0]  spi_tx_shift;
reg  [7:0]  spi_rx_shift;
reg         spi_busy;
reg         spi_done;
reg  [3:0]  spi_bits_left;
reg  [15:0] spi_half_count;
reg         spi_phase;
reg         spi_sclk;
reg         spi_mosi;

reg         sd_cs_n;

wire [31:0] response_shift_next =
    {response_shift[23:0], spi_rx_byte};
wire [127:0] data_shift_next =
    {data_shift[119:0], spi_rx_byte};
wire [31:0] capacity_mb_calculated =
    calculate_capacity_mb(csd_shift);

// DAT3 is CS in SPI mode. It is always driven so a hot-plugged card sees a
// defined CS-high state while the controller is idle.
assign sd_clk    = spi_sclk;
assign sd_cmd_o  = spi_busy ? spi_mosi : 1'b1;
assign sd_dat_o  = {sd_cs_n, 3'b000};
assign sd_dat_oe = 4'b1000;
assign busy      = (state != S_IDLE);

wire [7:0] sd_miso = {7'b0000000, sd_dat_i[0]};

integer crc_index;
function [6:0] crc7_40;
    input [39:0] data;
    reg [6:0] crc;
    reg feedback;
    begin
        crc = 7'd0;
        for (crc_index = 39; crc_index >= 0; crc_index = crc_index - 1) begin
            feedback = data[crc_index] ^ crc[6];
            crc = crc << 1;
            if (feedback)
                crc = crc ^ 7'h09;
        end
        crc7_40 = crc;
    end
endfunction

integer capacity_exponent;
function [31:0] calculate_capacity_mb;
    input [127:0] csd;
    reg [31:0] cs_size;
    begin
        capacity_exponent = 0;
        if (csd[127:126] == 2'b01) begin
            cs_size = {10'd0, csd[69:48]} + 32'd1;
            calculate_capacity_mb = cs_size >> 1;
        end else begin
            cs_size = {20'd0, csd[73:62]} + 32'd1;
            capacity_exponent = {1'b0, csd[83:80]} +
                                {1'b0, csd[49:47]} - 18;
            if (capacity_exponent >= 0)
                calculate_capacity_mb = cs_size << capacity_exponent;
            else
                calculate_capacity_mb = cs_size >> (-capacity_exponent);
        end
    end
endfunction

function [7:0] hex_ascii;
    input [3:0] value;
    begin
        if (value < 4'd10)
            hex_ascii = 8'h30 + {4'd0, value};
        else
            hex_ascii = 8'h37 + {4'd0, value};
    end
endfunction

function [7:0] type_ascii;
    input [4:0] index;
    begin
        case (card_type)
            CARD_SDHC: begin
                case (index)
                    5'd0: type_ascii = "S";
                    5'd1: type_ascii = "D";
                    5'd2: type_ascii = "H";
                    default: type_ascii = "C";
                endcase
            end
            CARD_SDXC: begin
                case (index)
                    5'd0: type_ascii = "S";
                    5'd1: type_ascii = "D";
                    5'd2: type_ascii = "X";
                    default: type_ascii = "C";
                endcase
            end
            default: begin
                case (index)
                    5'd0: type_ascii = "S";
                    5'd1: type_ascii = "D";
                    5'd2: type_ascii = "S";
                    default: type_ascii = "C";
                endcase
            end
        endcase
    end
endfunction

function [7:0] report_byte;
    input [7:0] index;
    reg [7:0] position;
    reg [4:0] nibble_index;
    reg [3:0] nibble_value;
    begin
        report_byte = 8'h00;
        if (report_status == 2'd1) begin
            case (index)
                8'd0:  report_byte = "S";
                8'd1:  report_byte = "D";
                8'd2:  report_byte = ":";
                8'd3:  report_byte = "N";
                8'd4:  report_byte = "O";
                8'd5:  report_byte = "T";
                8'd6:  report_byte = "_";
                8'd7:  report_byte = "F";
                8'd8:  report_byte = "O";
                8'd9:  report_byte = "U";
                8'd10: report_byte = "N";
                8'd11: report_byte = "D";
                8'd12: report_byte = 8'h0d;
                default: report_byte = 8'h0a;
            endcase
        end else if (report_status == 2'd2) begin
            case (index)
                8'd0:  report_byte = "S";
                8'd1:  report_byte = "D";
                8'd2:  report_byte = ":";
                8'd3:  report_byte = "R";
                8'd4:  report_byte = "E";
                8'd5:  report_byte = "A";
                8'd6:  report_byte = "D";
                8'd7:  report_byte = "_";
                8'd8:  report_byte = "F";
                8'd9:  report_byte = "A";
                8'd10: report_byte = "I";
                8'd11: report_byte = "L";
                8'd12: report_byte = 8'h0d;
                default: report_byte = 8'h0a;
            endcase
        end else begin
            if (index < 8'd15) begin
                case (index)
                    8'd0:  report_byte = "S";
                    8'd1:  report_byte = "D";
                    8'd2:  report_byte = ":";
                    8'd3:  report_byte = "O";
                    8'd4:  report_byte = "K";
                    8'd5:  report_byte = " ";
                    8'd6:  report_byte = "T";
                    8'd7:  report_byte = "Y";
                    8'd8:  report_byte = "P";
                    8'd9:  report_byte = "E";
                    8'd10: report_byte = "=";
                    default: report_byte = type_ascii(index - 8'd11);
                endcase
            end else if (index < 8'd20) begin
                case (index)
                    8'd15: report_byte = " ";
                    8'd16: report_byte = "C";
                    8'd17: report_byte = "A";
                    8'd18: report_byte = "P";
                    default: report_byte = "=";
                endcase
            end else if (index < (8'd20 + {5'd0, cap_length})) begin
                position = index - 8'd20;
                nibble_index = cap_length - 5'd1 - position[4:0];
                case (nibble_index)
                    5'd0: nibble_value = cap_bcd[3:0];
                    5'd1: nibble_value = cap_bcd[7:4];
                    5'd2: nibble_value = cap_bcd[11:8];
                    5'd3: nibble_value = cap_bcd[15:12];
                    5'd4: nibble_value = cap_bcd[19:16];
                    5'd5: nibble_value = cap_bcd[23:20];
                    default: nibble_value = cap_bcd[27:24];
                endcase
                report_byte = hex_ascii(nibble_value);
            end else begin
                position = index - 8'd20 - {5'd0, cap_length};
                case (position)
                    8'd0: report_byte = "M";
                    8'd1: report_byte = "B";
                    8'd2: report_byte = " ";
                    8'd3: report_byte = "C";
                    8'd4: report_byte = "I";
                    8'd5: report_byte = "D";
                    8'd6: report_byte = "=";
                    8'd39: report_byte = " ";
                    8'd40: report_byte = "C";
                    8'd41: report_byte = "S";
                    8'd42: report_byte = "D";
                    8'd43: report_byte = "=";
                    8'd45 + 8'd31: report_byte = 8'h0d;
                    8'd46 + 8'd31: report_byte = 8'h0a;
                    default: begin
                        if ((position >= 8'd7) && (position < 8'd39)) begin
                            nibble_index = 5'd31 -
                                (position[4:0] - 5'd7);
                            report_byte = hex_ascii(
                                cid_shift[{nibble_index, 2'b00} +: 4]);
                        end else if ((position >= 8'd44) &&
                                     (position < 8'd76)) begin
                            nibble_index = 5'd31 -
                                (position[4:0] - 5'd12);
                            report_byte = hex_ascii(
                                csd_shift[{nibble_index, 2'b00} +: 4]);
                        end
                    end
                endcase
            end
        end
    end
endfunction

always @(*) begin
    cap_bcd_adjusted = cap_bcd;
    if (cap_bcd[3:0] >= 4'd5)
        cap_bcd_adjusted[3:0] = cap_bcd[3:0] + 4'd3;
    if (cap_bcd[7:4] >= 4'd5)
        cap_bcd_adjusted[7:4] = cap_bcd[7:4] + 4'd3;
    if (cap_bcd[11:8] >= 4'd5)
        cap_bcd_adjusted[11:8] = cap_bcd[11:8] + 4'd3;
    if (cap_bcd[15:12] >= 4'd5)
        cap_bcd_adjusted[15:12] = cap_bcd[15:12] + 4'd3;
    if (cap_bcd[19:16] >= 4'd5)
        cap_bcd_adjusted[19:16] = cap_bcd[19:16] + 4'd3;
    if (cap_bcd[23:20] >= 4'd5)
        cap_bcd_adjusted[23:20] = cap_bcd[23:20] + 4'd3;
    if (cap_bcd[27:24] >= 4'd5)
        cap_bcd_adjusted[27:24] = cap_bcd[27:24] + 4'd3;
end

task start_spi_byte;
    input [7:0] data;
    input [5:0] next_state;
    begin
        spi_tx_data <= data;
        spi_start   <= 1'b1;
        spi_return  <= next_state;
        state       <= S_SPI_WAIT;
    end
endtask

task start_command;
    input [47:0] command;
    input [5:0]  response_state;
    begin
        cmd_shift          <= {command[47:8],
                               crc7_40(command[47:8]), 1'b1};
        cmd_bytes_left     <= 4'd6;
        response_bytes_left <= 8'd8;
        r1_done_state      <= response_state;
        state              <= S_CMD_SEND;
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spi_busy      <= 1'b0;
        spi_done      <= 1'b0;
        spi_rx_byte   <= 8'h00;
        spi_tx_shift  <= 8'h00;
        spi_rx_shift  <= 8'h00;
        spi_bits_left <= 4'd0;
        spi_half_count <= 16'd0;
        spi_phase     <= 1'b0;
        spi_sclk      <= 1'b0;
        spi_mosi      <= 1'b1;
    end else begin
        spi_done <= 1'b0;

        if (spi_start && !spi_busy) begin
            spi_busy       <= 1'b1;
            spi_tx_shift   <= spi_tx_data;
            spi_rx_shift   <= 8'h00;
            spi_bits_left  <= 4'd8;
            spi_half_count <= 16'd0;
            spi_phase      <= 1'b0;
            spi_sclk       <= 1'b0;
            spi_mosi       <= spi_tx_data[7];
        end else if (spi_busy) begin
            if (spi_half_count == (SPI_HALF_PERIOD - 16'd1)) begin
                spi_half_count <= 16'd0;
                if (!spi_phase) begin
                    spi_sclk     <= 1'b1;
                    spi_rx_shift <= {spi_rx_shift[6:0], sd_miso[0]};
                    spi_phase    <= 1'b1;
                end else begin
                    spi_sclk <= 1'b0;
                    if (spi_bits_left == 4'd1) begin
                        spi_busy    <= 1'b0;
                        spi_done    <= 1'b1;
                        spi_rx_byte <= spi_rx_shift;
                    end else begin
                        spi_bits_left <= spi_bits_left - 4'd1;
                        spi_tx_shift  <= {spi_tx_shift[6:0], 1'b1};
                        spi_mosi      <= spi_tx_shift[6];
                        spi_phase     <= 1'b0;
                    end
                end
            end else begin
                spi_half_count <= spi_half_count + 16'd1;
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                 <= S_IDLE;
        spi_tx_data           <= 8'h00;
        spi_start             <= 1'b0;
        spi_return            <= S_IDLE;
        r1_done_state         <= S_IDLE;
        query_previous        <= 1'b0;
        power_bytes           <= 8'd0;
        cmd_shift             <= 48'd0;
        cmd_bytes_left        <= 4'd0;
        response_bytes_left   <= 8'd0;
        token_retry           <= 16'd0;
        acmd41_retry          <= 32'd0;
        response_shift        <= 32'd0;
        cid_shift             <= 128'd0;
        csd_shift             <= 128'd0;
        data_shift            <= 128'd0;
        data_bytes_left       <= 8'd0;
        data_crc_bytes_left   <= 8'd0;
        read_target           <= 1'b0;
        r1                    <= 8'hff;
        init_v2               <= 1'b0;
        high_capacity         <= 1'b0;
        card_type             <= CARD_SDSC;
        capacity_mb           <= 32'd0;
        cap_work              <= 32'd0;
        cap_bcd               <= 28'd0;
        cap_iterations        <= 6'd0;
        cap_length            <= 3'd1;
        report_status         <= 2'd0;
        report_index          <= 8'd0;
        report_length         <= 8'd0;
        tx_valid              <= 1'b0;
        tx_data               <= 8'h00;
        tx_last               <= 1'b0;
        sd_cs_n               <= 1'b1;
        sd_cmd_oe             <= 1'b0;
    end else begin
        spi_start <= 1'b0;
        query_previous <= query;

        if (query && !query_previous && (state == S_IDLE)) begin
            power_bytes      <= 8'd10;
            response_shift   <= 32'd0;
            cid_shift        <= 128'd0;
            csd_shift        <= 128'd0;
            data_shift       <= 128'd0;
            init_v2          <= 1'b0;
            high_capacity    <= 1'b0;
            card_type        <= CARD_SDSC;
            capacity_mb      <= 32'd0;
            acmd41_retry     <= 32'd0;
            report_status    <= 2'd0;
            report_index     <= 8'd0;
            tx_valid         <= 1'b0;
            tx_last          <= 1'b0;
            sd_cs_n          <= 1'b1;
            sd_cmd_oe        <= 1'b1;
            state            <= S_POWER;
        end else begin
            case (state)
                S_IDLE: begin
                    tx_valid <= 1'b0;
                end

                S_POWER: begin
                    start_spi_byte(8'hff, S_POWER_NEXT);
                end

                S_POWER_NEXT: begin
                    if (power_bytes == 8'd1) begin
                        sd_cs_n <= 1'b0;
                        start_command(48'h40_00000000_00, S_CMD0_R1);
                    end else begin
                        power_bytes <= power_bytes - 8'd1;
                        state       <= S_POWER;
                    end
                end

                S_CMD_SEND: begin
                    start_spi_byte(cmd_shift[47:40], S_CMD_NEXT);
                end

                S_CMD_NEXT: begin
                    cmd_shift <= {cmd_shift[39:0], 8'h00};
                    if (cmd_bytes_left == 4'd1)
                        state <= S_R1_WAIT;
                    else begin
                        cmd_bytes_left <= cmd_bytes_left - 4'd1;
                        state          <= S_CMD_SEND;
                    end
                end

                S_SPI_WAIT: begin
                    if (spi_done)
                        state <= spi_return;
                end

                S_R1_WAIT: begin
                    if (response_bytes_left == 8'd0)
                        state <= S_FAIL_NOT_FOUND;
                    else
                        start_spi_byte(8'hff, S_R1_NEXT);
                end

                S_R1_NEXT: begin
                    if (spi_rx_byte[7] == 1'b0) begin
                        r1    <= spi_rx_byte;
                        state <= r1_done_state;
                    end else begin
                        response_bytes_left <= response_bytes_left - 8'd1;
                        state               <= S_R1_WAIT;
                    end
                end

                S_CMD0_R1: begin
                    if ((r1 & 8'h7e) == 8'h00)
                        start_command(48'h48_000001aa_00, S_CMD8_R1);
                    else
                        state <= S_FAIL_NOT_FOUND;
                end

                S_CMD8_R1: begin
                    if (r1[2]) begin
                        init_v2 <= 1'b0;
                        state   <= S_ACMD41_START;
                    end else if (r1 == 8'h01) begin
                        response_shift      <= 32'd0;
                        response_bytes_left <= 8'd4;
                        state               <= S_CMD8_R7;
                    end else begin
                        state <= S_FAIL_NOT_FOUND;
                    end
                end

                S_CMD8_R7: begin
                    start_spi_byte(8'hff, S_CMD8_R7_NEXT);
                end

                S_CMD8_R7_NEXT: begin
                    response_shift <= response_shift_next;
                    if (response_bytes_left == 8'd1) begin
                        if (response_shift_next[15:0] == 16'h01aa) begin
                            init_v2 <= 1'b1;
                            state   <= S_ACMD41_START;
                        end else begin
                            state <= S_FAIL_NOT_FOUND;
                        end
                    end else begin
                        response_bytes_left <=
                            response_bytes_left - 8'd1;
                        state <= S_CMD8_R7;
                    end
                end

                S_ACMD41_START: begin
                    acmd41_retry <= acmd41_retry + 32'd1;
                    if (acmd41_retry >= ACMD41_RETRY_LIMIT)
                        state <= S_FAIL_NOT_FOUND;
                    else
                        start_command(48'h77_00000000_00, S_CMD55_R1);
                end

                S_CMD55_R1: begin
                    if ((r1 & 8'h7e) == 8'h00) begin
                        if (init_v2)
                            start_command(48'h69_40000000_00,
                                          S_ACMD41_R1);
                        else
                            start_command(48'h69_00000000_00,
                                          S_ACMD41_R1);
                    end else begin
                        state <= S_FAIL_NOT_FOUND;
                    end
                end

                S_ACMD41_R1: begin
                    if ((r1 & 8'h7e) != 8'h00)
                        state <= S_FAIL_NOT_FOUND;
                    else if (r1[0] == 1'b0)
                        start_command(48'h7a_00000000_00,
                                      S_CMD58_R1);
                    else if (acmd41_retry >= ACMD41_RETRY_LIMIT)
                        state <= S_FAIL_NOT_FOUND;
                    else
                        state <= S_ACMD41_START;
                end

                S_CMD58_R1: begin
                    if (r1 == 8'h00) begin
                        response_shift      <= 32'd0;
                        response_bytes_left <= 8'd4;
                        state               <= S_CMD58_R4;
                    end else begin
                        state <= S_FAIL_NOT_FOUND;
                    end
                end

                S_CMD58_R4: begin
                    start_spi_byte(8'hff, S_CMD58_R4_NEXT);
                end

                S_CMD58_R4_NEXT: begin
                    response_shift <= response_shift_next;
                    if (response_bytes_left == 8'd1) begin
                        high_capacity <= response_shift_next[30];
                        read_target   <= 1'b0;
                        start_command(48'h4a_00000000_00,
                                      S_CMD10_R1);
                    end else begin
                        response_bytes_left <=
                            response_bytes_left - 8'd1;
                        state <= S_CMD58_R4;
                    end
                end

                S_CMD10_R1: begin
                    if (r1 == 8'h00) begin
                        token_retry <= DATA_TOKEN_RETRY_LIMIT;
                        state       <= S_DATA_TOKEN;
                    end else begin
                        state <= S_FAIL_READ;
                    end
                end

                S_CMD9_R1: begin
                    if (r1 == 8'h00) begin
                        token_retry <= DATA_TOKEN_RETRY_LIMIT;
                        state       <= S_DATA_TOKEN;
                    end else begin
                        state <= S_FAIL_READ;
                    end
                end

                S_DATA_TOKEN: begin
                    start_spi_byte(8'hff, S_DATA_TOKEN_NEXT);
                end

                S_DATA_TOKEN_NEXT: begin
                    if (spi_rx_byte == 8'hfe) begin
                        data_shift      <= 128'd0;
                        data_bytes_left <= 8'd16;
                        state           <= S_DATA_BYTES;
                    end else if (token_retry == 16'd0) begin
                        state <= S_FAIL_READ;
                    end else begin
                        token_retry <= token_retry - 16'd1;
                        state       <= S_DATA_TOKEN;
                    end
                end

                S_DATA_BYTES: begin
                    start_spi_byte(8'hff, S_DATA_BYTES_NEXT);
                end

                S_DATA_BYTES_NEXT: begin
                    data_shift <= data_shift_next;
                    if (data_bytes_left == 8'd1) begin
                        data_crc_bytes_left <= 8'd2;
                        state <= S_DATA_CRC;
                    end else begin
                        data_bytes_left <= data_bytes_left - 8'd1;
                        state <= S_DATA_BYTES;
                    end
                end

                S_DATA_CRC: begin
                    start_spi_byte(8'hff, S_DATA_CRC_NEXT);
                end

                S_DATA_CRC_NEXT: begin
                    if (data_crc_bytes_left == 8'd1) begin
                        if (read_target == 1'b0) begin
                            cid_shift   <= data_shift;
                            read_target <= 1'b1;
                            start_command(48'h49_00000000_00,
                                          S_CMD9_R1);
                        end else begin
                            csd_shift <= data_shift;
                            if ((data_shift == 128'd0) ||
                                (data_shift == {128{1'b1}}))
                                state <= S_FAIL_READ;
                            else
                                state <= S_DEASSERT;
                        end
                    end else begin
                        data_crc_bytes_left <=
                            data_crc_bytes_left - 8'd1;
                        state <= S_DATA_CRC;
                    end
                end

                S_DEASSERT: begin
                    sd_cs_n <= 1'b1;
                    start_spi_byte(8'hff, S_DEASSERT_NEXT);
                end

                S_DEASSERT_NEXT: begin
                    sd_cmd_oe <= 1'b0;
                    if (report_status == 2'd0)
                        state <= S_CAP_BCD_START;
                    else
                        state <= S_REPORT_PREPARE;
                end

                S_CAP_BCD_START: begin
                    capacity_mb <= capacity_mb_calculated;
                    cap_work    <= capacity_mb_calculated;
                    cap_bcd     <= 28'd0;
                    cap_iterations <= 6'd32;
                    if (high_capacity) begin
                        if (capacity_mb_calculated > 32'd32768)
                            card_type <= CARD_SDXC;
                        else
                            card_type <= CARD_SDHC;
                    end else begin
                        card_type <= CARD_SDSC;
                    end
                    state <= S_CAP_BCD;
                end

                S_CAP_BCD: begin
                    if (cap_iterations == 6'd1) begin
                        {cap_bcd, cap_work} <=
                            {cap_bcd_adjusted, cap_work} << 1;
                        state <= S_CAP_FINALIZE;
                    end else begin
                        {cap_bcd, cap_work} <=
                            {cap_bcd_adjusted, cap_work} << 1;
                        cap_iterations <= cap_iterations - 6'd1;
                    end
                end

                S_CAP_FINALIZE: begin
                    if (cap_bcd[27:24] != 4'd0)
                        cap_length <= 3'd7;
                    else if (cap_bcd[23:20] != 4'd0)
                        cap_length <= 3'd6;
                    else if (cap_bcd[19:16] != 4'd0)
                        cap_length <= 3'd5;
                    else if (cap_bcd[15:12] != 4'd0)
                        cap_length <= 3'd4;
                    else if (cap_bcd[11:8] != 4'd0)
                        cap_length <= 3'd3;
                    else if (cap_bcd[7:4] != 4'd0)
                        cap_length <= 3'd2;
                    else
                        cap_length <= 3'd1;
                    state <= S_REPORT_PREPARE;
                end

                S_REPORT_PREPARE: begin
                    report_index <= 8'd0;
                    if (report_status == 2'd0)
                        report_length <= 8'd98 + {5'd0, cap_length};
                    else
                        report_length <= 8'd14;
                    state <= S_REPORT;
                end

                S_REPORT: begin
                    if (!tx_valid) begin
                        tx_data  <= report_byte(report_index);
                        tx_last  <= (report_index == report_length - 8'd1);
                        tx_valid <= 1'b1;
                    end else if (tx_accept) begin
                        if (tx_last) begin
                            tx_valid <= 1'b0;
                            state    <= S_IDLE;
                        end else begin
                            report_index <= report_index + 8'd1;
                            tx_data <= report_byte(report_index + 8'd1);
                            tx_last <= ((report_index + 8'd1) ==
                                        report_length - 8'd1);
                        end
                    end
                end

                S_FAIL_NOT_FOUND: begin
                    report_status <= 2'd1;
                    state         <= S_DEASSERT;
                end

                S_FAIL_READ: begin
                    report_status <= 2'd2;
                    state         <= S_DEASSERT;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
end

endmodule

