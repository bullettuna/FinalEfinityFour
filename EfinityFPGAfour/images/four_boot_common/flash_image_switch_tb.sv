`timescale 1ns/1ps
module flash_image_switch_tb #(parameter CURRENT_SLOT=0);
 reg clk=0,rst_n=0,valid=0,safe_=0,error_=0;always #5 clk=~clk;
 reg [4:0] addr=0;reg [11:0] value=0;
 wire [1:0] selected,cbsel;wire [3:0] status;wire stop_,ena,config_;
 integer pulses=0,capture_edges=0,high_edges=0;
 reg config_d=0;
 flash_image_switch #(.CURRENT_SLOT(CURRENT_SLOT),.TIMEOUT_CYCLES(80)) dut(
  .clk(clk),.rst_n(rst_n),.write_valid(valid),.write_addr(addr),.write_value(value),
  .safe_to_switch(safe_),.cfg_error(error_),.selected_slot(selected),.status(status),
  .stop_request(stop_),.cfg_cbsel(cbsel),.cfg_ena(ena),.cfg_config(config_));
 always @(posedge clk)begin
  config_d<=config_;
  if(ena&&!config_)capture_edges<=capture_edges+1;
  if(config_)begin
   high_edges<=high_edges+1;
   if(!ena||capture_edges<8||!stop_)$fatal(1,"invalid CONFIG sequence");
  end
  if(config_&&!config_d)pulses<=pulses+1;
 end
 task write_(input [4:0] a,input [11:0] v);
  begin @(negedge clk);valid=1;addr=a;value=v;@(negedge clk);valid=0;repeat(3)@(negedge clk);end
 endtask
 task reset_;
  begin @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);end
 endtask
 integer target,p;
 initial begin
  error_=1;reset_;
  if(config_||ena||stop_||selected!=CURRENT_SLOT||status!=3)$fatal(1,"fallback auto-reboot or wrong default");
  error_=0;repeat(5)@(negedge clk);
  for(integer k=0;k<4;k=k+1)begin write_(18,k);if(selected!=k||config_||ena||stop_)$fatal(1,"selection triggered reboot");end
  write_(18,4);if(selected!=3)$fatal(1,"invalid slot accepted");
  write_(18,CURRENT_SLOT);write_(19,0);if(status!=4||stop_||config_)$fatal(1,"current image must be a no-op");
  for(integer k=0;k<4;k=k+1)if(k!=CURRENT_SLOT)begin
   safe_=0;reset_;capture_edges=0;high_edges=0;target=k;p=pulses;
   write_(18,k);write_(19,0);repeat(15)@(negedge clk);
   if(!stop_||ena||config_||status!=1)$fatal(1,"must wait for actual drain");
   write_(18,(k+1)%4);if(selected!=k)$fatal(1,"selection changed during reboot");
   safe_=1;wait(config_);#1;if(cbsel!=target)$fatal(1,"wrong Flash slot");
   wait(!config_);repeat(4)@(negedge clk);
   if(high_edges!=8||pulses!=p+1)$fatal(1,"wrong CONFIG pulse width/count");
   repeat(90)@(negedge clk);
   if(stop_||ena||config_||status!=3||pulses!=p+1)$fatal(1,"missing Flash caused a reboot loop");
  end
  safe_=0;reset_;write_(18,(CURRENT_SLOT+1)%4);p=pulses;write_(19,0);repeat(90)@(negedge clk);
  if(stop_||ena||config_||status!=3||pulses!=p)$fatal(1,"unsafe drain timeout triggered CONFIG");
  $display("PASS flash_image_switch slot=%0d: selection isolation, every destination, current no-op, drain, stable CBSEL/ENA, one CONFIG pulse, timeout and fallback loop prevention",CURRENT_SLOT);$finish;
 end
 initial begin #100000;$fatal(1,"switch controller timeout");end
endmodule
