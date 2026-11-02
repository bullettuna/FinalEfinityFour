`timescale 1ns/1ps
module pose7_perf_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,ps=0,ns=0,ds=0;reg [1:0] phase=0;
 wire pdone,ndone,ddone,nfault;wire [31:0] icrc,hcrc;wire [527:0] points;
 wire pv,pw,nv,nw,dv,dw;wire [31:0] pa,na,da;wire [127:0] pdata,ndata,ddata;
 wire cv=phase==0?pv:phase==1?nv:dv;
 wire cw=phase==0?pw:phase==1?nw:dw;
 wire [31:0] ca=phase==0?pa:phase==1?na:da;
 wire [127:0] cd=phase==0?pdata:phase==1?ndata:ddata;
 reg ready=0,rv=0;reg [127:0] rd;
`ifdef POSE7_PERF_CANDIDATE
 pose7_input_pool_fast pool(
`else
 pose7_input_pool pool(
`endif
 clk,rst_n,ps,,pdone,icrc,pv,ready&&phase==0,pw,pa,pdata,rv&&phase==0,rd);
 `ifdef POSE7_PERF_CANDIDATE
 pose7_network_fast network(
`else
 pose7_network network(
`endif
 clk,rst_n,ns,,ndone,nfault,nv,ready&&phase==1,nw,na,ndata,rv&&phase==1,rd);
 pose7_decode decoder(clk,rst_n,ds,,ddone,points,hcrc,dv,ready&&phase==2,dw,da,ddata,rv&&phase==2,rd);
 reg [7:0] memory[0:32'h23ffff];reg [7:0] snapshot[0:230399];reg [7:0] temp[0:299999];
 reg pending=0,pwrite;reg [31:0] paddr;reg [127:0] pdat;integer delay_count=0;
 integer cycle=0,j;
 always @(negedge clk)ready=!pending&&!rv&&(cycle%7!=3);
 always @(posedge clk)begin
  cycle<=cycle+1;rv<=0;
  if(cv&&ready)begin
   if(ca[3:0]!=0)$fatal(1,"unaligned DDR address %h",ca);
   if(!((ca>=32'h02000000&&ca<32'h02240000)||(ca>=32'h01800000&&ca<32'h01838400)))$fatal(1,"DDR range %h",ca);
   pending<=1;paddr<=ca;pdat<=cd;pwrite<=cw;delay_count<=cycle%4+1;
  end
  if(pending)begin
   if(delay_count>0)delay_count<=delay_count-1;
   else begin
    for(j=0;j<16;j=j+1)begin
     if(paddr<32'h02000000)begin
      if(pwrite)$fatal(1,"snapshot must be immutable");
      rd[j*8+:8]<=snapshot[paddr-32'h01800000+j];
     end else if(pwrite)memory[paddr-32'h02000000+j]<=pdat[j*8+:8];
     else rd[j*8+:8]<=memory[paddr-32'h02000000+j];
    end
    rv<=1;pending<=0;
   end
  end
 end
 task load_at(input string name,input integer address);
  integer f,n,k;
  begin
   f=$fopen(name,"rb");if(!f)$fatal(1,"cannot open %s",name);
   n=$fread(temp,f);$fclose(f);if(n>=300000)$fatal(1,"vector too large");
   for(k=0;k<n;k=k+1)begin
    if(address<32'h02000000)snapshot[address-32'h01800000+k]=temp[k];
    else memory[address-32'h02000000+k]=temp[k];
   end
  end
 endtask
 task check_at(input string name,input integer address);
  integer f,n,k;
  begin
   f=$fopen(name,"rb");if(!f)$fatal(1,"cannot open %s",name);
   n=$fread(temp,f);$fclose(f);
   for(k=0;k<n;k=k+1)if(memory[address-32'h02000000+k]!==temp[k])
    $fatal(1,"pipeline tensor %s byte %0d got %h expected %h",name,k,memory[address-32'h02000000+k],temp[k]);
  end
 endtask

 integer hist[0:9][0:17];integer glue_cycles=0,pool_cycles=0,decode_cycles=0;
 initial begin for(integer a=0;a<10;a=a+1)for(integer b=0;b<18;b=b+1)hist[a][b]=0;end
 always @(posedge clk)if(rst_n)begin
  if(phase==0)pool_cycles<=pool_cycles+1;
  if(phase==2)decode_cycles<=decode_cycles+1;
  if(phase==1)begin
   if(network.convolution && network.u_conv.layer<10 && network.u_conv.state<18)
    hist[network.u_conv.layer][network.u_conv.state]<=hist[network.u_conv.layer][network.u_conv.state]+1;
   else glue_cycles<=glue_cycles+1;
  end
 end

 integer fd,rc,idx,src,dst,k;string srcfile,dstfile;
 reg [527:0] expected_points;reg [31:0] expected_icrc,expected_hcrc;
 initial begin
  for(k=0;k<32'h240000;k=k+1)memory[k]=8'ha5;
  load_at("model.bin",32'h02000000);load_at("capture640.bin",32'h01800000);
  fd=$fopen("expected.vec","r");rc=$fscanf(fd,"%h %h %h",expected_points,expected_icrc,expected_hcrc);$fclose(fd);
  if(rc!=3)$fatal(1,"expected metadata");
  #22;rst_n=1;@(negedge clk);ps=1;@(negedge clk);ps=0;
  wait(pdone);#1;check_at("trace/input.u16",32'h02100000);
  if(icrc!==expected_icrc)$fatal(1,"pool CRC got %h expected %h",icrc,expected_icrc);
  $display("PASS image7 native 640x360 -> 256x144 OR bins and input CRC, cycle %0d",cycle);
  @(negedge clk);phase=1;ns=1;@(negedge clk);ns=0;
  wait(ndone);#1;if(nfault)$fatal(1,"network fault");
  fd=$fopen("stages.vec","r");
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %h %h %s %s\n",idx,src,dst,srcfile,dstfile);
   if(rc!=5)$fatal(1,"metadata");check_at(dstfile,dst);
  end
  $fclose(fd);
  check_at("trace/up0.u16",32'h021b0000);check_at("trace/concat.u16",32'h021e0000);
  $display("PASS image7 complete graph including nearest resize and concat, cycle %0d",cycle);
  @(negedge clk);phase=2;ds=1;@(negedge clk);ds=0;
  wait(ddone);#1;
  if(points!==expected_points)$fatal(1,"points got %h expected %h",points,expected_points);
  if(hcrc!==expected_hcrc)$fatal(1,"heatmap CRC got %h expected %h",hcrc,expected_hcrc);
  $display("PASS image7 full pipeline native input, all tensors, eleven decoded points and heatmap CRC with DDR stalls; cycles=%0d",cycle);
  $display("PROFILE pool=%0d glue=%0d decode=%0d total=%0d",pool_cycles,glue_cycles,decode_cycles,cycle);
  for(integer a=0;a<10;a=a+1)for(integer b=0;b<18;b=b+1)$display("PROFILE layer=%0d state=%0d cycles=%0d",a,b,hist[a][b]);
  $finish;
 end
 initial begin #250000000;$fatal(1,"pipeline timeout phase %0d",phase);end
endmodule
