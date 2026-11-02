`timescale 1ns/1ps
module key_press_debounce_tb;
reg clk=0,rst_n=0,key_n=1;
wire short_press,long_press;
integer shorts=0,longs=0;
reg old_short=0,old_long=0;
always #5 clk=~clk;
key_press_debounce #(.DEBOUNCE_CYCLES(4),.LONG_CYCLES(16)) dut(
 .clk(clk),.rst_n(rst_n),.key_n(key_n),.short_press(short_press),.long_press(long_press));
always @(posedge clk)begin
 #1;
 if(rst_n)begin
  if(short_press && long_press)$fatal(1,"FAIL simultaneous short/long events");
  if((old_short&&short_press)||(old_long&&long_press))$fatal(1,"FAIL multi-clock event");
  if(short_press)shorts=shorts+1;
  if(long_press)longs=longs+1;
 end
 old_short=short_press;old_long=long_press;
end
task hold_key(input bit value,input integer clocks);
 @(negedge clk);key_n=value;repeat(clocks)@(negedge clk);
endtask
task expect_counts(input integer s,input integer l);
 if(shorts!=s || longs!=l)$fatal(1,"FAIL events short=%0d long=%0d expected=%0d/%0d",shorts,longs,s,l);
endtask
integer i;
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 hold_key(1,12);
 // Pulses shorter than the debounce window never constitute a press.
 for(i=0;i<4;i=i+1)begin hold_key(0,2);hold_key(1,2);end
 hold_key(1,12);expect_counts(0,0);
 hold_key(0,10);hold_key(1,12);expect_counts(1,0);
 // A long press emits once while held. Brief release bounce cannot re-arm it.
 hold_key(0,40);expect_counts(1,1);
 hold_key(1,2);hold_key(0,30);expect_counts(1,1);
 hold_key(1,12);expect_counts(1,1);
 hold_key(0,10);hold_key(1,12);expect_counts(2,1);
 // Stable release after reset and a second long press work independently.
 @(negedge clk);rst_n=0;key_n=1;
 repeat(4)@(negedge clk);rst_n=1;
 hold_key(1,12);hold_key(0,40);hold_key(1,12);expect_counts(2,2);
 $display("PASS key_press_debounce: active-low bounce rejection, short/long single pulses, held-key release bounce, re-arm and reset");
 $finish;
end
initial begin #100000;$fatal(1,"FAIL GPIO key timeout");end
endmodule
