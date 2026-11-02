`timescale 1ns/1ps
// Sparse, color-consistent samples vote for a global Q1.5 exposure gain.
// A shared serial divider is used only once per 32x32 Bayer cells. No frame
// memory and no per-pixel divider. Estimate is committed in vertical blank.
module background_gain_estimator(
 input clk,input rst_n,input model_valid,input frame_start,input frame_end,
 input sample_valid,input [7:0] current_mean,background_mean,
 output reg [5:0] gain
);
 reg [11:0] histogram[0:32];
 reg [11:0] samples,best_votes;
 reg [5:0] scan,best_bin;
 reg [1:0] phase;
 reg dividing;reg [13:0] numerator,quotient;
 reg [8:0] remainder;reg [7:0] denominator;reg [3:0] bit_left;
 wire [9:0] trial={remainder,numerator[13]};
 wire subtract=trial>={2'd0,denominator};
 wire [13:0] next_quotient={quotient[12:0],subtract};
 wire better=histogram[scan]>best_votes;
 wire [11:0] winning_votes=better?histogram[scan]:best_votes;
 wire [5:0] winning_bin=better?scan:best_bin;
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   gain<=32;samples<=0;best_votes<=0;scan<=0;best_bin<=16;phase<=0;
   dividing<=0;numerator<=0;quotient<=0;remainder<=0;denominator<=1;bit_left<=0;
   for(i=0;i<33;i=i+1)histogram[i]<=0;
  end else if(!model_valid)begin
   gain<=32;samples<=0;best_votes<=0;phase<=0;dividing<=0;
   for(i=0;i<33;i=i+1)histogram[i]<=0;
  end else if(frame_start)begin
   samples<=0;best_votes<=0;scan<=0;best_bin<=gain-16;phase<=0;dividing<=0;
   for(i=0;i<33;i=i+1)histogram[i]<=0;
  end else begin
   if(frame_end)phase<=1;
   if(phase==1&&!dividing)begin phase<=2;scan<=0;best_votes<=0;end
   if(phase==2)begin
    if(better)begin best_votes<=histogram[scan];best_bin<=scan;end
    if(scan==32)begin
     if(samples>=4&&({2'd0,winning_votes}<<2)>=samples)gain<=winning_bin+16;
     phase<=3;
    end else scan<=scan+1'b1;
   end
   if(dividing)begin
    numerator<={numerator[12:0],1'b0};quotient<=next_quotient;
    remainder<=subtract?trial-denominator:trial;
    if(bit_left==0)begin
     dividing<=0;
     if(next_quotient>=16&&next_quotient<=48&&samples!=4095)begin
      histogram[next_quotient-16]<=histogram[next_quotient-16]+1'b1;samples<=samples+1'b1;
     end
    end else bit_left<=bit_left-1'b1;
   end else if(sample_valid&&phase==0&&background_mean!=0)begin
    numerator<=({6'd0,current_mean}<<5)+(background_mean>>1);
    denominator<=background_mean;quotient<=0;remainder<=0;bit_left<=13;dividing<=1;
   end
  end
 end
endmodule

// White-cloth reference from sparse samples in the outer 1/8 of the picture.
// Keep the four sensor sites separate: an unbalanced RAW white is not RGB gray.
// Four shared serial divisions run only in blank; no pixel/frame memory.
module background_white_estimator #(parameter SAMPLE_BITS=5,WIDTH_CELLS=960,HEIGHT_CELLS=540)(
 input clk,input rst_n,input enabled,input frame_start,input frame_end,input in_valid,
 input [31:0] current_quad,input [11:0] cell_x,input [9:0] cell_y,
 output reg [31:0] white_quad,output reg ready
);
 wire [9:0] total={2'd0,current_quad[31:24]}+{2'd0,current_quad[23:16]}+
                   {2'd0,current_quad[15:8]}+{2'd0,current_quad[7:0]};
 wire border=cell_x<WIDTH_CELLS/8||cell_x>=WIDTH_CELLS-WIDTH_CELLS/8||
             cell_y<HEIGHT_CELLS/8||cell_y>=HEIGHT_CELLS-HEIGHT_CELLS/8;
 wire sample=in_valid&&border&&cell_x[SAMPLE_BITS-1:0]==0&&cell_y[SAMPLE_BITS-1:0]==0&&total>=512;
 reg [17:0] sums[0:3];reg [9:0] count,denominator;
 reg [31:0] pending_quad;
 reg [2:0] phase;reg [1:0] channel;
 reg [17:0] numerator,quotient;reg [10:0] remainder;reg [4:0] bit_left;
 wire [11:0] trial={remainder,numerator[17]};
 wire subtract=trial>={2'd0,denominator};
 wire [17:0] next_quotient={quotient[16:0],subtract};
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   white_quad<=32'hc8c8c8c8;ready<=0;count<=0;phase<=0;channel<=0;
   denominator<=1;pending_quad<=0;numerator<=0;quotient<=0;remainder<=0;bit_left<=0;
   for(i=0;i<4;i=i+1)sums[i]<=0;
  end else if(!enabled)begin
   ready<=0;count<=0;phase<=0;
   for(i=0;i<4;i=i+1)sums[i]<=0;
  end else if(frame_start)begin
   count<=0;phase<=0;
   for(i=0;i<4;i=i+1)sums[i]<=0;
  end else begin
   if(phase==0&&sample&&count!=1023)begin
    count<=count+1'b1;
    for(i=0;i<4;i=i+1)sums[i]<=sums[i]+current_quad[31-i*8-:8];
   end
   if(frame_end)begin
    if(count>=4)begin phase<=1;channel<=0;denominator<=count;end
    else begin ready<=0;phase<=4;end
   end
   if(phase==1)begin
    numerator<=sums[channel]+(denominator>>1);quotient<=0;remainder<=0;bit_left<=17;phase<=2;
   end
   if(phase==2)begin
    numerator<={numerator[16:0],1'b0};quotient<=next_quotient;
    remainder<=subtract?trial-denominator:trial;
    if(bit_left==0)begin
     pending_quad[31-channel*8-:8]<=next_quotient[7:0];
     if(channel==3)phase<=3;else begin channel<=channel+1'b1;phase<=1;end
    end else bit_left<=bit_left-1'b1;
   end
   if(phase==3)begin white_quad<=pending_quad;ready<=1;phase<=4;end
  end
 end
endmodule

// Brightness/chromaticity separation on a matched Bayer quad (the two green
// sites remain separate). This preserves raw color without a second RGB frame.
// Moderate, approximately color-preserving darkening is a shadow candidate;
// deep dark objects and changes of color remain foreground. Never remove a
// shadow from only the strong mask: weak-region growth must reject it too.
module background_lighting_filter #(parameter SAMPLE_BITS=5,WIDTH_CELLS=960,HEIGHT_CELLS=540,WHITE_AVAILABLE=0)(
 input clk,input rst_n,input model_valid,input frame_start,input frame_end,
 input in_valid,input source_valid,input enabled,input binary_mode,input binary_pixel,input row_end,
 input [31:0] current_quad,background_quad,input [7:0] threshold,
 input [11:0] cell_x,input [9:0] cell_y,input white_mode,output wire white_ready,
 output wire out_valid,output reg strong_pixel,weak_pixel,
 output reg [7:0] current_mean,background_mean,output reg [11:0] out_x,output reg [9:0] out_y,
 output reg out_row_end,output wire [5:0] exposure_gain
);
 function [9:0] sum4;input [31:0] q;
  begin sum4={2'd0,q[31:24]}+{2'd0,q[23:16]}+{2'd0,q[15:8]}+{2'd0,q[7:0]};end
 endfunction
 function [7:0] scaled;input [13:0] q;
  begin scaled=q>=8160?8'd255:(q+14'd16)>>5;end
 endfunction
 function [7:0] diff8;input [7:0] a,b;begin diff8=a>=b?a-b:b-a;end endfunction
 function [17:0] diff18;input [17:0] a,b;begin diff18=a>=b?a-b:b-a;end endfunction
 function [7:0] max8;input [7:0] a,b;begin max8=a>b?a:b;end endfunction
 wire use_white=WHITE_AVAILABLE&&white_mode;
 wire [31:0] white_quad;
 generate if(WHITE_AVAILABLE)begin:g_white
  background_white_estimator #(.SAMPLE_BITS(SAMPLE_BITS),.WIDTH_CELLS(WIDTH_CELLS),.HEIGHT_CELLS(HEIGHT_CELLS)) u_white(
   .clk(clk),.rst_n(rst_n),.enabled(use_white),.frame_start(frame_start),.frame_end(frame_end),
   .in_valid(in_valid),.current_quad(current_quad),.cell_x(cell_x),.cell_y(cell_y),.white_quad(white_quad),.ready(white_ready));
 end else begin:g_no_white
  assign white_quad=0;assign white_ready=0;
 end endgenerate
 wire [31:0] reference_quad=use_white?white_quad:background_quad;
 wire [9:0] sum_c=sum4(current_quad),sum_b=sum4(reference_quad);
 wire [10:0] rounded_c={1'b0,sum_c}+2,rounded_b={1'b0,sum_b}+2;
 reg v0,v1,v2,src0,src1,en0,en1,bin0,bin1,bpix0,bpix1,last0,last1,w0,w1;
 reg [31:0] c0,b0,c1;
 reg [9:0] sc0,sb0,sb1;reg [7:0] cm0,bm0,cm1,bm1,t0,t1;
 reg [5:0] gain0;
 reg [11:0] x0,x1;reg [9:0] y0,y1;
 reg reliable0,reliable1;
 reg [17:0] cp[0:3],bp[0:3];reg [13:0] prediction[0:3],mean_prediction;
 reg [19:0] norm_product;
 wire [19:0] color_tolerance=(norm_product>>6)+({10'd0,sb1}<<1)+sb1;
 wire same_color=diff18(cp[0],bp[0])<=color_tolerance&&diff18(cp[1],bp[1])<=color_tolerance&&
                 diff18(cp[2],bp[2])<=color_tolerance&&diff18(cp[3],bp[3])<=color_tolerance;
 wire [7:0] predicted_mean=scaled(mean_prediction);
 wire [10:0] current_times8={cm1,3'd0};
 wire [10:0] background_times5=({3'd0,predicted_mean}<<2)+predicted_mean;
 wire shadow=reliable1&&same_color&&(w1||cm1<predicted_mean)&&current_times8>=background_times5;
 wire [7:0] color_delta=max8(max8(diff8(c1[31:24],scaled(prediction[0])),diff8(c1[23:16],scaled(prediction[1]))),
                            max8(diff8(c1[15:8],scaled(prediction[2])),diff8(c1[7:0],scaled(prediction[3]))));
 wire [7:0] distance=en1?color_delta:diff8(cm1,bm1);
 wire border=x1<WIDTH_CELLS/8||x1>=WIDTH_CELLS-WIDTH_CELLS/8||
             y1<HEIGHT_CELLS/8||y1>=HEIGHT_CELLS-HEIGHT_CELLS/8;
 wire vote=v1&&src1&&!bin1&&border&&reliable1&&same_color&&bm1>=32&&bm1<=224&&cm1>=16&&cm1<=239&&
           x1[SAMPLE_BITS-1:0]==0&&y1[SAMPLE_BITS-1:0]==0;
 background_gain_estimator u_gain(
   .clk(clk),.rst_n(rst_n),.model_valid(model_valid&&!use_white),.frame_start(frame_start),.frame_end(frame_end),
  .sample_valid(vote),.current_mean(cm1),.background_mean(bm1),.gain(exposure_gain));
 assign out_valid=v2;
 integer k;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   v0<=0;v1<=0;v2<=0;strong_pixel<=0;weak_pixel<=0;current_mean<=0;background_mean<=0;out_x<=0;out_y<=0;out_row_end<=0;
   src0<=0;src1<=0;en0<=0;en1<=0;bin0<=0;bin1<=0;bpix0<=0;bpix1<=0;last0<=0;last1<=0;w0<=0;w1<=0;
   c0<=0;b0<=0;c1<=0;sc0<=0;sb0<=0;sb1<=0;cm0<=0;bm0<=0;cm1<=0;bm1<=0;t0<=0;t1<=0;gain0<=32;
   x0<=0;x1<=0;y0<=0;y1<=0;reliable0<=0;reliable1<=0;norm_product<=0;mean_prediction<=0;
   for(k=0;k<4;k=k+1)begin cp[k]<=0;bp[k]<=0;prediction[k]<=0;end
  end else begin
   v0<=in_valid;v1<=v0;v2<=v1;
   c0<=current_quad;b0<=reference_quad;sc0<=sum_c;sb0<=sum_b;
   cm0<=rounded_c>>2;bm0<=rounded_b>>2;gain0<=use_white?6'd32:exposure_gain;
   src0<=source_valid&&(!use_white||white_ready);en0<=enabled||use_white;bin0<=binary_mode;bpix0<=binary_pixel;last0<=row_end;t0<=threshold;x0<=cell_x;y0<=cell_y;w0<=use_white;
   reliable0<=current_quad[31:24]>=8&&(use_white||current_quad[31:24]<250)&&current_quad[23:16]>=8&&(use_white||current_quad[23:16]<250)&&
              current_quad[15:8]>=8&&(use_white||current_quad[15:8]<250)&&current_quad[7:0]>=8&&(use_white||current_quad[7:0]<250)&&
              reference_quad[31:24]>=8&&(use_white||reference_quad[31:24]<250)&&reference_quad[23:16]>=8&&(use_white||reference_quad[23:16]<250)&&
              reference_quad[15:8]>=8&&(use_white||reference_quad[15:8]<250)&&reference_quad[7:0]>=8&&(use_white||reference_quad[7:0]<250);
   for(k=0;k<4;k=k+1)begin
    cp[k]<=c0[31-k*8-:8]*sb0;bp[k]<=b0[31-k*8-:8]*sc0;
    prediction[k]<=b0[31-k*8-:8]*gain0;
   end
   norm_product<=sc0*sb0;mean_prediction<=bm0*gain0;
   c1<=c0;sb1<=sb0;cm1<=cm0;bm1<=bm0;t1<=t0;x1<=x0;y1<=y0;
   src1<=src0;en1<=en0;bin1<=bin0;bpix1<=bpix0;last1<=last0;reliable1<=reliable0;w1<=w0;
   strong_pixel<=src1&&(bin1?bpix1:(distance>=t1&&!(en1&&shadow)));
   weak_pixel<=src1&&!bin1&&distance>=(t1>1?t1>>1:t1)&&!(en1&&shadow);
   current_mean<=cm1;background_mean<=bm1;out_x<=x1;out_y<=y1;out_row_end<=v1&&last1;
  end
 end
endmodule

// Compare matched Bayer 2x2 cells, never neighboring RAW color channels.
module background_bayer_average #(parameter WIDTH=1920,HEIGHT=1080,BINARY_AVAILABLE=0,REFINE_AVAILABLE=0,LIGHTING_AVAILABLE=0,WHITE_AVAILABLE=0)(
 input clk,input rst_n,input vsync,input href,input background_valid,input sample_valid,
 input [7:0] current_raw,background_raw,input [7:0] threshold,input binary_mode,input binary_pixel,input lighting_enable,input white_mode,output wire white_ready,
 output reg cell_valid,output reg cell_mask,output reg cell_weak_mask,output reg [7:0] current_mean,background_mean,
 output reg [$clog2(WIDTH/2)-1:0] cell_x,output reg [9:0] cell_y,output reg row_done
);
 localparam AW=$clog2(WIDTH/2);
 reg href_d;reg [11:0] x;reg [10:0] y;
 wire start_line=href&&!href_d;
 wire [11:0] cx=start_line?0:x;
 wire [10:0] cy=start_line?y+1'b1:y;
 wire [AW-1:0] pair_addr=cx>>1;
 reg [7:0] left_current,left_background,frame_threshold;reg frame_lighting,frame_white,vs_d;
 reg left_valid,frame_background_valid,left_binary;
 wire [8:0] pair_current={1'b0,left_current}+{1'b0,current_raw};
 wire [8:0] pair_background={1'b0,left_background}+{1'b0,background_raw};
 (* ram_style="block" *) reg [33:0] top_pairs[0:(1<<AW)-1];
 reg [33:0] top_pair;
 wire [8:0] top_current=LIGHTING_AVAILABLE?{1'b0,top_pair[31:24]}+{1'b0,top_pair[23:16]}:top_pair[17:9];
 wire [8:0] top_background=LIGHTING_AVAILABLE?{1'b0,top_pair[15:8]}+{1'b0,top_pair[7:0]}:top_pair[8:0];
 wire top_valid=LIGHTING_AVAILABLE?top_pair[32]:top_pair[18];
 wire top_binary=LIGHTING_AVAILABLE?top_pair[33]:top_pair[19];
 wire [9:0] sum_current={1'b0,top_current}+{1'b0,pair_current}+10'd2;
 wire [9:0] sum_background={1'b0,top_background}+{1'b0,pair_background}+10'd2;
 wire [7:0] cm=sum_current[9:2],bm=sum_background[9:2];
 wire [7:0] delta=cm>=bm?cm-bm:bm-cm;
 always @(posedge clk)top_pair<=top_pairs[pair_addr];
 always @(posedge clk)if(href&&cx[0]&&!cy[0])
  top_pairs[pair_addr]<=LIGHTING_AVAILABLE?{left_binary|binary_pixel,left_valid&&sample_valid,left_current,current_raw,left_background,background_raw}:
                                         {14'd0,left_binary|binary_pixel,left_valid&&sample_valid,pair_current,pair_background};
 wire light_valid,light_strong,light_weak,light_row;
 wire [7:0] light_cm,light_bm;wire [11:0] light_x;wire [9:0] light_y;
 generate if(LIGHTING_AVAILABLE)begin:g_lighting
  background_lighting_filter #(.WIDTH_CELLS(WIDTH/2),.HEIGHT_CELLS(HEIGHT/2),.WHITE_AVAILABLE(WHITE_AVAILABLE)) u_lighting(
   .clk(clk),.rst_n(rst_n),.model_valid(background_valid),.frame_start(href&&cx==0&&cy==0),.frame_end(vs_d&&!vsync),
   .in_valid(href&&cx[0]&&cy[0]&&cx<WIDTH&&cy<HEIGHT),.source_valid((frame_white||frame_background_valid)&&top_valid&&left_valid&&sample_valid),
   .enabled(frame_lighting),.binary_mode(BINARY_AVAILABLE&&binary_mode),.binary_pixel(top_binary|left_binary|binary_pixel),.row_end(cx==WIDTH-1),
   .current_quad({top_pair[31:16],left_current,current_raw}),.background_quad({top_pair[15:0],left_background,background_raw}),
   .threshold(frame_threshold),.cell_x({1'b0,cx[11:1]}),.cell_y(cy>>1),
   .white_mode(frame_white),.white_ready(white_ready),
   .out_valid(light_valid),.strong_pixel(light_strong),.weak_pixel(light_weak),.current_mean(light_cm),.background_mean(light_bm),
   .out_x(light_x),.out_y(light_y),.out_row_end(light_row),.exposure_gain());
 end else begin:g_lighting_disabled
  assign light_valid=0;assign light_strong=0;assign light_weak=0;assign light_row=0;
  assign light_cm=0;assign light_bm=0;assign light_x=0;assign light_y=0;assign white_ready=0;
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   href_d<=0;x<=0;y<=11'h7ff;left_current<=0;left_background<=0;left_valid<=0;left_binary<=0;
   frame_threshold<=24;frame_background_valid<=0;cell_valid<=0;cell_mask<=0;cell_weak_mask<=0;
   frame_lighting<=LIGHTING_AVAILABLE;frame_white<=0;vs_d<=0;
   current_mean<=0;background_mean<=0;cell_x<=0;cell_y<=0;row_done<=0;
  end else begin
   href_d<=href;vs_d<=vsync;cell_valid<=0;row_done<=0;
   if(LIGHTING_AVAILABLE)begin
    cell_valid<=light_valid;cell_mask<=light_strong;cell_weak_mask<=REFINE_AVAILABLE&&light_weak;
    current_mean<=light_cm;background_mean<=light_bm;cell_x<=light_x;cell_y<=light_y;row_done<=light_row;
   end
   if(!vsync)begin x<=0;y<=11'h7ff;end
   else if(href)begin
    if(start_line)begin x<=1;y<=y+1'b1;end else x<=x+1'b1;
    if(start_line&&cy==0)begin frame_threshold<=threshold;frame_background_valid<=background_valid;frame_lighting<=lighting_enable;frame_white<=WHITE_AVAILABLE&&white_mode;end
    if(!cx[0])begin left_current<=current_raw;left_background<=background_raw;left_valid<=sample_valid;left_binary<=binary_pixel;end
    else if(!LIGHTING_AVAILABLE&&cy[0]&&cx<WIDTH&&cy<HEIGHT)begin
     cell_valid<=1;cell_x<=pair_addr;cell_y<=cy>>1;current_mean<=cm;background_mean<=bm;
     cell_mask<=frame_background_valid&&top_pair[18]&&left_valid&&sample_valid&&((BINARY_AVAILABLE&&binary_mode)?(top_pair[19]|left_binary|binary_pixel):delta>=frame_threshold);
     cell_weak_mask<=REFINE_AVAILABLE&&frame_background_valid&&top_pair[18]&&left_valid&&sample_valid&&delta>=(frame_threshold>1?frame_threshold>>1:frame_threshold);
     if(cx==WIDTH-1)row_done<=1;
    end
   end
  end
 end
endmodule

// Mask-only kernels: no unused 28-bit RGB/edge sideband line buffers.
module background_mask_morph #(parameter WIDTH=960,HEIGHT=544,DILATE=0,STAGE=0,REFINE_AVAILABLE=0)(
 input clk,input rst_n,input vsync,input href,input mask,input raw_mask,input weak_mask,input [1:0] noise_mode,
 output reg out_vsync,output reg out_href,output reg out_mask,output reg out_raw_mask,output reg out_weak_mask
);
 localparam BITS=REFINE_AVAILABLE?3:2;
 wire v,h,s;wire [BITS-1:0] p11,p12,p13,p21,p22,p23,p31,p32,p33;
 wire [BITS-1:0] packed_pixel=REFINE_AVAILABLE?{weak_mask,raw_mask,mask}:{raw_mask,mask};
 VIP_Matrix_Generate_3X3_8Bit #(.IMG_HDISP(WIDTH),.IMG_VDISP(HEIGHT),.DATA_WIDTH(BITS)) matrix(
  .clk(clk),.rst_n(rst_n),.per_frame_vsync(vsync),.per_frame_href(href),.per_frame_hsync(1'b0),.per_img_Y(packed_pixel),
  .matrix_frame_vsync(v),.matrix_frame_href(h),.matrix_frame_hsync(s),
  .matrix_p11(p11),.matrix_p12(p12),.matrix_p13(p13),.matrix_p21(p21),.matrix_p22(p22),.matrix_p23(p23),
  .matrix_p31(p31),.matrix_p32(p32),.matrix_p33(p33));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin out_vsync<=0;out_href<=0;out_mask<=0;out_raw_mask<=0;out_weak_mask<=0;end
  else begin out_vsync<=v;out_href<=h;
   out_raw_mask<=h&&p22[1];
   out_weak_mask<=REFINE_AVAILABLE&&h&&p22[BITS-1];
   if(STAGE<2 && noise_mode!=1) begin
       if(STAGE==0 && noise_mode==2)
           out_mask<=h&&p22[0]&&(p11[0]|p12[0]|p13[0]|p21[0]|p23[0]|p31[0]|p32[0]|p33[0]);
       else out_mask<=h&&p22[0];
   end else out_mask<=h&&(DILATE?(p11[0]|p12[0]|p13[0]|p21[0]|p22[0]|p23[0]|p31[0]|p32[0]|p33[0]):
                                             (p11[0]&p12[0]&p13[0]&p21[0]&p22[0]&p23[0]&p31[0]&p32[0]&p33[0]));
  end
 end
endmodule

// Burst one contiguous half-width mask row after each Bayer row pair. Four
// kernels implement opening then closing. Their four-row center latency is
// removed by skipping four warm-up rows and flushing four zero bottom rows.
// A fixed 12-RAW-line timing delay leaves room to finish the row and repeat it
// twice. Only short line memories are needed; no full-frame DDR mask storage.
module background_mask_pipeline #(parameter WIDTH=1920,HEIGHT=1080,H_TOTAL=2200,BINARY_AVAILABLE=0,REFINE_AVAILABLE=0,LIGHTING_AVAILABLE=0,WHITE_AVAILABLE=0)(
 input clk,input rst_n,input in_vsync,input in_hsync,input in_href,
 input background_valid,input background_sample_valid,input [7:0] current_raw,background_raw,
 input [7:0] diff_threshold,input [1:0] noise_mode,input binary_mode,input binary_pixel,input original_edge,input lighting_enable,input white_mode,output wire white_ready,
 output reg out_vsync,output reg out_hsync,output reg out_href,output out_mask,output out_raw_mask,output out_weak_mask,output reg out_binary_pixel,output reg out_original_edge,
 output reg stream_error,
 output debug_cell_valid,output debug_cell_mask,output [7:0] debug_current_mean,debug_background_mean
);
 localparam SW=WIDTH/2,SH=HEIGHT/2,AW=$clog2(SW),TD=12*H_TOTAL,TW=$clog2(TD+1);
 wire cv,cm,cw,ready_row;wire [AW-1:0] ax;wire [9:0] ay;wire [7:0] am,bm;
 background_bayer_average #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BINARY_AVAILABLE(BINARY_AVAILABLE),.REFINE_AVAILABLE(REFINE_AVAILABLE),.LIGHTING_AVAILABLE(LIGHTING_AVAILABLE),.WHITE_AVAILABLE(WHITE_AVAILABLE)) average(
  .clk(clk),.rst_n(rst_n),.vsync(in_vsync),.href(in_href),.background_valid(background_valid),
  .sample_valid(background_sample_valid),.binary_mode(binary_mode),.binary_pixel(binary_pixel),.current_raw(current_raw),.background_raw(background_raw),.threshold(diff_threshold),
  .lighting_enable(lighting_enable),
  .white_mode(white_mode),.white_ready(white_ready),
  .cell_valid(cv),.cell_mask(cm),.cell_weak_mask(cw),.current_mean(am),.background_mean(bm),.cell_x(ax),.cell_y(ay),.row_done(ready_row));
 assign debug_cell_valid=cv;assign debug_cell_mask=cm;assign debug_current_mean=am;assign debug_background_mean=bm;
 localparam INPUT_BITS=REFINE_AVAILABLE?2:1;
 (* ram_style="block" *) reg [INPUT_BITS-1:0] input_rows[0:(1<<(AW+1))-1];
 always @(posedge clk)if(cv)input_rows[{ay[0],ax}]<=REFINE_AVAILABLE?{cw,cm}:cm;
 reg [1:0] serial_state;reg [AW-1:0] serial_x;reg serial_bank,serial_dummy;
 reg [INPUT_BITS-1:0] serial_pixel;
 reg serial_weak;
 reg serial_vsync,serial_href,serial_mask,flushing;reg [2:0] dummy_left;reg [31:0] row_timer;
 wire [AW-1:0] next_serial_x=(serial_state==2&&serial_x<SW-1)?serial_x+1'b1:0;
 always @(posedge clk)serial_pixel<=input_rows[{serial_bank,next_serial_x}];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   serial_state<=0;serial_x<=0;serial_bank<=0;serial_dummy<=0;serial_vsync<=0;serial_href<=0;serial_mask<=0;
   flushing<=0;dummy_left<=0;row_timer<=0;stream_error<=0;serial_weak<=0;
  end else begin
   serial_href<=0;
   if(row_timer!=0)row_timer<=row_timer-1'b1;
   if(ready_row&&serial_state!=0)stream_error<=1;
   case(serial_state)
    0:begin
     if(ready_row)begin
      serial_bank<=ay[0];serial_x<=0;serial_dummy<=0;serial_state<=1;serial_vsync<=1;row_timer<=2*H_TOTAL;
      if(ay==0)stream_error<=0;
      if(ay==SH-1)begin flushing<=1;dummy_left<=4;end
     end else if(flushing&&dummy_left!=0&&row_timer==0)begin
      serial_x<=0;serial_dummy<=1;serial_state<=1;dummy_left<=dummy_left-1'b1;row_timer<=2*H_TOTAL;
     end
    end
    1:serial_state<=2;
    2:begin
     serial_href<=1;serial_mask<=serial_dummy?1'b0:serial_pixel[0];
     serial_weak<=REFINE_AVAILABLE&&!serial_dummy&&serial_pixel[INPUT_BITS-1];
     if(serial_x==SW-1)serial_state<=3;else serial_x<=serial_x+1'b1;
    end
    3:begin
     serial_state<=0;
     if(serial_dummy&&dummy_left==0)begin flushing<=0;serial_vsync<=0;end
    end
   endcase
  end
 end
 reg [1:0] frame_noise;
 always @(posedge clk)if(!rst_n)frame_noise<=1;else if(ready_row&&ay==0)frame_noise<=noise_mode;
 wire [4:0] mv,mh,mm,mraw,mweak;
 assign mweak[0]=serial_weak;
 assign mraw[0]=serial_mask;
 assign mv[0]=serial_vsync;assign mh[0]=serial_href;assign mm[0]=serial_mask;
 genvar k;
 generate for(k=0;k<4;k=k+1)begin: kernels
  background_mask_morph #(.WIDTH(SW),.HEIGHT(SH+4),.DILATE(k==1||k==2),.STAGE(k),.REFINE_AVAILABLE(REFINE_AVAILABLE)) morph(
   .clk(clk),.rst_n(rst_n),.vsync(mv[k]),.href(mh[k]),.mask(mm[k]),.raw_mask(mraw[k]),.noise_mode(frame_noise),
   .weak_mask(mweak[k]),.out_weak_mask(mweak[k+1]),
   .out_vsync(mv[k+1]),.out_href(mh[k+1]),.out_mask(mm[k+1]),.out_raw_mask(mraw[k+1]));
 end endgenerate
 localparam MASK_BITS=REFINE_AVAILABLE?3:2;
 (* ram_style="block" *) reg [MASK_BITS-1:0] mask_rows[0:(1<<(AW+1))-1];
 reg mh_d;reg [AW-1:0] write_x;reg [9:0] write_y;
 wire [AW-1:0] wx=mh[4]&&!mh_d?0:write_x;
 reg [9:0] tag0,tag1;reg tag_valid0,tag_valid1;
 always @(posedge clk)if(mh[4]&&write_y>=4&&write_y<SH+4)mask_rows[{write_y[0],wx}]<=REFINE_AVAILABLE?{mweak[4],mraw[4],mm[4]}:{mraw[4],mm[4]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mh_d<=0;write_x<=0;write_y<=0;tag0<=0;tag1<=0;tag_valid0<=0;tag_valid1<=0;end
  else begin
   mh_d<=mh[4];
   if(!mv[4])write_y<=0;else if(mh_d&&!mh[4])write_y<=write_y+1'b1;
   if(mh[4])begin
    write_x<=wx+1'b1;
    if(wx==SW-1&&write_y>=4&&write_y<SH+4)begin
     if(write_y[0])begin tag1<=write_y-4;tag_valid1<=1;end
     else begin tag0<=write_y-4;tag_valid0<=1;end
    end
   end
  end
 end
 // One spare address separates the read and write ports. This preserves the
 // exact TD-cycle delay without relying on same-address RAM collision mode.
 (* ram_style="block" *) reg [4:0] timing[0:TD];
 reg [TW-1:0] time_ptr;reg [TW:0] time_fill;reg [4:0] delayed_timing;
 reg timing_read_valid;
 wire [TW-1:0] time_read_ptr=time_ptr==TD?0:time_ptr+1'b1;
 always @(posedge clk)timing[time_ptr]<={BINARY_AVAILABLE&&original_edge,BINARY_AVAILABLE&&binary_pixel,in_vsync,in_hsync,in_href};
 always @(posedge clk)delayed_timing<=timing[time_read_ptr];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin time_ptr<=0;time_fill<=0;timing_read_valid<=0;end
  else begin
   time_ptr<=time_ptr==TD?0:time_ptr+1'b1;
   if(time_fill<TD)time_fill<=time_fill+1'b1;
   timing_read_valid<=time_fill==TD;
  end
 end
 wire tv=timing_read_valid&&delayed_timing[2],th=timing_read_valid&&delayed_timing[1],te=timing_read_valid&&delayed_timing[0];
 reg te_d;reg [11:0] display_x;reg [10:0] display_y;
 wire [11:0] dx=te&&!te_d?0:display_x;
 wire [10:0] dy=te&&!te_d?display_y+1'b1:display_y;
 wire [AW-1:0] rx=dx>>1;
 reg [MASK_BITS-1:0] mask_pixel;reg read_valid;
 always @(posedge clk)mask_pixel<=mask_rows[{dy[1],rx}];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin te_d<=0;display_x<=0;display_y<=11'h7ff;out_vsync<=0;out_hsync<=0;out_href<=0;read_valid<=0;out_binary_pixel<=0;out_original_edge<=0;end
  else begin
   te_d<=te;out_vsync<=tv;out_hsync<=th;out_href<=te;out_binary_pixel<=te&&delayed_timing[3];out_original_edge<=te&&delayed_timing[4];
   read_valid<=te&&dx<WIDTH&&dy<HEIGHT&&!stream_error&&
    (dy[1]?(tag_valid1&&tag1==(dy>>1)):(tag_valid0&&tag0==(dy>>1)));
   if(!tv)begin display_x<=0;display_y<=11'h7ff;end
   else if(te)begin
    if(!te_d)begin display_x<=1;display_y<=display_y+1'b1;end else display_x<=display_x+1'b1;
   end
  end
 end
 assign out_mask=out_href&&read_valid&&mask_pixel[0];
 assign out_raw_mask=out_href&&read_valid&&mask_pixel[1];
 assign out_weak_mask=REFINE_AVAILABLE&&out_href&&read_valid&&mask_pixel[MASK_BITS-1];
endmodule
