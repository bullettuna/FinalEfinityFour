`timescale 1ns/1ps
module pose6_conv_tb;
 parameter LAYERS=10;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0;reg [3:0] layer_index;wire busy,done,fault;
 wire cv,cw;wire [31:0] ca;wire [127:0] cd;
 reg cr=0,rv=0;reg [127:0] rd;
 pose6_conv dut(clk,rst_n,start,layer_index,busy,done,fault,cv,cr,cw,ca,cd,rv,rd);
 reg [7:0] memory[0:32'h23ffff];
 reg [7:0] temp[0:199999];
 reg pending=0,pwrite;reg [31:0] paddr;reg [127:0] pdata;integer delay_count=0;
 integer cycle=0,j;
 always @(negedge clk)cr=!pending&&!rv&&(cycle%7!=3);
 always @(posedge clk)begin
  cycle<=cycle+1;rv<=0;
  if(cv&&cr)begin
   if(ca<32'h02000000||ca>=32'h02240000||ca[3:0]!=0)$fatal(1,"DDR address %h",ca);
   pending<=1;paddr<=ca-32'h02000000;pdata<=cd;pwrite<=cw;delay_count<=cycle%4+1;
  end
  if(pending)begin
   if(delay_count>0)delay_count<=delay_count-1;
   else begin
    for(j=0;j<16;j=j+1)begin
     if(pwrite)memory[paddr+j]<=pdata[j*8+:8];
     else rd[j*8+:8]<=memory[paddr+j];
    end
    rv<=1;pending<=0;
   end
  end
 end
 task load_at(input string name,input integer address);
  integer f,n,k;
  begin
   f=$fopen(name,"rb");if(!f)$fatal(1,"cannot open %s",name);
   n=$fread(temp,f);$fclose(f);
   if(n>=200000)$fatal(1,"vector too large");
   for(k=0;k<n;k=k+1)memory[address-32'h02000000+k]=temp[k];
  end
 endtask
 task check_at(input string name,input integer address);
  integer f,n,k;
  begin
   f=$fopen(name,"rb");if(!f)$fatal(1,"cannot open %s",name);
   n=$fread(temp,f);$fclose(f);
   for(k=0;k<n;k=k+1)if(memory[address-32'h02000000+k]!==temp[k])
    $fatal(1,"stage %0d byte %0d got %h expected %h",layer_index,k,memory[address-32'h02000000+k],temp[k]);
  end
 endtask
 integer fd,rc,idx,src,dst,count,k;string srcfile,dstfile;
 initial begin
  for(k=0;k<32'h240000;k=k+1)memory[k]=8'ha5;
  load_at("model.bin",32'h02000000);
  #22;rst_n=1;count=0;
  fd=$fopen("stages.vec","r");if(!fd)$fatal(1,"missing stages.vec");
  while(!$feof(fd)&&count<LAYERS)begin
   rc=$fscanf(fd,"%d %h %h %s %s\n",idx,src,dst,srcfile,dstfile);
   if(rc!=5)$fatal(1,"stage metadata");
   load_at(srcfile,src);
   @(negedge clk);layer_index=idx;start=1;@(negedge clk);start=0;
   wait(done);#1;
   if(fault)$fatal(1,"convolution fault");
   check_at(dstfile,dst);
   $display("PASS image6 convolution layer %0d at cycle %0d",idx,cycle);count=count+1;
  end
  if(count!=LAYERS)$fatal(1,"layer count");
  $display("PASS image6 tiled convolution exact uint16 outputs for %0d layers with DDR backpressure",count);
  $finish;
 end
 initial begin #500000000;$fatal(1,"convolution timeout layer %0d state %0d",layer_index,dut.state);end
endmodule
