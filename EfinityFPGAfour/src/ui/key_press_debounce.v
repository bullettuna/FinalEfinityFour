`timescale 1ns/1ps

// Active-low board key with a two-flop synchronizer, a debounce window and a
// single-shot long-press detector.  A press shorter than LONG_CYCLES produces
// one short_press pulse on release; a press that reaches LONG_CYCLES produces
// one long_press pulse while held.  Neither event repeats until the key has
// been stably released and pressed again.
module key_press_debounce #(
    parameter integer DEBOUNCE_CYCLES = 1920000,
    parameter integer LONG_CYCLES     = 76800000
)(
    input  clk,
    input  rst_n,
    input  key_n,
    output reg short_press,
    output reg long_press
);
localparam integer DB_WIDTH   = DEBOUNCE_CYCLES < 2 ? 1 : $clog2(DEBOUNCE_CYCLES);
localparam integer HOLD_WIDTH = LONG_CYCLES     < 2 ? 1 : $clog2(LONG_CYCLES);

reg key_meta, key_sync, key_stable, key_stable_d;
reg [DB_WIDTH-1:0]   debounce_count;
reg [HOLD_WIDTH-1:0] hold_count;
reg holding;

wire press_edge = key_stable_d && !key_stable;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_meta       <= 1'b1;
        key_sync       <= 1'b1;
        key_stable     <= 1'b1;
        key_stable_d   <= 1'b1;
        debounce_count <= {DB_WIDTH{1'b0}};
        hold_count     <= {HOLD_WIDTH{1'b0}};
        holding        <= 1'b0;
        short_press    <= 1'b0;
        long_press     <= 1'b0;
    end else begin
        key_meta <= key_n;
        key_sync <= key_meta;
        short_press <= 1'b0;
        long_press  <= 1'b0;

        if (key_sync == key_stable) begin
            debounce_count <= {DB_WIDTH{1'b0}};
        end else if (debounce_count == DEBOUNCE_CYCLES-1) begin
            key_stable     <= key_sync;
            debounce_count <= {DB_WIDTH{1'b0}};
        end else begin
            debounce_count <= debounce_count + 1'b1;
        end

        key_stable_d <= key_stable;

        if (press_edge) begin
            holding    <= 1'b1;
            hold_count <= {HOLD_WIDTH{1'b0}};
        end else if (holding) begin
            if (!key_stable) begin
                if (hold_count == LONG_CYCLES-1) begin
                    long_press <= 1'b1;
                    holding    <= 1'b0;
                end else begin
                    hold_count <= hold_count + 1'b1;
                end
            end else begin
                // Released before the long threshold: this was a short press.
                short_press <= 1'b1;
                holding     <= 1'b0;
            end
        end
    end
end

endmodule
