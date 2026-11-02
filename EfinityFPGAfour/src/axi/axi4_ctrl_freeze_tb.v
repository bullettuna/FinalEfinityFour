`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Self-checking frame-index scheduler test for axi4_ctrl freeze behavior.
// FIFO primitives are stubbed because this test isolates the DDR frame selector.
//////////////////////////////////////////////////////////////////////////////////

module W0_FIFO_32 (
    input wire wr_clk_i,
    input wire wr_en_i,
    input wire [31:0] wdata,
    input wire a_rst_i,
    input wire rd_clk_i,
    input wire rd_en_i,
    output wire [127:0] rdata,
    output wire prog_empty_o,
    output wire empty_o
);
assign rdata = 128'd0;
assign prog_empty_o = 1'b1;
assign empty_o = 1'b1;
endmodule

module R0_FIFO_8 (
    input wire wr_clk_i,
    input wire wr_en_i,
    input wire [127:0] wdata,
    input wire a_rst_i,
    output wire prog_full_o,
    input wire rd_clk_i,
    input wire rd_en_i,
    output wire [7:0] rdata,
    output wire empty_o,
    output wire almost_empty_o
);
assign prog_full_o = 1'b0;
assign rdata = 8'd0;
assign empty_o = 1'b1;
assign almost_empty_o = 1'b1;
endmodule

module axi4_ctrl_freeze_tb;

reg axi_clk;
reg axi_reset;
reg freeze_i;
reg wframe_vsync;
reg wframe_data_en;
reg [31:0] wframe_data;
reg rframe_vsync;
reg rframe_data_en;
reg forced_read_complete;
reg forced_write_complete;

wire [7:0] axi_awid;
wire [31:0] axi_awaddr;
wire [7:0] axi_awlen;
wire [2:0] axi_awsize;
wire [1:0] axi_awburst;
wire axi_awlock;
wire [3:0] axi_awcache;
wire [2:0] axi_awprot;
wire [3:0] axi_awqos;
wire axi_awvalid;
wire [127:0] axi_wdata;
wire [15:0] axi_wstrb;
wire axi_wlast;
wire axi_wvalid;
wire axi_bready;
wire [7:0] axi_arid;
wire [31:0] axi_araddr;
wire [7:0] axi_arlen;
wire [2:0] axi_arsize;
wire [1:0] axi_arburst;
wire axi_arlock;
wire [3:0] axi_arcache;
wire [2:0] axi_arprot;
wire [3:0] axi_arqos;
wire axi_arvalid;
wire axi_rready;
wire [7:0] rframe_data;
wire [31:0] tp_o;

axi4_ctrl #(
    .C_W_WIDTH(32),
    .C_R_WIDTH(8)
) dut (
    .axi_clk(axi_clk),
    .axi_reset(axi_reset),
    .axi_awid(axi_awid),
    .axi_awaddr(axi_awaddr),
    .axi_awlen(axi_awlen),
    .axi_awsize(axi_awsize),
    .axi_awburst(axi_awburst),
    .axi_awlock(axi_awlock),
    .axi_awcache(axi_awcache),
    .axi_awprot(axi_awprot),
    .axi_awqos(axi_awqos),
    .axi_awvalid(axi_awvalid),
    .axi_awready(1'b0),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wlast(axi_wlast),
    .axi_wvalid(axi_wvalid),
    .axi_wready(1'b0),
    .axi_bid(8'd0),
    .axi_bresp(2'd0),
    .axi_bvalid(1'b0),
    .axi_bready(axi_bready),
    .axi_arid(axi_arid),
    .axi_araddr(axi_araddr),
    .axi_arlen(axi_arlen),
    .axi_arsize(axi_arsize),
    .axi_arburst(axi_arburst),
    .axi_arlock(axi_arlock),
    .axi_arcache(axi_arcache),
    .axi_arprot(axi_arprot),
    .axi_arqos(axi_arqos),
    .axi_arvalid(axi_arvalid),
    .axi_arready(1'b0),
    .axi_rid(8'd0),
    .axi_rdata(128'd0),
    .axi_rresp(2'd0),
    .axi_rlast(1'b0),
    .axi_rvalid(1'b0),
    .axi_rready(axi_rready),
    .wframe_pclk(axi_clk),
    .wframe_vsync(wframe_vsync),
    .wframe_data_en(wframe_data_en),
    .wframe_data(wframe_data),
    .rframe_pclk(axi_clk),
    .rframe_vsync(rframe_vsync),
    .rframe_data_en(rframe_data_en),
    .rframe_data(rframe_data),
    .freeze_i(freeze_i),
    .photo_write_valid_i(1'b0),.photo_load_start_i(1'b0),.photo_load_end_i(1'b1),
    .photo_read_enable_i(1'b0),.photo_read_buffer_i(1'b0),.photo_rframe_pclk(axi_clk),
    .photo_rframe_vsync(rframe_vsync),.photo_rframe_data_en(1'b0),
    .read_underflow_sticky(),
    .read_underflow_count(),
    .bad_frame_sticky(),
    .bad_frame_count(),
    .tp_o(tp_o)
);

always #5 axi_clk = ~axi_clk;

task pulse_frame_events;
    input read_complete;
    input write_complete;
    begin
        @(negedge axi_clk);
        forced_read_complete = read_complete;
        forced_write_complete = write_complete;
        force dut.r_rframe_inc = forced_read_complete;
        force dut.r_wframe_inc = forced_write_complete;
        @(posedge axi_clk);
        #1;
        release dut.r_rframe_inc;
        release dut.r_wframe_inc;
    end
endtask

task check_indices;
    input [1:0] expected_write;
    input [1:0] expected_read;
    input [1:0] expected_last;
    begin
        if ((dut.rc_wframe_index !== expected_write) ||
            (dut.rc_rframe_index !== expected_read) ||
            (dut.r_wframe_index_last !== expected_last)) begin
            $display("FAIL indices expected write=%0d read=%0d last=%0d, got write=%0d read=%0d last=%0d",
                     expected_write, expected_read, expected_last,
                     dut.rc_wframe_index, dut.rc_rframe_index, dut.r_wframe_index_last);
            $fatal(1,"freeze regression failed");
        end
    end
endtask

initial begin
    axi_clk = 1'b0;
    axi_reset = 1'b1;
    freeze_i = 1'b0;
    wframe_vsync = 1'b0;
    wframe_data_en = 1'b0;
    wframe_data = 32'd0;
    rframe_vsync = 1'b0;
    rframe_data_en = 1'b0;
    forced_read_complete = 1'b0;
    forced_write_complete = 1'b0;

    repeat (4) @(posedge axi_clk);
    @(negedge axi_clk);
    axi_reset = 1'b0;
    @(posedge axi_clk);
    #1;
    check_indices(2'd0, 2'd2, 2'd0);

    // Establish a completed frame and select it for live display.
    pulse_frame_events(1'b0, 1'b1);
    check_indices(2'd1, 2'd2, 2'd0);
    pulse_frame_events(1'b1, 1'b0);
    check_indices(2'd1, 2'd0, 2'd0);

    freeze_i = 1'b1;

    // Capture keeps rotating while both read-only and simultaneous frame events
    // are prevented from changing the frozen display slot.
    pulse_frame_events(1'b1, 1'b1);
    check_indices(2'd2, 2'd0, 2'd1);
    pulse_frame_events(1'b0, 1'b1);
    check_indices(2'd3, 2'd0, 2'd2);
    pulse_frame_events(1'b1, 1'b0);
    check_indices(2'd3, 2'd0, 2'd2);
    pulse_frame_events(1'b1, 1'b1);
    check_indices(2'd1, 2'd0, 2'd3);

    // Unfreeze selects the latest complete captured frame at the next display
    // boundary. A simultaneous live event also follows the just-completed write.
    freeze_i = 1'b0;
    pulse_frame_events(1'b1, 1'b0);
    check_indices(2'd1, 2'd3, 2'd3);
    pulse_frame_events(1'b1, 1'b1);
    check_indices(2'd2, 2'd1, 2'd1);

    $display("PASS AXI live-frame freeze/unfreeze; no background capture path");
    $finish;
end

endmodule
