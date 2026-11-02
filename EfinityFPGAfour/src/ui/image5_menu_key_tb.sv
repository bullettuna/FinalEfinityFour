`timescale 1ns/1ps
module image5_menu_key_tb;
 reg clk=0,rst_n=0,key_n=1;wire short_press,long_press;
 always #5 clk=~clk;
 reg key_meta=1,key_sync=1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin key_meta<=1;key_sync<=1;end
  else begin key_meta<=key_n;key_sync<=key_meta;end
 end
 key_press_debounce #(.DEBOUNCE_CYCLES(4),.LONG_CYCLES(30)) dut(
  .clk(clk),.rst_n(rst_n),.key_n(key_sync),.short_press(short_press),.long_press(long_press));
 integer shorts=0,longs=0;
 always @(posedge clk)begin if(short_press)shorts++;if(long_press)longs++;end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
  clocks(4);rst_n=1;clocks(8);
  key_n=0;clocks(1);key_n=1;clocks(10);if(shorts||longs)$fatal(1,"Bounce triggered");
  key_n=0;clocks(15);key_n=1;clocks(15);if(shorts!=1||longs)$fatal(1,"Short release");
  key_n=0;clocks(80);if(shorts!=1||longs!=1)$fatal(1,"Long repeat");
  key_n=1;clocks(15);if(shorts!=1)$fatal(1,"Long release became short");
  key_n=0;clocks(15);key_n=1;clocks(15);if(shorts!=2||longs!=1)$fatal(1,"Release rearm");
  $display("PASS image5 menu key: bounce, one short on release, one long while held, no short after long, release rearm");$finish;
 end
 initial begin #20000;$fatal(1,"Menu key watchdog");end
endmodule
