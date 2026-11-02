`timescale 1ns/1ps
module photo_ddr_recovery_tb;
 reg clk=0,rst_n=0,read_start=0;
 always #5 clk=~clk;
 reg [19:0] offset=0;
 wire done,error,valid,busy,reset_required,arvalid,rready;
 wire [8:0] index;wire [7:0] data,arlen;wire [31:0] araddr;
 wire [3:0] debug_state,fault;wire [5:0] words;
 reg arready=0,rvalid=0,rlast=0;reg [127:0] rdata=0;reg [1:0] rresp=0;
 reg stall_ar=0,stall_r=0,omit_last=0,late_end=0,bad_resp=0,early_last=0;
 photo_ddr_dma #(.WIDTH(64),.HEIGHT(8),.READ_TIMEOUT(32),.RECOVERY_TIMEOUT(96)) dut(
  .clk(clk),.rst_n(rst_n),.pclk(clk),.prst_n(rst_n),.start(1'b0),.buffer_select(1'b0),.busy(),.done(),.error(),
  .pixel_valid(1'b0),.pixel_data(16'd0),.pixel_active(1'b0),.pixel_done_toggle(1'b0),
  .read_start(read_start),.read_buffer(1'b0),.read_offset(offset),.read_done(done),.read_error(error),
  .read_valid(valid),.read_index(index),.read_byte(data),.read_busy(busy),.read_debug(debug_state),
  .read_beats(words),.read_fault(fault),.read_reset_required(reset_required),
  .awaddr(),.awlen(),.awvalid(),.awready(1'b0),.wdata(),.wlast(),.wvalid(),.wready(1'b0),.bvalid(1'b0),.bresp(2'd0),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 function [7:0] expected(input integer k);expected=k^8'h5a;endfunction
 integer left=0,address=0,beat=0,received=0,done_count=0,error_count=0,bursts=0;
 always @(posedge clk)begin
  arready<=!stall_ar&&left==0&&!rvalid;
  if(arvalid&&arready)begin
   if(arlen!=7 || araddr[6:0]!=0)$fatal(1,"not an aligned short burst");
   left=8;address=araddr-32'h01600000;beat=0;arready<=0;bursts=bursts+1;
  end
  if(rvalid&&rready)begin
   rvalid<=0;
   if(left>0)begin left=left-1;address=address+16;beat=beat+1;if(rlast)left=0;end
   else late_end<=0;
  end
  if(!rvalid&&left>0&&!stall_r)begin
   for(integer k=0;k<16;k=k+1)rdata[k*8 +:8]<=expected(address+k);
   rvalid<=1;rresp<=bad_resp&&beat==3?2:0;
   rlast<=early_last?beat==2:(!omit_last&&left==1);
  end
  if(late_end&&left==0&&!rvalid)begin rvalid<=1;rlast<=1;rresp<=0;rdata<=0;end
  if(valid)begin
   if(data!==expected(offset+received)||index!=received)$fatal(1,"cached byte/index mismatch %d",received);
   received=received+1;
  end
  if(done)done_count=done_count+1;
  if(error)error_count=error_count+1;
 end
 task automatic start_sector;
  begin received=0;@(negedge clk);read_start=1;@(negedge clk);read_start=0;end
 endtask
 task automatic good_sector;
  integer before_done,before_bursts;
  begin
   before_done=done_count;before_bursts=bursts;start_sector();wait(done_count==before_done+1);
   @(negedge clk);
   if(received!=512||bursts-before_bursts!=4||busy||words!=32)$fatal(1,"sector not completed in four bursts");
  end
 endtask
 integer before_errors,before_done;
 initial begin
  repeat(8)@(negedge clk);rst_n=1;good_sector();offset=512;good_sector();offset=0;
  before_errors=error_count;stall_ar=1;start_sector();wait(error_count==before_errors+1);
  if(fault!=1||!busy||!arvalid||received!=0)$fatal(1,"address timeout incorrectly canceled/published");
  stall_ar=0;wait(!busy);repeat(4)@(negedge clk);
  if(error_count!=before_errors+1)$fatal(1,"address failure repeated");good_sector();
  before_errors=error_count;stall_r=1;start_sector();wait(error_count==before_errors+1);
  if(fault!=2||!busy||!rready||received!=0)$fatal(1,"data timeout not draining");
  stall_r=0;wait(!busy);good_sector();
  before_errors=error_count;omit_last=1;start_sector();wait(error_count==before_errors+1);
  if(fault!=3||!busy||received!=0)$fatal(1,"missing RLAST silently released");
  omit_last=0;late_end=1;wait(!busy);repeat(4)@(negedge clk);good_sector();
  before_errors=error_count;bad_resp=1;start_sector();wait(error_count==before_errors+1);
  if(fault!=4||busy||received!=0)$fatal(1,"bad response published pixels");bad_resp=0;good_sector();
  before_errors=error_count;early_last=1;start_sector();wait(error_count==before_errors+1);
  if(fault!=5||busy||received!=0)$fatal(1,"short response published pixels");early_last=0;good_sector();
  before_errors=error_count;before_done=done_count;stall_ar=1;start_sector();wait(reset_required);
  if(!busy||!arvalid||error_count!=before_errors+1||done_count!=before_done)$fatal(1,"permanent stall not safely latched");
  stall_ar=0;wait(!busy);if(reset_required)$fatal(1,"late response did not recover");good_sector();
  $display("PASS short-burst sector cache + AR/data timeout + late draining + missing/early RLAST + RRESP + reset-required recovery");
  $finish;
 end
 initial begin #1000000;$fatal(1,"DDR recovery regression timeout state=%d",debug_state);end
endmodule
