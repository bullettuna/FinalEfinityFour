`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Debounces frame-level shape results and emits fixed-length ASCII status lines.
// A recognized shape is reported immediately after STABLE_FRAMES matching frames,
// then periodically while it remains present. AUTO_ON_TRIGGER also reports
// NONE/WAIT while another object slot is present.
//////////////////////////////////////////////////////////////////////////////////

module shape_uart_reporter
#(
    parameter integer CLOCK_HZ      = 96000000,
    parameter integer REPORT_HZ     = 2,
    parameter integer STABLE_FRAMES = 3,
    parameter integer OBJECT_INDEX  = 0,
    parameter integer AUTO_ON_TRIGGER = 0
)
(
    input              clk,
    input              rst_n,
    input              report_enable,
    input              auto_trigger,
    input              frame_tick,
    input              shape_valid,
    input      [1:0]   shape_type,
    input              query_pulse,

    output             tx_valid,
    output     [7:0]   tx_data,
    output             tx_last,
    input              tx_accept,
    input              tx_done
);

localparam integer REPORT_INTERVAL = CLOCK_HZ / REPORT_HZ;

localparam [2:0] STATUS_NONE   = 3'd0;
localparam [2:0] STATUS_WAIT   = 3'd1;
localparam [2:0] STATUS_RECT   = 3'd2;
localparam [2:0] STATUS_CIRCLE = 3'd3;

reg [1:0] candidate_type;
reg [7:0] candidate_count;
reg       stable_recognized;
reg [1:0] stable_type;
reg       previous_report_enable;
reg       previous_auto_report_active;

reg [31:0] report_counter;
reg        auto_pending;
reg        query_pending;

reg        sending;
reg        waiting_done;
reg [3:0]  char_index;
reg [2:0]  message_status;

wire shape_is_recognized = shape_valid &&
                           ((shape_type == 2'd1) || (shape_type == 2'd2));

assign tx_valid = sending && !waiting_done;
assign tx_data  = status_character(message_status, char_index);
assign tx_last  = (OBJECT_INDEX == 0) ? (char_index == 4'd13) :
                                       (char_index == 4'd14);
wire auto_report_active = stable_recognized ||
                          ((AUTO_ON_TRIGGER != 0) && auto_trigger);

function [7:0] value_character;
    input [2:0] status;
    input [3:0] index;
    begin
        case (status)
            STATUS_RECT: begin
                case (index)
                    4'd0: value_character = "R";
                    4'd1: value_character = "E";
                    4'd2: value_character = "C";
                    4'd3: value_character = "T";
                    default: value_character = " ";
                endcase
            end
            STATUS_CIRCLE: begin
                case (index)
                    4'd0: value_character = "C";
                    4'd1: value_character = "I";
                    4'd2: value_character = "R";
                    4'd3: value_character = "C";
                    4'd4: value_character = "L";
                    4'd5: value_character = "E";
                    default: value_character = " ";
                endcase
            end
            STATUS_WAIT: begin
                case (index)
                    4'd0: value_character = "W";
                    4'd1: value_character = "A";
                    4'd2: value_character = "I";
                    4'd3: value_character = "T";
                    default: value_character = " ";
                endcase
            end
            default: begin
                case (index)
                    4'd0: value_character = "N";
                    4'd1: value_character = "O";
                    4'd2: value_character = "N";
                    4'd3: value_character = "E";
                    default: value_character = " ";
                endcase
            end
        endcase
    end
endfunction

function [7:0] status_character;
    input [2:0] status;
    input [3:0] index;
    begin
        case (index)
            4'd0: status_character = "S";
            4'd1: status_character = "H";
            4'd2: status_character = "A";
            4'd3: status_character = "P";
            4'd4: status_character = "E";
            default: begin
                if (OBJECT_INDEX == 0) begin
                    if (index == 4'd5)
                        status_character = "=";
                    else if (index == 4'd12)
                        status_character = 8'h0D;
                    else if (index == 4'd13)
                        status_character = 8'h0A;
                    else
                        status_character = value_character(status, index - 4'd6);
                end else begin
                    if (index == 4'd5)
                        status_character = 8'h30 + OBJECT_INDEX;
                    else if (index == 4'd6)
                        status_character = "=";
                    else if (index == 4'd13)
                        status_character = 8'h0D;
                    else if (index == 4'd14)
                        status_character = 8'h0A;
                    else
                        status_character = value_character(status, index - 4'd7);
                end
            end
        endcase
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        candidate_type         <= 2'd0;
        candidate_count        <= 8'd0;
        stable_recognized      <= 1'b0;
        stable_type            <= 2'd0;
        previous_report_enable <= 1'b0;
        previous_auto_report_active <= 1'b0;
        report_counter         <= 32'd0;
        auto_pending           <= 1'b0;
        query_pending          <= 1'b0;
        sending                <= 1'b0;
        waiting_done           <= 1'b0;
        char_index             <= 4'd0;
        message_status         <= STATUS_NONE;
    end else begin
        previous_report_enable <= report_enable;
        previous_auto_report_active <= auto_report_active;

        if (query_pulse)
            query_pending <= 1'b1;

        // One sample per video frame prevents a noisy single frame from being
        // announced as a recognized object.
        if (frame_tick) begin
            if (shape_is_recognized) begin
                if (candidate_type == shape_type) begin
                    if (candidate_count < STABLE_FRAMES)
                        candidate_count <= candidate_count + 8'd1;

                    if (!stable_recognized &&
                        ((candidate_count + 8'd1) >= STABLE_FRAMES)) begin
                        stable_recognized <= 1'b1;
                        stable_type       <= shape_type;
                        if (report_enable)
                            auto_pending <= 1'b1;
                    end
                end else begin
                    candidate_type    <= shape_type;
                    candidate_count   <= 8'd1;
                    stable_recognized <= (STABLE_FRAMES <= 1);
                    stable_type       <= shape_type;
                    if (report_enable && (STABLE_FRAMES <= 1))
                        auto_pending <= 1'b1;
                end
            end else begin
                candidate_type    <= 2'd0;
                candidate_count   <= 8'd0;
                stable_recognized <= 1'b0;
                stable_type       <= 2'd0;
                auto_pending      <= 1'b0;
            end
        end

        // Report twice per second while a stable recognized shape remains.
        if (report_enable && auto_report_active) begin
            if ((!previous_report_enable && report_enable) ||
                !previous_auto_report_active) begin
                report_counter <= 32'd0;
                auto_pending   <= 1'b1;
            end else if (report_counter >= (REPORT_INTERVAL - 1)) begin
                report_counter <= 32'd0;
                auto_pending   <= 1'b1;
            end else begin
                report_counter <= report_counter + 32'd1;
            end
        end else begin
            report_counter <= 32'd0;
            if (!report_enable)
                auto_pending <= 1'b0;
        end

        if (!sending) begin
            if (query_pending || query_pulse) begin
                sending       <= 1'b1;
                waiting_done  <= 1'b0;
                char_index    <= 4'd0;
                query_pending <= 1'b0;

                if (stable_recognized)
                    message_status <= (stable_type == 2'd2) ?
                                      STATUS_CIRCLE : STATUS_RECT;
                else if (shape_valid)
                    message_status <= STATUS_WAIT;
                else
                    message_status <= STATUS_NONE;
            end else if (auto_pending && report_enable && auto_report_active) begin
                sending       <= 1'b1;
                waiting_done  <= 1'b0;
                char_index    <= 4'd0;
                auto_pending  <= 1'b0;
                if (stable_recognized)
                    message_status <= (stable_type == 2'd2) ?
                                      STATUS_CIRCLE : STATUS_RECT;
                else if (shape_valid)
                    message_status <= STATUS_WAIT;
                else
                    message_status <= STATUS_NONE;
            end
        end else begin
            if (tx_accept)
                waiting_done <= 1'b1;

            if (waiting_done && tx_done) begin
                waiting_done <= 1'b0;
                if (tx_last) begin
                    sending    <= 1'b0;
                    char_index <= 4'd0;
                end else begin
                    char_index <= char_index + 4'd1;
                end
            end
        end
    end
end

endmodule
