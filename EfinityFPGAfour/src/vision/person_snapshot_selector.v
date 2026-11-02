`timescale 1ns/1ps
// Single-person candidate extraction, not a semantic person detector.
// A 2x2 OR reduction of the 960x540 mask captures one 480x270 snapshot.
// Offline 8-connected flood fills retain up to 16 real components, select a
// primary candidate and merge nearby fragments. A second flood fill copies
// only those components, not all pixels in their bounding rectangle.
// Mask and boundary are double-buffered and published at the next frame start.
// A busy analysis skips input frames; HDMI timing is never stalled.
module person_snapshot_selector #(
    parameter WIDTH=480, HEIGHT=270, MAX_COMPONENTS=16,
    parameter MIN_AREA=32, MIN_WIDTH=4, MIN_HEIGHT=8,
    parameter FRAGMENT_AREA=4, MERGE_GAP=8, PAD=4, SHRINK_STEP=2,
    parameter QUEUE_BITS=12,
    parameter REFINE=0, GROW_PAD=8, GROW_FACTOR=3, GROW_EXTRA=64, MAX_HOLE=64,
    parameter POSE_MATCH=0,
    parameter X_BITS=$clog2(WIDTH), Y_BITS=$clog2(HEIGHT),
    parameter A_BITS=$clog2(WIDTH*HEIGHT)
)(
    input clk, input rst_n, input source_valid, input invalidate,
    input in_vsync, input in_hsync, input in_href, input in_mask,input in_weak_mask,
    output reg refine_fallback,
    output reg out_vsync, output reg out_hsync, output reg out_href,
    output wire out_mask, output wire out_contour,
    output reg bbox_valid, output reg [11:0] bbox_x_min, bbox_x_max,
    output reg [10:0] bbox_y_min, bbox_y_max,
    output wire busy, output reg processing_error,
    output reg [31:0] completed_snapshots,
    input in_canny,input in_canny_valid,
    output reg pose_tick,output reg [2:0] pose_id,
    output reg [9:0] pose_similarity,pose_margin,pose_edge_support
);
localparam PIXELS=WIDTH*HEIGHT, FULL_W=WIDTH*4, FULL_H=HEIGHT*4;
localparam IDLE=0,CAPTURE=1,CLEAR=2,SCAN_REQ=3,SCAN_CHECK=4,
    POP_REQ=5,POP_WAIT=6,POP_SETUP=7,N_REQ=8,N_CHECK=9,COMP_DONE=10,
    CHOOSE=11,MERGE=12,COPY_CLEAR=13,COPY_SEED=14,
    EDGE_REQ=15,EDGE_CHECK=16,EDGE_N_REQ=17,EDGE_N_CHECK=18,EDGE_WRITE=19,
    FINISH=20,RANK_MIN=21,STORE_COMPONENT=22,RANK_MAIN=23,PRIME_MAIN=24,
    SEED_WAIT=25,SEED_CHECK=26,PREPARE_GROW=27,HOLE_CLEAR=28,
    HOLE_FILL_START=29,HOLE_FILL_WAIT=30,HOLE_FILL_WRITE=31,
    MATCH_START=32,MATCH_WAIT=33;
reg [5:0] state;
reg href_d;
reg [11:0] stream_x;
reg [10:0] stream_y;
wire [11:0] px=(in_href&&!href_d)?0:stream_x;
wire [10:0] py=(in_href&&!href_d)?stream_y+1'b1:stream_y;
wire frame_first=in_href&&px==0&&py==0;
wire frame_last=in_href&&px==FULL_W-1&&py==FULL_H-1;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin href_d<=0;stream_x<=0;stream_y<=11'h7ff;end
    else begin
        href_d<=in_href;
        if(!in_vsync)begin stream_x<=0;stream_y<=11'h7ff;end
        else if(in_href)begin stream_x<=px+1'b1;stream_y<=py;end
    end
end
function [A_BITS-1:0] address;
    input [X_BITS-1:0] x; input [Y_BITS-1:0] y;
    begin address=y*WIDTH+x;end
endfunction
reg pair_left;
(* ram_style="block" *) reg top_pairs[0:WIDTH-1];
reg top_q;
// Confidence states: 0 background, 1 weak, 2 strong, 3 visited strong.
// Initial strong-component analysis marks 2->3 in place. Copy visitation
// reuses selected bit 0; hole visitation reuses its temporary bit 1.
reg [1:0] weak_left,weak_top_q,confidence_q;
(* ram_style="block" *) reg [1:0] weak_top[0:WIDTH-1];
(* ram_style="block" *) reg [1:0] confidence[0:PIXELS-1];
wire weak_q=confidence_q!=0;
always @(posedge clk)begin
    if(!REFINE)begin
        top_q<=top_pairs[px>>2];
        if(state==CAPTURE && in_href)begin
            if(px[1:0]==0)pair_left<=in_mask;
            if(px[1:0]==2 && py[1:0]==0)top_pairs[px>>2]<=pair_left|in_mask;
        end
    end
end
wire snapshot_we=state==CAPTURE && in_href && px[1:0]==2 && py[1:0]==2;
wire [A_BITS-1:0] capture_addr=address(px>>2,py>>2);
(* ram_style="block" *) reg snapshot[0:PIXELS-1];
(* ram_style="block" *) reg visited[0:PIXELS-1];
(* ram_style="block" *) reg [1:0] selected0[0:PIXELS-1],selected1[0:PIXELS-1];
(* ram_style="block" *) reg [X_BITS+Y_BITS-1:0] queue[0:(1<<QUEUE_BITS)-1];
reg [QUEUE_BITS-1:0] head,tail;
reg [QUEUE_BITS:0] queued;
reg [X_BITS+Y_BITS-1:0] queue_q;
reg [A_BITS-1:0] cursor;
reg [X_BITS-1:0] scan_x,pop_x,component_seed_x,component_x_min,component_x_max;
reg [Y_BITS-1:0] scan_y,pop_y,component_seed_y,component_y_min,component_y_max;
reg [A_BITS:0] component_area;
reg [3:0] neighbor;
reg copy_pass,edge_boundary;
reg copy_refine,hole_pass,hole_border;
reg [A_BITS+2:0] strong_total,growth_limit,selected_total;
reg [A_BITS:0] hole_remaining;
reg [X_BITS-1:0] base_x_min,base_x_max,search_x_min,search_x_max;
reg [Y_BITS-1:0] base_y_min,base_y_max,search_y_min,search_y_max;
reg front_bank,pending,pending_valid;
reg [X_BITS-1:0] merged_x_min,merged_x_max;
reg [Y_BITS-1:0] merged_y_min,merged_y_max;
reg [MAX_COMPONENTS-1:0] chosen;
// Tight bounds are measured from the final repaired mask, independently of
// the padded/smoothed display rectangle.
reg [X_BITS-1:0] tight_x_min,tight_x_max;
reg [Y_BITS-1:0] tight_y_min,tight_y_max;
wire match_done,match_busy;
wire [X_BITS-1:0] match_x;
wire [Y_BITS-1:0] match_y;
wire [2:0] match_pose;
wire [9:0] match_similarity,match_margin,match_edge_support;
wire match_cancel=!source_valid||invalidate;
wire match_canny;
reg capture_edges_valid,invalid_reported;
reg [4:0] candidate_index,merge_round;
reg [A_BITS:0] counts[0:MAX_COMPONENTS-1];
reg [X_BITS-1:0] seeds_x[0:MAX_COMPONENTS-1],xmin[0:MAX_COMPONENTS-1],xmax[0:MAX_COMPONENTS-1];
reg [Y_BITS-1:0] seeds_y[0:MAX_COMPONENTS-1],ymin[0:MAX_COMPONENTS-1],ymax[0:MAX_COMPONENTS-1];
integer i;
reg [4:0] min_slot,best_slot;
reg [A_BITS+2:0] best_score;
wire overlap=bbox_valid && (xmin[candidate_index]*4<=bbox_x_max) && (xmax[candidate_index]*4+3>=bbox_x_min) &&
                             (ymin[candidate_index]*4<=bbox_y_max) && (ymax[candidate_index]*4+3>=bbox_y_min);
wire [A_BITS+2:0] score=overlap ? (counts[candidate_index]<<1)+counts[candidate_index] : counts[candidate_index];
wire primary_eligible=counts[candidate_index]>=MIN_AREA &&
    xmax[candidate_index]-xmin[candidate_index]+1>=MIN_WIDTH && ymax[candidate_index]-ymin[candidate_index]+1>=MIN_HEIGHT;
// Each neighbor is visited through synchronous RAM (request/check phases).
reg signed [X_BITS:0] nx;
reg signed [Y_BITS:0] ny;
always @(*) begin
    nx=$signed({1'b0,pop_x});ny=$signed({1'b0,pop_y});
    case(neighbor)
        0:begin nx=nx-1;ny=ny-1;end
        1:ny=ny-1;
        2:begin nx=nx+1;ny=ny-1;end
        3:nx=nx-1;
        4:nx=nx+1;
        5:begin nx=nx-1;ny=ny+1;end
        6:ny=ny+1;
        7:begin nx=nx+1;ny=ny+1;end
    endcase
end
wire neighbor_valid=nx>=0 && nx<WIDTH && ny>=0 && ny<HEIGHT;
wire flood_neighbor_valid=neighbor_valid&&(!hole_pass||neighbor==1||neighbor==3||neighbor==4||neighbor==6);
wire [A_BITS-1:0] neighbor_addr=neighbor_valid ? address(nx,ny) : 0;
reg [A_BITS-1:0] process_addr;
reg visited_we,visited_value,selected_we;
reg [1:0] selected_value;
reg legacy_foreground_q,legacy_visited_q;
reg [1:0] sel0_q,sel1_q,video0_q,video1_q;
wire [1:0] process_selected=front_bank?sel0_q:sel1_q;
wire foreground_q=REFINE?confidence_q[1]:legacy_foreground_q;
wire visited_q=REFINE?(hole_pass?process_selected[1]:copy_pass?process_selected[0]:confidence_q==3):legacy_visited_q;
wire inside_search=nx>=search_x_min&&nx<=search_x_max&&ny>=search_y_min&&ny<=search_y_max;
wire eligible=!visited_q&&(hole_pass?!process_selected[0]:
              (REFINE&&copy_pass&&copy_refine?(weak_q&&inside_search):foreground_q));
wire candidate_near=counts[candidate_index]>=FRAGMENT_AREA &&
    xmin[candidate_index]<=merged_x_max+MERGE_GAP && xmax[candidate_index]+MERGE_GAP>=merged_x_min &&
    ymin[candidate_index]<=merged_y_max+MERGE_GAP && ymax[candidate_index]+MERGE_GAP>=merged_y_min;
always @(*)begin
    process_addr=cursor;visited_we=0;visited_value=0;selected_we=0;selected_value=0;
    if(POSE_MATCH&&(state==MATCH_START||state==MATCH_WAIT))process_addr=address(match_x,match_y);
    case(state)
        CLEAR:visited_we=1;
        SCAN_CHECK:begin if(eligible)begin visited_we=1;visited_value=1;end end
        POP_SETUP:begin
            process_addr=address(queue_q[X_BITS-1:0],queue_q[X_BITS+Y_BITS-1:X_BITS]);
            if(copy_pass&&!hole_pass)begin selected_we=1;selected_value=1;end
        end
        N_REQ,N_CHECK,EDGE_N_REQ,EDGE_N_CHECK:begin
            process_addr=neighbor_addr;
            if(state==N_CHECK && flood_neighbor_valid && eligible && queued<(1<<QUEUE_BITS))begin visited_we=1;visited_value=1;end
        end
        COPY_CLEAR:begin visited_we=1;selected_we=1;end
        COPY_SEED:begin
            if(candidate_index<MAX_COMPONENTS && chosen[candidate_index])begin
                process_addr=address(seeds_x[candidate_index],seeds_y[candidate_index]);
                if(!REFINE)begin visited_we=1;visited_value=1;end
            end
        end
        SEED_WAIT,SEED_CHECK:begin
            process_addr=address(seeds_x[candidate_index],seeds_y[candidate_index]);
            if(state==SEED_CHECK&&!visited_q)begin visited_we=1;visited_value=1;end
        end
        HOLE_CLEAR:visited_we=1;
        HOLE_FILL_WRITE:begin
            process_addr=address(queue_q[X_BITS-1:0],queue_q[X_BITS+Y_BITS-1:X_BITS]);
            selected_we=1;selected_value=REFINE?3:1;
        end
        EDGE_WRITE:begin selected_we=1;selected_value={edge_boundary,1'b1};end
    endcase
    if(REFINE&&visited_we&&visited_value)begin
        if(hole_pass)begin selected_we=1;selected_value=2;end
        else if(copy_pass)begin selected_we=1;selected_value=1;end
    end
end
generate if(POSE_MATCH)begin:g_pose_match
    // One snapshot of 8x8-OR Canny cells, held from capture through matching.
    // RAW mask and Canny arrive at identical coordinates via the line ring.
    localparam CW=(WIDTH+1)/2,CH=(HEIGHT+1)/2;
    (* ram_style="block" *)reg canny_snapshot[0:CW*CH-1];
    reg [CW-1:0] canny_columns;
    reg horizontal_or,canny_q;
    wire capturing=(state==CAPTURE)||(state==IDLE&&frame_first&&!pending);
    wire h_or=px[2:0]==0?in_canny:(horizontal_or|in_canny);
    wire block_or=py[2:0]==0?h_or:(canny_columns[px>>3]|h_or);
    always @(posedge clk)begin
        if(capturing&&in_href)begin
            horizontal_or<=h_or;
            if(px[2:0]==7)begin
                canny_columns[px>>3]<=block_or;
                if(py[2:0]==7)canny_snapshot[(py>>3)*CW+(px>>3)]<=block_or;
            end
        end
        canny_q<=canny_snapshot[(match_y>>1)*CW+(match_x>>1)];
    end
    assign match_canny=canny_q;
    person_pose_matcher #(.X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_matcher(
        .clk(clk),.rst_n(rst_n),.start(state==MATCH_START),.cancel(match_cancel),
        .candidate_valid(pending_valid),.edge_frame_valid(capture_edges_valid),
        .xmin(tight_x_min),.xmax(tight_x_max),.ymin(tight_y_min),.ymax(tight_y_max),
        .busy(match_busy),.done(match_done),.read_x(match_x),.read_y(match_y),
        .mask_pixel(process_selected[0]),.canny_pixel(match_canny),
        .pose_id(match_pose),.similarity(match_similarity),.margin(match_margin),.edge_support(match_edge_support));
end else begin:g_pose_disabled
    assign match_done=0;assign match_busy=0;assign match_x=0;assign match_y=0;
    assign match_canny=0;assign match_pose=0;assign match_similarity=0;assign match_margin=0;assign match_edge_support=0;
end endgenerate
wire [A_BITS-1:0] video_addr=(in_href && px<FULL_W && py<FULL_H)?address(px>>2,py>>2):0;
reg queue_we;
reg [QUEUE_BITS-1:0] queue_write_addr;
reg [X_BITS+Y_BITS-1:0] queue_write_data;
// All seed/neighbor writes share one physical write port. Separate assignments
// to queue[0] and queue[tail] would infer multiple write ports and explode FFs.
always @(*)begin
    queue_we=0;queue_write_addr=0;queue_write_data={scan_y,scan_x};
    if(state==SCAN_CHECK && eligible)queue_we=1;
    if(state==N_CHECK && flood_neighbor_valid && eligible && queued<(1<<QUEUE_BITS))begin
        queue_we=1;queue_write_addr=tail;queue_write_data={ny[Y_BITS-1:0],nx[X_BITS-1:0]};
    end
    if(((!REFINE&&state==COPY_SEED)||(REFINE&&state==SEED_CHECK&&!visited_q)) && candidate_index<MAX_COMPONENTS && chosen[candidate_index])begin
        queue_we=1;queue_write_data={seeds_y[candidate_index],seeds_x[candidate_index]};
    end
end
always @(posedge clk)begin
    if(!REFINE)begin
        if(snapshot_we)snapshot[capture_addr]<=top_q|pair_left|in_mask;
        legacy_foreground_q<=snapshot[process_addr];legacy_visited_q<=visited[process_addr];
    end
    sel0_q<=selected0[process_addr];sel1_q<=selected1[process_addr];
    video0_q<=selected0[video_addr];video1_q<=selected1[video_addr];
    queue_q<=queue[head];
    if(!REFINE&&visited_we)visited[process_addr]<=visited_value;
    if(selected_we)begin
        if(front_bank)selected0[process_addr]<=selected_value;
        else selected1[process_addr]<=selected_value;
    end
    if(queue_we)queue[queue_write_addr]<=queue_write_data;
end
wire capture_strong=weak_top_q[1]|weak_left[1]|in_mask;
wire capture_weak=weak_top_q[0]|weak_left[0]|in_weak_mask|in_mask;
wire confidence_we=REFINE&&(snapshot_we||(!copy_pass&&!hole_pass&&visited_we&&visited_value));
wire [A_BITS-1:0] confidence_addr=snapshot_we?capture_addr:process_addr;
wire [1:0] confidence_value=snapshot_we?(capture_strong?2:capture_weak?1:0):3;
always @(posedge clk)begin
 if(confidence_we)confidence[confidence_addr]<=confidence_value;
 if(REFINE)begin
  weak_top_q<=weak_top[px>>2];confidence_q<=confidence[process_addr];
  if(state==CAPTURE&&in_href)begin
   if(px[1:0]==0)weak_left<={in_mask,in_weak_mask|in_mask};
   if(px[1:0]==2&&py[1:0]==0)weak_top[px>>2]<=weak_left|{in_mask,in_weak_mask|in_mask};
  end
 end
end

reg display_bank,display_valid;
assign out_mask=out_href&&display_valid&&(display_bank?video1_q[0]:video0_q[0]);
assign out_contour=out_href&&display_valid&&(display_bank?(video1_q[0]&&video1_q[1]):(video0_q[0]&&video0_q[1]));
assign busy=state!=IDLE || pending;
wire [11:0] new_x_min=merged_x_min>PAD?(merged_x_min-PAD)*4:0;
wire [11:0] new_x_max=(merged_x_max+PAD+1)*4>=FULL_W?FULL_W-1:(merged_x_max+PAD+1)*4-1;
wire [10:0] new_y_min=merged_y_min>PAD?(merged_y_min-PAD)*4:0;
wire [10:0] new_y_max=(merged_y_max+PAD+1)*4>=FULL_H?FULL_H-1:(merged_y_max+PAD+1)*4-1;
wire same_target=bbox_valid && new_x_min<=bbox_x_max && new_x_max>=bbox_x_min &&
                                new_y_min<=bbox_y_max && new_y_max>=bbox_y_min;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state<=IDLE;cursor<=0;scan_x<=0;scan_y<=0;pop_x<=0;pop_y<=0;
        head<=0;tail<=0;queued<=0;neighbor<=0;copy_pass<=0;edge_boundary<=0;
        component_area<=0;component_seed_x<=0;component_seed_y<=0;
        component_x_min<=0;component_x_max<=0;component_y_min<=0;component_y_max<=0;
        front_bank<=0;pending<=0;pending_valid<=0;chosen<=0;candidate_index<=0;merge_round<=0;
        min_slot<=0;best_slot<=0;best_score<=0;
        merged_x_min<=0;merged_x_max<=0;merged_y_min<=0;merged_y_max<=0;
        bbox_valid<=0;bbox_x_min<=0;bbox_x_max<=0;bbox_y_min<=0;bbox_y_max<=0;
        out_vsync<=0;out_hsync<=0;out_href<=0;display_bank<=0;display_valid<=0;
        processing_error<=0;completed_snapshots<=0;
        copy_refine<=0;hole_pass<=0;hole_border<=0;strong_total<=0;growth_limit<=0;selected_total<=0;
        hole_remaining<=0;refine_fallback<=0;
        base_x_min<=0;base_x_max<=0;base_y_min<=0;base_y_max<=0;
        search_x_min<=0;search_x_max<=0;search_y_min<=0;search_y_max<=0;
        tight_x_min<=0;tight_x_max<=0;tight_y_min<=0;tight_y_max<=0;
        capture_edges_valid<=0;invalid_reported<=0;pose_tick<=0;pose_id<=0;pose_similarity<=0;pose_margin<=0;pose_edge_support<=0;
        for(i=0;i<MAX_COMPONENTS;i=i+1)begin counts[i]<=0;seeds_x[i]<=0;seeds_y[i]<=0;xmin[i]<=0;xmax[i]<=0;ymin[i]<=0;ymax[i]<=0;end
    end else begin
        pose_tick<=0;
        if(source_valid&&!invalidate)invalid_reported<=0;
        if(POSE_MATCH&&state==CAPTURE&&in_href&&!in_canny_valid)capture_edges_valid<=0;
        out_vsync<=in_vsync;out_hsync<=in_hsync;out_href<=in_href;
        display_bank<=(frame_first&&pending)?!front_bank:front_bank;
        display_valid<=source_valid&&!invalidate&&((frame_first&&pending)?pending_valid:bbox_valid);
        if(frame_first&&pending)begin
            front_bank<=!front_bank;pending<=0;bbox_valid<=pending_valid;
            if(pending_valid)begin
                bbox_x_min<=same_target&&new_x_min>bbox_x_min+SHRINK_STEP*4?bbox_x_min+SHRINK_STEP*4:new_x_min;
                bbox_x_max<=same_target&&new_x_max+SHRINK_STEP*4<bbox_x_max?bbox_x_max-SHRINK_STEP*4:new_x_max;
                bbox_y_min<=same_target&&new_y_min>bbox_y_min+SHRINK_STEP*4?bbox_y_min+SHRINK_STEP*4:new_y_min;
                bbox_y_max<=same_target&&new_y_max+SHRINK_STEP*4<bbox_y_max?bbox_y_max-SHRINK_STEP*4:new_y_max;
            end
        end
        if(!source_valid || invalidate)begin
            state<=IDLE;pending<=0;bbox_valid<=0;display_valid<=0;
            if(POSE_MATCH&&!invalid_reported)begin
                pose_tick<=1;pose_id<=0;pose_similarity<=0;pose_margin<=0;pose_edge_support<=0;invalid_reported<=1;
            end
        end else case(state)
            IDLE:if(frame_first&&!pending)begin
                state<=CAPTURE;processing_error<=0;refine_fallback<=0;hole_pass<=0;copy_refine<=0;
                capture_edges_valid<=in_canny_valid;
                for(i=0;i<MAX_COMPONENTS;i=i+1)counts[i]<=0;
            end
            CAPTURE:if(frame_last)begin state<=CLEAR;cursor<=0;end
                else if(!in_vsync)begin state<=IDLE;processing_error<=1;end
            CLEAR:if(cursor==PIXELS-1)begin cursor<=0;scan_x<=0;scan_y<=0;copy_pass<=0;state<=SCAN_REQ;end
                else cursor<=cursor+1'b1;
            SCAN_REQ:state<=SCAN_CHECK;
            SCAN_CHECK:if(eligible)begin
                component_seed_x<=scan_x;component_seed_y<=scan_y;
                component_x_min<=scan_x;component_x_max<=scan_x;component_y_min<=scan_y;component_y_max<=scan_y;
                component_area<=0;head<=0;tail<=1;queued<=1;state<=POP_REQ;
                hole_border<=0;
            end else if(cursor==PIXELS-1)begin
                if(hole_pass)begin hole_pass<=0;cursor<=0;scan_x<=0;scan_y<=0;state<=EDGE_REQ;end
                else state<=CHOOSE;
            end
            else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_REQ;end
            POP_REQ:if(queued==0)state<=COMP_DONE;else state<=POP_WAIT;
            POP_WAIT:state<=POP_SETUP;
            POP_SETUP:begin
                pop_x<=queue_q[X_BITS-1:0];pop_y<=queue_q[X_BITS+Y_BITS-1:X_BITS];
                head<=head+1'b1;queued<=queued-1'b1;neighbor<=0;state<=N_REQ;
                component_area<=component_area+1'b1;
                if(hole_pass&&(queue_q[X_BITS-1:0]==0||queue_q[X_BITS-1:0]==WIDTH-1||queue_q[X_BITS+Y_BITS-1:X_BITS]==0||queue_q[X_BITS+Y_BITS-1:X_BITS]==HEIGHT-1))hole_border<=1;
                if(REFINE&&copy_pass&&!hole_pass)begin
                    selected_total<=selected_total+1'b1;
                    if(copy_refine)begin
                        if(queue_q[X_BITS-1:0]<merged_x_min)merged_x_min<=queue_q[X_BITS-1:0];
                        if(queue_q[X_BITS-1:0]>merged_x_max)merged_x_max<=queue_q[X_BITS-1:0];
                        if(queue_q[X_BITS+Y_BITS-1:X_BITS]<merged_y_min)merged_y_min<=queue_q[X_BITS+Y_BITS-1:X_BITS];
                        if(queue_q[X_BITS+Y_BITS-1:X_BITS]>merged_y_max)merged_y_max<=queue_q[X_BITS+Y_BITS-1:X_BITS];
                        if(selected_total>=growth_limit)begin
                            copy_refine<=0;refine_fallback<=1;cursor<=0;state<=COPY_CLEAR;
                            merged_x_min<=base_x_min;merged_x_max<=base_x_max;merged_y_min<=base_y_min;merged_y_max<=base_y_max;
                        end
                    end
                end
                if(queue_q[X_BITS-1:0]<component_x_min)component_x_min<=queue_q[X_BITS-1:0];
                if(queue_q[X_BITS-1:0]>component_x_max)component_x_max<=queue_q[X_BITS-1:0];
                if(queue_q[X_BITS+Y_BITS-1:X_BITS]<component_y_min)component_y_min<=queue_q[X_BITS+Y_BITS-1:X_BITS];
                if(queue_q[X_BITS+Y_BITS-1:X_BITS]>component_y_max)component_y_max<=queue_q[X_BITS+Y_BITS-1:X_BITS];
            end
            N_REQ:state<=N_CHECK;
            N_CHECK:begin
                if(flood_neighbor_valid&&eligible)begin
                    if(queued==(1<<QUEUE_BITS))begin state<=IDLE;processing_error<=1;pending<=0;bbox_valid<=0;end
                    else begin tail<=tail+1'b1;queued<=queued+1'b1;end
                end
                if(!(flood_neighbor_valid&&eligible&&queued==(1<<QUEUE_BITS)))begin
                    if(neighbor==7)state<=POP_REQ;else begin neighbor<=neighbor+1'b1;state<=N_REQ;end
                end
            end
            COMP_DONE:if(hole_pass)begin
                if(!hole_border&&component_area!=0&&component_area<=MAX_HOLE)begin hole_remaining<=component_area;state<=HOLE_FILL_START;end
                else if(cursor==PIXELS-1)begin hole_pass<=0;cursor<=0;scan_x<=0;scan_y<=0;state<=EDGE_REQ;end
                else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_REQ;end
            end else if(copy_pass)begin candidate_index<=candidate_index+1'b1;state<=COPY_SEED;end
            else begin candidate_index<=0;min_slot<=0;state<=RANK_MIN;end
            RANK_MIN:begin
                if(counts[candidate_index]<counts[min_slot])min_slot<=candidate_index;
                if(candidate_index==MAX_COMPONENTS-1)state<=STORE_COMPONENT;
                else candidate_index<=candidate_index+1'b1;
            end
            STORE_COMPONENT:begin
                if(component_area>=FRAGMENT_AREA && component_area>counts[min_slot])begin
                    counts[min_slot]<=component_area;seeds_x[min_slot]<=component_seed_x;seeds_y[min_slot]<=component_seed_y;
                    xmin[min_slot]<=component_x_min;xmax[min_slot]<=component_x_max;ymin[min_slot]<=component_y_min;ymax[min_slot]<=component_y_max;
                end
                if(cursor==PIXELS-1)state<=CHOOSE;
                else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_REQ;end
            end
            CHOOSE:begin
                best_score<=0;best_slot<=0;candidate_index<=0;state<=RANK_MAIN;
            end
            RANK_MAIN:begin
                if(primary_eligible && score>best_score)begin best_score<=score;best_slot<=candidate_index;end
                if(candidate_index==MAX_COMPONENTS-1)state<=PRIME_MAIN;
                else candidate_index<=candidate_index+1'b1;
            end
            PRIME_MAIN:begin
                chosen<=0;pending_valid<=best_score!=0;candidate_index<=0;merge_round<=0;
                if(best_score!=0)begin
                    chosen[best_slot]<=1;merged_x_min<=xmin[best_slot];merged_x_max<=xmax[best_slot];
                    merged_y_min<=ymin[best_slot];merged_y_max<=ymax[best_slot];state<=MERGE;
                end else begin cursor<=0;state<=COPY_CLEAR;end
            end
            MERGE:begin
                if(candidate_near)begin
                    chosen[candidate_index]<=1;
                    if(xmin[candidate_index]<merged_x_min)merged_x_min<=xmin[candidate_index];
                    if(xmax[candidate_index]>merged_x_max)merged_x_max<=xmax[candidate_index];
                    if(ymin[candidate_index]<merged_y_min)merged_y_min<=ymin[candidate_index];
                    if(ymax[candidate_index]>merged_y_max)merged_y_max<=ymax[candidate_index];
                end
                if(candidate_index==MAX_COMPONENTS-1)begin
                    candidate_index<=0;
                    if(merge_round==1)begin cursor<=0;strong_total<=0;state<=REFINE?PREPARE_GROW:COPY_CLEAR;end else merge_round<=merge_round+1'b1;
                end else candidate_index<=candidate_index+1'b1;
            end
            PREPARE_GROW:begin
                if(chosen[candidate_index])strong_total<=strong_total+counts[candidate_index];
                if(candidate_index==MAX_COMPONENTS-1)begin
                    growth_limit<=(strong_total+(chosen[candidate_index]?counts[candidate_index]:0))*GROW_FACTOR+GROW_EXTRA;
                    base_x_min<=merged_x_min;base_x_max<=merged_x_max;base_y_min<=merged_y_min;base_y_max<=merged_y_max;
                    search_x_min<=merged_x_min>GROW_PAD?merged_x_min-GROW_PAD:0;
                    search_x_max<=merged_x_max+GROW_PAD>=WIDTH?WIDTH-1:merged_x_max+GROW_PAD;
                    search_y_min<=merged_y_min>GROW_PAD?merged_y_min-GROW_PAD:0;
                    search_y_max<=merged_y_max+GROW_PAD>=HEIGHT?HEIGHT-1:merged_y_max+GROW_PAD;
                    cursor<=0;copy_refine<=1;state<=COPY_CLEAR;
                end else candidate_index<=candidate_index+1'b1;
            end
            COPY_CLEAR:begin
                if(cursor==0)begin selected_total<=0;tight_x_min<=WIDTH-1;tight_x_max<=0;tight_y_min<=HEIGHT-1;tight_y_max<=0;end
                if(cursor==PIXELS-1)begin cursor<=0;candidate_index<=0;copy_pass<=1;state<=COPY_SEED;end
                else cursor<=cursor+1'b1;
            end
            COPY_SEED:if(candidate_index==MAX_COMPONENTS)begin cursor<=0;scan_x<=0;scan_y<=0;state<=(REFINE&&MAX_HOLE!=0&&pending_valid)?HOLE_CLEAR:EDGE_REQ;end
                else if(chosen[candidate_index])begin
                    if(REFINE)state<=SEED_WAIT;
                    else begin head<=0;tail<=1;queued<=1;state<=POP_REQ;end
                end
                else candidate_index<=candidate_index+1'b1;
            SEED_WAIT:state<=SEED_CHECK;
            SEED_CHECK:if(visited_q)begin candidate_index<=candidate_index+1'b1;state<=COPY_SEED;end
                else begin head<=0;tail<=1;queued<=1;state<=POP_REQ;end
            HOLE_CLEAR:if(cursor==PIXELS-1)begin cursor<=0;scan_x<=0;scan_y<=0;hole_pass<=1;state<=SCAN_REQ;end
                else cursor<=cursor+1'b1;
            HOLE_FILL_START:begin head<=0;state<=HOLE_FILL_WAIT;end
            HOLE_FILL_WAIT:state<=HOLE_FILL_WRITE;
            HOLE_FILL_WRITE:begin
                head<=head+1'b1;hole_remaining<=hole_remaining-1'b1;
                if(hole_remaining>1)state<=HOLE_FILL_WAIT;
                else if(cursor==PIXELS-1)begin hole_pass<=0;cursor<=0;scan_x<=0;scan_y<=0;state<=EDGE_REQ;end
                else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=SCAN_REQ;end
            end
            EDGE_REQ:state<=EDGE_CHECK;
            EDGE_CHECK:if(process_selected[0])begin
                pop_x<=scan_x;pop_y<=scan_y;neighbor<=0;edge_boundary<=0;state<=EDGE_N_REQ;
                if(scan_x<tight_x_min)tight_x_min<=scan_x;
                if(scan_x>tight_x_max)tight_x_max<=scan_x;
                if(scan_y<tight_y_min)tight_y_min<=scan_y;
                if(scan_y>tight_y_max)tight_y_max<=scan_y;
            end
                else if(cursor==PIXELS-1)state<=FINISH;
                else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=EDGE_REQ;end
            EDGE_N_REQ:state<=EDGE_N_CHECK;
            EDGE_N_CHECK:begin
                if(!neighbor_valid || !process_selected[0])edge_boundary<=1;
                if(neighbor==7)state<=EDGE_WRITE;else begin neighbor<=neighbor+1'b1;state<=EDGE_N_REQ;end
            end
            EDGE_WRITE:if(cursor==PIXELS-1)state<=FINISH;
                else begin cursor<=cursor+1'b1;if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;state<=EDGE_REQ;end
            FINISH:if(POSE_MATCH)state<=MATCH_START;
                else begin pending<=1;completed_snapshots<=completed_snapshots+1'b1;state<=IDLE;end
            MATCH_START:state<=MATCH_WAIT;
            MATCH_WAIT:if(match_done)begin
                pose_tick<=1;pose_id<=match_pose;pose_similarity<=match_similarity;pose_margin<=match_margin;pose_edge_support<=match_edge_support;
                pending<=1;completed_snapshots<=completed_snapshots+1'b1;state<=IDLE;
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule
