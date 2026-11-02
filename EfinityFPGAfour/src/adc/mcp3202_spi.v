`timescale 1ns/1ps
// MCP3202 protocol reference: Dominic Meads SPI_MCP3202 V2.0 (GitHub).
// Reworked for a resettable integer clock divider and alternating channels.
// Wire format follows Microchip DS21034F Fig. 6-1: 01 A0/E0 00, Mode 0.
module mcp3202_spi #(
    parameter integer CLOCK_HZ = 96000000,
    parameter integer SPI_HZ = 500000,
    parameter integer CHANNEL_SAMPLE_HZ = 1000
)(
    input clk, input rst_n, input spi_miso,
    output reg spi_sclk, output reg spi_mosi, output reg cs_adc,
    output reg sample_valid, output reg sample_channel,
    output reg [11:0] sample_data
);
localparam integer HALF_CYCLES = CLOCK_HZ / (2*SPI_HZ);
localparam integer SLOT_CYCLES = CLOCK_HZ / (2*CHANNEL_SAMPLE_HZ);
localparam integer RESET_WAIT_CYCLES = CLOCK_HZ < 1000000 ? 1 : CLOCK_HZ/1000000;
localparam integer HALF_WIDTH = HALF_CYCLES <= 1 ? 1 : $clog2(HALF_CYCLES);
localparam integer SLOT_WIDTH = SLOT_CYCLES <= 1 ? 1 : $clog2(SLOT_CYCLES);
reg [HALF_WIDTH-1:0] half_count;
reg [SLOT_WIDTH-1:0] slot_count;
reg [23:0] tx_shift, rx_shift;
reg [4:0] bit_index;
reg active, next_channel;
reg miso_meta, miso_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        miso_meta <= 0;
        miso_sync <= 0;
    end else begin
        miso_meta <= spi_miso;
        miso_sync <= miso_meta;
    end
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Guarantee at least 1 us of CS high time after reset release.
        slot_count <= SLOT_CYCLES-RESET_WAIT_CYCLES;
        half_count <= 0;
        tx_shift <= 0;
        rx_shift <= 0;
        bit_index <= 0;
        active <= 0;
        next_channel <= 0;
        spi_sclk <= 0;
        spi_mosi <= 0;
        cs_adc <= 1;
        sample_valid <= 0;
        sample_channel <= 0;
        sample_data <= 0;
    end else begin
        sample_valid <= 0;
        if (slot_count == SLOT_CYCLES-1) slot_count <= 0;
        else slot_count <= slot_count + 1'b1;
        if (!active) begin
            spi_sclk <= 0;
            cs_adc <= 1;
            half_count <= 0;
            if (slot_count == 0) begin
                active <= 1;
                cs_adc <= 0;
                spi_mosi <= 0;
                tx_shift <= next_channel ? 24'h01e000 : 24'h01a000;
                rx_shift <= 0;
                bit_index <= 0;
            end
        end else if (half_count == HALF_CYCLES-1) begin
            half_count <= 0;
            if (!spi_sclk) begin
                spi_sclk <= 1;
                rx_shift <= {rx_shift[22:0], miso_sync};
            end else begin
                spi_sclk <= 0;
                if (bit_index == 23) begin
                    active <= 0;
                    cs_adc <= 1;
                    spi_mosi <= 0;
                    sample_valid <= 1;
                    sample_channel <= next_channel;
                    sample_data <= rx_shift[11:0];
                    next_channel <= !next_channel;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    tx_shift <= {tx_shift[22:0],1'b0};
                    spi_mosi <= tx_shift[22];
                end
            end
        end else half_count <= half_count + 1'b1;
    end
end
endmodule
