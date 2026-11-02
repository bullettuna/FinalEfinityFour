`timescale 1ns/1ps
module adc_input_ctrl_tb;
reg clk=0,rst_n=0,valid=0,channel=0;
reg [11:0] data=0;
wire [11:0] raw0,raw1,knob,key_voltage;
wire ready,event_valid;
wire [1:0] code;
integer events=0,n;
reg [1:0] codes[0:15];
always #5 clk=~clk;
adc_input_ctrl dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample_channel(channel),
    .sample_data(data),.raw_ch0(raw0),.raw_ch1(raw1),.knob_value(knob),.knob_ready(ready),
    .key_voltage(key_voltage),.key_event(event_valid),.key_code(code));
always @(posedge clk) begin #1; if(event_valid) begin codes[events]=code;events=events+1;end end
task sample(input bit ch,input integer value);
    @(negedge clk);channel=ch;data=value;valid=1;
    @(negedge clk);valid=0;
endtask
task key_samples(input integer value,input integer count);
    integer k;
    for(k=0;k<count;k=k+1) sample(1,value);
endtask
task count_is(input integer expected);
    if(events!=expected) $fatal(1,"Expected %0d key events, saw %0d",expected,events);
endtask
initial begin
    repeat(5) @(posedge clk); @(negedge clk);rst_n=1;
    // No zero-padded startup mean is published.
    for(n=0;n<7;n=n+1) begin sample(0,n*8); if(ready) $fatal(1,"Mean valid too early"); end
    sample(0,56);
    if(!ready || knob!==28 || raw0!==56) $fatal(1,"Eight-point mean incorrect");
    sample(0,64); if(knob!==36) $fatal(1,"Moving mean did not replace oldest sample");
    // Power up with a held ADC key: release is required before first event.
    key_samples(2048,40); count_is(0);
    key_samples(4095,23);
    // Median rejects an isolated spike in released state.
    key_samples(1016,1); key_samples(4095,23); count_is(0);
    // Nineteen decoded samples are insufficient; CH0 does not advance debounce.
    key_samples(2048,20); count_is(0);
    for(n=0;n<30;n=n+1) sample(0,4095);
    count_is(0); key_samples(2048,1); count_is(1);
    if(codes[0]!=1) $fatal(1,"SW2 code wrong");
    key_samples(2048,100); count_is(1);
    // Changing held key, combinations, invalid voltage cannot re-arm.
    key_samples(814,40); key_samples(1016,40); key_samples(1500,40); count_is(1);
    key_samples(4095,10); key_samples(2048,30); count_is(1);
    key_samples(4095,23); key_samples(1016,23); count_is(2);
    if(codes[1]!=2) $fatal(1,"SW3 code wrong");
    key_samples(4095,23); key_samples(814,23); count_is(3);
    if(codes[2]!=3) $fatal(1,"Combined key code wrong");
    key_samples(4095,23);
    key_samples(900,30); key_samples(930,30); key_samples(1800,30); count_is(3);
    // Window edges and normal release/press cycles.
    key_samples(1900,23); count_is(4);
    key_samples(4095,23); key_samples(1100,23); count_is(5);
    key_samples(4095,23); key_samples(740,23); count_is(6);
    @(negedge clk);rst_n=0;
    @(negedge clk);rst_n=1;
    key_samples(814,40); count_is(6);
    $display("PASS ADC controls: mean startup/moving window, median spikes, exact debounce, release arming, long holds, key transitions, windows, reset");
    $finish;
end
initial begin #100000; $fatal(1,"Control timeout"); end
endmodule
