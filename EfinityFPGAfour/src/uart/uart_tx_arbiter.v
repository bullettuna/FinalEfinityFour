`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Shares one byte-oriented UART transmitter between command replies and the
// multi-byte shape-status reporter. Command replies have priority. The message
// source holds msg_tx_valid until msg_tx_accept, then waits for msg_tx_done.
//////////////////////////////////////////////////////////////////////////////////

module uart_tx_arbiter
(
    input              clk,
    input              rst_n,

    input              cmd_tx_start,
    input      [7:0]   cmd_tx_data,
    output reg         cmd_tx_done,

    input              msg_tx_valid,
    input      [7:0]   msg_tx_data,
    input              msg_tx_last,
    output reg         msg_tx_accept,
    output reg         msg_tx_done,

    input              msg2_tx_valid,
    input      [7:0]   msg2_tx_data,
    input              msg2_tx_last,
    output reg         msg2_tx_accept,
    output reg         msg2_tx_done,

    input              msg3_tx_valid,
    input      [7:0]   msg3_tx_data,
    input              msg3_tx_last,
    output reg         msg3_tx_accept,
    output reg         msg3_tx_done,

    input              msg4_tx_valid,
    input      [7:0]   msg4_tx_data,
    input              msg4_tx_last,
    output reg         msg4_tx_accept,
    output reg         msg4_tx_done,

    input              uart_tx_done,
    output reg [7:0]   uart_tx_data,
    output reg         uart_tx_start
);

reg       uart_busy;
reg       owner_is_message;
reg       owner_is_message2;
reg       owner_is_message3;
reg       owner_is_message4;
reg       owner_message_last;
reg       message_active;
reg       command_pending;
reg [7:0] command_pending_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cmd_tx_done          <= 1'b0;
        msg_tx_accept        <= 1'b0;
        msg_tx_done          <= 1'b0;
        msg2_tx_accept       <= 1'b0;
        msg2_tx_done         <= 1'b0;
		msg3_tx_accept       <= 1'b0;
		msg3_tx_done         <= 1'b0;
        msg4_tx_accept      <= 1'b0;
        msg4_tx_done        <= 1'b0;
        uart_tx_data         <= 8'h00;
        uart_tx_start        <= 1'b0;
        uart_busy            <= 1'b0;
        owner_is_message     <= 1'b0;
        owner_is_message2    <= 1'b0;
		owner_is_message3    <= 1'b0;
        owner_is_message4   <= 1'b0;
        owner_message_last   <= 1'b0;
        message_active       <= 1'b0;
        command_pending      <= 1'b0;
        command_pending_data <= 8'h00;
    end else begin
        cmd_tx_done   <= 1'b0;
        msg_tx_accept <= 1'b0;
        msg_tx_done   <= 1'b0;
        msg2_tx_accept <= 1'b0;
        msg2_tx_done   <= 1'b0;
		msg3_tx_accept <= 1'b0;
		msg3_tx_done   <= 1'b0;
        msg4_tx_accept <= 1'b0;
        msg4_tx_done   <= 1'b0;
        uart_tx_start <= 1'b0;

        // The command decoder emits a one-clock start pulse. Preserve it while
        // a status-message byte owns the physical UART.
        if ((uart_busy || message_active) && cmd_tx_start && !command_pending) begin
            command_pending      <= 1'b1;
            command_pending_data <= cmd_tx_data;
        end

        if (uart_busy) begin
            if (uart_tx_done) begin
                uart_busy <= 1'b0;
                if (owner_is_message) begin
                    if (owner_is_message3)
						msg3_tx_done <= 1'b1;
                    else if (owner_is_message4)
                        msg4_tx_done <= 1'b1;
                    else if (owner_is_message2)
                        msg2_tx_done <= 1'b1;
                    else
                        msg_tx_done <= 1'b1;
                end else
                    cmd_tx_done <= 1'b1;

                if (owner_is_message && owner_message_last)
                    message_active <= 1'b0;
            end
        end else begin
            // Once a status line starts, keep it contiguous. Command replies
            // wait until the final LF byte has physically left the UART.
            if (message_active) begin
				if (!owner_is_message2 && !owner_is_message3 && !owner_is_message4 && msg_tx_valid) begin
                    uart_tx_data       <= msg_tx_data;
                    uart_tx_start      <= 1'b1;
                    uart_busy          <= 1'b1;
                    owner_is_message   <= 1'b1;
                    owner_message_last <= msg_tx_last;
                    msg_tx_accept      <= 1'b1;
                end else if (owner_is_message2 && msg2_tx_valid) begin
                    uart_tx_data       <= msg2_tx_data;
                    uart_tx_start      <= 1'b1;
                    uart_busy          <= 1'b1;
                    owner_is_message   <= 1'b1;
                    owner_message_last <= msg2_tx_last;
                    msg2_tx_accept     <= 1'b1;
				end else if (owner_is_message3 && msg3_tx_valid) begin
					uart_tx_data       <= msg3_tx_data;
					uart_tx_start      <= 1'b1;
					uart_busy          <= 1'b1;
					owner_is_message   <= 1'b1;
					owner_message_last <= msg3_tx_last;
					msg3_tx_accept     <= 1'b1;
                end else if (owner_is_message4 && msg4_tx_valid) begin
                    uart_tx_data       <= msg4_tx_data;
                    uart_tx_start      <= 1'b1;
                    uart_busy          <= 1'b1;
                    owner_is_message   <= 1'b1;
                    owner_message_last <= msg4_tx_last;
                    msg4_tx_accept     <= 1'b1;
                end
            end else if (command_pending) begin
                uart_tx_data     <= command_pending_data;
                uart_tx_start    <= 1'b1;
                uart_busy        <= 1'b1;
                owner_is_message <= 1'b0;
                command_pending  <= 1'b0;
            end else if (cmd_tx_start) begin
                uart_tx_data     <= cmd_tx_data;
                uart_tx_start    <= 1'b1;
                uart_busy        <= 1'b1;
                owner_is_message <= 1'b0;
            end else if (msg_tx_valid) begin
                uart_tx_data       <= msg_tx_data;
                uart_tx_start      <= 1'b1;
                uart_busy          <= 1'b1;
                owner_is_message   <= 1'b1;
                owner_is_message2  <= 1'b0;
				owner_is_message3  <= 1'b0;
                owner_is_message4  <= 1'b0;
                owner_message_last <= msg_tx_last;
                message_active     <= 1'b1;
                msg_tx_accept      <= 1'b1;
            end else if (msg2_tx_valid) begin
                uart_tx_data       <= msg2_tx_data;
                uart_tx_start      <= 1'b1;
                uart_busy          <= 1'b1;
                owner_is_message   <= 1'b1;
                owner_is_message2  <= 1'b1;
				owner_is_message3  <= 1'b0;
                owner_is_message4  <= 1'b0;
                owner_message_last <= msg2_tx_last;
                message_active     <= 1'b1;
                msg2_tx_accept     <= 1'b1;
			end else if (msg3_tx_valid) begin
				uart_tx_data       <= msg3_tx_data;
				uart_tx_start      <= 1'b1;
				uart_busy          <= 1'b1;
				owner_is_message   <= 1'b1;
				owner_is_message2  <= 1'b0;
				owner_is_message3  <= 1'b1;
                owner_is_message4  <= 1'b0;
				owner_message_last <= msg3_tx_last;
				message_active     <= 1'b1;
				msg3_tx_accept     <= 1'b1;
			end else if (msg4_tx_valid) begin
				uart_tx_data       <= msg4_tx_data;
				uart_tx_start      <= 1'b1;
				uart_busy          <= 1'b1;
				owner_is_message   <= 1'b1;
				owner_is_message2  <= 1'b0;
				owner_is_message3  <= 1'b0;
				owner_is_message4  <= 1'b1;
				owner_message_last <= msg4_tx_last;
				message_active     <= 1'b1;
				msg4_tx_accept     <= 1'b1;
            end
        end
    end
end

endmodule
