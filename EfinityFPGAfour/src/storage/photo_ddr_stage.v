`timescale 1ns/1ps
// Publish only after all packed gallery words have an OK DDR BRESP.
module photo_ddr_stage #(parameter [19:0] PHOTO_BYTES=1036800,parameter WAIT_TIMEOUT=96000000)(
 input clk,input rst_n,
 input load_start,input load_byte_valid,input [7:0] load_byte,input [19:0] load_byte_offset,
 input load_done,input load_error,input gallery_mode,input display_vsync_toggle,
 input word_commit,input writer_busy,input write_error,
 output reg load_busy,output reg load_failed,output reg [19:0] loaded_byte_count,
 output reg load_abort,output reg load_ready,
 output reg photo_write_valid,output reg photo_write_buffer,
 output reg [19:0] photo_write_offset,output reg [7:0] photo_write_data,
 output reg gallery_display_enable,output reg display_buffer,output reg display_switch_toggle
);
 reg source_done,vsync_seen;reg [19:0] committed_bytes;reg [31:0] wait_timer;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   load_busy<=0;load_failed<=0;loaded_byte_count<=0;load_abort<=0;load_ready<=0;
   photo_write_valid<=0;photo_write_buffer<=0;photo_write_offset<=0;photo_write_data<=0;
   gallery_display_enable<=0;display_buffer<=0;display_switch_toggle<=0;
   source_done<=0;committed_bytes<=0;vsync_seen<=0;wait_timer<=0;
  end else begin
   photo_write_valid<=0;load_abort<=0;load_ready<=0;
   if(load_start&&!load_busy)begin
    load_busy<=1;load_failed<=0;loaded_byte_count<=0;committed_bytes<=0;source_done<=0;wait_timer<=0;
    photo_write_buffer<=!display_buffer;photo_write_offset<=0;
   end
   if(!gallery_mode)gallery_display_enable<=0;
   if(load_busy)begin
    if(load_byte_valid||word_commit||load_done)wait_timer<=0;
    else if(wait_timer<WAIT_TIMEOUT)wait_timer<=wait_timer+1'b1;
    if(word_commit)committed_bytes<=committed_bytes+16;
    if(load_byte_valid&&!load_failed&&gallery_mode)begin
     if(loaded_byte_count<PHOTO_BYTES && load_byte_offset<PHOTO_BYTES)begin
      photo_write_valid<=1;photo_write_data<=load_byte;photo_write_offset<=load_byte_offset;
      loaded_byte_count<=loaded_byte_count+1'b1;
     end else begin load_failed<=1;load_abort<=1;end
    end
    if((load_error||write_error||wait_timer>=WAIT_TIMEOUT)&&!load_failed)begin
     load_failed<=1;load_abort<=1;
    end
    if(load_done)begin
     source_done<=1;
     if(loaded_byte_count!=PHOTO_BYTES)begin load_failed<=1;load_abort<=1;end
    end
    if((load_failed||!gallery_mode)&&!writer_busy&&!photo_write_valid)load_busy<=0;
   end
   if(display_vsync_toggle!=vsync_seen)begin
    vsync_seen<=display_vsync_toggle;
    if(load_busy&&source_done&&!load_failed&&!load_error&&!write_error&&gallery_mode&&!writer_busy&&committed_bytes==PHOTO_BYTES&&loaded_byte_count==PHOTO_BYTES)begin
     display_buffer<=photo_write_buffer;gallery_display_enable<=1;
     display_switch_toggle<=!display_switch_toggle;load_busy<=0;load_ready<=1;
    end
   end
  end
 end
endmodule
