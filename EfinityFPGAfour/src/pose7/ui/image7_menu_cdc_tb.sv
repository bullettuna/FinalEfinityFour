`timescale 1ns/1ps
module image7_menu_cdc_tb;
reg sclk=0,pclk=0,srst_n=0,prst_n=0,vs=1;always #5 sclk=~sclk;always #3.367 pclk=~pclk;
reg [145:0] source=0;wire [145:0] active;
image7_menu_cdc #(.WIDTH(146)) dut(sclk,srst_n,pclk,prst_n,vs,source,active);
initial begin
 #100;srst_n=1;prst_n=1;#100;source={146{1'b1}};#300;
 if(active!==0)$fatal(1,"record committed during active frame");
 vs=0;#100;if(active!=={146{1'b1}})$fatal(1,"blank commit missing");
 vs=1;source=146'h12345678901234567890123456789;#500;
 if(active!=={146{1'b1}})$fatal(1,"active frame torn");
 vs=0;#100;if(active!==source)$fatal(1,"coherent record missing");
 vs=1;#200;source=146'hff;#200;source=146'h55;#200;vs=0;#100;vs=1;#300;vs=0;#200;
 if(active!==source)$fatal(1,"mailbox did not deliver latest state");
 $display("PASS image7_menu_cdc: held bundle, blank-only commit, queued latest update");$finish;
end
initial begin #10000;$fatal(1,"CDC timeout");end
endmodule
