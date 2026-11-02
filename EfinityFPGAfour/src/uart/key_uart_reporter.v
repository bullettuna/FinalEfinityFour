`timescale 1ns/1ps

// Active-low button: both edges must stay stable for 20 ms at 96 MHz.
// One complete "key  1\r\n" line per press; holding never repeats.
module key_uart_reporter #(
    parameter integer DEBOUNCE_CYCLES = 1920000
)(
    input clk,
    input rst_n,
    input key_n,
    output tx_valid,
    output reg [7:0] tx_data,
    output tx_last,
    input tx_accept,
    input tx_done
);
localparam integer COUNT_WIDTH = DEBOUNCE_CYCLES <= 1 ? 1 : $clog2(DEBOUNCE_CYCLES);
reg key_meta, key_sync, key_stable;
reg [COUNT_WIDTH-1:0] debounce_count;
wire stable_change = (key_sync != key_stable) &&
                     (debounce_count == DEBOUNCE_CYCLES-1);
wire press_event = stable_change && !key_sync;

// Only the second synchronizer stage feeds the debounce logic.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_meta <= 1'b1;
        key_sync <= 1'b1;
        key_stable <= 1'b1;
        debounce_count <= 0;
    end else begin
        key_meta <= key_n;
        key_sync <= key_meta;
        if (key_sync == key_stable) begin
            debounce_count <= 0;
        end else if (stable_change) begin
            key_stable <= key_sync;
            debounce_count <= 0;
        end else begin
            debounce_count <= debounce_count + 1'b1;
        end
    end
end

// Count presses while another UART message owns the transmitter.
reg [15:0] pending_count;
reg sending, waiting;
reg [2:0] byte_index;
wire take_event = !sending && (pending_count != 0);
wire put_event = press_event && ((pending_count != 16'hffff) || take_event);
assign tx_valid = sending && !waiting;
assign tx_last = sending && (byte_index == 3'd7);
always @* begin
    case (byte_index)
        0: tx_data = "k";
        1: tx_data = "e";
        2: tx_data = "y";
        3: tx_data = " ";
        4: tx_data = " ";
        5: tx_data = "1";
        6: tx_data = 8'h0d;
        7: tx_data = 8'h0a;
        default: tx_data = 8'h00;
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pending_count <= 0;
        sending <= 1'b0;
        waiting <= 1'b0;
        byte_index <= 0;
    end else begin
        case ({put_event, take_event})
            2'b10: pending_count <= pending_count + 1'b1;
            2'b01: pending_count <= pending_count - 1'b1;
            default: pending_count <= pending_count;
        endcase
        if (take_event) begin
            sending <= 1'b1;
            waiting <= 1'b0;
            byte_index <= 0;
        end else if (tx_valid && tx_accept) begin
            waiting <= 1'b1;
        end else if (waiting && tx_done) begin
            waiting <= 1'b0;
            if (byte_index == 3'd7)
                sending <= 1'b0;
            else
                byte_index <= byte_index + 1'b1;
        end
    end
end
endmodule
