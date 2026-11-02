`timescale 1ns/1ps
module pose6_arithmetic_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0;wire busy,done;wire [15:0] value;
 reg signed [47:0] accumulator;reg [30:0] multiplier,pm;reg [5:0] shift,ps;
 reg [15:0] cz,oz,expected;reg relu;
 pose6_requant rq(clk,rst_n,start,busy,done,accumulator,multiplier,shift,cz,relu,pm,ps,oz,value);
 reg valid=0,first=0,last=0;reg signed [16:0] activation;reg [255:0] weights;
 reg [767:0] biases,expected_sums;wire [767:0] sums;wire mac_done;
 pose6_mac16 mac(clk,rst_n,valid,first,last,activation,weights,biases,mac_done,sums);
 integer fd,n,rc,i,count;
 initial begin
  #22;rst_n=1;count=0;
  fd=$fopen("requant.vec","r");if(!fd)$fatal(1,"missing requant vectors");
  while(!$feof(fd))begin
   @(negedge clk);
   rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h\n",accumulator,multiplier,shift,cz,relu,pm,ps,oz,expected);
   if(rc!=9)$fatal(1,"bad requant vector");
   start=1;@(negedge clk);start=0;
   wait(done);#1;
   if(value!==expected)$fatal(1,"requant case %0d got %h expected %h",count,value,expected);
   count=count+1;
  end
  $fclose(fd);
  if(count!=500)$fatal(1,"requant count");
  fd=$fopen("mac.vec","r");if(!fd)$fatal(1,"missing MAC vectors");count=0;
  while(!$feof(fd))begin
   @(negedge clk);rc=$fscanf(fd,"%d %h %h\n",n,biases,expected_sums);
   if(rc!=3)$fatal(1,"bad MAC header");
   for(i=0;i<n;i=i+1)begin
    if(i%7==3)begin valid=0;@(negedge clk);end
    rc=$fscanf(fd,"%h %h\n",activation,weights);
    if(rc!=2)$fatal(1,"bad MAC vector");
    valid=1;first=(i==0);last=(i==n-1);@(negedge clk);
   end
   valid=0;first=0;last=0;wait(mac_done);#1;
   if(sums!==expected_sums)$fatal(1,"MAC sequence %0d mismatch",count);
   count=count+1;
  end
  if(count!=6)$fatal(1,"MAC count");
  $display("PASS image6 MAC16, negative activations, bias, bubbles, 48-bit sums and 500 two-stage RNE cases");
  $finish;
 end
 initial begin #1000000;$fatal(1,"arithmetic timeout");end
endmodule
