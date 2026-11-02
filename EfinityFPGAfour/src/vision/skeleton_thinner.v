`timescale 1ns/1ps
// Offline Zhang-Suen on a captured binary silhouette. Both subiterations read
// immutable source RAM and write the other RAM. No in-pass destructive thinning.
// Short endpoint-to-junction paths are pruned; isolated lines are preserved.
module skeleton_thinner #(
 parameter WIDTH=120,HEIGHT=68,MAX_ITER=64,SPUR_LENGTH=3,
 parameter AW=$clog2(WIDTH*HEIGHT),XB=$clog2(WIDTH),YB=$clog2(HEIGHT)
)(
 input clk,input rst_n,input cancel,input load_en,input [AW-1:0] load_addr,input load_pixel,input start,
 input [AW-1:0] result_addr,output result_pixel,
 output reg busy,output reg done,output reg converged,
 output reg [7:0] iterations,output reg [15:0] pixels,endpoints,branches,pruned
);
 localparam SIZE=WIDTH*HEIGHT,IDLE=0,READ=1,USE=2,EVAL=3,PASS_END=4,NEXT=5,DELETE=6,FINISH=7;
 localparam THIN=0,PRUNE=1,TRACE=2,COUNT=3;
 (* ram_style="block" *)reg work0[0:SIZE-1],work1[0:SIZE-1];
 reg q0,q1,bank;reg [3:0] state;reg [1:0] operation;
 reg [XB-1:0] x,scan_x,previous_x;reg [YB-1:0] y,scan_y,previous_y;
 reg [AW-1:0] cursor;reg [3:0] neighbor;reg [8:0] window;
 reg phase,pass_changed,iteration_changed;
 localparam PATH_SIZE=SPUR_LENGTH>0?SPUR_LENGTH:1;
 reg [AW-1:0] path[0:PATH_SIZE-1];reg [7:0] path_count,delete_index;
 reg signed [XB:0] nx;reg signed [YB:0] ny;
 always @(*)begin
  nx=$signed({1'b0,x});ny=$signed({1'b0,y});
  case(neighbor)
   1:ny=ny-1;
   2:begin nx=nx+1;ny=ny-1;end
   3:nx=nx+1;
   4:begin nx=nx+1;ny=ny+1;end
   5:ny=ny+1;
   6:begin nx=nx-1;ny=ny+1;end
   7:nx=nx-1;
   8:begin nx=nx-1;ny=ny-1;end
  endcase
 end
 wire in_bounds=nx>=0&&nx<WIDTH&&ny>=0&&ny<HEIGHT;
 wire [AW-1:0] sample_addr=in_bounds?ny*WIDTH+nx:0;
 wire [AW-1:0] current_addr=y*WIDTH+x;
 wire [AW-1:0] read_addr=busy?sample_addr:result_addr;
 assign result_pixel=bank?q1:q0;
 wire remove_pixel;
 reg we0,we1,write_pixel;reg [AW-1:0] write_addr;
 always @(*)begin
  we0=0;we1=0;write_addr=load_addr;write_pixel=load_pixel;
  if(load_en&&!busy)we0=1;
  if(state==EVAL&&operation==THIN)begin
   write_addr=current_addr;write_pixel=window[0]&&!remove_pixel;
   if(bank)we0=1;else we1=1;
  end
  if(state==DELETE)begin
   write_addr=path[delete_index];write_pixel=0;
   if(bank)we1=1;else we0=1;
  end
 end
 always @(posedge clk)begin
  q0<=work0[read_addr];q1<=work1[read_addr];
  if(we0)work0[write_addr]<=write_pixel;
  if(we1)work1[write_addr]<=write_pixel;
 end
 // Prefer orthogonal paths over redundant diagonal links. Without this,
 // the pixel next to a T junction looks like a corner and stops spur tracing.
 wire [8:1] graph;
 assign graph[1]=window[1];assign graph[3]=window[3];
 assign graph[5]=window[5];assign graph[7]=window[7];
 assign graph[2]=window[2]&&!window[1]&&!window[3];
 assign graph[4]=window[4]&&!window[3]&&!window[5];
 assign graph[6]=window[6]&&!window[5]&&!window[7];
 assign graph[8]=window[8]&&!window[7]&&!window[1];
 integer k;reg [3:0] degree,transitions,graph_degree;
 reg [XB-1:0] next_x;reg [YB-1:0] next_y;
 reg signed [XB:0] tx;reg signed [YB:0] ty;
 always @(*)begin
  degree=0;transitions=0;graph_degree=0;next_x=x;next_y=y;tx=0;ty=0;
  for(k=1;k<=8;k=k+1)begin
   degree=degree+window[k];
   graph_degree=graph_degree+graph[k];
   if(!window[k]&&window[k==8?1:k+1])transitions=transitions+1'b1;
   tx=$signed({1'b0,x});ty=$signed({1'b0,y});
   case(k)
    1:ty=ty-1;2:begin tx=tx+1;ty=ty-1;end
    3:tx=tx+1;4:begin tx=tx+1;ty=ty+1;end
    5:ty=ty+1;6:begin tx=tx-1;ty=ty+1;end
    7:tx=tx-1;8:begin tx=tx-1;ty=ty-1;end
   endcase
   if(graph[k]&&(operation!=TRACE||tx!=previous_x||ty!=previous_y))begin next_x=tx;next_y=ty;end
  end
 end
 assign remove_pixel=window[0]&&degree>=2&&degree<=6&&transitions==1&&
  (phase?(!(window[1]&&window[3]&&window[7])&&!(window[1]&&window[5]&&window[7])):
         (!(window[1]&&window[3]&&window[5])&&!(window[3]&&window[5]&&window[7])));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;operation<=THIN;busy<=0;done<=0;converged<=0;bank<=0;
   x<=0;y<=0;scan_x<=0;scan_y<=0;previous_x<=0;previous_y<=0;cursor<=0;neighbor<=0;window<=0;
   phase<=0;pass_changed<=0;iteration_changed<=0;iterations<=0;
   pixels<=0;endpoints<=0;branches<=0;pruned<=0;path_count<=0;delete_index<=0;
  end else if(cancel)begin state<=IDLE;busy<=0;done<=0;converged<=0;end
  else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     state<=READ;operation<=THIN;busy<=1;converged<=0;bank<=0;
     x<=0;y<=0;scan_x<=0;scan_y<=0;cursor<=0;neighbor<=0;
     phase<=0;pass_changed<=0;iteration_changed<=0;iterations<=1;
     pixels<=0;endpoints<=0;branches<=0;pruned<=0;
    end
    READ:state<=USE;
    USE:begin
     window[neighbor]<=in_bounds&&(bank?q1:q0);
     if(neighbor==8)state<=EVAL;else begin neighbor<=neighbor+1'b1;state<=READ;end
    end
    EVAL:begin
     neighbor<=0;
     if(operation==THIN)begin
      if(remove_pixel)pass_changed<=1;
      if(cursor==SIZE-1)state<=PASS_END;
      else begin cursor<=cursor+1'b1;if(x==WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;state<=READ;end
     end else if(operation==PRUNE)begin
      if(SPUR_LENGTH>0&&window[0]&&graph_degree==1)begin
       path[0]<=current_addr;path_count<=1;previous_x<=x;previous_y<=y;
       x<=next_x;y<=next_y;operation<=TRACE;state<=READ;
      end else state<=NEXT;
     end else if(operation==TRACE)begin
      if(graph_degree>=3)begin delete_index<=0;state<=DELETE;end
      else if(graph_degree==2&&path_count<SPUR_LENGTH)begin
       path[path_count]<=current_addr;path_count<=path_count+1'b1;
       previous_x<=x;previous_y<=y;x<=next_x;y<=next_y;state<=READ;
      end else state<=NEXT;
     end else begin
      if(window[0])begin
       pixels<=pixels+1'b1;
       if(graph_degree==1)endpoints<=endpoints+1'b1;
       if(graph_degree>=3)branches<=branches+1'b1;
      end
      state<=NEXT;
     end
    end
    PASS_END:begin
     bank<=!bank;x<=0;y<=0;scan_x<=0;scan_y<=0;cursor<=0;neighbor<=0;pass_changed<=0;
     if(!phase)begin phase<=1;iteration_changed<=pass_changed;state<=READ;end
     else if(!(iteration_changed||pass_changed))begin
      converged<=1;operation<=SPUR_LENGTH>0?PRUNE:COUNT;state<=READ;
     end else if(iterations>=MAX_ITER)begin operation<=COUNT;state<=READ;end
     else begin phase<=0;iteration_changed<=0;iterations<=iterations+1'b1;state<=READ;end
    end
    DELETE:begin
     pruned<=pruned+1'b1;
     if(delete_index+1>=path_count)state<=NEXT;else delete_index<=delete_index+1'b1;
    end
    NEXT:begin
     if(cursor==SIZE-1)begin
      if(operation==COUNT)state<=FINISH;
      else begin operation<=COUNT;cursor<=0;x<=0;y<=0;scan_x<=0;scan_y<=0;neighbor<=0;state<=READ;end
     end else begin
      cursor<=cursor+1'b1;neighbor<=0;
      if(operation!=COUNT)operation<=PRUNE;
      if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;x<=0;y<=scan_y+1'b1;end
      else begin scan_x<=scan_x+1'b1;x<=scan_x+1'b1;y<=scan_y;end
      state<=READ;
     end
    end
    FINISH:begin done<=1;busy<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
