`timescale 1ns/1ps
// Evidence-only upper-body graph filter. Class 1 is the rooted trunk path;
// classes 2/3 are screen-left/right arm paths. No missing bone is fabricated.
// Torso support is estimated from the lower silhouette, then a bounded BFS
// supplies parent paths. Arm attachment, length and temporal priors select
// at most one supported path on each side. This is not joint detection.
module upper_body_constraint #(
 parameter WIDTH=120,HEIGHT=68,MAX_ENDPOINTS=32,
 parameter AW=$clog2(WIDTH*HEIGHT),XB=$clog2(WIDTH),YB=$clog2(HEIGHT)
)(
 input clk,input rst_n,input cancel,input load_en,input [AW-1:0] load_addr,
 input load_mask,input load_skeleton,input start,input [AW-1:0] result_addr,
 output [1:0] result_class,output reg busy,output reg done,
 output reg body_valid,output reg [1:0] arm_flags,output reg overflow
);
 localparam SIZE=WIDTH*HEIGHT;
 localparam IDLE=0,BREQ=1,BUSE=2,LOWER_SET=3,LREQ=4,LUSE=5,HIST=6,
  ROOT_SET=7,RREQ=8,RUSE=9,SEED=10,POPREQ=11,POPUSE=12,NODEREQ=13,NODEUSE=14,
  NREQ=15,NUSE=16,NODEEND=17,TRUNK=18,TREQ=19,TUSE=20,CBEGIN=21,
  PREQ=22,PUSE=23,SCORE=24,CHOOSE=25,MARKSTART=26,MREQ=27,MUSE=28,FINISH=29,
  CLOAD=30,SELECT=31;
 reg [5:0] state;
 (* ram_style="block" *)reg [1:0] image[0:SIZE-1],classes[0:SIZE-1];
 // Parent direction f=unvisited, 8=root; upper byte is saturated BFS distance.
 (* ram_style="block" *)reg [11:0] navigation[0:SIZE-1];
 (* ram_style="block" *)reg [XB+YB-1:0] queue[0:(1<<AW)-1];
 reg [1:0] image_q,class_q;reg [11:0] nav_q;reg [XB+YB-1:0] queue_q;
 reg [AW-1:0] cursor,head,tail;reg [AW:0] queued,steps,path_length,wrong_side;
 reg [XB-1:0] x,cur_x,root_x,top_x,min_x,max_x,center_x;
 reg [YB-1:0] y,cur_y,root_y,top_y,min_y,max_y,lower_y;
 reg any_mask,root_found;
 reg [15:0] root_score;
 reg [YB:0] column[0:WIDTH-1],support_limit;
 reg [XB:0] col,run_length,run_start,best_width,best_start,margin;
 reg [3:0] neighbor,degree;reg [7:0] current_distance;
 reg [XB+YB-1:0] endpoints[0:MAX_ENDPOINTS-1];
 localparam EB=$clog2(MAX_ENDPOINTS+1);
 reg [EB-1:0] endpoint_count,candidate_index;
 reg [XB-1:0] stem_x,left_x,right_x;
 reg [YB-1:0] stem_y,left_y,right_y;
 reg [XB+YB-1:0] left_stem,right_stem;
 reg [15:0] left_score,right_score;
 reg have_left,have_right,mark_right;
 reg [1:0] previous_flags;reg previous_body;
 reg [XB-1:0] previous_cx,previous_left_x,previous_right_x;
 reg [YB-1:0] previous_root_y,previous_left_y,previous_right_y;
 wire [YB:0] body_height={1'b0,max_y}-{1'b0,min_y}+1'b1;
 wire [YB:0] trunk_height={1'b0,root_y}-{1'b0,top_y};
 function integer absolute;input integer value;begin absolute=value<0?-value:value;end endfunction
 reg signed [XB:0] nx;reg signed [YB:0] ny;
 always @(*)begin
  nx=$signed({1'b0,cur_x});ny=$signed({1'b0,cur_y});
  case(neighbor)
   0:ny=ny-1;1:begin nx=nx+1;ny=ny-1;end
   2:nx=nx+1;3:begin nx=nx+1;ny=ny+1;end
   4:ny=ny+1;5:begin nx=nx-1;ny=ny+1;end
   6:nx=nx-1;7:begin nx=nx-1;ny=ny-1;end
  endcase
 end
 wire neighbor_valid=nx>=0&&nx<WIDTH&&ny>=0&&ny<HEIGHT;
 wire [AW-1:0] neighbor_addr=neighbor_valid?ny*WIDTH+nx:0;
 wire [AW-1:0] current_addr=cur_y*WIDTH+cur_x;
 reg [AW-1:0] read_addr;
 always @(*)begin
  read_addr=cursor;
  case(state)
   NREQ,NUSE:read_addr=neighbor_addr;
   NODEREQ,NODEUSE,TREQ,TUSE,PREQ,PUSE,MREQ,MUSE:read_addr=current_addr;
  endcase
  if(!busy)read_addr=result_addr;
 end
 reg signed [XB:0] parent_x;reg signed [YB:0] parent_y;
 always @(*)begin
  parent_x=$signed({1'b0,cur_x});parent_y=$signed({1'b0,cur_y});
  case(nav_q[3:0])
   0:parent_y=parent_y-1;1:begin parent_x=parent_x+1;parent_y=parent_y-1;end
   2:parent_x=parent_x+1;3:begin parent_x=parent_x+1;parent_y=parent_y+1;end
   4:parent_y=parent_y+1;5:begin parent_x=parent_x-1;parent_y=parent_y+1;end
   6:parent_x=parent_x-1;7:begin parent_x=parent_x-1;parent_y=parent_y-1;end
  endcase
 end
 wire enqueue=state==NUSE&&neighbor_valid&&image_q==3&&nav_q[3:0]==15&&queued<SIZE;
 wire [2:0] reverse_direction=neighbor[2:0]+3'd4;
 wire [7:0] next_distance=current_distance==255?8'd255:current_distance+1'b1;
 reg nav_we,class_we,queue_we;reg [AW-1:0] write_addr,queue_write_addr;
 reg [11:0] nav_value;reg [1:0] class_value;reg [XB+YB-1:0] queue_value;
 always @(*)begin
  nav_we=0;class_we=0;queue_we=0;write_addr=current_addr;nav_value=0;class_value=0;
  queue_write_addr=tail;queue_value={ny[YB-1:0],nx[XB-1:0]};
  if(state==BUSE)begin write_addr=cursor;nav_we=1;nav_value=12'h00f;class_we=1;end
  if(state==SEED&&root_found)begin
   write_addr=root_y*WIDTH+root_x;nav_we=1;nav_value=12'h008;
   queue_we=1;queue_write_addr=0;queue_value={root_y,root_x};
  end
  if(enqueue)begin write_addr=neighbor_addr;nav_we=1;nav_value={next_distance,1'b0,reverse_direction};queue_we=1;end
  if(state==TUSE&&image_q==3)begin class_we=1;class_value=1;end
  if(state==MUSE&&image_q==3&&class_q==0)begin class_we=1;class_value=mark_right?3:2;end
 end
 always @(posedge clk)begin
  if(load_en&&!busy)image[load_addr]<={load_skeleton&&load_mask,load_mask};
  image_q<=image[read_addr];nav_q<=navigation[read_addr];class_q<=classes[read_addr];
  queue_q<=queue[head];
  if(nav_we)navigation[write_addr]<=nav_value;
  if(class_we)classes[write_addr]<=class_value;
  if(queue_we)queue[queue_write_addr]<=queue_value;
 end
 assign result_class=class_q;
 // Separate endpoint mux, arithmetic and winning-path selection into clocks.
 wire [XB+YB-1:0] selected_endpoint=candidate_index<MAX_ENDPOINTS?endpoints[candidate_index]:0;
 reg [XB+YB-1:0] candidate;
 reg [15:0] score_q;reg candidate_valid_q;
 wire [XB-1:0] candidate_x=candidate[XB-1:0];
 wire [YB-1:0] candidate_y=candidate[XB+YB-1:XB];
 wire candidate_right=candidate_x>center_x;
 integer candidate_score,prior_distance,min_arm_length,max_arm_length,root_cost,run_center,target_center;
 reg candidate_valid;
 always @(*)begin
  root_cost=absolute($signed({1'b0,x})-$signed({1'b0,center_x}))*4+max_y-y;
  run_center=run_start+((run_length-1)>>1);
  target_center=previous_body?previous_cx:((min_x+max_x)>>1);
  min_arm_length=trunk_height>>2;if(min_arm_length<3)min_arm_length=3;
  max_arm_length=trunk_height*4+best_width;
  prior_distance=0;
  if(previous_body&&previous_flags[candidate_right])begin
   if(candidate_right)
    prior_distance=absolute($signed({1'b0,candidate_x})-($signed({1'b0,previous_right_x})+$signed({1'b0,center_x})-$signed({1'b0,previous_cx})))+
                   absolute($signed({1'b0,candidate_y})-($signed({1'b0,previous_right_y})+$signed({1'b0,root_y})-$signed({1'b0,previous_root_y})));
   else
    prior_distance=absolute($signed({1'b0,candidate_x})-($signed({1'b0,previous_left_x})+$signed({1'b0,center_x})-$signed({1'b0,previous_cx})))+
                   absolute($signed({1'b0,candidate_y})-($signed({1'b0,previous_left_y})+$signed({1'b0,root_y})-$signed({1'b0,previous_root_y})));
  end
  candidate_score=path_length*4+absolute($signed({1'b0,candidate_x})-$signed({1'b0,center_x}))*2-(prior_distance>>1);
  if(candidate_score<1)candidate_score=1;
  candidate_valid=path_length>=min_arm_length&&path_length<=max_arm_length&&
    cur_y<=top_y+(trunk_height>>1)+1&&wrong_side*3<=path_length;
 end
 task advance_scan;input [5:0] next_state;
  begin cursor<=cursor+1'b1;if(x==WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;state<=next_state;end
 endtask
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;body_valid<=0;arm_flags<=0;overflow<=0;
   cursor<=0;head<=0;tail<=0;queued<=0;steps<=0;path_length<=0;wrong_side<=0;
   x<=0;y<=0;cur_x<=0;cur_y<=0;root_x<=0;root_y<=0;top_x<=0;top_y<=0;
   min_x<=0;max_x<=0;min_y<=0;max_y<=0;center_x<=0;lower_y<=0;
   any_mask<=0;root_found<=0;root_score<=0;support_limit<=0;
   col<=0;run_length<=0;run_start<=0;best_width<=0;best_start<=0;margin<=0;
   neighbor<=0;degree<=0;current_distance<=0;endpoint_count<=0;candidate_index<=0;
   stem_x<=0;stem_y<=0;left_x<=0;left_y<=0;right_x<=0;right_y<=0;left_stem<=0;right_stem<=0;
   left_score<=0;right_score<=0;have_left<=0;have_right<=0;mark_right<=0;
   previous_flags<=0;previous_body<=0;previous_cx<=0;previous_root_y<=0;
   previous_left_x<=0;previous_left_y<=0;previous_right_x<=0;previous_right_y<=0;
   candidate<=0;score_q<=0;candidate_valid_q<=0;
   for(i=0;i<WIDTH;i=i+1)column[i]<=0;
  end else if(cancel)begin
   state<=IDLE;busy<=0;done<=0;body_valid<=0;arm_flags<=0;previous_body<=0;previous_flags<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     busy<=1;body_valid<=0;arm_flags<=0;overflow<=0;state<=BREQ;
     cursor<=0;x<=0;y<=0;any_mask<=0;min_x<=WIDTH-1;max_x<=0;min_y<=HEIGHT-1;max_y<=0;
     endpoint_count<=0;have_left<=0;have_right<=0;left_score<=0;right_score<=0;
     for(i=0;i<WIDTH;i=i+1)column[i]<=0;
    end
    BREQ:state<=BUSE;
    BUSE:begin
     if(image_q[0])begin
      any_mask<=1;if(x<min_x)min_x<=x;if(x>max_x)max_x<=x;if(y<min_y)min_y<=y;if(y>max_y)max_y<=y;
     end
     if(cursor==SIZE-1)state<=LOWER_SET;else advance_scan(BREQ);
    end
    LOWER_SET:if(!any_mask||body_height<8)state<=FINISH;
     else begin lower_y<=min_y+(body_height*2)/3;cursor<=0;x<=0;y<=0;state<=LREQ;end
    LREQ:state<=LUSE;
    LUSE:begin
     if(image_q[0]&&y>=lower_y)column[x]<=column[x]+1'b1;
     if(cursor==SIZE-1)begin
      support_limit<=((max_y-lower_y+1)*3+3)>>2;
      col<=0;run_length<=0;run_start<=0;best_width<=0;best_start<=0;state<=HIST;
     end else advance_scan(LREQ);
    end
    HIST:begin
     if(col<WIDTH&&column[col]>=support_limit)begin
      if(run_length==0)run_start<=col;run_length<=run_length+1'b1;
     end else begin
      if(run_length>best_width||(run_length!=0&&run_length==best_width&&absolute(run_center-target_center)<absolute(best_start+((best_width-1)>>1)-target_center)))begin
       best_start<=run_start;best_width<=run_length;
      end
      run_length<=0;
     end
     if(col==WIDTH)state<=ROOT_SET;else col<=col+1'b1;
    end
    ROOT_SET:if(best_width<3)state<=FINISH;
     else begin
      center_x<=best_start+((best_width-1)>>1);margin<=(best_width>>2)>0?best_width>>2:1;
      cursor<=0;x<=0;y<=0;root_found<=0;root_score<=16'hffff;state<=RREQ;
     end
    RREQ:state<=RUSE;
    RUSE:begin
     if(image_q==3&&x>=best_start&&x<best_start+best_width&&y>=min_y+(body_height>>1)&&root_cost<root_score)begin
      root_found<=1;root_x<=x;root_y<=y;root_score<=root_cost;
     end
     if(cursor==SIZE-1)state<=SEED;else advance_scan(RREQ);
    end
    SEED:if(!root_found)state<=FINISH;
     else begin head<=0;tail<=1;queued<=1;top_x<=root_x;top_y<=root_y;state<=POPREQ;end
    POPREQ:state<=POPUSE;
    POPUSE:begin cur_x<=queue_q[XB-1:0];cur_y<=queue_q[XB+YB-1:XB];head<=head+1'b1;queued<=queued-1'b1;state<=NODEREQ;end
    NODEREQ:state<=NODEUSE;
    NODEUSE:begin
     current_distance<=nav_q[11:4];neighbor<=0;degree<=0;
     if(absolute($signed({1'b0,cur_x})-$signed({1'b0,center_x}))<=margin&&
       (cur_y<top_y||(cur_y==top_y&&absolute($signed({1'b0,cur_x})-$signed({1'b0,center_x}))<absolute($signed({1'b0,top_x})-$signed({1'b0,center_x})))))begin top_x<=cur_x;top_y<=cur_y;end
     state<=NREQ;
    end
    NREQ:state<=NUSE;
    NUSE:begin
     if(neighbor_valid&&image_q==3)begin
      degree<=degree+1'b1;
      if(nav_q[3:0]==15)begin
       if(queued>=SIZE)begin overflow<=1;state<=FINISH;end
       else begin tail<=tail+1'b1;queued<=queued+1'b1;end
      end
     end
     if(!(neighbor_valid&&image_q==3&&nav_q[3:0]==15&&queued>=SIZE))begin
      if(neighbor==7)state<=NODEEND;else begin neighbor<=neighbor+1'b1;state<=NREQ;end
     end
    end
    NODEEND:begin
     if(degree==1&&(cur_x!=root_x||cur_y!=root_y)&&absolute($signed({1'b0,cur_x})-$signed({1'b0,center_x}))>margin)begin
      if(endpoint_count<MAX_ENDPOINTS)begin endpoints[endpoint_count]<={cur_y,cur_x};endpoint_count<=endpoint_count+1'b1;end
      else overflow<=1;
     end
     state<=queued==0?TRUNK:POPREQ;
    end
    TRUNK:if(overflow||trunk_height<3||trunk_height<(body_height>>2))state<=FINISH;
     else begin body_valid<=1;cur_x<=top_x;cur_y<=top_y;steps<=0;state<=TREQ;end
    TREQ:state<=TUSE;
    TUSE:if(image_q!=3||nav_q[3:0]==15||steps>=SIZE)begin body_valid<=0;state<=FINISH;end
     else if(cur_x==root_x&&cur_y==root_y)begin candidate_index<=0;state<=CLOAD;end
     else begin cur_x<=parent_x;cur_y<=parent_y;steps<=steps+1'b1;state<=TREQ;end
    CLOAD:if(candidate_index>=endpoint_count)state<=CHOOSE;
     else begin candidate<=selected_endpoint;state<=CBEGIN;end
    CBEGIN:begin cur_x<=candidate_x;cur_y<=candidate_y;path_length<=0;wrong_side<=0;steps<=0;state<=PREQ;end
    PREQ:state<=PUSE;
    PUSE:if(class_q==1)state<=SCORE;
     else if(image_q!=3||nav_q[3:0]>=8||steps>=SIZE)begin candidate_index<=candidate_index+1'b1;state<=CLOAD;end
     else begin
      path_length<=path_length+1'b1;steps<=steps+1'b1;
      if((candidate_right&&cur_x+margin<center_x)||(!candidate_right&&cur_x>center_x+margin))wrong_side<=wrong_side+1'b1;
      stem_x<=cur_x;stem_y<=cur_y;cur_x<=parent_x;cur_y<=parent_y;state<=PREQ;
     end
    SCORE:begin score_q<=candidate_score;candidate_valid_q<=candidate_valid;state<=SELECT;end
    SELECT:begin
     if(candidate_valid_q)begin
      if(candidate_right&&(!have_right||score_q>right_score))begin
       have_right<=1;right_score<=score_q;right_x<=candidate_x;right_y<=candidate_y;right_stem<={stem_y,stem_x};
      end
      if(!candidate_right&&(!have_left||score_q>left_score))begin
       have_left<=1;left_score<=score_q;left_x<=candidate_x;left_y<=candidate_y;left_stem<={stem_y,stem_x};
      end
     end
     candidate_index<=candidate_index+1'b1;state<=CLOAD;
    end
    CHOOSE:begin
     if(have_left&&have_right&&left_stem==right_stem)begin
      if(left_score>=right_score)have_right<=0;else have_left<=0;
     end
     mark_right<=0;state<=MARKSTART;
    end
    MARKSTART:if(mark_right?have_right:have_left)begin
     cur_x<=mark_right?right_x:left_x;cur_y<=mark_right?right_y:left_y;steps<=0;state<=MREQ;
     arm_flags[mark_right]<=1;
    end else if(!mark_right)begin mark_right<=1;end else state<=FINISH;
    MREQ:state<=MUSE;
    MUSE:if(class_q==1)begin if(mark_right)state<=FINISH;else begin mark_right<=1;state<=MARKSTART;end end
     else if(image_q!=3||nav_q[3:0]>=8||steps>=SIZE)begin body_valid<=0;arm_flags<=0;state<=FINISH;end
     else begin cur_x<=parent_x;cur_y<=parent_y;steps<=steps+1'b1;state<=MREQ;end
    FINISH:begin
     done<=1;busy<=0;state<=IDLE;
     previous_body<=body_valid&&!overflow;previous_flags<=body_valid&&!overflow?arm_flags:0;
     previous_cx<=center_x;previous_root_y<=root_y;
     previous_left_x<=left_x;previous_left_y<=left_y;previous_right_x<=right_x;previous_right_y<=right_y;
    end
   endcase
  end
 end
endmodule
