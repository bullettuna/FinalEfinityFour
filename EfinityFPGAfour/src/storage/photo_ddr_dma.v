`timescale 1ns/1ps
// Private 1 MiB capture buffers. Existing live/background/gallery areas end
// below 0x01600000. Pixels are stored bottom-up, little-endian for RGB565 BMP.
module photo_ddr_dma #(
 parameter WIDTH=960,HEIGHT=540, READ_TIMEOUT=4800000, RECOVERY_TIMEOUT=48000000,
 parameter [31:0] BASE0=32'h01600000,BASE1=32'h01700000
)(
 input clk,input rst_n,input pclk,input prst_n,
 input start,input buffer_select,output reg busy,output reg done,output reg error,
 input pixel_valid,input [15:0] pixel_data,input pixel_active,input pixel_done_toggle,
 input read_start,input read_buffer,input [19:0] read_offset,
 output reg read_done,output reg read_error,output reg read_valid,
 output reg [8:0] read_index,output reg [7:0] read_byte,
 output read_busy,output [3:0] read_debug,output reg [5:0] read_beats,
 output reg [3:0] read_fault,output reg read_reset_required,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,
 input bvalid,input [1:0] bresp,
 output reg [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 localparam ROW_BYTES=WIDTH*2, WORDS=WIDTH*HEIGHT/8;
 reg act_d;reg [2:0] pack_n;reg [111:0] pack;
 reg [19:0] pixel_count;reg overflow;
 reg push;reg [127:0] packed_data;
 wire push_ready,head_valid;wire [127:0] head_data;wire [10:0] available;
 wire pop;
 always @(posedge pclk or negedge prst_n) begin
  if(!prst_n) begin act_d<=0;pack_n<=0;pack<=0;pixel_count<=0;overflow<=0;push<=0;packed_data<=0;end
  else begin
   act_d<=pixel_active;push<=0;
   if(pixel_active&&!act_d) begin pack_n<=0;pixel_count<=0;overflow<=0;end
   if(push&&!push_ready) overflow<=1;
   if(pixel_valid) begin
    if(pixel_count<WIDTH*HEIGHT) begin
     pixel_count<=pixel_count+1'b1;
     pack<={pixel_data,pack[111:16]};pack_n<=pack_n+1'b1;
     if(pack_n==7) begin packed_data<={pixel_data,pack};push<=1;end
    end else overflow<=1;
   end
  end
 end
 photo_async_fifo #(.WIDTH(128),.ABITS(10)) fifo(
  .wclk(pclk),.wrst_n(prst_n),.wvalid(push),.wready(push_ready),.wdata(packed_data),
  .rclk(clk),.rrst_n(rst_n),.rvalid(head_valid),.rready(pop),.rdata(head_data),.rcount(available));
 (* async_reg="true" *) reg d1,d2,o1,o2;
 (* async_reg="true" *) reg [19:0] n1,n2;
 reg done_seen,source_finished,bad;reg [3:0] settle;
 reg [2:0] ws;reg [2:0] beat;
 reg [19:0] row_base;reg [11:0] col;
 reg [19:0] words_written;reg slot;
 assign awaddr=(slot?BASE1:BASE0)+row_base+col;
 assign awlen=7;assign awvalid=(ws==1);
 assign wvalid=(ws==2)&&head_valid;
 assign wdata=head_data;assign wlast=(beat==7);
 // A malformed partial final burst is drained without publishing the frame.
 assign pop=((ws==2)&&wready) || ((ws==0)&&source_finished&&settle==15&&available<8);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin d1<=0;d2<=0;o1<=0;o2<=0;n1<=0;n2<=0;done_seen<=0;
   source_finished<=0;settle<=0;bad<=0;ws<=0;beat<=0;row_base<=0;col<=0;
   words_written<=0;slot<=0;busy<=0;done<=0;error<=0;end
  else begin
   d1<=pixel_done_toggle;d2<=d1;o1<=overflow;o2<=o1;n1<=pixel_count;n2<=n1;
   done<=0;error<=0;
   if(start&&!busy) begin busy<=1;slot<=buffer_select;words_written<=0;
    row_base<=(HEIGHT-1)*ROW_BYTES;col<=0;bad<=0;source_finished<=0;settle<=0;done_seen<=d2;end
   if(busy&&d2!=done_seen) begin done_seen<=d2;source_finished<=1;end
   if(source_finished&&settle!=15) settle<=settle+1'b1;
   case(ws)
    0: if(busy) begin
     if(available>=8 && words_written<WORDS) begin beat<=0;ws<=1;end
     else if(source_finished&&settle==15&&!head_valid&&available==0) begin
      busy<=0;source_finished<=0;
      if(!bad&&!o2&&n2==WIDTH*HEIGHT&&words_written==WORDS) done<=1;else error<=1;
     end
    end
    1: if(awready) ws<=2;
    2: if(wvalid&&wready) begin beat<=beat+1'b1;if(beat==7) ws<=3;end
    3: if(bvalid) begin
     if(bresp!=0) bad<=1;
     words_written<=words_written+8;
     if(col==ROW_BYTES-128) begin col<=0;row_base<=row_base-ROW_BYTES;end else col<=col+128;
     ws<=0;
    end
    default: ws<=0;
   endcase
  end
 end
 // Four short (8 x 128-bit) bursts fill a 512-byte sector first. DDR is
 // released before byte serialization; RREADY stays high throughout a burst.
 localparam R_IDLE=0,R_ADDR=1,R_DATA=2,R_LOAD=3,R_EMIT=4,
  R_DRAIN_ADDR=5,R_DRAIN_DATA=6,R_FINISH=7;
 reg [2:0] rs;reg [1:0] burst;reg [2:0] rd_beat;
 reg [4:0] word_index;reg [3:0] byte_index;
 reg rd_bad;reg [31:0] read_timer;
 (* ram_style="block" *) reg [127:0] sector_words[0:31];
 reg [127:0] cached_word;
 always @(posedge clk)begin
  if(rs==R_DATA&&rvalid&&rready)sector_words[{burst,rd_beat}]<=rdata;
  if(rs==R_LOAD)cached_word<=sector_words[word_index];
 end
 assign read_busy=(rs!=R_IDLE);
 assign read_debug=read_reset_required?4'd8:{1'b0,rs};
 assign arlen=7;
 assign arvalid=(rs==R_ADDR)||(rs==R_DRAIN_ADDR);
 assign rready=(rs==R_DATA)||(rs==R_DRAIN_DATA);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   rs<=R_IDLE;burst<=0;rd_beat<=0;word_index<=0;byte_index<=0;
   rd_bad<=0;read_timer<=0;read_beats<=0;read_fault<=0;read_reset_required<=0;
   araddr<=0;read_done<=0;read_error<=0;read_valid<=0;read_byte<=0;read_index<=0;
  end else begin
   read_done<=0;read_error<=0;read_valid<=0;
   case(rs)
    R_IDLE:if(read_start)begin
     rd_bad<=0;read_beats<=0;read_index<=0;burst<=0;rd_beat<=0;
     word_index<=0;byte_index<=0;read_timer<=0;read_fault<=0;read_reset_required<=0;
     araddr<=(read_buffer?BASE1:BASE0)+read_offset;
     if(read_offset[8:0]!=0 || read_offset>WIDTH*HEIGHT*2-512)begin read_error<=1;read_fault<=6;end
     else rs<=R_ADDR;
    end
    R_ADDR:begin
     if(arready)begin rs<=R_DATA;read_timer<=0;end
     else if(read_timer==READ_TIMEOUT-1)begin
      // VALID remains asserted. An offered address cannot be silently
      // canceled; finish its eventual transaction without publishing data.
      read_error<=1;read_fault<=1;read_timer<=0;rs<=R_DRAIN_ADDR;
     end else read_timer<=read_timer+1'b1;
    end
    R_DATA:begin
     if(rvalid&&rready)begin
      read_timer<=0;read_beats<=read_beats+1'b1;rd_beat<=rd_beat+1'b1;
      if(rresp!=0)begin rd_bad<=1;read_fault<=4;end
      if(rlast)begin
       if(rd_beat!=7 || rd_bad || rresp!=0)begin
        read_error<=1;rs<=R_IDLE;
        if(rd_beat!=7)read_fault<=5;
       end else if(burst==3)begin word_index<=0;rs<=R_LOAD;end
       else begin burst<=burst+1'b1;rd_beat<=0;araddr<=araddr+128;rs<=R_ADDR;end
      end else if(rd_beat==7)begin
       read_error<=1;read_fault<=3;read_timer<=0;rs<=R_DRAIN_DATA;
      end
     end else if(read_timer==READ_TIMEOUT-1)begin
      read_error<=1;read_fault<=2;read_timer<=0;rs<=R_DRAIN_DATA;
     end else read_timer<=read_timer+1'b1;
    end
    R_LOAD:begin byte_index<=0;rs<=R_EMIT;end
    R_EMIT:begin
     read_valid<=1;read_byte<=cached_word[byte_index*8 +:8];read_index<={word_index,byte_index};
     if(byte_index==15)begin
      if(word_index==31)rs<=R_FINISH;
      else begin word_index<=word_index+1'b1;rs<=R_LOAD;end
     end else byte_index<=byte_index+1'b1;
    end
    R_FINISH:begin rs<=R_IDLE;read_done<=1;end
    R_DRAIN_ADDR:begin
     if(arready)begin rs<=R_DRAIN_DATA;read_timer<=0;end
     else if(read_timer<RECOVERY_TIMEOUT)read_timer<=read_timer+1'b1;
     else read_reset_required<=1;
    end
    R_DRAIN_DATA:begin
     if(rvalid&&rready)begin
      read_timer<=0;
      if(rlast)begin rs<=R_IDLE;read_reset_required<=0;end
     end else if(read_timer<RECOVERY_TIMEOUT)read_timer<=read_timer+1'b1;
     else read_reset_required<=1;
    end
    default:rs<=R_IDLE;
   endcase
  end
 end
endmodule
