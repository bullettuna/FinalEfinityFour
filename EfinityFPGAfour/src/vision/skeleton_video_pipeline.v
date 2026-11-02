`timescale 1ns/1ps
// Captures a complete selected silhouette with square-pixel OR pooling.
// Work RAM is private to the offline core; display banks swap only in blank.
module skeleton_video_pipeline #(
 parameter WIDTH=1920,HEIGHT=1080,STEP_LOG2=4,MAX_ITER=64,
 parameter GW=(WIDTH+(1<<STEP_LOG2)-1)>>STEP_LOG2,
 parameter GH=(HEIGHT+(1<<STEP_LOG2)-1)>>STEP_LOG2,AW=$clog2(GW*GH)
)(
 input clk,input rst_n,input source_valid,input selected_pixel,
 input in_vsync,input in_hsync,input in_href,input [23:0] reference_rgb,input [2:0] view,
 output reg out_vsync,output reg out_hsync,output reg out_href,output reg [23:0] out_rgb,
 output reg display_active,output reg sample_tick,output reg sample_valid,output reg sample_converged,
 output reg [7:0] sample_iterations,output reg [15:0] sample_pixels,sample_endpoints,sample_branches,sample_pruned,
 output busy,output reg sample_body_valid,output reg [1:0] sample_arm_flags
);
 localparam SIZE=GW*GH,IDLE=0,CAPTURE=1,START=2,ANALYZE=3,COPY_READ=4,COPY_WAIT=5,COPY_WRITE=6,PUBLISH=7;
 reg [3:0] state;
 localparam BODY_START=8,BODY_WAIT=9,BODY_READ=10,BODY_DELAY=11,BODY_WRITE=12;
 reg de_d;reg [11:0] x;reg [10:0] y;
 wire [11:0] dx=in_href&&!de_d?12'd0:x;
 wire [10:0] dy=in_href&&!de_d?y+1'b1:y;
 wire first=in_vsync&&in_href&&dx==0&&dy==0;
 wire last=in_href&&dx==WIDTH-1&&dy==HEIGHT-1;
 wire capturing=state==CAPTURE||(state==IDLE&&first&&source_valid);
 wire [AW-1:0] grid_addr=(dy>>STEP_LOG2)*GW+(dx>>STEP_LOG2);
 wire block_x_end=((dx&((1<<STEP_LOG2)-1))==((1<<STEP_LOG2)-1))||dx==WIDTH-1;
 wire block_y_end=((dy&((1<<STEP_LOG2)-1))==((1<<STEP_LOG2)-1))||dy==HEIGHT-1;
 reg [GW-1:0] columns;
 reg horizontal;
 wire row_value=((dx&((1<<STEP_LOG2)-1))==0?1'b0:horizontal)||selected_pixel;
 wire cell_value=((dy&((1<<STEP_LOG2)-1))==0?1'b0:columns[dx>>STEP_LOG2])||row_value;
 wire load_en=capturing&&in_href&&block_x_end&&block_y_end&&source_valid;
 (* ram_style="block" *)reg original[0:SIZE-1];
 (* ram_style="block" *)reg [1:0] display0[0:SIZE-1],display1[0:SIZE-1];
 (* ram_style="block" *)reg [1:0] classes0[0:SIZE-1],classes1[0:SIZE-1];
 reg [1:0] cq0,cq1;
 reg original_q;reg [1:0] q0,q1;
 reg front_bank,front_valid;
 reg [AW-1:0] copy_addr;
 wire core_pixel,core_busy,core_done,core_converged;
 wire [7:0] core_iterations;wire [15:0] core_pixels,core_endpoints,core_branches,core_pruned;
 skeleton_thinner #(.WIDTH(GW),.HEIGHT(GH),.MAX_ITER(MAX_ITER)) u_thinner(
  .clk(clk),.rst_n(rst_n),.cancel(!source_valid),.load_en(load_en),.load_addr(grid_addr),.load_pixel(cell_value),
  .start(state==START&&source_valid),.result_addr(copy_addr),.result_pixel(core_pixel),
  .busy(core_busy),.done(core_done),.converged(core_converged),.iterations(core_iterations),
  .pixels(core_pixels),.endpoints(core_endpoints),.branches(core_branches),.pruned(core_pruned));
 wire body_done,body_valid;wire [1:0] body_class,body_arms;
 upper_body_constraint #(.WIDTH(GW),.HEIGHT(GH)) u_body_constraint(
  .clk(clk),.rst_n(rst_n),.cancel(!source_valid||(state==BODY_START&&!core_converged)),
  .load_en(state==COPY_WRITE&&source_valid),.load_addr(copy_addr),.load_mask(original_q),.load_skeleton(core_pixel),
  .start(state==BODY_START&&core_converged&&source_valid),.result_addr(copy_addr),.result_class(body_class),
  .busy(),.done(body_done),.body_valid(body_valid),.arm_flags(body_arms),.overflow());
 assign busy=state!=IDLE;
 wire [AW-1:0] display_addr=in_href&&dx<WIDTH&&dy<HEIGHT?grid_addr:{AW{1'b0}};
 always @(posedge clk)begin
  if(load_en)original[grid_addr]<=cell_value;
  original_q<=original[copy_addr];
  q0<=display0[display_addr];q1<=display1[display_addr];
  cq0<=classes0[display_addr];cq1<=classes1[display_addr];
  if(state==COPY_WRITE&&source_valid)begin
   if(front_bank)display0[copy_addr]<={core_pixel,original_q};
   else display1[copy_addr]<={core_pixel,original_q};
  end
  if(state==BODY_WRITE&&source_valid)begin
   if(front_bank)classes0[copy_addr]<=body_class;
   else classes1[copy_addr]<=body_class;
  end
 end
 reg had_source;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;de_d<=0;x<=0;y<=11'h7ff;columns<=0;horizontal<=0;
   front_bank<=0;front_valid<=0;copy_addr<=0;had_source<=0;
   sample_tick<=0;sample_valid<=0;sample_converged<=0;sample_iterations<=0;
   sample_pixels<=0;sample_endpoints<=0;sample_branches<=0;sample_pruned<=0;
   sample_body_valid<=0;sample_arm_flags<=0;
  end else begin
   de_d<=in_href;
   if(!in_vsync)begin x<=0;y<=11'h7ff;end
   else if(in_href)begin x<=dx+1'b1;y<=dy;end
   sample_tick<=0;had_source<=source_valid;
   if(!source_valid)begin
    state<=IDLE;front_valid<=0;sample_valid<=0;
    sample_body_valid<=0;sample_arm_flags<=0;
    if(had_source)sample_tick<=1;
   end else begin
    if(capturing&&in_href)begin
     horizontal<=row_value;
     if(block_x_end)columns[dx>>STEP_LOG2]<=cell_value;
    end
    case(state)
     IDLE:if(first)state<=CAPTURE;
     CAPTURE:if(last)state<=START;else if(!in_vsync)state<=IDLE;
     START:state<=ANALYZE;
     ANALYZE:if(core_done)begin copy_addr<=0;state<=COPY_READ;end
     COPY_READ:state<=COPY_WAIT;
     COPY_WAIT:state<=COPY_WRITE;
     COPY_WRITE:if(copy_addr==SIZE-1)state<=BODY_START;else begin copy_addr<=copy_addr+1'b1;state<=COPY_READ;end
     BODY_START:state<=core_converged?BODY_WAIT:PUBLISH;
     BODY_WAIT:if(body_done)begin copy_addr<=0;state<=BODY_READ;end
     BODY_READ:state<=BODY_DELAY;
     BODY_DELAY:state<=BODY_WRITE;
     BODY_WRITE:if(copy_addr==SIZE-1)state<=PUBLISH;else begin copy_addr<=copy_addr+1'b1;state<=BODY_READ;end
     PUBLISH:if(!in_vsync)begin
      front_bank<=!front_bank;front_valid<=1;state<=IDLE;
      sample_tick<=1;sample_valid<=core_pixels!=0;sample_converged<=core_converged;
      sample_iterations<=core_iterations;sample_pixels<=core_pixels;
      sample_endpoints<=core_endpoints;sample_branches<=core_branches;sample_pruned<=core_pruned;
      sample_body_valid<=core_converged&&body_valid;
      sample_arm_flags<=core_converged&&body_valid?body_arms:0;
     end
    endcase
   end
  end
 end
 reg dv,dh,de,valid_d,bank_d,conv_d,body_d;reg [23:0] rgb_d;reg [2:0] view_active,view_d;
 wire [1:0] shown=bank_d?q1:q0;
 wire [1:0] shown_class=bank_d?cq1:cq0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   dv<=0;dh<=0;de<=0;rgb_d<=0;valid_d<=0;bank_d<=0;conv_d<=0;view_active<=0;view_d<=0;
   out_vsync<=0;out_hsync<=0;out_href<=0;out_rgb<=0;display_active<=0;
   body_d<=0;
  end else begin
   if(!in_vsync)view_active<=view;
   dv<=in_vsync;dh<=in_hsync;de<=in_href;rgb_d<=reference_rgb;
   valid_d<=front_valid&&source_valid;bank_d<=front_bank;conv_d<=sample_converged;view_d<=view_active;
   body_d<=sample_body_valid;
   out_vsync<=dv;out_hsync<=dh;out_href<=de;
   if(!dv)display_active<=view_active!=0&&view_active<=6;
   out_rgb<=0;
   if(de)case(view_d)
    1,2:out_rgb<=rgb_d;
    3:out_rgb<=valid_d&&shown[0]?24'hffffff:24'd0;
    4:out_rgb<=valid_d&&shown[1]?(conv_d?24'hffffff:24'hffff00):24'd0;
    5:out_rgb<=!valid_d?24'd0:shown[1]?24'hff2020:shown[0]?24'h505050:24'd0;
    6:out_rgb<=!valid_d?24'd0:body_d&&shown_class==1?24'h20ff20:
       body_d&&shown_class==2?24'h20ffff:body_d&&shown_class==3?24'hff20ff:shown[0]?24'h505050:24'd0;
   endcase
  end
 end
endmodule
