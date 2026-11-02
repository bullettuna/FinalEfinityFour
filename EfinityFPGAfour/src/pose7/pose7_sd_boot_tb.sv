`timescale 1ns/1ps
module pose7_sd_boot_tb #(parameter SDSC=1,VOLUME_LBA=2048,FAULT=0);
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 wire busy,done,ready,error;wire [7:0] error_code;wire [5:0] ec;wire [3:0] er;
 wire sdclk,co,ce,ci;wire [3:0] di,do_,de;
 wire cv,cw;wire [31:0] ca;wire [127:0] cd;
 reg cr=0,rv=0,mfault=0;reg pending=0;integer delay_count=0,cycle=0,writes=0;
 wire card_ok,fat_ok,found,hdr_ok,crc_ok;wire [31:0] file_size,read_bytes;
 pose7_sd_boot boot(.clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.ready(ready),.error(error),.error_code(error_code),
  .error_command(ec),.sd_error_reason(er),.sd_clk(sdclk),.sd_cmd_o(co),.sd_cmd_oe(ce),.sd_cmd_i(ci),.sd_dat_i(di),.sd_dat_o(do_),.sd_dat_oe(de),
  .command_valid(cv),.command_ready(cr),.command_write(cw),.command_address(ca),.command_data(cd),.response_valid(rv),.memory_fault(mfault),
  .card_initialized(card_ok),.fat_valid(fat_ok),.file_found(found),.header_valid(hdr_ok),.crc_valid(crc_ok),.file_size(file_size),.read_bytes(read_bytes));
 pose7_sd_card_tb #(.SDSC(SDSC),.VOLUME_LBA(VOLUME_LBA)) card(sdclk,co,ce,ci,do_,de,di,1'b0,FAULT==4);
 integer offset,k;reg [7:0] expected;
 always @(negedge clk)cr=rst_n&&!pending&&!rv&&cycle%7!=3;
 always @(posedge clk)begin
  cycle<=cycle+1;rv<=0;
  if(cv&&cr)begin
   if(!cw||ca[3:0]!=0)$fatal(1,"SD writer alignment/direction");
   if(ca>=32'h02000000&&ca<32'h02000000+162592)offset=128+ca-32'h02000000;
   else if(ca>=32'h02100000&&ca<32'h02100000+73728)offset=128+162592+ca-32'h02100000;
   else $fatal(1,"SD DDR address %h",ca);
   for(k=0;k<16;k=k+1)begin
    expected=card.boot_file[offset+k];
    if(FAULT==3&&offset+k==160)expected=expected^8'h01;
    if(cd[k*8+:8]!==expected)$fatal(1,"SD DDR byte %0d got %h expected %h",offset+k,cd[k*8+:8],expected);
   end
   writes<=writes+1;pending<=1;delay_count<=cycle%5+1;
  end
  if(pending)begin
   if(delay_count!=0)delay_count<=delay_count-1;
   else begin rv<=1;pending<=0;end
  end
 end
 initial begin
  card.fault=FAULT;
  #32;rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done||error);#1;
  if(FAULT==0)begin
   if(!card_ok||!fat_ok||!found||!hdr_ok||!crc_ok||file_size!=236448||read_bytes!=236448)$fatal(1,"Incomplete SD diagnostic milestones");
   if(!ready||error||writes!=14770)$fatal(1,"SD boot did not complete: err=%h writes=%0d cmd=%0d reason=%0d",error_code,writes,ec,er);
   if(SDSC&&card.cmd16_count==0)$fatal(1,"SDSC requires CMD16 and byte addressing");
   $display("PASS SD4 boot: SDSC=%0d partition=%0d fragmented directory/file FAT chains, full package, 14770 exact DDR writes, CRCs",SDSC,VOLUME_LBA);
  end else begin
   if(crc_ok)$fatal(1,"Fault incorrectly reports CRC success");
   if(FAULT==1&&(!card_ok||!fat_ok||found||file_size!=0))$fatal(1,"Missing-file diagnostics");
   if(FAULT==2&&(!found||file_size!=236447))$fatal(1,"Wrong-size diagnostics");
   if(FAULT==3&&(!hdr_ok||read_bytes!=236448))$fatal(1,"Payload CRC diagnostics");
   if(FAULT==5&&(!found||hdr_ok))$fatal(1,"Bad-header diagnostics");
   if(FAULT==7&&fat_ok)$fatal(1,"Invalid FAT reported valid");
   if(ready||!error)$fatal(1,"bad SD package enabled model");
   if((FAULT==1&&error_code!=4)||(FAULT==2&&error_code!=5)||(FAULT==3&&error_code!=8'h21)||
      (FAULT==4&&error_code!=2)||(FAULT==5&&error_code!=8'h20)||(FAULT==6&&error_code!=6)||(FAULT==7&&error_code!=3))
    $fatal(1,"wrong error %h fault=%0d cmd=%0d reason=%0d",error_code,FAULT,ec,er);
   if((FAULT==1||FAULT==2||FAULT==4||FAULT==5||FAULT==7)&&writes!=0)$fatal(1,"Rejected metadata/sector wrote DDR");
   $display("PASS SD4 boot rejects fault=%0d error=%h writes=%0d without model readiness",FAULT,error_code,writes);
  end
  if(card.writes!=0)$fatal(1,"Boot loader wrote SD card");
  $finish;
 end
 initial begin #400000000;$fatal(1,"SD boot timeout error=%h reader=%0d host=%0d",error_code,boot.reader.state,boot.host.state);end
endmodule
