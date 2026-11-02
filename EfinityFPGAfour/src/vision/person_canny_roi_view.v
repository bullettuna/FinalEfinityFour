`timescale 1ns/1ps
// Canny stays ahead of the R mask display by approximately twelve lines.
// A sixteen-line edge-only ring bridges their spatial timing without a frame
// buffer. Complete-row/epoch tags reject stale or partially written rows.
module person_canny_roi_view #(parameter WIDTH=1920,HEIGHT=1080,ROW_BITS=4,X_BITS=$clog2(WIDTH))(
 input clk,input rst_n,input [2:0] view_req,input source_valid,
 input edge_vsync,input edge_href,input edge_pixel,
 input target_vsync,input target_hsync,input target_href,
 input bbox_valid,input [11:0] bbox_x_min,bbox_x_max,input [10:0] bbox_y_min,bbox_y_max,
 output reg out_vsync,output reg out_hsync,output reg out_href,output reg [23:0] out_rgb,
 output reg display_active,
 // Independent of display mode/ROI; matches out_vsync/out_href coordinates.
 output wire aligned_edge,output wire aligned_edge_valid
);
localparam ROWS=1<<ROW_BITS;
(* ram_style="block" *)reg pixels[0:(1<<(ROW_BITS+X_BITS))-1];
reg [10:0] row_y[0:ROWS-1];reg row_epoch[0:ROWS-1];reg [ROWS-1:0] row_valid;
reg edge_vs_d,edge_de_d,target_vs_d,target_de_d,edge_epoch,target_epoch;
reg [11:0] ex,tx;reg [10:0] ey,ty;
wire [11:0] epx=edge_href&&!edge_de_d?0:ex;
wire [10:0] epy=edge_href&&!edge_de_d?ey+1'b1:ey;
wire [11:0] tpx=target_href&&!target_de_d?0:tx;
wire [10:0] tpy=target_href&&!target_de_d?ty+1'b1:ty;
wire [ROW_BITS+X_BITS-1:0] write_addr={epy[ROW_BITS-1:0],epx[X_BITS-1:0]};
wire [ROW_BITS+X_BITS-1:0] read_addr={tpy[ROW_BITS-1:0],tpx[X_BITS-1:0]};
(* async_reg="true" *)reg [2:0] view_meta,view_sync;
reg active_frame,roi_valid;reg [11:0] xmin,xmax;reg [10:0] ymin,ymax;
reg edge_q,vs_q,hs_q,de_q,inside_q,row_ok_q,box_q;
integer i;
reg edge_q_delayed,row_ok_delayed;
assign aligned_edge=out_href&&edge_q_delayed;
assign aligned_edge_valid=out_href&&row_ok_delayed;
always @(posedge clk)begin
 if(edge_href&&epx<WIDTH&&epy<HEIGHT)pixels[write_addr]<=edge_pixel;
 edge_q<=pixels[read_addr];
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  row_valid<=0;edge_vs_d<=0;edge_de_d<=0;target_vs_d<=0;target_de_d<=0;
  edge_epoch<=0;target_epoch<=0;ex<=0;tx<=0;ey<=11'h7ff;ty<=11'h7ff;
  view_meta<=0;view_sync<=0;active_frame<=0;roi_valid<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;
  vs_q<=0;hs_q<=0;de_q<=0;inside_q<=0;row_ok_q<=0;box_q<=0;
  out_vsync<=0;out_hsync<=0;out_href<=0;out_rgb<=0;display_active<=0;
  edge_q_delayed<=0;row_ok_delayed<=0;
  for(i=0;i<ROWS;i=i+1)begin row_y[i]<=0;row_epoch[i]<=0;end
 end else begin
  view_meta<=view_req;view_sync<=view_meta;
  edge_vs_d<=edge_vsync;edge_de_d<=edge_href;target_vs_d<=target_vsync;target_de_d<=target_href;
  if(edge_vsync&&!edge_vs_d)edge_epoch<=!edge_epoch;
  if(target_vsync&&!target_vs_d)target_epoch<=!target_epoch;
  if(!edge_vsync)begin ex<=0;ey<=11'h7ff;end
  else if(edge_href)begin
   ex<=epx+1'b1;ey<=epy;
   if(epx==WIDTH-1&&epy<HEIGHT)begin row_y[epy[ROW_BITS-1:0]]<=epy;row_epoch[epy[ROW_BITS-1:0]]<=edge_epoch;row_valid[epy[ROW_BITS-1:0]]<=1;end
  end
  if(!target_vsync)begin
   tx<=0;ty<=11'h7ff;active_frame<=view_sync==6;
   roi_valid<=bbox_valid;xmin<=bbox_x_min;xmax<=bbox_x_max;ymin<=bbox_y_min;ymax<=bbox_y_max;
  end else if(target_href)begin tx<=tpx+1'b1;ty<=tpy;end
  vs_q<=target_vsync;hs_q<=target_hsync;de_q<=target_href;
  inside_q<=roi_valid&&tpx>=xmin&&tpx<=xmax&&tpy>=ymin&&tpy<=ymax;
  box_q<=roi_valid&&(((tpx==xmin||tpx==xmax)&&tpy>=ymin&&tpy<=ymax)||((tpy==ymin||tpy==ymax)&&tpx>=xmin&&tpx<=xmax));
  row_ok_q<=row_valid[tpy[ROW_BITS-1:0]]&&row_y[tpy[ROW_BITS-1:0]]==tpy&&row_epoch[tpy[ROW_BITS-1:0]]==target_epoch;
  out_vsync<=vs_q;out_hsync<=hs_q;out_href<=de_q;
  edge_q_delayed<=edge_q;row_ok_delayed<=row_ok_q;
  out_rgb<=!de_q||!source_valid?24'd0:box_q?24'h00ff00:(inside_q&&row_ok_q&&edge_q?24'hffffff:24'd0);
  if(!vs_q)display_active<=active_frame;
 end
end
endmodule
