`timescale 1ns/1ps
// Passive observers only: no ready/reset/mode output can affect live video.
module image2_video_count_sync(
 input source_clk,clk,rst_n,input [31:0] source_count,output [31:0] count
);
 reg [31:0] gray;
 (* async_reg="true" *) reg [31:0] meta,sync_count;
 always @(posedge source_clk or negedge rst_n)
  if(!rst_n)gray<=0;else gray<=(source_count>>1)^source_count;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin meta<=0;sync_count<=0;end
  else begin meta<=gray;sync_count<=meta;end
 genvar k;
 generate for(k=0;k<32;k=k+1)begin:g_decode
  assign count[k]=^(sync_count>>k);
 end endgenerate
endmodule

module image2_video_counters #(parameter EXPECTED_WORDS=518400)(
 input clk,cam_clk,pixel_clk,rst_n,
 input cam_vs,cam_de,input [31:0] underflow_count,bad_frame_count,status,
 input [31:0] video_awaddr,video_araddr,
 input video_awvalid,video_awready,video_arvalid,video_arready,
 input aux_awvalid,aux_awready,aux_arvalid,aux_arready,
 output [383:0] data
);
 reg cam_vs_d;
 reg [31:0] camera_frames,camera_good,camera_words,frame_words;
 always @(posedge cam_clk or negedge rst_n)begin
  if(!rst_n)begin cam_vs_d<=0;camera_frames<=0;camera_good<=0;camera_words<=0;frame_words<=0;end
  else begin
   cam_vs_d<=cam_vs;
   if(!cam_vs_d&&cam_vs)frame_words<=0;
   else if(cam_vs&&cam_de)frame_words<=frame_words+1'b1;
   if(cam_vs&&cam_de)camera_words<=camera_words+1'b1;
   if(cam_vs_d&&!cam_vs)begin
    camera_frames<=camera_frames+1'b1;
    if(frame_words==EXPECTED_WORDS)camera_good<=camera_good+1'b1;
   end
  end
 end
 wire [31:0] frames_sync,good_sync,words_sync,underflow_sync;
 image2_video_count_sync c0(cam_clk,clk,rst_n,camera_frames,frames_sync);
 image2_video_count_sync c1(cam_clk,clk,rst_n,camera_good,good_sync);
 image2_video_count_sync c2(cam_clk,clk,rst_n,camera_words,words_sync);
 image2_video_count_sync c3(pixel_clk,clk,rst_n,underflow_count,underflow_sync);
 reg [31:0] ticks,read_frames,read_changes,write_changes,aux_reads,aux_writes;
 reg [1:0] read_buffer,write_buffer;
 reg read_seen,write_seen;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ticks<=0;read_frames<=0;read_changes<=0;write_changes<=0;aux_reads<=0;aux_writes<=0;
   read_buffer<=0;write_buffer<=0;read_seen<=0;write_seen<=0;end
  else begin
   ticks<=ticks+1'b1;
   if(video_arvalid&&video_arready&&video_araddr[21:0]==0)begin
    read_frames<=read_frames+1'b1;
    if(read_seen&&read_buffer!=video_araddr[23:22])read_changes<=read_changes+1'b1;
    read_seen<=1;read_buffer<=video_araddr[23:22];
   end
   if(video_awvalid&&video_awready)begin
    if(write_seen&&write_buffer!=video_awaddr[23:22])write_changes<=write_changes+1'b1;
    write_seen<=1;write_buffer<=video_awaddr[23:22];
   end
   if(aux_arvalid&&aux_arready)aux_reads<=aux_reads+1'b1;
   if(aux_awvalid&&aux_awready)aux_writes<=aux_writes+1'b1;
  end
 end
 // Least-significant word is first on the wire. Ring changes are observed
 // descriptors, not a guarantee that pixels reached the screen successfully.
 assign data={status,aux_writes,aux_reads,underflow_sync,bad_frame_count,
              write_changes,read_changes,read_frames,words_sync,good_sync,frames_sync,ticks};
endmodule

// ~2D reply: P2D1 + twelve little-endian uint32 words + CRC32 of first 52
// bytes. Capture once, then hold every byte stable through UART backpressure.
module image2_video_packet(
 input clk,rst_n,start,input [383:0] data,
 output reg busy,output last,output valid,output [7:0] byte_data,input ready
);
 reg [415:0] held;
 reg [5:0] index;
 reg [31:0] crc;
 function [31:0] crc_byte;
  input [31:0] previous;input [7:0] b;reg [31:0] c;integer k;
  begin c=previous^b;for(k=0;k<8;k=k+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 assign last=busy && index==55;
 assign valid=busy;
 assign byte_data=index<52?held[index*8+:8]:(~crc>>((index-52)*8));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin held<=0;index<=0;crc<=0;busy<=0;end
  else if(start&&!busy)begin held<={data,32'h31443250};index<=0;crc<=32'hffffffff;busy<=1;end
  else if(valid&&ready)begin
   if(index<52)crc<=crc_byte(crc,byte_data);
   if(index==55)busy<=0;else index<=index+1'b1;
  end
 end
endmodule
