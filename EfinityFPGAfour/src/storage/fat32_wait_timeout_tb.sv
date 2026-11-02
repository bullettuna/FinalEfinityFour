`timescale 1ns/1ps
module fat32_wait_timeout_tb;
 reg clk=0,rst_n=0,start=0,init_done=0;always #5 clk=~clk;
 wire busy,done,error;wire [7:0] code;wire [5:0] error_stage;
 fat32_photo_writer #(.WIDTH(64),.HEIGHT(8),.WAIT_TIMEOUT(16)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.error(error),.error_code(code),.file_number(),
  .debug_state(),.debug_purpose(),.error_stage(error_stage),.init_start(),.init_done(init_done),.init_error(1'b0),.capacity_mb(32'd128),
  .block_start(),.block_write(),.block_lba(),.block_done(1'b0),.block_error(1'b0),.block_rx_valid(1'b0),.block_rx_data(8'd0),.block_byte_index(9'd0),.block_tx_byte(),
  .photo_start(),.photo_offset(),.photo_done(1'b0),.photo_error(1'b0),.photo_valid(1'b0),.photo_index(9'd0),.photo_byte(8'd0));
 integer errors=0;
 always @(posedge clk)begin if(error)errors=errors+1;if(done)$fatal(1,"timeout falsely returned success");end
 task automatic begin_save;
  begin @(negedge clk);start=1;@(negedge clk);start=0;end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst_n=1;begin_save();wait(errors==1);@(negedge clk);
  if(busy||code!=10||error_stage!=1)$fatal(1,"lost init callback not timed out");
  repeat(40)@(negedge clk);if(errors!=1)$fatal(1,"timeout repeats");
  begin_save();repeat(3)@(negedge clk);init_done=1;@(negedge clk);init_done=0;
  wait(errors==2);@(negedge clk);
  if(busy||code!=10||error_stage!=28)$fatal(1,"lost block callback not timed out");
  $display("PASS FAT32 no-progress wait deadlines + one-shot errors + next request");$finish;
 end
 initial begin #100000;$fatal(1,"writer timeout regression stalled");end
endmodule
