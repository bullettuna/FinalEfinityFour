`timescale 1ns/1ps
module photo_gallery_stage_tb;
 reg clk=0,rst=0,start=0,valid=0,done=0,mode=1,vs=0,take=0,commit=0,inject=0;
 reg [7:0] data=0;reg [19:0] offset=0;
 always #5 clk=~clk;
 wire byte_valid,bufsel,busy,failed,abort,loaded,enabled,displaybuf;
 wire [7:0] wd;wire [19:0] wo;
 wire qvalid,qbusy,qerror,qbuf;wire [127:0] word;wire [19:0] addr;
 photo_ddr_stage #(.PHOTO_BYTES(64),.WAIT_TIMEOUT(2000)) stage(
  .clk(clk),.rst_n(rst),.load_start(start),.load_byte_valid(valid),.load_byte(data),.load_byte_offset(offset),
  .load_done(done),.load_error(1'b0),.gallery_mode(mode),.display_vsync_toggle(vs),
  .word_commit(commit),.writer_busy(qbusy),.write_error(qerror||inject),.load_busy(busy),.load_failed(failed),
  .load_abort(abort),.load_ready(loaded),.photo_write_valid(byte_valid),.photo_write_buffer(bufsel),
  .photo_write_offset(wo),.photo_write_data(wd),.gallery_display_enable(enabled),.display_buffer(displaybuf));
 gallery_word_fifo #(.ABITS(2)) fifo(.clk(clk),.rst_n(rst),.stream_start(start),.stream_end(done||failed),
  .byte_valid(byte_valid),.byte_data(wd),.byte_offset(wo),.byte_buffer(bufsel),
  .word_valid(qvalid),.word_take(take),.word_data(word),.word_offset(addr),.word_buffer(qbuf),.busy(qbusy),.error(qerror));
 task send;
  begin
   @(negedge clk);start=1;@(negedge clk);start=0;
   for(integer k=0;k<64;k=k+1)begin valid=1;data=k;offset=k;@(negedge clk);end
   valid=0;repeat(3)@(negedge clk);done=1;@(negedge clk);done=0;
  end
 endtask
 task drain;
  reg [127:0] expected;
  begin
   for(integer n=0;n<4;n=n+1)begin
    wait(qvalid);@(negedge clk);
    for(integer k=0;k<16;k=k+1)expected[127-k*8 -:8]=n*16+k;
    if(word!==expected||addr!=n*16||qbuf!=bufsel)$fatal(1,"queued DDR word corrupt");
    repeat(5)begin @(negedge clk);if(word!==expected)$fatal(1,"stalled payload changed");end
    take=1;@(negedge clk);take=0;repeat(7)@(negedge clk);
    if(enabled&&!failed)$fatal(1,"published before BRESP");
    commit=1;@(negedge clk);commit=0;
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;send();vs=!vs;repeat(5)@(negedge clk);
  if(enabled||failed)$fatal(1,"early publish / FIFO failure");drain();
  repeat(8)@(negedge clk);if(enabled)$fatal(1,"publish outside VSYNC");vs=!vs;
  repeat(3)@(negedge clk);if(!enabled||busy)$fatal(1,"committed image not published");
  mode=0;repeat(3)@(negedge clk);mode=1;send();inject=1;@(negedge clk);inject=0;
  // Failed data must drain, but cannot publish even with enough commits.
  for(integer n=0;n<4;n=n+1)begin wait(qvalid);@(negedge clk);take=1;commit=1;@(negedge clk);take=0;commit=0;end
  repeat(12)@(negedge clk);vs=!vs;repeat(4)@(negedge clk);
  if(!failed||enabled||busy)$fatal(1,"DDR error falsely published / failed to drain");
  $display("PASS gallery FIFO ordering/stalls + all DDR BRESP commit before VSYNC publish + error drain");$finish;
 end
 initial begin #100000;$fatal(1,"stage timeout");end
endmodule
