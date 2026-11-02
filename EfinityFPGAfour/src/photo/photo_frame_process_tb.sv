`timescale 1ns/1ps
module photo_frame_process_tb #(parameter WIDTH=32,HEIGHT=24,QUICK=0);
 localparam N=WIDTH*HEIGHT,A=32'h01600000,B=32'h01800000,C=32'h01900000,Q=32'h01a00000;
 reg clk=0,rst_n=0,start=0,slot=0,median=1;reg [1:0] mode=2,clean=1;
 always #5 clk=~clk;
 wire busy,done,error;wire [5:0] stage;
 wire [31:0] awaddr,araddr;wire [7:0] awlen,arlen;wire awvalid,wlast,wvalid,arvalid,rready;
 wire [127:0] wdata;reg [127:0] rdata;
 reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=1;reg [1:0] bresp=0,rresp=0;
 photo_frame_process #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.MEM_TIMEOUT(1000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.buffer_select(slot),.mode(mode),.median_enable(median),
  .cleanup_level(clean),.min_pixels(11'd20),.high_threshold(11'd60),.low_threshold(11'd30),
  .busy(busy),.done(done),.error(error),.debug_stage(stage),
  .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 // Compact model: 1MiB regions are mapped to consecutive N-sized regions.
 reg [7:0] memory[0:16*N+255];
 function integer mapped(input [31:0] address);
  if(address>=A&&address<A+N*2)mapped=address-A;
  else if(address>=A+32'h100000&&address<A+32'h100000+N*2)mapped=N*2+address-A-32'h100000;
  else if(address>=B&&address<B+N*2)mapped=N*4+address-B;
  else if(address>=C&&address<C+N*2)mapped=N*6+address-C;
  else if(address>=Q&&address<Q+N*4)mapped=N*8+address-Q;
  else begin $fatal(1,"workspace out of range %h",address);mapped=0;end
 endfunction
 integer cycle=0,read_delay=0;reg [31:0] pending_read,pending_write;reg writing=0,reading=0;
 reg inject_read_error=0,inject_write_error=0,stall_address=0;
 reg offered=0;reg [31:0] stable_address;
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(!rst_n)begin awready<=0;wready<=0;bvalid<=0;arready<=0;rvalid<=0;writing<=0;reading<=0;read_delay<=0;offered<=0;end
  else begin
   awready<=!writing&&!bvalid&&(cycle%7!=0);
   wready<=writing&&(cycle%5!=0);
   arready<=!reading&&!rvalid&&(cycle%9!=0)&&!stall_address;
   if(awvalid&&!awready)begin
    if(offered&&awaddr!==stable_address)$fatal(1,"AW changed under backpressure");
    offered<=1;stable_address<=awaddr;
   end else offered<=0;
   if(awvalid&&awready)begin
    if(awlen!=0)$fatal(1,"unexpected burst");pending_write<=awaddr;writing<=1;
   end
   if(wvalid&&wready)begin
    if(!wlast)$fatal(1,"missing WLAST");
    for(integer k=0;k<16;k=k+1)memory[mapped(pending_write)+k]<=wdata[k*8+:8];
    writing<=0;bvalid<=1;bresp<=inject_write_error?2:0;
   end else if(bvalid)bvalid<=0;
   if(arvalid&&arready)begin pending_read<=araddr;reading<=1;read_delay<=3;end
   if(reading)begin
    if(read_delay!=0)read_delay<=read_delay-1;
    else begin
     for(integer k=0;k<16;k=k+1)rdata[k*8+:8]<=memory[mapped(pending_read)+k];
     rvalid<=1;reading<=0;rresp<=inject_read_error?2:0;
    end
   end
   if(rvalid&&rready)rvalid<=0;
  end
 end
 reg [15:0] input_image[0:N-1],expected[0:N-1],classes[0:N-1];
 task reset;
  @(negedge clk);rst_n=0;start=0;repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
 endtask
 task run_photo(input integer test_case,input integer med,input integer cleanup,input integer kind);
  string path;integer baseline;
  median=med;clean=cleanup;mode=kind;slot=test_case%2;
  path=$sformatf("input%0d.hex",test_case);$readmemh(path,input_image);
  path=kind==1?$sformatf("gray%0d_%0d.hex",test_case,med):$sformatf("edge%0d_%0d_%0d.hex",test_case,med,cleanup);
  $readmemh(path,expected);
  for(integer k=0;k<N;k=k+1)begin
   memory[(slot?N*2:0)+2*k]=input_image[k][7:0];memory[(slot?N*2:0)+2*k+1]=0;
  end
  baseline=cycle;@(negedge clk);start=1;@(negedge clk);start=0;
  // Configuration changes after acceptance must not affect this snapshot.
  repeat(5)@(negedge clk);median=!med;clean=2-cleanup;mode=0;
  while(!done&&!error)@(negedge clk);
  if(error)$fatal(1,"processor error at stage %d",stage);
  for(integer k=0;k<N;k=k+1)
   if({memory[(slot?N*2:0)+2*k+1],memory[(slot?N*2:0)+2*k]}!==expected[k])
    $fatal(1,"case %d median %d clean %d mode %d pixel %d got %h expected %h",test_case,med,cleanup,kind,k,
     {memory[(slot?N*2:0)+2*k+1],memory[(slot?N*2:0)+2*k]},expected[k]);
  $display("PASS image2 frame case=%0d median=%0d clean=%0d mode=%0d cycles=%0d",test_case,med,cleanup,kind,cycle-baseline);
  @(negedge clk);
 endtask
 initial begin
  for(integer k=0;k<16*N+256;k=k+1)memory[k]=8'ha5;
  reset();
  if(QUICK==3)begin
   // Fill the entire candidate frame: one component consumes the maximum
   // queue capacity, spans every border and crosses Y=511 in the tall test.
   for(integer k=0;k<N;k=k+1)begin memory[N*6+2*k]=k==N-1?2:1;memory[N*6+2*k+1]=0;end
   @(negedge clk);dut.state=10;dut.busy=1;dut.slot_base=A;dut.image_mode=2;dut.clean=1;dut.minimum=20;
   dut.index=0;dut.x=0;dut.y=0;
   while(!done&&!error)@(negedge clk);
   if(error)$fatal(1,"full component queue fault");
   for(integer k=0;k<N;k=k+1)if({memory[2*k+1],memory[2*k]}!==16'hffff)$fatal(1,"full component pixel %d",k);
   $display("PASS %0dx%0d all-pixel weak component with final strong seed, maximum queue occupancy, borders and 10-bit Y",WIDTH,HEIGHT);$finish;
  end
  if(QUICK==2)begin
   run_photo(0,1,1,2);
   $display("PASS full 960x540 snapshot processing, DDR workspace and complete-frame output");$finish;
  end
  for(integer c=0;c<(QUICK?1:4);c=c+1)for(integer m=0;m<2;m=m+1)begin
   run_photo(c,m,1,1);
   for(integer d=0;d<(QUICK?1:3);d=d+1)run_photo(c,m,d,2);
  end
  // Directed connectivity proof starts at the public ternary boundary of the
  // controller, bypassing arithmetic only. Frame tests above exercise all passes.
  if(!QUICK)for(integer d=0;d<3;d=d+1)begin
   reset();$readmemh("classes.hex",classes);$readmemh($sformatf("components%0d.hex",d),expected);
   for(integer k=0;k<N;k=k+1)begin memory[N*6+2*k]=classes[k];memory[N*6+2*k+1]=0;end
   @(negedge clk);dut.state=10;dut.busy=1;dut.slot_base=A;dut.image_mode=2;dut.clean=d;dut.minimum=20;dut.index=0;dut.x=0;dut.y=0;
   while(!done&&!error)@(negedge clk);
   if(error)$fatal(1,"component processor error");
   for(integer k=0;k<N;k=k+1)if({memory[2*k+1],memory[2*k]}!==expected[k])$fatal(1,"component clean %d pixel %d",d,k);
   $display("PASS complete hysteresis long weak chain, pure weak rejection, speckle, small loop clean=%0d",d);
  end
  reset();inject_read_error=1;mode=2;median=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(error);repeat(30)@(negedge clk);if(done||!busy)$fatal(1,"read fault published a frame");
  $display("PASS DDR read failure latches reset-required without completion");
  reset();inject_read_error=0;inject_write_error=1;mode=1;median=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(error);repeat(30)@(negedge clk);if(done||!busy)$fatal(1,"write fault published a frame");
  $display("PASS DDR write failure latches reset-required without completion");
  reset();inject_write_error=0;stall_address=1;mode=1;median=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(error);repeat(20)@(negedge clk);if(!arvalid||done)$fatal(1,"timed-out ARVALID was canceled");
  $display("PASS stalled AXI address remains offered after timeout; reset required");
  $display("PASS all image2 full-frame Canny and workspace tests");$finish;
 end
 initial begin #(64'd20000000000);$fatal(1,"test watchdog state=%d",stage);end
endmodule
