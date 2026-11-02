`timescale 1ns/1ps
// Queue byte-addressed gallery words independently of the active AXI write.
// MSB-first word packing matches R0_FIFO_8 ENDIANESS=0 byte read order.
module gallery_word_fifo #(parameter ABITS=6)(
 input clk,input rst_n,input stream_start,input stream_end,
 input byte_valid,input [7:0] byte_data,input [19:0] byte_offset,input byte_buffer,
 output word_valid,input word_take,output [127:0] word_data,
 output [19:0] word_offset,output word_buffer,output busy,output reg error
);
 reg active,failed,push;reg [3:0] packed_count;
 reg [127:0] pack;reg [19:0] base_offset;reg base_buffer;
 reg [148:0] queued_word;
 wire ready;wire [148:0] head;wire [ABITS:0] count;
 photo_async_fifo #(.WIDTH(149),.ABITS(ABITS)) fifo(
  .wclk(clk),.wrst_n(rst_n),.wvalid(push),.wready(ready),.wdata(queued_word),
  .rclk(clk),.rrst_n(rst_n),.rvalid(word_valid),.rready(word_take),.rdata(head),.rcount(count));
 assign {word_buffer,word_offset,word_data}=head;
 assign busy=active||push||packed_count!=0||word_valid||count!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;failed<=0;push<=0;packed_count<=0;pack<=0;base_offset<=0;base_buffer<=0;queued_word<=0;error<=0;end
  else begin
   push<=0;error<=0;
   if(stream_start)begin active<=1;failed<=0;packed_count<=0;end
   if(push&&!ready&&!failed)begin failed<=1;error<=1;end
   if(byte_valid&&active&&!failed)begin
    if((packed_count==0&&byte_offset[3:0]!=0)||
       (packed_count!=0&&(byte_offset!=base_offset+packed_count||byte_buffer!=base_buffer)))begin
     failed<=1;error<=1;
    end else begin
     if(packed_count==0)begin base_offset<=byte_offset;base_buffer<=byte_buffer;end
     pack<={pack[119:0],byte_data};packed_count<=packed_count+1'b1;
     if(packed_count==15)begin queued_word<={base_buffer,base_offset,pack[119:0],byte_data};push<=1;end
    end
   end
   if(stream_end)begin active<=0;packed_count<=0;end
   if(stream_start)begin active<=1;failed<=0;packed_count<=0;end
  end
 end
endmodule
