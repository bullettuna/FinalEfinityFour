`timescale 1ns/1ps
// Decode the real UART wire, including arbitration and byte completion.
module key_uart_reporter_tb;
reg clk=0, rst_n=0, key_n=1, cmd_start=0;
wire valid, last, accept, done, phy_start, phy_done, serial_tx;
wire [7:0] data, phy_data;
reg [7:0] received[0:127];
integer received_count=0;
always #5 clk=~clk;
key_uart_reporter #(.DEBOUNCE_CYCLES(20)) dut (
    .clk(clk), .rst_n(rst_n), .key_n(key_n),
    .tx_valid(valid), .tx_data(data), .tx_last(last), .tx_accept(accept), .tx_done(done)
);
uart_tx_arbiter arb (
    .clk(clk), .rst_n(rst_n), .cmd_tx_start(cmd_start), .cmd_tx_data(8'h21), .cmd_tx_done(),
    .msg_tx_valid(1'b0), .msg_tx_data(8'd0), .msg_tx_last(1'b0), .msg_tx_accept(), .msg_tx_done(),
    .msg2_tx_valid(1'b0), .msg2_tx_data(8'd0), .msg2_tx_last(1'b0), .msg2_tx_accept(), .msg2_tx_done(),
    .msg3_tx_valid(valid), .msg3_tx_data(data), .msg3_tx_last(last), .msg3_tx_accept(accept), .msg3_tx_done(done),
    .msg4_tx_valid(1'b0), .msg4_tx_data(8'd0), .msg4_tx_last(1'b0), .msg4_tx_accept(), .msg4_tx_done(),
    .uart_tx_done(phy_done), .uart_tx_data(phy_data), .uart_tx_start(phy_start)
);
// Every clock is a 16x baud tick; one bit lasts 16 clocks.
uart_transfer phy (.clk(clk), .rst_n(rst_n), .clken_16bps(1'b1),
    .txd(serial_tx), .txd_en(phy_start), .txd_data(phy_data), .txd_flag(phy_done));
integer bit_number;
reg [7:0] decoded;
initial forever begin
    @(negedge serial_tx);
    if (rst_n) begin
        repeat(24) @(posedge clk);
        #1;
        for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
            decoded[bit_number]=serial_tx;
            repeat(16) @(posedge clk);
            #1;
        end
        if(serial_tx!==1'b1) $fatal(1,"UART stop bit invalid");
        received[received_count]=decoded;
        received_count=received_count+1;
    end
end
task level(input bit value, input integer clocks);
    @(negedge clk); key_n=value;
    repeat(clocks) @(posedge clk);
endtask
task wait_bytes(input integer count);
    integer watchdog;
    begin
        watchdog=0;
        while(received_count<count && watchdog<15000) begin
            @(negedge clk); watchdog=watchdog+1;
        end
        if(received_count!=count) $fatal(1,"Expected %0d bytes, received %0d",count,received_count);
    end
endtask
task quiet(input integer count);
    repeat(3000) @(negedge clk);
    if(received_count!=count) $fatal(1,"Unexpected repeated or glitch-triggered message");
endtask
task check_line(input integer offset);
    reg [63:0] expected;
    integer n;
    begin
        expected={"key  1",8'h0d,8'h0a};
        for(n=0;n<8;n=n+1)
            if(received[offset+n]!==expected[63-n*8-:8])
                $fatal(1,"Bad line byte %0d: %02x",offset+n,received[offset+n]);
    end
endtask
initial begin
    repeat(5) @(posedge clk);
    @(negedge clk); rst_n=1;
    quiet(0);
    // Short pulses and interrupted low intervals cannot accumulate.
    level(0,19); level(1,8); level(0,7); level(1,30);
    quiet(0);
    // Bouncing press followed by a stable hold yields exactly one line.
    level(0,3); level(1,3); level(0,5); level(1,4); level(0,30);
    wait_bytes(8); check_line(0); quiet(8);
    // Release bounce shorter than the filter cannot re-arm a held button.
    level(1,19); level(0,40); quiet(8);
    level(1,3); level(0,4); level(1,30); quiet(8);
    // A command arriving inside a key line waits until CR/LF is complete.
    level(0,30);
    @(negedge clk); cmd_start=1;
    @(negedge clk); cmd_start=0;
    // Two new presses while UART is busy must both be remembered.
    level(1,30); level(0,30); level(1,30); level(0,30);
    wait_bytes(33);
    check_line(8);
    if(received[16]!=="!") $fatal(1,"Command was lost or interleaved into key line");
    check_line(17); check_line(25); quiet(33);
    // A stable release never emits a message; reset while idle is quiet.
    level(1,30); quiet(33);
    @(negedge clk); rst_n=0;
    repeat(5) @(posedge clk);
    @(negedge clk); rst_n=1;
    quiet(33);
    level(0,30); wait_bytes(41); check_line(33); quiet(41);
    $display("PASS key debounce, bounce rejection, long hold, release re-arm, queued presses, contiguous UART and reset");
    $finish;
end
initial begin #2000000; $fatal(1,"Test timeout"); end
endmodule
