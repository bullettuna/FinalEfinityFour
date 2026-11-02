`timescale 1ns/1ps
// On-demand, DDR-backed grayscale Canny and exact 8-connected hysteresis.
// No streaming/local hysteresis precedes this path: weak candidates survive
// until their WHOLE component is examined. Flood fill is equivalent to retaining
// low-threshold components containing a high-threshold seed. The component's
// queue is then reused to mark only its actual pixels, never its bounding box.
//
// Workspace (all below 32 MiB): A 0x01800000..0x018fffff (16-bit median/gradient),
// B 0x01900000..0x019fffff (16-bit Gaussian/classification/visited/keep),
// Q 0x01a00000..0x01bfffff (32-bit coordinates, up to WIDTH*HEIGHT entries).
// Input/output: private bottom-up RGB565 slots 0x01600000 / 0x01700000.
// Serialized stencil passes trade snapshot latency for small on-chip storage.
module photo_frame_process #(
 parameter WIDTH=960,HEIGHT=540,MEM_TIMEOUT=48000000,
 parameter [31:0] BASE0=32'h01600000,BASE1=32'h01700000,
 parameter [31:0] WORK_A=32'h01800000,WORK_B=32'h01900000,QUEUE_BASE=32'h01a00000
)(
 input clk,input rst_n,input start,input buffer_select,input [1:0] mode,
 input median_enable,input [1:0] cleanup_level,input [10:0] min_pixels,
 input [10:0] high_threshold,low_threshold,
 output reg busy,done,error,output [5:0] debug_stage,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,rvalid,output rready
);
 localparam N=WIDTH*HEIGHT;
 localparam IDLE=0,PIXEL=1,TAP=2,TAP_GOT=3,CALC=4,SORT=5,STORE=6,NEXT=7,
  WAIT_MEM=8,ADVANCE=9,SCAN=10,SCAN_GOT=11,SEED_QUEUE=12,QREAD=13,QGOT=14,
  NEIGHBOR=15,NGOT=16,NQUEUE=17,NNEXT=18,COMPLETE=19,MARK=20,MARK_GOT=21,
  MARK_WRITE=22,MARK_NEXT=23,SCAN_NEXT=24,RENDER=25,RENDER_GOT=26,RENDER_NEXT=27,FAILED=28;
 reg [5:0] state,resume;
 assign debug_stage=state;
 reg request,write_request,wide,invalidate;
 reg [31:0] address,payload;
 wire memory_ready,memory_done,memory_fault;wire [31:0] value;
 photo_work_memory #(.TIMEOUT(MEM_TIMEOUT)) u_memory(
  .clk(clk),.rst_n(rst_n),.invalidate(invalidate),.req(request),.wr(write_request),.size32(wide),
  .addr(address),.data(payload),.ready(memory_ready),.done(memory_done),.result(value),.fault(memory_fault),
  .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bvalid(bvalid),.bresp(bresp),
  .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 task access;
  input write_op,wide_op;input [31:0] location,datum;input [5:0] next_state;
  begin request<=1;write_request<=write_op;wide<=wide_op;address<=location;payload<=datum;
   resume<=next_state;state<=WAIT_MEM;end
 endtask
 reg [31:0] slot_base,source_base,destination_base,render_base;
 reg [1:0] image_mode,clean;
 reg [10:0] high,low,minimum;
 reg [2:0] pass;
 reg [19:0] index,qhead,qtail,mark_index,count;
 reg [9:0] x,y,cx,cy,nx,ny,minx,maxx,miny,maxy;
 reg [3:0] tap;
 reg [2:0] neighbor;
 reg [15:0] taps[0:8];
 reg [7:0] sorted[0:8];reg [3:0] sort_limit,sort_pos;
 reg [15:0] computed;
 reg has_strong,keep_component;
 reg [15:0] candidate;
 integer tx,ty,dx,dy,ax,ay;
 reg neighbor_valid;
 reg [31:0] neighbor_index,center_index;
 always @*begin
  // Window order: TL,T,TR,L,C,R,BL,B,BR; replicate image borders.
  tx=x;ty=y;
  case(tap)0:begin tx=x-1;ty=y-1;end 1:ty=y-1;2:begin tx=x+1;ty=y-1;end
   3:tx=x-1;5:tx=x+1;6:begin tx=x-1;ty=y+1;end 7:ty=y+1;8:begin tx=x+1;ty=y+1;end endcase
  if(tx<0)tx=0;if(tx>=WIDTH)tx=WIDTH-1;if(ty<0)ty=0;if(ty>=HEIGHT)ty=HEIGHT-1;
  dx=0;dy=0;
  case(neighbor)0:begin dx=-1;dy=-1;end 1:dy=-1;2:begin dx=1;dy=-1;end
   3:dx=-1;4:dx=1;5:begin dx=-1;dy=1;end 6:dy=1;7:begin dx=1;dy=1;end endcase
  ax=cx+dx;ay=cy+dy;
  neighbor_valid=ax>=0&&ax<WIDTH&&ay>=0&&ay<HEIGHT;
  neighbor_index=ay*WIDTH+ax;center_index=cy*WIDTH+cx;
 end
 // Same L1 Sobel and four-direction constants as the existing Canny kernels.
 integer gx,gy,absx,absy,gaussian_sum;
 reg [1:0] direction;
 reg [10:0] magnitude,ma,mb;
 always @*begin
  gx=taps[2][7:0]+2*taps[5][7:0]+taps[8][7:0]-taps[0][7:0]-2*taps[3][7:0]-taps[6][7:0];
  gy=taps[0][7:0]+2*taps[1][7:0]+taps[2][7:0]-taps[6][7:0]-2*taps[7][7:0]-taps[8][7:0];
  absx=gx<0?-gx:gx;absy=gy<0?-gy:gy;
  magnitude=absx+absy;
  if(absy*256<=absx*106)direction=0;
  else if(absx*256<=absy*106)direction=2;
  else if((gx<0)==(gy<0))direction=1;else direction=3;
  gaussian_sum=taps[0][7:0]+taps[2][7:0]+taps[6][7:0]+taps[8][7:0]+
   2*(taps[1][7:0]+taps[3][7:0]+taps[5][7:0]+taps[7][7:0])+4*taps[4][7:0]+8;
  case(taps[4][12:11])
   0:begin ma=taps[3][10:0];mb=taps[5][10:0];end
   1:begin ma=taps[2][10:0];mb=taps[6][10:0];end
   2:begin ma=taps[1][10:0];mb=taps[7][10:0];end
   default:begin ma=taps[0][10:0];mb=taps[8][10:0];end
  endcase
 end
 wire small_component=count<minimum&&(clean==2||((maxx-minx)<8&&(maxy-miny)<8));
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;resume<=IDLE;busy<=0;done<=0;error<=0;request<=0;write_request<=0;wide<=0;invalidate<=0;
   address<=0;payload<=0;slot_base<=0;source_base<=0;destination_base<=0;render_base<=0;
   image_mode<=0;clean<=0;high<=0;low<=0;minimum<=0;pass<=0;index<=0;x<=0;y<=0;
   qhead<=0;qtail<=0;mark_index<=0;count<=0;cx<=0;cy<=0;nx<=0;ny<=0;
   minx<=0;maxx<=0;miny<=0;maxy<=0;tap<=0;neighbor<=0;sort_limit<=0;sort_pos<=0;
   computed<=0;has_strong<=0;keep_component<=0;candidate<=0;
   for(i=0;i<9;i=i+1)begin taps[i]<=0;sorted[i]<=0;end
  end else begin
   request<=0;invalidate<=0;done<=0;error<=0;
   if(memory_fault&&state!=IDLE&&state!=FAILED)begin error<=1;state<=FAILED;end
   else case(state)
    IDLE:if(start)begin
     busy<=1;invalidate<=1;slot_base<=buffer_select?BASE1:BASE0;image_mode<=mode;
     clean<=cleanup_level;minimum<=min_pixels;high<=high_threshold;
     low<=low_threshold>high_threshold?high_threshold:low_threshold;
     index<=0;x<=0;y<=0;source_base<=buffer_select?BASE1:BASE0;
     if(WIDTH>1024||HEIGHT>1024||N*2>1048576||N*4>2097152)begin error<=1;state<=FAILED;end
     else if(mode==0)begin busy<=0;done<=1;end
     else if(median_enable)begin pass<=0;destination_base<=WORK_A;state<=PIXEL;end
     else if(mode==1)begin render_base<=buffer_select?BASE1:BASE0;state<=RENDER;end
     else begin pass<=1;destination_base<=WORK_B;state<=PIXEL;end
    end
    WAIT_MEM:if(memory_done)state<=resume;
    PIXEL:begin tap<=0;state<=TAP;end
    TAP:access(0,0,source_base+((ty*WIDTH+tx)<<1),0,TAP_GOT);
    TAP_GOT:begin taps[tap]<=value[15:0];sorted[tap]<=value[7:0];
     if(tap==8)state<=CALC;else begin tap<=tap+1'b1;state<=TAP;end end
    CALC:case(pass)
     0:begin sort_limit<=8;sort_pos<=0;state<=SORT;end
     1:begin computed<=gaussian_sum>>4;state<=STORE;end
     2:begin computed<={3'd0,direction,magnitude};state<=STORE;end
     default:begin
      if(x==0||x==WIDTH-1||y==0||y==HEIGHT-1||taps[4][10:0]==0||
       taps[4][10:0]<ma||taps[4][10:0]<mb)computed<=0;
      else if(taps[4][10:0]>=high)computed<=2;
      else if(taps[4][10:0]>=low)computed<=1;else computed<=0;
      state<=STORE;
     end
    endcase
    SORT:begin
     if(sorted[sort_pos]>sorted[sort_pos+1'b1])begin
      sorted[sort_pos]<=sorted[sort_pos+1'b1];sorted[sort_pos+1'b1]<=sorted[sort_pos];end
     if(sort_pos==sort_limit-1)begin
      if(sort_limit==1)begin state<=ADVANCE;end
      else begin sort_limit<=sort_limit-1'b1;sort_pos<=0;end
     end else sort_pos<=sort_pos+1'b1;
    end
    ADVANCE:begin computed<={8'd0,sorted[4]};state<=STORE;end
    STORE:access(1,0,destination_base+(index<<1),{16'd0,computed},NEXT);
    NEXT:begin
     if(index==N-1)begin
      index<=0;x<=0;y<=0;
      case(pass)
       0:if(image_mode==1)begin render_base<=WORK_A;state<=RENDER;end
         else begin pass<=1;source_base<=WORK_A;destination_base<=WORK_B;state<=PIXEL;end
       1:begin pass<=2;source_base<=WORK_B;destination_base<=WORK_A;state<=PIXEL;end
       2:begin pass<=3;source_base<=WORK_A;destination_base<=WORK_B;state<=PIXEL;end
       default:begin state<=SCAN;end
      endcase
     end else begin index<=index+1'b1;if(x==WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;state<=PIXEL;end
    end
    SCAN:access(0,0,WORK_B+(index<<1),0,SCAN_GOT);
    SCAN_GOT:if(value[1:0]!=0&&!value[2])begin
     candidate<=value[15:0];count<=1;has_strong<=value[1];qhead<=0;qtail<=1;
     minx<=x;maxx<=x;miny<=y;maxy<=y;
     access(1,0,WORK_B+(index<<1),{16'd0,value[15:0]|16'd4},SEED_QUEUE);
    end else state<=SCAN_NEXT;
    SEED_QUEUE:access(1,1,QUEUE_BASE,{12'd0,y,x},QREAD);
    QREAD:if(qhead==qtail)state<=COMPLETE;
     else access(0,1,QUEUE_BASE+(qhead<<2),0,QGOT);
    QGOT:begin cx<=value[9:0];cy<=value[19:10];qhead<=qhead+1'b1;neighbor<=0;state<=NEIGHBOR;end
    NEIGHBOR:if(!neighbor_valid)state<=NNEXT;
     else begin nx<=ax;ny<=ay;access(0,0,WORK_B+(neighbor_index<<1),0,NGOT);end
    NGOT:if(value[1:0]!=0&&!value[2])begin
     if(qtail>=N)begin error<=1;state<=FAILED;end
     else begin candidate<=value[15:0];
      access(1,0,WORK_B+(neighbor_index<<1),{16'd0,value[15:0]|16'd4},NQUEUE);end
    end else state<=NNEXT;
    NQUEUE:begin
     access(1,1,QUEUE_BASE+(qtail<<2),{12'd0,ny,nx},NNEXT);
     qtail<=qtail+1'b1;count<=count+1'b1;has_strong<=has_strong||candidate[1];
     if(nx<minx)minx<=nx;if(nx>maxx)maxx<=nx;if(ny<miny)miny<=ny;if(ny>maxy)maxy<=ny;
    end
    NNEXT:if(neighbor==7)state<=QREAD;else begin neighbor<=neighbor+1'b1;state<=NEIGHBOR;end
    COMPLETE:begin keep_component<=has_strong&&(clean==0||!small_component);mark_index<=0;state<=MARK;end
    MARK:if(!keep_component||mark_index==qtail)state<=SCAN_NEXT;
     else access(0,1,QUEUE_BASE+(mark_index<<2),0,MARK_GOT);
    MARK_GOT:begin cx<=value[9:0];cy<=value[19:10];state<=MARK_WRITE;end
    MARK_WRITE:access(1,0,WORK_B+(center_index<<1),32'd12,MARK_NEXT);
    MARK_NEXT:begin mark_index<=mark_index+1'b1;state<=MARK;end
    SCAN_NEXT:if(index==N-1)begin index<=0;render_base<=WORK_B;state<=RENDER;end
     else begin index<=index+1'b1;if(x==WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;state<=SCAN;end
    RENDER:access(0,0,render_base+(index<<1),0,RENDER_GOT);
    RENDER_GOT:access(1,0,slot_base+(index<<1),image_mode==2?(value[3]?32'hffff:32'd0):
     {16'd0,value[7:3],value[7:2],value[7:3]},RENDER_NEXT);
    RENDER_NEXT:if(index==N-1)begin busy<=0;done<=1;state<=IDLE;end
     else begin index<=index+1'b1;state<=RENDER;end
    // Latching FAILED protects a partially transformed slot and outstanding AXI.
    // Only a full reset may release it; no TF write is started after an error.
    FAILED:busy<=1;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
