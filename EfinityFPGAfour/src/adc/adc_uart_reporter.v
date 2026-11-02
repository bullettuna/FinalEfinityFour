`timescale 1ns/1ps
// Only debounced ADC key events produce UART lines. ADC values never stream.
module adc_uart_reporter (
    input clk, input rst_n,
    input key_event, input [1:0] key_code,
    output tx_valid, output reg [7:0] tx_data, output tx_last,
    input tx_accept, input tx_done
);
reg [1:0] queue[0:15];
reg [3:0] wp,rp;
reg [4:0] queue_count;
reg sending,waiting;
reg [1:0] active_key;
reg [3:0] byte_index;
wire pop_key = !sending && queue_count != 0;
wire put_key = key_event && (queue_count < 16 || pop_key);
wire [3:0] last_index = active_key == 3 ? 4'd9 : 4'd7;
assign tx_valid = sending && !waiting;
assign tx_last = sending && byte_index == last_index;
always @* begin
    tx_data = 8'h00;
    case (byte_index)
        0: tx_data="k"; 1: tx_data="e"; 2: tx_data="y";
        3,4: tx_data=" ";
        5: tx_data = active_key == 2 ? "3" : "2";
        6: tx_data = active_key == 3 ? "+" : 8'h0d;
        7: tx_data = active_key == 3 ? "3" : 8'h0a;
        8: tx_data=8'h0d; 9: tx_data=8'h0a;
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wp<=0; rp<=0; queue_count<=0;
        sending<=0; waiting<=0;
        active_key<=0; byte_index<=0;
    end else begin
        if (put_key) begin queue[wp]<=key_code; wp<=wp+1'b1; end
        if (pop_key) rp<=rp+1'b1;
        case ({put_key,pop_key})
            2'b10: queue_count<=queue_count+1'b1;
            2'b01: queue_count<=queue_count-1'b1;
            default: queue_count<=queue_count;
        endcase
        if (pop_key) begin
            active_key<=queue[rp]; sending<=1; waiting<=0; byte_index<=0;
        end else if (tx_valid && tx_accept) waiting<=1;
        else if (waiting && tx_done) begin
            waiting<=0;
            if (byte_index==last_index) sending<=0;
            else byte_index<=byte_index+1'b1;
        end
    end
end
endmodule
