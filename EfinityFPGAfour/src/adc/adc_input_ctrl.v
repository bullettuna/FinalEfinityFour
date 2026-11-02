`timescale 1ns/1ps
// CH0: eight-sample moving mean. CH1: median-of-three and stable key windows.
module adc_input_ctrl #(
    parameter integer DEBOUNCE_SAMPLES = 20,
    parameter integer RELEASE_MIN = 3900,
    parameter integer SW2_MIN = 1900, SW2_MAX = 2200,
    parameter integer SW3_MIN = 940, SW3_MAX = 1100,
    parameter integer BOTH_MIN = 740, BOTH_MAX = 890
)(
    input clk, input rst_n,
    input sample_valid, input sample_channel, input [11:0] sample_data,
    output reg [11:0] raw_ch0, output reg [11:0] raw_ch1,
    output reg [11:0] knob_value, output reg knob_ready,
    output reg knob_sample,
    output reg [11:0] key_voltage,
    output reg key_event, output reg [1:0] key_code
);
reg [11:0] knob_history[0:7];
reg [14:0] knob_sum;
reg [2:0] knob_index;
reg [3:0] knob_count;
wire [14:0] knob_next_sum = knob_sum - {3'd0,knob_history[knob_index]} + {3'd0,sample_data};
reg [11:0] key_history0, key_history1;
reg [1:0] key_history_count;
function [11:0] median3;
    input [11:0] a,b,c;
    begin
        if (a > b) median3 = b > c ? b : (a > c ? c : a);
        else median3 = a > c ? a : (b > c ? c : b);
    end
endfunction
wire [11:0] key_median = median3(sample_data,key_history0,key_history1);
// 0=release, 1=SW2, 2=SW3, 3=both, 4=outside every valid window.
reg [2:0] decoded_key;
always @* begin
    if (key_median >= RELEASE_MIN) decoded_key = 0;
    else if (key_median >= SW2_MIN && key_median <= SW2_MAX) decoded_key = 1;
    else if (key_median >= SW3_MIN && key_median <= SW3_MAX) decoded_key = 2;
    else if (key_median >= BOTH_MIN && key_median <= BOTH_MAX) decoded_key = 3;
    else decoded_key = 4;
end
localparam integer DB_WIDTH = DEBOUNCE_SAMPLES < 2 ? 1 : $clog2(DEBOUNCE_SAMPLES+1);
reg [DB_WIDTH-1:0] stable_count;
reg [2:0] candidate;
reg armed;
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        raw_ch0 <= 0; raw_ch1 <= 0;
        knob_sum <= 0; knob_index <= 0; knob_count <= 0;
        knob_value <= 0; knob_ready <= 0; knob_sample <= 0;
        for (i=0;i<8;i=i+1) knob_history[i] <= 0;
        key_history0 <= 0; key_history1 <= 0; key_history_count <= 0;
        key_voltage <= 0; candidate <= 4; stable_count <= 0;
        armed <= 0; key_event <= 0; key_code <= 0;
    end else begin
        key_event <= 0;
        knob_sample <= 0;
        if (sample_valid && !sample_channel) begin
            raw_ch0 <= sample_data;
            knob_history[knob_index] <= sample_data;
            knob_index <= knob_index + 1'b1;
            knob_sum <= knob_next_sum;
            if (knob_count < 8) knob_count <= knob_count + 1'b1;
            if (knob_count >= 7) begin
                knob_value <= knob_next_sum[14:3];
                knob_ready <= 1;
                // One-cycle event for consumers that need to act once per
                // averaged sample (the menu settle timer and edit steps).
                knob_sample <= 1;
            end
        end
        if (sample_valid && sample_channel) begin
            raw_ch1 <= sample_data;
            key_history1 <= key_history0;
            key_history0 <= sample_data;
            if (key_history_count < 2) key_history_count <= key_history_count + 1'b1;
            if (key_history_count == 2) begin
                key_voltage <= key_median;
                if (decoded_key == 4) begin
                    candidate <= 4;
                    stable_count <= 0;
                end else begin
                    if (decoded_key != candidate) begin
                        candidate <= decoded_key;
                        stable_count <= 1;
                    end else if (stable_count < DEBOUNCE_SAMPLES)
                        stable_count <= stable_count + 1'b1;
                    if ((decoded_key == candidate && stable_count >= DEBOUNCE_SAMPLES-1) ||
                        DEBOUNCE_SAMPLES == 1) begin
                        if (decoded_key == 0) armed <= 1;
                        else if (armed) begin
                            key_event <= 1;
                            key_code <= decoded_key[1:0];
                            armed <= 0;
                        end
                    end
                end
            end
        end
    end
end
endmodule
