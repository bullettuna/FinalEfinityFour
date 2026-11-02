`timescale 1ns/1ps
module pose7_requant_batch_tb;
 reg clk=0,rst_n=0,start=0,ref_start=0;always #5 clk=~clk;
 reg [767:0] accumulators;reg [4:0] count;wire [3:0] index;
 reg [30:0] multipliers[0:15];reg [5:0] shifts[0:15];
 reg [15:0] z0,z1;reg relu;reg [30:0] pm;reg [5:0] ps;
 wire done,busy,ref_done;wire [255:0] values;wire [15:0] ref_value;
 integer j,checks=0;reg [255:0] expected;
 pose7_requant_batch batch(.clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
  .accumulators(accumulators),.count(count),.meta_lane(index),.multiplier(multipliers[index]),.shift(shifts[index]),
  .conv_zero(z0),.relu(relu),.post_multiplier(pm),.post_shift(ps),.output_zero(z1),.values(values));
 pose7_requant reference(.clk(clk),.rst_n(rst_n),.start(ref_start),.busy(),.done(ref_done),
  .accumulator($signed(accumulators[j*48+:48])),.multiplier(multipliers[j]),.shift(shifts[j]),
  .conv_zero(z0),.relu(relu),.post_multiplier(pm),.post_shift(ps),.output_zero(z1),.value(ref_value));
 initial begin
  j=0;#30;rst_n=1;
  for(integer test=0;test<512;test=test+1)begin
   @(negedge clk);count=1+test%16;z0=$urandom;z1=$urandom;relu=test[0];pm=$urandom;ps=test%64;expected=0;
   if(test<16)begin z0=32768;z1=32768;pm=1;ps=1;end
   for(integer lane=0;lane<16;lane=lane+1)begin
    accumulators[lane*48+:48]=test[1]?{$urandom,$urandom}:$signed($random);
    multipliers[lane]=$urandom;shifts[lane]=(test+lane)%64;
    if(test<16)begin accumulators[lane*48+:48]=$signed(2*lane-15);multipliers[lane]=1;shifts[lane]=1;end
   end
   if(test==16)accumulators[47:0]=48'h800000000000;
   if(test==17)accumulators[47:0]=48'h7fffffffffff;
   start=1;@(negedge clk);start=0;
   for(j=0;j<count;j=j+1)begin
    ref_start=1;@(negedge clk);ref_start=0;wait(ref_done);@(negedge clk);
    expected[j*16+:16]=ref_value;checks=checks+1;
   end
   wait(!busy);@(negedge clk);
   if(values!==expected)$fatal(1,"batch differs test=%0d n=%0d got=%h expected=%h",test,count,values,expected);
  end
  $display("PASS pose7_requant_batch: %0d channels, all batch lengths, signed limits, variable shifts, both saturating RNE passes, ReLU and lane order match frozen scalar",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"batch equivalence timeout");end
endmodule
