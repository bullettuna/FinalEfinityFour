`timescale 1ns/1ps

/******************************************************************************
 * Streaming connected-component core derived from LinkRunCCA.
 *
 * Original work Copyright (C) 2016 J.W. Tang
 * Verilog integration/namespacing Copyright (C) 2026 project contributors
 *
 * This file is licensed under the GNU Lesser General Public License, version
 * 3 or (at your option) any later version. It is derived from:
 *   https://github.com/Topi-ab/linkruncca
 *
 * Please cite:
 * J. W. Tang et al., "A linked list run-length-based single-pass connected
 * component analysis for real-time embedded hardware," Journal of Real-Time
 * Image Processing, 2016. doi:10.1007/s11554-016-0590-2.
 *
 * Local changes:
 *   - namespace all module names with linkruncca_
 *   - expose image dimensions as module parameters
 *   - add reset inputs to the pixel window and row-delay registers
 *   - use ANSI-style ports so width errors are caught during elaboration
 ******************************************************************************/

module linkruncca_core #(
    parameter integer IMAGE_WIDTH  = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer X_BITS       = $clog2(IMAGE_WIDTH),
    parameter integer Y_BITS       = $clog2(IMAGE_HEIGHT),
    parameter integer ADDRESS_BITS = X_BITS - 1,
    parameter integer DATA_BITS    = 2 * (X_BITS + Y_BITS),
    parameter integer LATENCY      = 3
) (
    input                       clk,
    input                       rst,
    input                       datavalid,
    input                       pix_in,
    output reg                  datavalid_out,
    output reg [DATA_BITS-1:0]  box_out,
    output reg                  label_overflow
);

wire [ADDRESS_BITS-1:0] next_waddr, next_wdata, next_raddr, next_rdata;
wire [ADDRESS_BITS-1:0] head_waddr, head_wdata, head_raddr, head_rdata;
wire [ADDRESS_BITS-1:0] tail_waddr, tail_wdata, tail_raddr, tail_rdata;
wire [ADDRESS_BITS-1:0] data_raddr, data_waddr;
wire [DATA_BITS-1:0] data_rdata, data_wdata;
wire next_we, head_we, tail_we, data_we;

wire win_a, win_b, win_c, win_d;
wire row_previous_1, row_previous_2;
wire first_previous, first_next;
wire output_event, head_changed, data_accumulate, data_merge, clear_data;
wire end_of_component;
wire [ADDRESS_BITS-1:0] previous_label;
wire [ADDRESS_BITS-1:0] previous_head;
wire [ADDRESS_BITS-1:0] previous_tail;
wire [ADDRESS_BITS-1:0] previous_next;
wire [DATA_BITS-1:0] previous_data;
wire [DATA_BITS-1:0] accumulated_data;
wire filler_left, filler_previous, filler_out;
reg [ADDRESS_BITS-1:0] run_guard_count;

linkruncca_table_ram #(.DATA_WIDTH(ADDRESS_BITS), .ADDR_WIDTH(ADDRESS_BITS))
    u_next_table (
        .clk(clk), .we(next_we && datavalid),
        .write_addr(next_waddr), .data(next_wdata),
        .read_addr(next_raddr), .q(next_rdata)
    );

linkruncca_table_ram #(.DATA_WIDTH(ADDRESS_BITS), .ADDR_WIDTH(ADDRESS_BITS))
    u_head_table (
        .clk(clk), .we(head_we && datavalid),
        .write_addr(head_waddr), .data(head_wdata),
        .read_addr(head_raddr), .q(head_rdata)
    );

linkruncca_table_ram #(.DATA_WIDTH(ADDRESS_BITS), .ADDR_WIDTH(ADDRESS_BITS))
    u_tail_table (
        .clk(clk), .we(tail_we && datavalid),
        .write_addr(tail_waddr), .data(tail_wdata),
        .read_addr(tail_raddr), .q(tail_rdata)
    );

linkruncca_table_ram #(.DATA_WIDTH(DATA_BITS), .ADDR_WIDTH(ADDRESS_BITS))
    u_data_table (
        .clk(clk), .we(data_we && datavalid),
        .write_addr(data_waddr), .data(data_wdata),
        .read_addr(data_raddr), .q(data_rdata)
    );

linkruncca_holes_filler u_holes_filler (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .pix_in_current(pix_in), .pix_in_previous(filler_previous),
    .left(filler_left), .pix_out(filler_out)
);

linkruncca_row_buffer #(.LENGTH(IMAGE_WIDTH - 2)) u_filler_row_buffer (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .pix_in(filler_left), .pix_out1(filler_previous), .pix_out2()
);

linkruncca_window u_window (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .pix_in_current(filler_out), .pix_in_previous(row_previous_1),
    .a(win_a), .b(win_b), .c(win_c), .d(win_d)
);

linkruncca_row_buffer #(.LENGTH(IMAGE_WIDTH - 2)) u_row_buffer (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .pix_in(win_c), .pix_out1(row_previous_1), .pix_out2(row_previous_2)
);

linkruncca_table_reader #(
    .ADDRESS_BITS(ADDRESS_BITS), .DATA_BITS(DATA_BITS)
) u_table_reader (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .a(win_a), .b(win_b), .row_previous_1(row_previous_1),
    .row_previous_2(row_previous_2), .accumulated_data(accumulated_data),
    .output_event(output_event), .head_changed(head_changed),
    .data_we(data_we), .data_waddr(data_waddr),
    .head_rdata(head_rdata), .tail_rdata(tail_rdata),
    .next_rdata(next_rdata), .data_rdata(data_rdata),
    .head_wdata(head_wdata), .tail_wdata(tail_wdata),
    .head_raddr(head_raddr), .tail_raddr(tail_raddr),
    .next_raddr(next_raddr), .data_raddr(data_raddr),
    .previous_label(previous_label), .previous_head(previous_head),
    .previous_next(previous_next), .previous_tail(previous_tail),
    .previous_data(previous_data), .first_previous(first_previous),
    .first_next(first_next)
);

linkruncca_equivalence_resolver #(
    .ADDRESS_BITS(ADDRESS_BITS), .DATA_BITS(DATA_BITS)
) u_equivalence_resolver (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .a(win_a), .b(win_b), .c(win_c), .d(win_d),
    .previous_label(previous_label), .previous_head(previous_head),
    .previous_next(previous_next), .previous_tail(previous_tail),
    .previous_data(previous_data), .first_previous(first_previous),
    .first_next(first_next), .accumulated_data(accumulated_data),
    .head_we(head_we), .tail_we(tail_we), .next_we(next_we),
    .data_we(data_we), .head_waddr(head_waddr),
    .tail_waddr(tail_waddr), .next_waddr(next_waddr),
    .data_waddr(data_waddr), .head_wdata(head_wdata),
    .tail_wdata(tail_wdata), .next_wdata(next_wdata),
    .data_wdata(data_wdata), .head_changed(head_changed),
    .data_accumulate(data_accumulate), .data_merge(data_merge),
    .clear_data(clear_data), .end_of_component(end_of_component),
    .output_event(output_event)
);

linkruncca_feature_accumulator #(
    .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
    .X_BITS(X_BITS), .Y_BITS(Y_BITS), .DATA_BITS(DATA_BITS),
    .LATENCY(LATENCY)
) u_feature_accumulator (
    .clk(clk), .rst(rst), .datavalid(datavalid),
    .data_accumulate(data_accumulate), .data_merge(data_merge),
    .clear_data(clear_data), .previous_data(previous_data),
    .accumulated_data(accumulated_data)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        datavalid_out <= 1'b0;
        box_out       <= {DATA_BITS{1'b0}};
        label_overflow <= 1'b0;
        run_guard_count <= {ADDRESS_BITS{1'b0}};
    end else begin
        datavalid_out <= 1'b0;
        if (datavalid) begin
            // Both LinkRunCCA label counters advance once per completed run.
            // Mark the whole frame invalid before either counter can wrap and
            // alias a live table entry.
            if (win_c && !win_d) begin
                if (&run_guard_count)
                    label_overflow <= 1'b1;
                else
                    run_guard_count <= run_guard_count + 1'b1;
            end
            box_out <= previous_data;
            if (end_of_component)
                datavalid_out <= 1'b1;
        end
    end
end

endmodule


module linkruncca_table_ram #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 10
) (
    input                       clk,
    input                       we,
    input      [ADDR_WIDTH-1:0] write_addr,
    input      [DATA_WIDTH-1:0] data,
    input      [ADDR_WIDTH-1:0] read_addr,
    output     [DATA_WIDTH-1:0] q
);

(* ram_style = "block", syn_ramstyle = "block_ram" *)
reg [DATA_WIDTH-1:0] ram [0:(1 << ADDR_WIDTH)-1];
reg [ADDR_WIDTH-1:0] read_addr_reg;

always @(posedge clk) begin
    read_addr_reg = read_addr;
    if (we)
        ram[write_addr] = data;
end

assign q = ram[read_addr_reg];

endmodule


module linkruncca_holes_filler (
    input  clk,
    input  rst,
    input  datavalid,
    input  pix_in_current,
    input  pix_in_previous,
    output reg left,
    output pix_out
);

reg top_pixel;
reg center_pixel;
reg right_pixel;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        top_pixel    <= 1'b0;
        left         <= 1'b0;
        center_pixel <= 1'b0;
        right_pixel  <= 1'b0;
    end else if (datavalid) begin
        top_pixel    <= pix_in_previous;
        left         <= center_pixel;
        center_pixel <= right_pixel;
        right_pixel  <= pix_in_current;
    end
end

assign pix_out = (top_pixel && (left || right_pixel)) ? 1'b1 : center_pixel;

endmodule


module linkruncca_row_buffer #(
    parameter integer LENGTH = 640
) (
    input  clk,
    input  rst,
    input  datavalid,
    input  pix_in,
    output pix_out1,
    output pix_out2
);

reg [LENGTH-1:0] row_delay;

always @(posedge clk or posedge rst) begin
    if (rst)
        row_delay <= {LENGTH{1'b0}};
    else if (datavalid) begin
        row_delay[LENGTH-1:1] <= row_delay[LENGTH-2:0];
        row_delay[0]          <= pix_in;
    end
end

assign pix_out1 = row_delay[LENGTH-1];
assign pix_out2 = row_delay[LENGTH-2];

endmodule


module linkruncca_window (
    input  clk,
    input  rst,
    input  datavalid,
    input  pix_in_current,
    input  pix_in_previous,
    output reg a,
    output reg b,
    output reg c,
    output reg d
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        a <= 1'b0;
        b <= 1'b0;
        c <= 1'b0;
        d <= 1'b0;
    end else if (datavalid) begin
        a <= b;
        b <= pix_in_previous;
        c <= d;
        d <= pix_in_current;
    end
end

endmodule


module linkruncca_feature_accumulator #(
    parameter integer IMAGE_WIDTH  = 512,
    parameter integer IMAGE_HEIGHT = 512,
    parameter integer X_BITS       = 9,
    parameter integer Y_BITS       = 9,
    parameter integer DATA_BITS    = 36,
    parameter integer LATENCY      = 3
) (
    input                       clk,
    input                       rst,
    input                       datavalid,
    input                       data_accumulate,
    input                       data_merge,
    input                       clear_data,
    input      [DATA_BITS-1:0] previous_data,
    output reg [DATA_BITS-1:0] accumulated_data
);

localparam integer RESET_X = IMAGE_WIDTH - LATENCY;
localparam integer RESET_Y = IMAGE_HEIGHT - 1;

reg [X_BITS-1:0] x_pos;
reg [Y_BITS-1:0] y_pos;

wire [X_BITS-1:0] current_min_x = accumulated_data[DATA_BITS-1:DATA_BITS-X_BITS];
wire [X_BITS-1:0] current_max_x = accumulated_data[DATA_BITS-X_BITS-1:2*Y_BITS];
wire [Y_BITS-1:0] current_min_y = accumulated_data[2*Y_BITS-1:Y_BITS];
wire [Y_BITS-1:0] current_max_y = accumulated_data[Y_BITS-1:0];

wire [X_BITS-1:0] accumulated_min_x =
    (data_accumulate && (x_pos < current_min_x)) ? x_pos : current_min_x;
wire [X_BITS-1:0] accumulated_max_x =
    (data_accumulate && (x_pos > current_max_x)) ? x_pos : current_max_x;
wire [Y_BITS-1:0] accumulated_min_y =
    (data_accumulate && (y_pos < current_min_y)) ? y_pos : current_min_y;
wire [Y_BITS-1:0] accumulated_max_y =
    (data_accumulate && (y_pos > current_max_y)) ? y_pos : current_max_y;

wire [X_BITS-1:0] merged_min_x =
    (data_merge &&
     (previous_data[DATA_BITS-1:DATA_BITS-X_BITS] < accumulated_min_x)) ?
    previous_data[DATA_BITS-1:DATA_BITS-X_BITS] : accumulated_min_x;
wire [X_BITS-1:0] merged_max_x =
    (data_merge &&
     (previous_data[DATA_BITS-X_BITS-1:2*Y_BITS] > accumulated_max_x)) ?
    previous_data[DATA_BITS-X_BITS-1:2*Y_BITS] : accumulated_max_x;
wire [Y_BITS-1:0] merged_min_y =
    (data_merge &&
     (previous_data[2*Y_BITS-1:Y_BITS] < accumulated_min_y)) ?
    previous_data[2*Y_BITS-1:Y_BITS] : accumulated_min_y;
wire [Y_BITS-1:0] merged_max_y =
    (data_merge &&
     (previous_data[Y_BITS-1:0] > accumulated_max_y)) ?
    previous_data[Y_BITS-1:0] : accumulated_max_y;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        x_pos <= RESET_X[X_BITS-1:0];
        y_pos <= RESET_Y[Y_BITS-1:0];
    end else if (datavalid) begin
        if (x_pos == (IMAGE_WIDTH - 1)) begin
            x_pos <= {X_BITS{1'b0}};
            if (y_pos == (IMAGE_HEIGHT - 1))
                y_pos <= {Y_BITS{1'b0}};
            else
                y_pos <= y_pos + 1'b1;
        end else begin
            x_pos <= x_pos + 1'b1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        accumulated_data <= {
            {X_BITS{1'b1}}, {X_BITS{1'b0}},
            {Y_BITS{1'b1}}, {Y_BITS{1'b0}}
        };
    end else if (datavalid) begin
        if (clear_data) begin
            accumulated_data <= {
                {X_BITS{1'b1}}, {X_BITS{1'b0}},
                {Y_BITS{1'b1}}, {Y_BITS{1'b0}}
            };
        end else begin
            accumulated_data <= {
                merged_min_x, merged_max_x, merged_min_y, merged_max_y
            };
        end
    end
end

endmodule


module linkruncca_equivalence_resolver #(
    parameter integer ADDRESS_BITS = 9,
    parameter integer DATA_BITS    = 36
) (
    input                       clk,
    input                       rst,
    input                       datavalid,
    input                       a,
    input                       b,
    input                       c,
    input                       d,
    input      [ADDRESS_BITS-1:0] previous_label,
    input      [ADDRESS_BITS-1:0] previous_head,
    input      [ADDRESS_BITS-1:0] previous_next,
    input      [ADDRESS_BITS-1:0] previous_tail,
    input      [DATA_BITS-1:0] previous_data,
    input                       first_previous,
    input                       first_next,
    input      [DATA_BITS-1:0] accumulated_data,
    output reg                  head_we,
    output reg                  tail_we,
    output reg                  next_we,
    output reg                  data_we,
    output reg [ADDRESS_BITS-1:0] head_waddr,
    output reg [ADDRESS_BITS-1:0] tail_waddr,
    output reg [ADDRESS_BITS-1:0] next_waddr,
    output reg [ADDRESS_BITS-1:0] data_waddr,
    output reg [ADDRESS_BITS-1:0] head_wdata,
    output reg [ADDRESS_BITS-1:0] tail_wdata,
    output reg [ADDRESS_BITS-1:0] next_wdata,
    output reg [DATA_BITS-1:0] data_wdata,
    output                      head_changed,
    output                      data_accumulate,
    output                      data_merge,
    output                      clear_data,
    output reg                  end_of_component,
    output                      output_event
);

reg [ADDRESS_BITS-1:0] component_counter;
reg [ADDRESS_BITS-1:0] cached_head;
reg first_flag;
reg head_before_flag;

wire end_current_run  = c && !d;
wire end_previous_run = a && !b;

assign output_event    = b && d && (!a || !c);
assign data_merge      = output_event && !(first_flag && (previous_head == cached_head));
assign data_accumulate = d;
assign clear_data      = end_current_run;
assign head_changed    = head_before_flag && (previous_next == previous_label);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        component_counter <= {ADDRESS_BITS{1'b0}};
        cached_head       <= {ADDRESS_BITS{1'b0}};
        first_flag        <= 1'b0;
    end else if (datavalid) begin
        if (end_current_run) begin
            component_counter <= component_counter + 1'b1;
            first_flag        <= 1'b0;
        end else if (output_event) begin
            cached_head <= head_wdata;
            first_flag  <= 1'b1;
        end
    end
end

always @* begin
    head_we          = 1'b0;
    head_waddr       = {ADDRESS_BITS{1'b0}};
    head_wdata       = {ADDRESS_BITS{1'b0}};
    tail_we          = 1'b0;
    tail_waddr       = {ADDRESS_BITS{1'b0}};
    tail_wdata       = {ADDRESS_BITS{1'b0}};
    next_we          = 1'b0;
    next_waddr       = {ADDRESS_BITS{1'b0}};
    next_wdata       = {ADDRESS_BITS{1'b0}};
    data_we          = 1'b0;
    data_waddr       = {ADDRESS_BITS{1'b0}};
    data_wdata       = {DATA_BITS{1'b0}};
    end_of_component = 1'b0;
    head_before_flag = 1'b0;

    if (end_current_run) begin
        next_we    = 1'b1;
        next_waddr = component_counter;
        next_wdata = component_counter;
        head_we    = 1'b1;
        head_waddr = component_counter;
        head_wdata = component_counter;
        if (!first_flag) begin
            data_we    = 1'b1;
            data_waddr = component_counter;
            data_wdata = accumulated_data;
        end else begin
            data_we    = 1'b1;
            data_waddr = cached_head;
            data_wdata = accumulated_data;
        end
    end else if (end_previous_run) begin
        if (!first_previous) begin
            data_we    = 1'b1;
            data_waddr = previous_next;
            data_wdata = previous_data;
            if (first_next)
                end_of_component = 1'b1;
        end else begin
            head_we          = 1'b1;
            head_waddr       = previous_next;
            head_wdata       = previous_head;
            head_before_flag = 1'b1;
        end
    end else if (output_event) begin
        case ({first_flag, first_previous})
            2'b00: begin
                head_we    = 1'b1;
                head_waddr = previous_next;
                head_wdata = component_counter;
                tail_we    = 1'b1;
                tail_waddr = head_wdata;
                tail_wdata = component_counter;
            end
            2'b01: begin
                head_we    = 1'b1;
                head_waddr = previous_next;
                head_wdata = previous_head;
                tail_we    = 1'b1;
                tail_waddr = head_wdata;
                tail_wdata = component_counter;
                next_we    = 1'b1;
                next_waddr = previous_tail;
                next_wdata = component_counter;
            end
            2'b10: begin
                head_we    = 1'b1;
                head_waddr = previous_next;
                head_wdata = cached_head;
                tail_we    = 1'b1;
                tail_waddr = head_wdata;
                tail_wdata = component_counter;
            end
            default: begin
                head_we    = 1'b1;
                head_waddr = previous_next;
                head_wdata = previous_head;
                tail_we    = 1'b1;
                tail_waddr = head_wdata;
                tail_wdata = component_counter;
                next_we    = 1'b1;
                next_waddr = previous_tail;
                next_wdata = cached_head;
            end
        endcase
    end
end

endmodule


module linkruncca_table_reader #(
    parameter integer ADDRESS_BITS = 9,
    parameter integer DATA_BITS    = 36
) (
    input                       clk,
    input                       rst,
    input                       datavalid,
    input                       a,
    input                       b,
    input                       row_previous_1,
    input                       row_previous_2,
    input      [DATA_BITS-1:0] accumulated_data,
    input                       output_event,
    input                       head_changed,
    input                       data_we,
    input      [ADDRESS_BITS-1:0] data_waddr,
    input      [ADDRESS_BITS-1:0] head_rdata,
    input      [ADDRESS_BITS-1:0] tail_rdata,
    input      [ADDRESS_BITS-1:0] next_rdata,
    input      [DATA_BITS-1:0] data_rdata,
    input      [ADDRESS_BITS-1:0] head_wdata,
    input      [ADDRESS_BITS-1:0] tail_wdata,
    output     [ADDRESS_BITS-1:0] head_raddr,
    output     [ADDRESS_BITS-1:0] tail_raddr,
    output     [ADDRESS_BITS-1:0] next_raddr,
    output     [ADDRESS_BITS-1:0] data_raddr,
    output reg [ADDRESS_BITS-1:0] previous_label,
    output reg [ADDRESS_BITS-1:0] previous_head,
    output reg [ADDRESS_BITS-1:0] previous_next,
    output     [ADDRESS_BITS-1:0] previous_tail,
    output     [DATA_BITS-1:0] previous_data,
    output reg                  first_previous,
    output reg                  first_next
);

reg [ADDRESS_BITS-1:0] label_counter;
reg [ADDRESS_BITS-1:0] cached_tail;
reg [DATA_BITS-1:0] cached_data;

wire data_cache_needed = data_we && (data_waddr == previous_head);

assign next_raddr = label_counter;
assign head_raddr = label_counter;
assign tail_raddr = head_changed ? head_wdata : head_rdata;
assign data_raddr = head_changed ? head_wdata : head_rdata;
assign previous_tail = (!a && b) ? tail_rdata : cached_tail;
assign previous_data = (!a && b) ? data_rdata : cached_data;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        label_counter  <= {ADDRESS_BITS{1'b0}};
        previous_label <= {ADDRESS_BITS{1'b0}};
    end else if (datavalid) begin
        previous_label <= label_counter;
        if (row_previous_1 && !row_previous_2)
            label_counter <= label_counter + 1'b1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        previous_next <= {ADDRESS_BITS{1'b0}};
        previous_head <= {ADDRESS_BITS{1'b0}};
        first_previous <= 1'b0;
        first_next     <= 1'b0;
        cached_tail    <= {ADDRESS_BITS{1'b0}};
        cached_data    <= {DATA_BITS{1'b0}};
    end else if (datavalid) begin
        cached_tail <= previous_tail;
        cached_data <= previous_data;
        if (data_cache_needed)
            cached_data <= accumulated_data;

        if (!b && row_previous_1) begin
            previous_head  <= tail_raddr;
            first_previous <= (tail_raddr != previous_label);
            previous_next  <= next_rdata;
            first_next     <= (next_rdata == previous_label);
        end else if (output_event) begin
            cached_tail    <= tail_wdata;
            first_previous <= 1'b1;
            previous_head  <= head_wdata;
        end
    end
end

endmodule
