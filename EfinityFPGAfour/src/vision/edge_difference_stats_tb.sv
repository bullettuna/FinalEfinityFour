`timescale 1ns/1ps
module edge_difference_stats_tb;
reg clk=0,pclk=0,rst_n=0,vs=0,de=0,cur=0,ref_edge=0,expanded=0,fg=0,query=0,accept=0;
reg [31:0] captured=32'h1234abcd;
reg frozen=1,tolerance=1,ready=1,source=1;
wire busy,valid,last;wire [7:0] data;
always #7 clk=~clk;always #5 pclk=~pclk;
edge_difference_stats dut(.clk(clk),.rst_n(rst_n),.pclk(pclk),.prst_n(rst_n),
 .vsync(vs),.href(de),.current_edge(cur),.reference_edge(ref_edge),.expanded_edge(expanded),.foreground(fg),
 .captured_crc(captured),.tolerance_active(tolerance),.reference_ready(ready),.frozen(frozen),.source_active(source),
 .query(query),.busy(busy),.tx_valid(valid),.tx_data(data),.tx_last(last),.tx_accept(accept));
function automatic [31:0] bit_crc(input [31:0] crc,input bit value);
 bit_crc=(crc<<1)^((crc[31]^value)?32'h04c11db7:32'd0);
endfunction
reg [31:0] expected_cur,expected_ref;
integer n=0,m=0;
string received,expected;
reg [7:0] held;
initial begin
 repeat(6)@(negedge clk);rst_n=1;
 @(negedge pclk);vs=1;expected_cur=32'hffffffff;expected_ref=32'hffffffff;
 for(integer i=0;i<32;i++)begin
  de=1;cur=(i%3==0);ref_edge=(i%5==0);expanded=ref_edge&&i!=10;fg=cur&&!expanded;
  expected_cur=bit_crc(expected_cur,cur);expected_ref=bit_crc(expected_ref,ref_edge);
  n+=fg;m+=ref_edge&&!expanded;@(negedge pclk);
 end
 de=0;vs=0;repeat(8)@(negedge clk);
 expected=$sformatf("A=%08x C=%08x B=%08x N=%08x M=%08x F=1 T=1 R=1 E=1",captured,~expected_cur,~expected_ref,n,m);
 expected=expected.toupper();expected={expected,8'd13,8'd10};received="";
 query=1;@(negedge clk);query=0;wait(busy);
 // Published values/flags can change while UART is stalled; the message
 // must still describe one consistent query snapshot.
 captured=0;frozen=0;tolerance=0;ready=0;source=0;
 for(integer i=0;i<72;i++)begin
  @(negedge clk);accept=0;held=data;
  repeat(2)begin @(posedge clk);#1;if(!valid||data!==held)$fatal(1,"stats byte changed while stalled");@(negedge clk);end
  if(last!==(i==71))$fatal(1,"stats packet boundary");
  received={received,data};accept=1;@(negedge clk);accept=0;
 end
 if(busy||received!=expected)$fatal(1,"stats message mismatch received=%s expected=%s",received,expected);
 $display("PASS edge S diagnostics: exact CRC/counts, asynchronous frame publication, latched query, UART stalls, flags and 72-byte CRLF message");$finish;
end
initial begin #100000;$fatal(1,"stats UART timeout");end
endmodule
