`timescale 1ns/1ps
module adc_uart_reporter_tb;
reg clk=0,rst_n=0,ready=0,event_valid=0,key_n=1,cmd_start=0;
reg [11:0] knob=2048,raw1=4095;
reg [1:0] code=0;
wire valid,last,accept,done,kvalid,klast,kaccept,kdone,phy_start,phy_done,serial_tx;
wire [7:0] data,kdata,phy_data;
always #5 clk=~clk;
adc_uart_reporter dut (
    .clk(clk),.rst_n(rst_n),
    .key_event(event_valid),.key_code(code),.tx_valid(valid),.tx_data(data),
    .tx_last(last),.tx_accept(accept),.tx_done(done));
wire [10:0] high_threshold,low_threshold;
adc_threshold_ctrl threshold_ctrl(.clk(clk),.rst_n(rst_n),.knob_value(knob),.knob_ready(ready),
    .knob_enable(1'b1),
    .uart_update(1'b0),.uart_high(11'd45),.uart_low(11'd22),
    .high_threshold(high_threshold),.low_threshold(low_threshold));
key_uart_reporter #(.DEBOUNCE_CYCLES(20)) gpio_key (.clk(clk),.rst_n(rst_n),.key_n(key_n),
    .tx_valid(kvalid),.tx_data(kdata),.tx_last(klast),.tx_accept(kaccept),.tx_done(kdone));
uart_tx_arbiter arb (
    .clk(clk),.rst_n(rst_n),.cmd_tx_start(cmd_start),.cmd_tx_data(8'h21),.cmd_tx_done(),
    .msg_tx_valid(1'b0),.msg_tx_data(8'd0),.msg_tx_last(1'b0),.msg_tx_accept(),.msg_tx_done(),
    .msg2_tx_valid(1'b0),.msg2_tx_data(8'd0),.msg2_tx_last(1'b0),.msg2_tx_accept(),.msg2_tx_done(),
    .msg3_tx_valid(kvalid),.msg3_tx_data(kdata),.msg3_tx_last(klast),.msg3_tx_accept(kaccept),.msg3_tx_done(kdone),
    .msg4_tx_valid(valid),.msg4_tx_data(data),.msg4_tx_last(last),.msg4_tx_accept(accept),.msg4_tx_done(done),
    .uart_tx_done(phy_done),.uart_tx_data(phy_data),.uart_tx_start(phy_start));
uart_transfer phy(.clk(clk),.rst_n(rst_n),.clken_16bps(1'b1),.txd(serial_tx),
    .txd_en(phy_start),.txd_data(phy_data),.txd_flag(phy_done));
string lines[0:31],current="";
integer line_count=0,commands=0,bit_number;
reg [7:0] decoded;
initial forever begin
    @(negedge serial_tx);
    if(rst_n) begin
        repeat(24) @(posedge clk); #1;
        for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
            decoded[bit_number]=serial_tx; repeat(16) @(posedge clk); #1;
        end
        if(serial_tx!==1) $fatal(1,"Invalid UART stop");
        if(decoded=="!") begin
            if(current!="") $fatal(1,"Command interleaved into ADC/key line");
            commands=commands+1;
        end else if(decoded==10) begin
            lines[line_count]=current;line_count=line_count+1;current="";
        end else if(decoded!=13) current=$sformatf("%s%c",current,decoded);
    end
end
task emit(input integer value);
    @(negedge clk);code=value;event_valid=1;
    @(negedge clk);event_valid=0;
endtask
task await_lines(input integer count);
    integer watchdog;
    watchdog=0;
    while(line_count<count && watchdog<60000) begin @(negedge clk);watchdog=watchdog+1;end
    if(line_count!=count) $fatal(1,"UART line timeout %0d/%0d",line_count,count);
endtask
initial begin
    repeat(5) @(posedge clk); @(negedge clk);rst_n=1;ready=1;
    repeat(30000) @(negedge clk);
    if(line_count || current!="" || commands || high_threshold!=1024 || low_threshold!=512)
        $fatal(1,"Startup streamed ADC or did not control thresholds");
    knob=0;raw1=1016;repeat(15000) @(negedge clk);
    knob=4095;raw1=814;repeat(15000) @(negedge clk);
    if(line_count || current!="" || high_threshold!=2047 || low_threshold!=1023)
        $fatal(1,"Moving knob streamed ADC or did not change threshold");
    emit(1);
    wait(phy_start); // First ADC key line now owns the physical UART.
    @(negedge clk);key_n=0;cmd_start=1;
    @(negedge clk);cmd_start=0;
    emit(2);emit(3);
    await_lines(4);
    if(lines[0]!="key  2" || lines[1]!="key  1" ||
       lines[2]!="key  3" || lines[3]!="key  2+3" || commands!=1)
        $fatal(1,"UART line content/order incorrect: %s | %s | %s | %s",lines[0],lines[1],lines[2],lines[3]);
    repeat(25000) @(negedge clk);
    if(line_count!=4) $fatal(1,"Stationary knob/held GPIO key repeated");
    knob=2048;raw1=2048;repeat(25000) @(negedge clk);
    knob=2055;raw1=4095;repeat(25000) @(negedge clk);
    if(line_count!=4 || current!="") $fatal(1,"ADC diagnostic streaming is still active");
    $display("PASS silent ADC actual UART: knob controls thresholds without output, event queue, combo, GPIO key coexistence, contiguous command replies");
    $finish;
end
initial begin #3000000; $fatal(1,"Reporter timeout"); end
endmodule
