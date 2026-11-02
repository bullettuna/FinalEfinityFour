`timescale 1ns/1ps
// One owned dual-clock snapshot; never write while the FT clock owns it.
// Grey uses centre decimation. Binary preview ORs each SCALE x SCALE tile,
// preserving thin Canny lines instead of discarding them by decimation.
module ft_snapshot #(parameter WIDTH=1920,HEIGHT=1080,SCALE=6)(
 input pclk,input prst_n,input edge_mode,
 input vs,input de,input [7:0] pixel,
 input fclk,input frst_n,input [15:0] raddr,output reg [7:0] rdata,
 output available,input release_frame
);
 localparam OW=WIDTH/SCALE,OH=HEIGHT/SCALE;
 (* ram_style="block" *) reg [7:0] memory[0:65535];
 reg [OW-1:0] row_or;
 reg capturing,ready_toggle,vs_d,de_d,group_or;
 reg [15:0] written;
 reg [11:0] x;reg [10:0] y;reg [3:0] xp,yp;
 reg [11:0] block_x;
 reg ack,ack_meta,ack_sync,ready_meta,ready_sync;
 assign available=ready_sync!=ack;
 wire sample_gray=xp==SCALE/2&&yp==SCALE/2;
 wire sample_edge=xp==SCALE-1&&yp==SCALE-1;
 wire write_sample=capturing&&de&&(edge_mode?sample_edge:sample_gray);
 wire [7:0] value=edge_mode?((row_or[block_x]||group_or||pixel!=0)?8'hff:0):pixel;
 always @(posedge pclk)if(write_sample)memory[written]<=value;
 always @(posedge fclk)rdata<=memory[raddr];
 always @(posedge fclk or negedge frst_n)begin
  if(!frst_n)begin ready_meta<=0;ready_sync<=0;ack<=0;end
  else begin ready_meta<=ready_toggle;ready_sync<=ready_meta;if(release_frame)ack<=ready_sync;end
 end
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin
   capturing<=0;ready_toggle<=0;vs_d<=0;de_d<=0;group_or<=0;
   written<=0;x<=0;y<=0;xp<=0;yp<=0;block_x<=0;ack_meta<=0;ack_sync<=0;row_or<=0;
  end else begin
   ack_meta<=ack;ack_sync<=ack_meta;vs_d<=vs;de_d<=de;
   if(!vs)begin x<=0;y<=0;xp<=0;yp<=0;block_x<=0;group_or<=0;end
   if(vs&&!vs_d&&ack_sync==ready_toggle)begin capturing<=1;written<=0;end
   if(vs_d&&!vs&&capturing)begin
    capturing<=0;
    if(written==OW*OH)ready_toggle<=!ready_toggle;
   end
   if(de)begin
    x<=x+1'b1;
    if(xp==SCALE-1)begin
     xp<=0;block_x<=block_x+1'b1;group_or<=0;
     if(capturing&&edge_mode)row_or[block_x]<=yp==0?(group_or||pixel!=0):(row_or[block_x]||group_or||pixel!=0);
    end else begin xp<=xp+1'b1;group_or<=group_or||pixel!=0;end
    if(write_sample)written<=written+1'b1;
   end
   if(de_d&&!de)begin
    x<=0;xp<=0;block_x<=0;group_or<=0;y<=y+1'b1;
    yp<=yp==SCALE-1?0:yp+1'b1;
   end
  end
 end
endmodule
