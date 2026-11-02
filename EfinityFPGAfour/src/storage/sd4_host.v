`timescale 1ns/1ps
// Native 3.3 V SD memory host, 4-bit data, 512-byte CMD17/CMD24 transactions.
// Never asserts DAT3 as SPI CS. CRC7 and four CRC16 lanes are checked.
// CMD13 follows every write; block_done requires READY_FOR_DATA/TRAN state.
module sd4_host #(
 parameter CLK_HZ=96000000, INIT_DIV=120, FAST_DIV=8,
 parameter POWER_CYCLES=960000, DATA_TIMEOUT=48000000, INIT_RETRIES=8192,
 parameter INIT_TIMEOUT=CLK_HZ
)(input clk,input rst_n,
 output reg sd_clk,output sd_cmd_o,output sd_cmd_oe,input sd_cmd_i,
 input [3:0] sd_dat_i,output reg [3:0] sd_dat_o,output reg [3:0] sd_dat_oe,
 input init_start,output reg init_busy,output reg init_done,output reg init_error,
 output reg [5:0] error_command,output reg [3:0] error_reason,
 output reg high_capacity,output reg initialized,output reg [31:0] capacity_mb,
 input block_start,input block_write,input [31:0] block_lba,
 output reg block_busy,output reg block_done,output reg block_error,
 output reg block_rx_valid,output reg [7:0] block_rx_data,
 output reg [8:0] block_byte_index,input [7:0] block_tx_byte
);
 reg [15:0] divider;
 wire [15:0] division=initialized?FAST_DIV:INIT_DIV;
 wire half_tick=(divider==division-1);
 wire rise=half_tick&&!sd_clk,fall=half_tick&&sd_clk;
 (* async_reg="true" *) reg cm1,cm2;
 (* async_reg="true" *) reg [3:0] di1,di2;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin divider<=0;sd_clk<=0;cm1<=1;cm2<=1;di1<=15;di2<=15;end
  else begin cm1<=sd_cmd_i;cm2<=cm1;di1<=sd_dat_i;di2<=di1;
   if(half_tick) begin divider<=0;sd_clk<=~sd_clk;end else divider<=divider+1'b1;
  end
 end
 reg cmd_start;reg [5:0] cmd_index;reg [31:0] cmd_arg;reg [1:0] cmd_kind;
 wire cmd_busy,cmd_done,cmd_error;wire [135:0] resp;wire [3:0] cmd_error_reason;
 sd4_command cmd(.clk(clk),.rst_n(rst_n),.rise(rise),.fall(fall),.start(cmd_start),
  .command(cmd_index),.argument(cmd_arg),.response_kind(cmd_kind),.cmd_i(cm2),
  .cmd_o(sd_cmd_o),.cmd_oe(sd_cmd_oe),.busy(cmd_busy),.done(cmd_done),.error(cmd_error),
  .error_reason(cmd_error_reason),.response(resp));
 function [15:0] crc16;
 input [15:0] c;input b;
 begin crc16={c[14:0],1'b0}^((c[15]^b)?16'h1021:16'h0000);end
 endfunction
 function [31:0] csd_capacity;
 input [127:0] c;reg [63:0] size;
 begin
  if(c[127:126]==1) csd_capacity=({10'd0,c[69:48]}+1)>>1;
  else begin size=({52'd0,c[73:62]}+1) << (c[83:80]+c[49:47]+2);csd_capacity=size>>20;end
 end
 endfunction
 localparam IDLE=0,POWER=1,CLOCKS=2,C0=3,C8=4,C55=5,C41=6,C2=7,C3=8,C9=9,C7=10,
  SELECT_WAIT=11,C16=12,BUS55=13,BUS6=14,READY=15,BLOCK_CMD=16,TRANSFER=17,
  STATUS=18,WAIT_CMD=19,FAIL=20,INIT_FINISH=21,CHECK_READY=22;
 reg [5:0] state,after_cmd;
 reg [31:0] timer;reg [15:0] retries,rca;reg [7:0] clocks;
 reg v2,write_op,command_ok;
 // Error numbers are also decoded by photo_event_uart; keep their meanings
 // stable so an on-board failure identifies both the command and its cause.
 localparam ERR_NONE=0,ERR_TIMEOUT=1,ERR_CRC=2,ERR_FRAME=3,ERR_STATUS=4,
  ERR_ECHO=5,ERR_INIT_TIMEOUT=6,ERR_BUSY_TIMEOUT=7,ERR_CSD=8,
  ERR_DATA_CRC=9,ERR_DATA_TOKEN=10,ERR_DATA_TIMEOUT=11,ERR_ADDRESS=12,ERR_VOLTAGE=13;
 reg acmd_polling;reg [31:0] acmd_timer;
 wire status_bad=|(resp[39:8]&32'hfdffe008);
 task launch;
 input [5:0] ix;input [31:0] arg;input [1:0] k;input [5:0] next_state;
 begin cmd_index<=ix;cmd_arg<=arg;cmd_kind<=k;cmd_start<=1;after_cmd<=next_state;state<=WAIT_CMD;end
 endtask
 task fail;
 input [3:0] reason;
 begin error_command<=cmd_index;error_reason<=reason;state<=FAIL;end
 endtask
 // Data engine is armed before CMD17, since the card can start DAT while the
 // command response is still being checked. The upper layer waits for CRC.
 localparam D_IDLE=0,D_RSTART=1,D_RDATA=2,D_RCRC=3,D_REND=4,D_WGAP=5,
  D_WSTART=6,D_WDATA=7,D_WCRC=8,D_WEND=9,D_RELEASE=10,D_TOKEN=11,D_TOKENBITS=12,D_BUSY=13;
 reg [3:0] ds;reg [10:0] nibble;reg [4:0] crc_bit;
 reg [15:0] crc0,crc1,crc2,crc3;
 reg [7:0] tx_byte;reg [3:0] hi_nibble;reg [4:0] token;
 reg [3:0] token_bits;reg data_done,data_failed;
 reg [3:0] data_error_reason;
 reg [31:0] data_timer;
 wire [3:0] tx_nibble=nibble[0]?tx_byte[3:0]:block_tx_byte[7:4];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;after_cmd<=IDLE;timer<=0;retries<=0;rca<=0;clocks<=0;v2<=1;
   write_op<=0;command_ok<=0;cmd_start<=0;cmd_index<=0;cmd_arg<=0;cmd_kind<=0;
   error_command<=0;error_reason<=ERR_NONE;acmd_polling<=0;acmd_timer<=0;
   initialized<=0;high_capacity<=0;capacity_mb<=0;init_busy<=0;init_done<=0;init_error<=0;
   block_busy<=0;block_done<=0;block_error<=0;block_rx_valid<=0;block_rx_data<=0;block_byte_index<=0;
   sd_dat_o<=15;sd_dat_oe<=0;ds<=D_IDLE;nibble<=0;crc_bit<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
   tx_byte<=0;hi_nibble<=0;token<=0;token_bits<=0;data_done<=0;data_failed<=0;
   data_error_reason<=ERR_NONE;data_timer<=0;
  end else begin
   cmd_start<=0;init_done<=0;init_error<=0;block_done<=0;block_error<=0;block_rx_valid<=0;
   if(acmd_polling && acmd_timer<INIT_TIMEOUT) acmd_timer<=acmd_timer+1'b1;
   case(state)
    IDLE: if(init_start) begin
     initialized<=0;init_busy<=1;timer<=0;retries<=0;v2<=1;
     error_command<=0;error_reason<=ERR_NONE;acmd_polling<=0;acmd_timer<=0;state<=POWER;
    end
    POWER: if(timer==POWER_CYCLES-1) begin clocks<=0;state<=CLOCKS;end else timer<=timer+1'b1;
    CLOCKS: if(rise) begin if(clocks==79) launch(0,0,0,C0);else clocks<=clocks+1'b1;end
    C0: launch(8,32'h000001aa,1,C8);
    C8: begin
     // Older SDSC cards may reject CMD8 or omit its response. A corrupt
     // response is a communication error, not evidence of an older card.
     if(resp[30]) begin v2<=0;launch(55,0,1,C55);end
     else if(resp[39:8]==32'h000001aa) begin v2<=1;launch(55,0,1,C55);end
     else fail(ERR_ECHO);
    end
    C55: if(status_bad || !resp[13]) fail(ERR_STATUS);
          else begin
           if(!acmd_polling) begin acmd_polling<=1;acmd_timer<=0;end
           launch(41,v2?32'h40ff8000:32'h00ff8000,3,C41);
          end
    C41: begin
     if((resp[39:8]&32'h00ff8000)==0) fail(ERR_VOLTAGE);
     else if(resp[39]) begin acmd_polling<=0;high_capacity<=v2&&resp[38];launch(2,0,2,C2);end
     else if(retries==INIT_RETRIES-1 || acmd_timer>=INIT_TIMEOUT) fail(ERR_INIT_TIMEOUT);
     else begin retries<=retries+1'b1;launch(55,0,1,C55);end
    end
    C2: launch(3,0,1,C3);
    C3: if(resp[23:21]!=0 || resp[39:24]==0) fail(ERR_STATUS);
        else begin rca<=resp[39:24];launch(9,{resp[39:24],16'd0},2,C9);end
    C9: begin
     if(resp[127:126]>1 || csd_capacity(resp[127:0])==0 ||
        ((resp[127:126]==1)!=high_capacity)) fail(ERR_CSD);
     else begin capacity_mb<=csd_capacity(resp[127:0]);launch(7,{rca,16'd0},1,C7);end
    end
    C7: if(status_bad) fail(ERR_STATUS);else begin timer<=0;clocks<=0;state<=SELECT_WAIT;end
    SELECT_WAIT: begin
     timer<=timer+1'b1;
     if(timer>=DATA_TIMEOUT) fail(ERR_BUSY_TIMEOUT);
     else if(rise) begin
      if(clocks!=8) clocks<=clocks+1'b1;
      else if(di2[0]) begin
       if(high_capacity) launch(55,{rca,16'd0},1,BUS55);else launch(16,512,1,C16);
      end
     end
    end
    C16: if(status_bad) fail(ERR_STATUS);else launch(55,{rca,16'd0},1,BUS55);
    BUS55: if(status_bad||!resp[13]) fail(ERR_STATUS);else launch(6,2,1,BUS6);
    BUS6: if(status_bad) fail(ERR_STATUS);else state<=INIT_FINISH;
    INIT_FINISH: if(fall) begin initialized<=1;init_busy<=0;init_done<=1;state<=READY;end
    READY: begin
     if(init_start) begin
      init_busy<=1;error_command<=0;error_reason<=ERR_NONE;launch(13,{rca,16'd0},1,CHECK_READY);
     end
     else if(block_start) begin
      block_busy<=1;write_op<=block_write;command_ok<=0;data_done<=0;data_failed<=0;
      data_timer<=0;block_byte_index<=0;nibble<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
      data_error_reason<=ERR_NONE;error_reason<=ERR_NONE;
      if(!high_capacity && block_lba[31:23]!=0) begin
       error_command<=block_write?24:17;error_reason<=ERR_ADDRESS;state<=FAIL;
      end else begin
       if(!block_write) ds<=D_RSTART;
       launch(block_write?24:17,high_capacity?block_lba:(block_lba<<9),1,BLOCK_CMD);
      end
     end
    end
    BLOCK_CMD: if(status_bad) fail(ERR_STATUS);else begin
     command_ok<=1;state<=TRANSFER;
     if(write_op) begin ds<=D_WGAP;clocks<=0;data_timer<=0;end
    end
    TRANSFER: begin
     if(data_failed) fail(data_error_reason);
     else if(data_done&&command_ok) begin
      if(write_op) launch(13,{rca,16'd0},1,STATUS);
      else begin block_busy<=0;block_done<=1;state<=READY;end
     end
    end
    STATUS: if(status_bad || !resp[16] || resp[20:17]!=4) fail(ERR_STATUS);
       else begin block_busy<=0;block_done<=1;state<=READY;end
    CHECK_READY: if(status_bad || !resp[16] || resp[20:17]!=4) fail(ERR_STATUS);
       else begin init_busy<=0;init_done<=1;state<=READY;end
    WAIT_CMD: begin
     if(cmd_error) begin
      if(after_cmd==C8 && cmd_error_reason==ERR_TIMEOUT) begin v2<=0;launch(55,0,1,C55);end
      else fail(cmd_error_reason);
     end else if(cmd_done) state<=after_cmd;
    end
    FAIL: begin
     sd_dat_oe<=0;ds<=D_IDLE;initialized<=0;acmd_polling<=0;
     if(init_busy) init_error<=1;else block_error<=1;
     init_busy<=0;block_busy<=0;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
   if(ds!=D_IDLE && state!=FAIL) begin
    if(data_timer>=DATA_TIMEOUT) begin
     data_failed<=1;data_error_reason<=ERR_DATA_TIMEOUT;ds<=D_IDLE;sd_dat_oe<=0;
    end
    else begin
     data_timer<=data_timer+1'b1;
     case(ds)
      D_RSTART: if(rise && di2==0) begin nibble<=0;ds<=D_RDATA;end
      D_RDATA: if(rise) begin
       crc0<=crc16(crc0,di2[0]);crc1<=crc16(crc1,di2[1]);crc2<=crc16(crc2,di2[2]);crc3<=crc16(crc3,di2[3]);
       if(!nibble[0]) hi_nibble<=di2;else begin
        block_rx_data<={hi_nibble,di2};block_rx_valid<=1;block_byte_index<=nibble[9:1];end
       if(nibble==1023) begin crc_bit<=15;ds<=D_RCRC;end else nibble<=nibble+1'b1;
      end
      D_RCRC: if(rise) begin
       if(di2!={crc3[crc_bit],crc2[crc_bit],crc1[crc_bit],crc0[crc_bit]}) begin
        data_failed<=1;data_error_reason<=ERR_DATA_CRC;
       end
       if(crc_bit==0) ds<=D_REND;else crc_bit<=crc_bit-1'b1;
      end
      D_REND: if(rise) begin
       if(di2!=15) begin data_failed<=1;data_error_reason<=ERR_FRAME;end
       data_done<=1;ds<=D_IDLE;
      end
      D_WGAP: if(fall) begin if(clocks==7) begin sd_dat_oe<=15;sd_dat_o<=0;ds<=D_WDATA;nibble<=0;end else clocks<=clocks+1'b1;end
      D_WDATA: if(fall) begin
       sd_dat_o<=tx_nibble;
       crc0<=crc16(crc0,tx_nibble[0]);crc1<=crc16(crc1,tx_nibble[1]);
       crc2<=crc16(crc2,tx_nibble[2]);crc3<=crc16(crc3,tx_nibble[3]);
       if(!nibble[0])tx_byte<=block_tx_byte;else if(nibble!=1023)block_byte_index<=block_byte_index+1'b1;
       if(nibble==1023)begin crc_bit<=15;ds<=D_WCRC;end else nibble<=nibble+1'b1;
      end
      D_WCRC: if(fall) begin sd_dat_o<={crc3[crc_bit],crc2[crc_bit],crc1[crc_bit],crc0[crc_bit]};
       if(crc_bit==0)ds<=D_WEND;else crc_bit<=crc_bit-1'b1;end
      D_WEND: if(fall) begin sd_dat_o<=15;ds<=D_RELEASE;end
      D_RELEASE: if(fall) begin sd_dat_oe<=0;ds<=D_TOKEN;end
      D_TOKEN: if(rise&&!di2[0]) begin token<=0;token_bits<=1;ds<=D_TOKENBITS;end
      D_TOKENBITS: if(rise) begin
       token<={token[3:0],di2[0]};
       if(token_bits==4)begin
        if({token[3:0],di2[0]}!=5'b00101) begin data_failed<=1;data_error_reason<=ERR_DATA_TOKEN;end
        clocks<=0;ds<=D_BUSY;
       end else token_bits<=token_bits+1'b1;
      end
      D_BUSY: if(rise) begin
       if(clocks!=8)clocks<=clocks+1'b1;
       else if(di2[0])begin data_done<=1;ds<=D_IDLE;end
      end
      default:ds<=D_IDLE;
     endcase
    end
   end
  end
 end
endmodule
