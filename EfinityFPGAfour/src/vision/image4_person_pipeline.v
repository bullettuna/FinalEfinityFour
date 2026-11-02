`timescale 1ns/1ps
// Private image4 segmentation frontend: selected mask is independent of view.
module image4_person_pipeline #(parameter WIDTH=1920,HEIGHT=1080,H_TOTAL=2200,DUAL_SOURCE=0,RAW_REFINE=0,POSE_MATCH=0,LIGHTING_AVAILABLE=0,WHITE_AVAILABLE=0,WEAK_GROWTH=0)(
    input clk,input rst_n,input background_valid,input sample_valid,input stream_fault,
    input in_vsync,input in_hsync,input in_href,input [7:0] current_raw,background_raw,
    input [7:0] threshold_req,input [1:0] noise_req,input [2:0] view_req,input lighting_req,input white_req,
    output reg white_active,output wire white_ready,
    input edge_source_req,input edge_vsync,input edge_hsync,input edge_href,input edge_foreground,input edge_pixel,
    input edge_reference_valid,input edge_stream_fault,output reg edge_source_active,
    output reg out_vsync,output reg out_hsync,output reg out_href,output reg [23:0] out_rgb,
    output reg selected_pixel,output wire [2:0] active_view,
    output reg display_active,output wire candidate_valid,output wire analysis_busy,
    output wire processing_error,output wire [11:0] roi_x_min,roi_x_max,output wire [10:0] roi_y_min,roi_y_max,
    input canny_vsync,input canny_href,input canny_pixel,input pose_config_changed,
    output wire pose_tick,output wire [2:0] pose_id,
    output wire [9:0] pose_similarity,pose_margin,pose_edge_support
);
(* async_reg="true" *) reg [7:0] threshold_meta,threshold_sync;
(* async_reg="true" *) reg [1:0] noise_meta,noise_sync;
(* async_reg="true" *) reg [2:0] view_meta,view_sync;
(* async_reg="true" *) reg ready_meta,ready_sync;
reg [7:0] threshold_active;
reg [1:0] noise_active;
reg [2:0] view_active;
(* async_reg="true" *)reg light_meta,light_sync;
(* async_reg="true" *)reg white_meta,white_sync;
reg light_active;
reg config_changed,invalidate_pending,selector_invalidate;
wire mv,mh,me,mask,raw_mask,weak_mask,mask_error,binary_raw,original_edge;
(* async_reg="true" *)reg source_meta,source_sync;
reg source_changed,source_changed_d;
wire pv=edge_source_active?edge_vsync:in_vsync;
wire ph=edge_source_active?edge_hsync:in_hsync;
wire pe=edge_source_active?edge_href:in_href;
wire selected_ready=white_active?white_ready:edge_source_active?edge_reference_valid:ready_sync;
wire selected_fault=white_active?1'b0:edge_source_active?edge_stream_fault:stream_fault;
wire pipeline_rst_n=rst_n&&!source_changed;
// The reference commits in RAW blank, before the delayed mask finishes its
// previous frame. Publish readiness to the matcher only in mask blank.
reg white_output_ready;
always @(posedge clk or negedge pipeline_rst_n)begin
 if(!pipeline_rst_n)white_output_ready<=0;
 else if(!mv)white_output_ready<=white_ready;
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin source_meta<=0;source_sync<=0;edge_source_active<=0;source_changed<=0;source_changed_d<=0;white_meta<=0;white_sync<=0;white_active<=0;end
 else begin
  source_meta<=DUAL_SOURCE&&edge_source_req;source_sync<=source_meta;source_changed<=0;source_changed_d<=source_changed;
  white_meta<=WHITE_AVAILABLE&&white_req;white_sync<=white_meta;
  if(!in_vsync&&white_active!=white_sync)begin white_active<=white_sync;source_changed<=1;end
  if(!in_vsync&&(!DUAL_SOURCE||!edge_vsync)&&edge_source_active!=source_sync)begin
   edge_source_active<=source_sync;source_changed<=1;
  end
 end
end
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        threshold_meta<=24;threshold_sync<=24;threshold_active<=24;
        noise_meta<=2;noise_sync<=2;noise_active<=2;
        view_meta<=0;view_sync<=0;view_active<=0;
        ready_meta<=0;ready_sync<=0;config_changed<=0;invalidate_pending<=0;selector_invalidate<=0;
        light_meta<=LIGHTING_AVAILABLE;light_sync<=LIGHTING_AVAILABLE;light_active<=LIGHTING_AVAILABLE;
    end else begin
        threshold_meta<=threshold_req;threshold_sync<=threshold_meta;
        noise_meta<=noise_req;noise_sync<=noise_meta;
        view_meta<=view_req;view_sync<=view_meta;
        ready_meta<=background_valid;ready_sync<=ready_meta;
        light_meta<=LIGHTING_AVAILABLE&&lighting_req;light_sync<=light_meta;
        config_changed<=0;
        selector_invalidate<=0;
        if(config_changed)invalidate_pending<=1;
        // RAW and morphology blank at different times. Finish the previous
        // mask frame before invalidating a result for new threshold/noise.
        if(!mv&&invalidate_pending)begin selector_invalidate<=1;invalidate_pending<=0;end
        if(!in_vsync)begin
            config_changed<=(threshold_active!=threshold_sync)||(noise_active!=noise_sync)||(light_active!=light_sync);
            threshold_active<=threshold_sync;noise_active<=noise_sync;light_active<=light_sync;
        end
        if(!mv)view_active<=view_sync;
    end
end
background_mask_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(H_TOTAL),.BINARY_AVAILABLE(DUAL_SOURCE),.REFINE_AVAILABLE(RAW_REFINE),.LIGHTING_AVAILABLE(LIGHTING_AVAILABLE),.WHITE_AVAILABLE(WHITE_AVAILABLE)) u_background_mask_pipeline(
    .clk(clk),.rst_n(pipeline_rst_n),.in_vsync(pv),.in_hsync(ph),.in_href(pe),
    .background_valid(selected_ready),.background_sample_valid(white_active?1'b1:edge_source_active?selected_ready:sample_valid),
    .current_raw(current_raw),.background_raw(background_raw),.diff_threshold(threshold_active),.noise_mode(noise_active),.binary_mode(edge_source_active),.binary_pixel(edge_foreground),.original_edge(edge_pixel),
    .lighting_enable(light_active),
    .white_mode(white_active),.white_ready(white_ready),
    .out_vsync(mv),.out_hsync(mh),.out_href(me),.out_mask(mask),.out_raw_mask(raw_mask),.out_weak_mask(weak_mask),.out_binary_pixel(binary_raw),.out_original_edge(original_edge),.stream_error(mask_error),
    .debug_cell_valid(),.debug_cell_mask(),.debug_current_mean(),.debug_background_mean()
);
wire sv,sh,se,selected_mask,contour,selector_error;
wire [11:0] xmin,xmax;
wire [10:0] ymin,ymax;
// One invalid cycle after reset release publishes POSE:0 even if the other
// mode already has a valid model, so UART confirmation never crosses modes.
wire valid_source=(white_active?white_output_ready:selected_ready)&&!selected_fault&&!mask_error&&!source_changed&&!source_changed_d;
wire match_v,match_h,match_e,match_mask,match_weak,match_canny,match_canny_valid;
wire diagnostic_raw,diagnostic_clean,diagnostic_edge;
generate if(POSE_MATCH)begin:g_match_alignment
    reg [1:0] mask_delay,weak_delay,raw_delay,original_delay;
    always @(posedge clk)begin
        mask_delay<={mask_delay[0],mask};weak_delay<={weak_delay[0],weak_mask};
        raw_delay<={raw_delay[0],raw_mask};original_delay<={original_delay[0],original_edge};
    end
    assign match_mask=mask_delay[1];assign match_weak=weak_delay[1];
    assign diagnostic_raw=raw_delay[1];assign diagnostic_clean=mask_delay[1];assign diagnostic_edge=original_delay[1];
    // Existing row/epoch tags reject mixed frames; selector freezes the paired
    // coarse edge snapshot until its matching job has completed.
    person_canny_roi_view #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_edge_alignment(
        .clk(clk),.rst_n(pipeline_rst_n),.view_req(3'd0),.source_valid(1'b1),
        .edge_vsync(canny_vsync),.edge_href(canny_href),.edge_pixel(canny_pixel),
        .target_vsync(mv),.target_hsync(mh),.target_href(me),
        .bbox_valid(1'b0),.bbox_x_min(12'd0),.bbox_x_max(12'd0),.bbox_y_min(11'd0),.bbox_y_max(11'd0),
        .out_vsync(match_v),.out_hsync(match_h),.out_href(match_e),.out_rgb(),.display_active(),
        .aligned_edge(match_canny),.aligned_edge_valid(match_canny_valid));
end else begin:g_match_alignment_disabled
    assign match_v=mv;assign match_h=mh;assign match_e=me;assign match_mask=mask;assign match_weak=weak_mask;
    assign match_canny=0;assign match_canny_valid=0;
    assign diagnostic_raw=raw_mask;assign diagnostic_clean=mask;assign diagnostic_edge=original_edge;
end endgenerate
person_snapshot_selector #(.WIDTH(WIDTH/4),.HEIGHT(HEIGHT/4),.REFINE(RAW_REFINE),.POSE_MATCH(POSE_MATCH)) u_person_snapshot_selector(
    .clk(clk),.rst_n(pipeline_rst_n),.source_valid(valid_source),.invalidate(selector_invalidate||(POSE_MATCH&&pose_config_changed)),
    // Keep strong-mask capture, component selection and hole filling. With
    // weak growth disabled, the selector cannot add N/2-only foreground.
    .in_vsync(match_v),.in_hsync(match_h),.in_href(match_e),.in_mask(match_mask),.in_weak_mask(WEAK_GROWTH?match_weak:1'b0),
    .in_canny(match_canny),.in_canny_valid(match_canny_valid),
    .pose_tick(pose_tick),.pose_id(pose_id),.pose_similarity(pose_similarity),.pose_margin(pose_margin),.pose_edge_support(pose_edge_support),
    .out_vsync(sv),.out_hsync(sh),.out_href(se),.out_mask(selected_mask),.out_contour(contour),
    .bbox_valid(candidate_valid),.bbox_x_min(xmin),.bbox_x_max(xmax),.bbox_y_min(ymin),.bbox_y_max(ymax),
    .busy(analysis_busy),.processing_error(selector_error),.completed_snapshots()
);
assign processing_error=mask_error||selector_error;
assign roi_x_min=xmin;assign roi_x_max=xmax;assign roi_y_min=ymin;assign roi_y_max=ymax;
assign active_view=view_active;
reg aligned_raw,aligned_clean,aligned_edge,de_d;
reg [11:0] x;
reg [10:0] y;
wire [11:0] dx=se&&!de_d?0:x;
wire [10:0] dy=se&&!de_d?y+1'b1:y;
wire on_box=candidate_valid &&
    (((dx==xmin||dx==xmax)&&dy>=ymin&&dy<=ymax)||((dy==ymin||dy==ymax)&&dx>=xmin&&dx<=xmax));
reg draw;
always @(*)begin
    case(view_active)
        1:draw=aligned_raw&&valid_source;
        2:draw=aligned_clean&&valid_source;
        4:draw=edge_source_active?(aligned_edge&&candidate_valid&&dx>=xmin&&dx<=xmax&&dy>=ymin&&dy<=ymax):contour;
        default:draw=selected_mask;
    endcase
end
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        aligned_raw<=0;aligned_clean<=0;aligned_edge<=0;de_d<=0;x<=0;y<=11'h7ff;
        out_vsync<=0;out_hsync<=0;out_href<=0;out_rgb<=0;display_active<=0;selected_pixel<=0;
    end else begin
        aligned_raw<=edge_source_active?binary_raw:diagnostic_raw;aligned_clean<=diagnostic_clean;aligned_edge<=diagnostic_edge;
        de_d<=se;
        if(!sv)begin x<=0;y<=11'h7ff;end
        else if(se)begin x<=dx+1'b1;y<=dy;end
        out_vsync<=sv;out_hsync<=sh;out_href<=se;
        selected_pixel<=se&&valid_source&&selected_mask;
        out_rgb<=!se?24'd0:((view_active==5&&on_box&&valid_source)?24'h00ff00:(draw?24'hffffff:24'd0));
        if(!sv)display_active<=view_active!=0&&view_active<=5;
    end
end
endmodule
