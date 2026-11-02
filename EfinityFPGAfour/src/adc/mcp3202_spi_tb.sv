`timescale 1ns/1ps
module mcp3202_spi_tb #(parameter PRODUCTION=0);
reg clk=0,rst_n=0,miso=1'bz;
wire sclk,mosi,cs,valid,channel;
wire [11:0] data;
always #(PRODUCTION ? 5.208333 : 500) clk=~clk;
mcp3202_spi #(.CLOCK_HZ(PRODUCTION ? 96000000 : 1000000),
    .SPI_HZ(PRODUCTION ? 500000 : 50000),.CHANNEL_SAMPLE_HZ(1000)) dut (
    .clk(clk),.rst_n(rst_n),.spi_miso(miso),.spi_sclk(sclk),.spi_mosi(mosi),.cs_adc(cs),
    .sample_valid(valid),.sample_channel(channel),.sample_data(data));
integer edges=0,frames=0,samples=0;
reg [23:0] command;
reg selected;
reg [11:0] held_value;
time last_edge,cs_fall,last_cs_rise=0;
reg prior_valid=0;
localparam integer HALF_NS=PRODUCTION ? 1000 : 10000;
localparam integer OUTPUT_DELAY_NS=PRODUCTION ? 200 : 30;
function [11:0] pattern(input integer n);
    case(n%4) 0:pattern=0; 1:pattern=4095; 2:pattern=12'h800; 3:pattern=12'ha55; endcase
endfunction
always @(negedge cs) begin
    if(sclk!==0) $fatal(1,"SPI must idle low");
    if(last_cs_rise && $time-last_cs_rise<500) $fatal(1,"CS high time too short");
    edges=0;command=0;selected=0;cs_fall=$time;last_edge=$time;miso=1'bz;
end
always @(posedge sclk) if(!cs) begin
    if($time-last_edge<HALF_NS-2 || $time-last_edge>HALF_NS+2) $fatal(1,"SPI low half-period incorrect");
    last_edge=$time;
    command={command[22:0],mosi};
    if(edges==9) begin
        selected=mosi;
        held_value=selected ? 12'hfff : pattern(frames/2);
    end
    edges=edges+1;
end
always @(negedge sclk) if(!cs) begin
    if($time-last_edge<HALF_NS-2 || $time-last_edge>HALF_NS+2) $fatal(1,"SPI high half-period incorrect");
    last_edge=$time;
    if(edges==11) miso<=#OUTPUT_DELAY_NS 0;
    else if(edges>=12 && edges<=23) miso<=#OUTPUT_DELAY_NS held_value[23-edges];
end
always @(posedge cs) begin
    last_cs_rise=$time;
    if(rst_n && edges) begin
        if(edges!=24 || command!==(selected ? 24'h01e000 : 24'h01a000))
            $fatal(1,"Bad MCP3202 frame: %0d edges, command %06x",edges,command);
        if(selected!==((frames%2)!=0)) $fatal(1,"Channels did not alternate");
        frames=frames+1;
    end
    miso<=#30 1'bz;
end
always @(posedge clk) begin
    #1;
    if(rst_n && valid) begin
        if(prior_valid) $fatal(1,"Sample valid lasted more than one cycle");
        if(channel!==selected || data!==held_value)
            $fatal(1,"Wrong ADC result: ch=%0d data=%03x expected=%03x",channel,data,held_value);
        samples=samples+1;
    end
    prior_valid=valid;
end
initial begin
    repeat(5) @(posedge clk); @(negedge clk); rst_n=1;
    wait(samples==16);
    @(negedge cs); repeat(30) @(posedge clk);
    @(negedge clk); rst_n=0; #1;
    if(cs!==1 || sclk!==0 || valid!==0) $fatal(1,"Reset did not abort SPI transaction");
    frames=0; edges=0;
    repeat(5) @(posedge clk); @(negedge clk); rst_n=1;
    wait(samples==24);
    $display("PASS MCP3202 independent wire model: command, Mode0 timing, channel alternation, 12-bit alignment, delayed MISO, mid-frame reset");
    $finish;
end
initial begin #30000000; $fatal(1,"SPI timeout"); end
endmodule
