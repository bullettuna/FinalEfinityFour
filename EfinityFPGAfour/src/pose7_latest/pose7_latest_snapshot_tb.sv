`timescale 1ns/1ps
module pose7_latest_snapshot_tb;
 reg clk=0,pclk=0,rst_n=0,enable=0,latest=1,acquire_=0,release_=0,stall=0;
 always #5 clk=~clk;always #3 pclk=~pclk;
 integer cx=0,cy=0,frame=1,cycle=0,published=0,aw_count=0,bad_frames=0;
 always @(posedge pclk)if(rst_n)begin
  if(cx==111)begin cx<=0;if(cy==51)begin cy<=0;frame<=frame+1;end else cy<=cy+1;end else cx<=cx+1;
 end
 wire vs=cy<48,de=cy<48&&cx>=2&&cx<98;
 wire [7:0] pixel=frame;
 wire available,stopped,fault,byte_valid;wire [31:0] read_base,aw,ar;wire [7:0] byte_data;
 wire av,wv,wl,arv,rr;wire [127:0] wd;wire [7:0] al,rl;
 reg [20:0] address=0;
 reg [7:0] memory[0:1023];integer bank_id[0:1];integer last_complete=0;
 reg capturing_d=0,fault_d=0;
 reg [1:0] ws=0,rs=0;reg [31:0] wa=0,ra=0;reg [3:0] wb=0,rb=0;
 wire awready=ws==0&&!stall&&cycle%5!=0,wready=ws==1&&!stall&&cycle%7!=0,bvalid=ws==2&&!stall;
 wire arready=rs==0&&cycle%5!=2,rvalid=rs==1&&cycle%4!=1;
 wire [127:0] rd;
 function integer offset(input [31:0] a);
  begin
   if(a>=32'h01800000&&a<32'h01800200)offset=a-32'h01800000;
   else if(a>=32'h01a00000&&a<32'h01a00200)offset=512+a-32'h01a00000;
   else offset=0; // Idle read-bus values are not transactions.
  end
 endfunction
 for(genvar g=0;g<16;g=g+1)assign rd[g*8+:8]=memory[offset(ra+rb*16+g)];
 pose7_latest_snapshot #(.WIDTH(96),.HEIGHT(48),.FIFO_BITS(4)) dut(
  .clk(clk),.rst_n(rst_n),.pclk(pclk),.enable(enable),.latest_mode(latest),.acquire_frame(acquire_),.read_base(read_base),
  .edge_mode(1'b0),.resolution(2'd1),.vs(vs),.de(de),.pixel(pixel),
  .available(available),.release_frame(release_),.stopped(stopped),.fault(fault),
  .address(address),.byte_data(byte_data),.byte_valid(byte_valid),.frame_width(),.frame_height(),
  .awaddr(aw),.awlen(al),.awvalid(av),.awready(awready),.wdata(wd),.wlast(wl),.wvalid(wv),.wready(wready),.bvalid(bvalid),.bresp(2'd0),
  .araddr(ar),.arlen(rl),.arvalid(arv),.arready(arready),.rdata(rd),.rresp(2'd0),.rlast(rb==7),.rvalid(rvalid),.rready(rr));
 always @(posedge clk)if(rst_n)begin
  cycle<=cycle+1;capturing_d<=dut.capturing;
  fault_d<=fault;if(fault&&!fault_d)bad_frames<=bad_frames+1;
  if(dut.capturing&&!capturing_d)bank_id[dut.write_bank]<=frame;
  if(dut.active_latest&&dut.state==2&&dut.capture_available&&enable)begin
   if(fault)$fatal(1,"bad/partial frame published");
   last_complete<=bank_id[dut.write_bank];published<=published+1;
  end
  if(av&&awready)begin
   if(al!=7||aw[3:0]!=0)$fatal(1,"invalid capture burst");
   if(!((aw>=32'h01800000&&aw<32'h01800200)||(aw>=32'h01a00000&&aw<32'h01a00200)))$fatal(1,"write outside banks");
   if(dut.locked_valid&&aw[21]==dut.locked_bank)$fatal(1,"write accepted into consumer-owned bank");
   wa<=aw;wb<=0;ws<=1;aw_count<=aw_count+1;
  end
  if(wv&&wready)begin
   if(dut.locked_valid&&wa[21]==dut.locked_bank)$fatal(1,"write into locked bank");
   if(wl!==(wb==7))$fatal(1,"write burst truncated");
   for(integer j=0;j<16;j=j+1)memory[offset(wa+wb*16+j)]<=wd[j*8+:8];
   wb<=wb+1'b1;if(wl)ws<=2;
  end
  if(bvalid)ws<=0;
  if(arv&&arready)begin if(rl!=7)$fatal(1,"legacy read burst");ra<=ar;rb<=0;rs<=1;end
  if(rvalid&&rr)begin rb<=rb+1'b1;if(rb==7)rs<=0;end
 end
 integer held_id,held_bank,before_,base_count;
 task take;
  begin
   wait(available);@(negedge clk);held_bank=read_base[21];held_id=last_complete;
   if(bank_id[held_bank]!=held_id)$fatal(1,"did not choose most recent completed frame");
   acquire_=1;@(negedge clk);acquire_=0;
   if(!dut.locked_valid||dut.locked_bank!=held_bank)$fatal(1,"acquisition lost to allocation");
   for(integer i=0;i<512;i=i+1)if(memory[held_bank*512+i]!==held_id[7:0])$fatal(1,"torn/unwritten acquired frame byte %0d",i);
  end
 endtask
 task drop;
  begin @(negedge clk);release_=1;@(negedge clk);release_=0;end
 endtask
 initial begin
  ra=32'h01800000;wa=ra;
  for(integer i=0;i<1024;i=i+1)memory[i]=8'hcc;
  #50;rst_n=1;enable=1;
  take();before_=published;
  repeat(45000)@(negedge clk);
  if(published<before_+6)$fatal(1,"producer stopped while consumer holds frame");
  for(integer i=0;i<512;i=i+1)if(memory[held_bank*512+i]!==held_id[7:0])$fatal(1,"producer overwrote locked frame");
  // Block a write while the camera keeps running: overflow must be discarded,
  // then a later complete frame must recover without touching the lock.
  wait(!dut.capturing);wait(dut.capturing);@(negedge clk);
  stall=1;repeat(15000)@(negedge clk);stall=0;repeat(15000)@(negedge clk);
  if(bad_frames==0)$fatal(1,"overflow scenario did not exercise a discarded frame");
  for(integer i=0;i<512;i=i+1)if(memory[held_bank*512+i]!==held_id[7:0])$fatal(1,"overflow damaged locked frame");
  drop();repeat(10000)@(negedge clk);take();
  enable=0;repeat(5000)@(negedge clk);if(stopped)$fatal(1,"stop ignored consumer ownership");
  drop();wait(stopped);if(ws!=0||rs!=0||available)$fatal(1,"stop abandoned transaction/frame");
  // Exercise both sides of the acquisition/allocation race repeatedly.
  enable=1;
  for(integer i=0;i<20;i=i+1)begin take();repeat(100+i*173)@(negedge clk);drop();end
  // OFF and acquire may arrive together after the caller observed READY.
  wait(available);@(negedge clk);acquire_=1;enable=0;@(negedge clk);acquire_=0;
  if(!dut.locked_valid)$fatal(1,"OFF lost an already-started acquisition");
  drop();wait(stopped);enable=1;take();latest=0;
  repeat(5000)@(negedge clk);
  if(!dut.active_latest||!dut.locked_valid)$fatal(1,"mode switch invalidated a reader-owned bank");
  drop();wait(!dut.active_latest);repeat(10)@(negedge clk);
  wait(available);repeat(2)@(negedge clk);held_id=memory[0];base_count=aw_count;
  for(integer i=0;i<512;i=i+1)begin
   @(negedge clk);address=i;wait(byte_valid);repeat(2)@(negedge clk);
   if(byte_data!==held_id[7:0])$fatal(1,"legacy byte stream changed");
  end
  repeat(10000)@(negedge clk);if(aw_count!=base_count)$fatal(1,"legacy frozen frame overwritten");
  drop();enable=0;wait(stopped);
  $display("PASS latest snapshot: two banks, newest complete frame, long ownership, no overwrite/tearing, overflow recovery, acquire/allocation races, drained stop/restart and legacy immutable byte stream");$finish;
 end
 initial begin #10000000;$fatal(1,"latest snapshot timeout state=%0d cap=%0d",dut.state,dut.u_capture.capture_state);end
endmodule
