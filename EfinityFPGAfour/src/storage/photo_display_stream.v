`timescale 1ns/1ps
// Little-endian RGB565 -> exact 2x scaling, with a retained source line.
module photo_display_stream #(
 parameter [11:0] DISPLAY_WIDTH=1920,parameter [10:0] DISPLAY_HEIGHT=1080
)(
 input clk,input rst_n,input gallery_enable,input photo_stream_reset,
 input in_vsync,input in_hsync,input in_href,
 input photo_byte_valid,input [7:0] photo_byte,output photo_byte_ready,
 output reg out_vsync,output reg out_hsync,output reg out_href,
 output [7:0] out_red,output [7:0] out_green,output [7:0] out_blue,
 output reg frame_error
);
 localparam SOURCE_WIDTH=DISPLAY_WIDTH/2,SOURCE_PIXELS=SOURCE_WIDTH*(DISPLAY_HEIGHT/2);
 reg vsync_d,href_d,enable_d,armed;
 reg [11:0] display_x;reg [10:0] display_y;
 reg byte_phase;reg [7:0] low_byte;
 reg [15:0] word0,word1,displayed_word,out_word;
 reg [15:0] line_read_word;
 reg use_line;
 reg wp,rp;reg [1:0] word_count;reg [19:0] received_words;
 (* ram_style="block" *) reg [15:0] source_line[0:SOURCE_WIDTH-1];
 wire frame_start=in_vsync&&!vsync_d,line_start=in_href&&!href_d;
 wire [11:0] current_x=line_start?12'd0:display_x;
 wire [10:0] current_y=line_start?(display_y+1'b1):display_y;
 wire active=in_href&&current_x<DISPLAY_WIDTH&&current_y<DISPLAY_HEIGHT;
 wire source_pixel=active&&!current_y[0]&&!current_x[0];
 wire reset_stream=frame_start||photo_stream_reset||!gallery_enable||(gallery_enable!=enable_d);
 assign photo_byte_ready=gallery_enable&&armed&&!reset_stream&&!frame_error&&
                         received_words<SOURCE_PIXELS&&(word_count<2||source_pixel);
 wire byte_take=photo_byte_valid&&photo_byte_ready;
 wire push_word=byte_take&&byte_phase;
 wire [15:0] incoming_word={photo_byte,low_byte};
 wire word_available=(word_count!=0)||push_word;
 wire [15:0] head_word=word_count!=0?(rp?word1:word0):incoming_word;
 wire pop_word=gallery_enable&&armed&&!reset_stream&&!frame_error&&source_pixel&&word_available;
 wire pixel_missing=gallery_enable&&armed&&!reset_stream&&!frame_error&&source_pixel&&!word_available;
 // Keep the RAM read register separate from the RGB/source selection. Mixing
 // these in one conditional assignment prevents Efinity BRAM inference.
 always @(posedge clk)begin
  if(pop_word)source_line[current_x[11:1]]<=head_word;
 end
 always @(posedge clk)line_read_word<=source_line[current_x[11:1]];
 // Both source and repeated lines still have one registered output cycle.
 always @(posedge clk)begin
  use_line<=gallery_enable&&armed&&!reset_stream&&!frame_error&&active&&current_y[0];
  if(gallery_enable&&armed&&!reset_stream&&!frame_error&&active)begin
   if(!current_x[0])out_word<=word_available?head_word:16'd0;
   else out_word<=displayed_word;
  end else out_word<=0;
 end
 wire [15:0] output_pixel=use_line?line_read_word:out_word;
 assign out_red=out_href?{output_pixel[15:11],3'b000}:8'd0;
 assign out_green=out_href?{output_pixel[10:5],2'b00}:8'd0;
 assign out_blue=out_href?{output_pixel[4:0],3'b000}:8'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   vsync_d<=0;href_d<=0;enable_d<=0;armed<=0;display_x<=0;display_y<=11'h7ff;
   byte_phase<=0;low_byte<=0;word0<=0;word1<=0;wp<=0;rp<=0;word_count<=0;received_words<=0;
   displayed_word<=0;frame_error<=0;out_vsync<=0;out_hsync<=0;out_href<=0;
  end else begin
   vsync_d<=in_vsync;href_d<=in_href;enable_d<=gallery_enable;
   out_vsync<=in_vsync;out_hsync<=in_hsync;out_href<=in_href;
   if(frame_start)begin display_x<=0;display_y<=11'h7ff;armed<=gallery_enable;end
   else if(in_href)begin
    if(line_start)begin display_x<=1;display_y<=display_y+1'b1;end
    else if(display_x<DISPLAY_WIDTH-1)display_x<=display_x+1'b1;
   end
   if(reset_stream)begin
    byte_phase<=0;word_count<=0;wp<=0;rp<=0;received_words<=0;displayed_word<=0;frame_error<=0;
    if(!gallery_enable)armed<=0;
    else if(gallery_enable!=enable_d)armed<=in_vsync;
   end else begin
    if(byte_take)begin
     byte_phase<=!byte_phase;
     if(!byte_phase)low_byte<=photo_byte;
     else begin
      if(wp)word1<=incoming_word;else word0<=incoming_word;
      wp<=!wp;received_words<=received_words+1'b1;
     end
    end
    if(pop_word)begin rp<=!rp;displayed_word<=head_word;end
    case({push_word,pop_word})
     2'b10:word_count<=word_count+1'b1;
     2'b01:word_count<=word_count-1'b1;
     default:begin end
    endcase
    if(pixel_missing)begin frame_error<=1;displayed_word<=0;end
   end
  end
 end
endmodule
