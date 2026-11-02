`timescale 1ns/1ps
module pose7_pool_equivalence_tb;
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 wire [1:0] done,cv,cw;wire [31:0] address[0:1],crc[0:1];wire [127:0] data[0:1];
 reg [1:0] ready=0,response=0,pending=0,finished=0;
 reg [127:0] returned[0:1],saved_data[0:1];reg [31:0] saved_address[0:1];reg [1:0] saved_write;
 integer cycle=0,test=0,waits[0:1],writes[0:1];
 reg [127:0] output0[0:4607],output1[0:4607];
 pose7_input_pool old_(clk,rst_n,start,,done[0],crc[0],cv[0],ready[0],cw[0],address[0],data[0],response[0],returned[0]);
 pose7_input_pool_fast fast_(clk,rst_n,start,,done[1],crc[1],cv[1],ready[1],cw[1],address[1],data[1],response[1],returned[1]);
 function [7:0] pixel(input integer offset);
  integer x,y;
  begin
   x=offset%640;y=offset/640;
   case(test)
    0:pixel=0;
    1:pixel=((x*37+y*101)%251==0)?8'hff:0;
    2:pixel=(x==0||x==639||y==0||y==359)?8'h01:0;
    default:pixel=(((x^y)%7)==0)?8'h80:0;
   endcase
  end
 endfunction
 always @(negedge clk)for(integer k=0;k<2;k=k+1)ready[k]=!pending[k]&&!response[k]&&(cycle%11!=k+2);
 always @(posedge clk)begin
  cycle<=cycle+1;response<=0;finished<=finished|done;
  for(integer k=0;k<2;k=k+1)begin
   if(cv[k]&&ready[k])begin
    if(address[k][3:0]!=0)$fatal(1,"unaligned pool transaction");
    pending[k]<=1;saved_address[k]<=address[k];saved_data[k]<=data[k];saved_write[k]<=cw[k];waits[k]<=cycle%5;
   end
   if(pending[k])begin
    if(waits[k]!=0)waits[k]<=waits[k]-1;
    else begin
     if(saved_write[k])begin
      if(saved_address[k]!==32'h02100000+writes[k]*16||writes[k]>=4608)$fatal(1,"pool write order/range");
      if(k==0)output0[writes[k]]<=saved_data[k];else output1[writes[k]]<=saved_data[k];
      writes[k]<=writes[k]+1;
     end else begin
      if(saved_address[k]<32'h01800000||saved_address[k]>=32'h01838400)$fatal(1,"snapshot read out of bounds");
      for(integer j=0;j<16;j=j+1)returned[k][j*8+:8]<=pixel(saved_address[k]-32'h01800000+j);
     end
     pending[k]<=0;response[k]<=1;
    end
   end
  end
 end
 initial begin
  #30;rst_n=1;
  for(test=0;test<4;test=test+1)begin
   @(negedge clk);finished=0;writes[0]=0;writes[1]=0;start=1;
   @(negedge clk);start=0;wait(finished==3);@(negedge clk);
   if(crc[0]!==crc[1]||writes[0]!=4608||writes[1]!=4608)$fatal(1,"pool CRC/length mismatch");
   for(integer i=0;i<4608;i=i+1)if(output0[i]!==output1[i])$fatal(1,"pool tensor test=%0d word=%0d got=%h expected=%h",test,i,output1[i],output0[i]);
  end
  $display("PASS pose7_input_pool_fast: four complete snapshots, empty/sparse/boundary/nonbinary pixels, repeated runs, variable DDR stalls, all 73728 output bytes and CRC exactly match frozen pool");$finish;
 end
 initial begin #100000000;$fatal(1,"pool equivalence timeout");end
endmodule
