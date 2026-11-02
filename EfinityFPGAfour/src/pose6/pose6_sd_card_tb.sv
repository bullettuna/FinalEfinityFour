`timescale 1ns/1ps
// Derived from image2 native card model; FAT32 fragmented boot-file fixture, not synthesized.
module pose6_sd_card_tb #(parameter SDSC=1, LEGACY_CMD8=0, BOOT_NOISE=0, VOLUME_LBA=2048)(
 input sdclk,input cmd_o,input cmd_oe,output reg cmd_i=1,
 input [3:0] dat_o,input [3:0] dat_oe,output reg [3:0] dat_i=15,
 input reject_write,input corrupt_read);
 reg [31:0] saved_lba[0:31];reg [7:0] saved[0:31][0:511];integer slots=0;
 integer writes=0,reads=0;reg four_bit=0;
 integer command_count[0:63];integer sd_cycles=0,last_response_cycle=-100,
  last_command_cycle=-100,acmd_attempts=0,cmd16_count=0;
 integer failure_command=-1,failure_mode=0;
 reg cmd8_supported=!LEGACY_CMD8,cmd8_illegal=0,stay_busy=0,select_busy=0,voltage_supported=1;
 reg rca_issued=0,selected=0,block_length_set=0;
 always @(posedge sdclk) sd_cycles=sd_cycles+1;
 reg [47:0] packet;reg [127:0] csd;integer i,j;
 function automatic [6:0] crc7(input [135:0] value,input integer bits);
  reg [6:0] c;integer k;
  begin c=0;for(k=bits-1;k>=0;k=k-1)begin
   if(c[6]^value[k])c=(c<<1)^7'h09;else c=c<<1;
  end crc7=c;end
 endfunction
 function automatic [15:0] crc16(input [15:0] c,input bit b);
  crc16=(c<<1)^((c[15]^b)?16'h1021:16'h0);
 endfunction
 localparam [87:0] MODEL_NAME="MODEL6  BIN";
 reg [7:0] boot_file[0:235231];
 integer fault=0;
 initial begin : load_package
  integer f,n;
  f=$fopen("MODEL6.BIN","rb");if(!f)$fatal(1,"missing MODEL6.BIN");
  n=$fread(boot_file,f);$fclose(f);if(n!=235232)$fatal(1,"boot package length");
 end
 function automatic [7:0] getbyte(input [31:0] lba,input integer ix);
  integer cluster_number,sector_number,logical_sector,file_index,entry,n;
  reg [31:0] v;
  begin
   getbyte=0;
   if(lba==0&&VOLUME_LBA!=0)begin
    if(ix==450)getbyte=8'h0c;
    if(ix>=454&&ix<=457)getbyte=VOLUME_LBA>>((ix-454)*8);
    if(ix==510)getbyte=8'h55;if(ix==511)getbyte=8'haa;
   end else if(lba==VOLUME_LBA)begin
    case(ix)
     11:getbyte=0;12:getbyte=fault==7?4:2;13:getbyte=8;14:getbyte=32;16:getbyte=2;
     32,33,34,35:getbyte=32'd4194304>>((ix-32)*8);
     36,37,38,39:getbyte=32'd4096>>((ix-36)*8);
     44:getbyte=2;82:getbyte="F";83:getbyte="A";84:getbyte="T";85:getbyte="3";86:getbyte="2";
     510:getbyte=8'h55;511:getbyte=8'haa;
    endcase
   end else if(lba==VOLUME_LBA+32||lba==VOLUME_LBA+33)begin
    entry=(lba-VOLUME_LBA-32)*128+ix/4;v=0;
    if(entry<2)v=32'h0ffffff8;
    else if(entry==2)v=5;
    else if(entry==5)v=32'h0fffffff;
    else if(entry>=7&&(entry-7)%3==0&&(entry-7)/3<58)begin
     n=(entry-7)/3;v=(n==57||fault==6&&n==0)?32'h0fffffff:entry+3;
    end
    getbyte=v>>((ix%4)*8);
   end else if(lba>=VOLUME_LBA+8224)begin
    sector_number=lba-VOLUME_LBA-8224;
    cluster_number=2+(sector_number/8);
    if(cluster_number==2)begin
     if(ix%32==0)getbyte=8'he5; // Full root cluster; follow FAT to cluster 5.
    end else if(cluster_number==5)begin
     if(sector_number%8==0&&ix<32)begin
      if(ix<11)getbyte=MODEL_NAME[(10-ix)*8+:8];
      if(fault==1&&ix==0)getbyte="X";
      if(ix==11)getbyte=8'h20;
      if(ix==26)getbyte=7;
      if(ix>=28&&ix<=31)getbyte=(fault==2?235231:235232)>>((ix-28)*8);
     end
    end else if(cluster_number>=7&&(cluster_number-7)%3==0)begin
     logical_sector=((cluster_number-7)/3)*8+sector_number%8;
     file_index=logical_sector*512+ix;
     if(file_index<235232)begin
      getbyte=boot_file[file_index];
      if(fault==3&&file_index==100)getbyte=getbyte^8'h01;
      if(fault==5&&file_index==4)getbyte=getbyte^8'h01;
     end
    end
   end
  end
 endfunction
 task automatic short_response(input [5:0] ix,input [31:0] value,input bit no_crc);
  reg [47:0] p;integer k;
  begin
   p={2'b00,ix,value,7'd0,1'b1};
   if(failure_command==packet[45:40])begin
    if(failure_mode==1)return;
    if(failure_mode==3)p[45:40]=ix^1;
    if(failure_mode==4)p[39:8]=value|32'h00400000;
    if(failure_mode==5)p[39:8]=value^1;
   end
   p[7:1]=no_crc?7'h7f:crc7(p>>8,40);
   if(failure_command==packet[45:40] && failure_mode==2)p[1]=~p[1];
   repeat(2)@(negedge sdclk);
   for(k=47;k>=0;k=k-1)begin @(negedge sdclk);cmd_i=p[k];end
   @(negedge sdclk);cmd_i=1;last_response_cycle=sd_cycles;
  end
 endtask
 task automatic long_response(input [127:0] value);
  reg [135:0] p;integer k;
  begin
   p={8'h3f,value};p[7:1]=crc7(value>>8,120);p[0]=1;
   if(failure_command==packet[45:40])begin
    if(failure_mode==1)return;
    if(failure_mode==2)p[1]=~p[1];
    if(failure_mode==3)p[128]=~p[128];
   end
   repeat(2)@(negedge sdclk);
   for(k=135;k>=0;k=k-1)begin @(negedge sdclk);cmd_i=p[k];end
   @(negedge sdclk);cmd_i=1;last_response_cycle=sd_cycles;
  end
 endtask
 task automatic read_sector(input [31:0] lba);
  reg [15:0] c[0:3];reg [7:0] b;reg [3:0] n;integer k,l;
  begin
   reads=reads+1;for(l=0;l<4;l=l+1)c[l]=0;
   repeat(2)@(negedge sdclk);dat_i=0;
   for(k=0;k<1024;k=k+1)begin
    b=getbyte(lba,k/2);n=(k%2)?b[3:0]:b[7:4];
    @(negedge sdclk);dat_i=n;
    for(l=0;l<4;l=l+1)c[l]=crc16(c[l],n[l]);
   end
   for(k=15;k>=0;k=k-1)begin
    @(negedge sdclk);dat_i={c[3][k],c[2][k],c[1][k],c[0][k]};
    if(corrupt_read&&k==7)dat_i[2]=~dat_i[2];
   end
   @(negedge sdclk);dat_i=15;
  end
 endtask
 task automatic write_sector(input [31:0] lba);
  reg [15:0] c[0:3];reg [7:0] data[0:511];reg [3:0] high;reg [4:0] status;
  integer k,l,slot;
  begin
   for(l=0;l<4;l=l+1)c[l]=0;
   do @(posedge sdclk);while(!(dat_oe==15&&dat_o==0));
   for(k=0;k<1024;k=k+1)begin
    @(posedge sdclk);
    if(dat_oe!=15)$fatal(1,"DAT ownership lost");
    if(k%2==0)high=dat_o;else data[k/2]={high,dat_o};
    for(l=0;l<4;l=l+1)c[l]=crc16(c[l],dat_o[l]);
   end
   for(k=15;k>=0;k=k-1)begin @(posedge sdclk);
    if(dat_o!={c[3][k],c[2][k],c[1][k],c[0][k]})$fatal(1,"host write CRC mismatch");end
   @(posedge sdclk);if(dat_o!=15)$fatal(1,"missing data end");
   repeat(2)@(negedge sdclk);
   status=reject_write?5'b01011:5'b00101;
   for(k=4;k>=0;k=k-1)begin dat_i={3'b111,status[k]};@(negedge sdclk);end
   dat_i=14;repeat(12)@(negedge sdclk);dat_i=15;
   if(!reject_write)begin
    slot=-1;for(k=0;k<slots;k=k+1)if(saved_lba[k]==lba)slot=k;
    if(slot<0)begin slot=slots;slots=slots+1;if(slots>32)$fatal(1,"model sector store full");saved_lba[slot]=lba;end
    for(k=0;k<512;k=k+1)saved[slot][k]=data[k];writes=writes+1;
   end
  end
 endtask
 initial begin
  for(i=0;i<64;i=i+1)command_count[i]=0;
  if(SDSC)csd=128'h002F00325F5A83AFEDB7FFBF96800011;
  else begin csd=0;csd[127:126]=1;csd[69:48]=255;end
  forever begin
   @(posedge sdclk);
   if(cmd_oe&&!cmd_o)begin
    if(sd_cycles-last_response_cycle<8)$fatal(1,"N_RC gap shorter than 8 clocks");
    if(sd_cycles-last_command_cycle<8)$fatal(1,"N_CC gap shorter than 8 clocks");
    packet=0;
    for(i=46;i>=0;i=i-1)begin @(posedge sdclk);packet={packet[46:0],cmd_o};end
    last_command_cycle=sd_cycles;command_count[packet[45:40]]=command_count[packet[45:40]]+1;
    if(packet[7:1]!=crc7(packet>>8,40)||packet[0]!=1)$fatal(1,"command CRC bad %h",packet);
    case(packet[45:40])
     0:begin
      four_bit=0;rca_issued=0;selected=0;block_length_set=0;acmd_attempts=0;dat_i=15;
      if(dat_oe!=0)$fatal(1,"SPI entry driven during CMD0");
     end
     8:begin
      if(cmd8_supported)short_response(8,32'h1aa,0);
      else if(cmd8_illegal)short_response(8,32'h00400000,0);
     end
     55:begin
      if(packet[39:8]!=(rca_issued?32'h12340000:0))$fatal(1,"wrong CMD55 RCA");
      short_response(55,selected?32'h920:32'h20,0);
     end
     41:begin
      acmd_attempts=acmd_attempts+1;
      if(!cmd8_supported && packet[38])$fatal(1,"legacy SDSC sent HCS=1");
      if(!voltage_supported)short_response(63,32'h80000000,1);
      else if(acmd_attempts<3 || stay_busy)short_response(63,32'h00ff8000,1);
      else short_response(63,SDSC?32'h80ff8000:32'hc0ff8000,1);
     end
     2:long_response(128'h035344534D4920201000001E8D00C313);
     3:begin rca_issued=1;short_response(3,32'h12340600,0);end
     9:long_response(csd);
     7:begin
      if(packet[39:8]!=32'h12340000)$fatal(1,"wrong CMD7 RCA");
      selected=1;short_response(7,32'h900,0);if(select_busy)dat_i=14;
     end
     16:begin
      if(!SDSC || packet[39:8]!=512 || !selected)$fatal(1,"invalid CMD16 block length");
      cmd16_count=cmd16_count+1;block_length_set=1;short_response(16,32'h900,0);
     end
     6:begin
      if(packet[39:8]!=2 || !selected || (SDSC&&!block_length_set))$fatal(1,"invalid four-bit switch");
      four_bit=1;short_response(6,32'h920,0);
     end
     13:short_response(13,32'h900,0);
     17:begin
      if(!four_bit || (SDSC&&packet[16:8]!=0))$fatal(1,"read mode/address wrong");
      short_response(17,32'h900,0);read_sector(SDSC?(packet[39:8]>>9):packet[39:8]);
     end
     24:begin
      if(!four_bit || (SDSC&&packet[16:8]!=0))$fatal(1,"write mode/address wrong");
      short_response(24,32'h900,0);write_sector(SDSC?(packet[39:8]>>9):packet[39:8]);
     end
     default:$fatal(1,"unexpected command %d",packet[45:40]);
    endcase
   end
  end
 end
endmodule
