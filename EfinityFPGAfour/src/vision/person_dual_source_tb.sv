`timescale 1ns/1ps
module person_dual_source_tb #(parameter W=64,H=48,HT=80);
localparam DELAY=12*HT+3;
reg clk=0,rst=0,vs=0,hs=0,de=0,edge_req=0,edge_ready=1;
reg [7:0] current=40;reg fg=0,actual_edge=0;
wire ov,oh,oe,active,valid,busy,error,source_active;wire [23:0] rgb;
always #5 clk=~clk;
person_roi_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.DUAL_SOURCE(1)) dut(
 .clk(clk),.rst_n(rst),.background_valid(1'b1),.sample_valid(de),.stream_fault(1'b0),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.current_raw(current),.background_raw(8'd40),
 .threshold_req(8'd24),.noise_req(2'd2),.view_req(3'd1),.edge_source_req(edge_req),
 .edge_source_active(source_active),.edge_vsync(vs),.edge_hsync(hs),.edge_href(de),
 .edge_foreground(fg),.edge_pixel(actual_edge),.edge_reference_valid(edge_ready),.edge_stream_fault(1'b0),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_rgb(rgb),.display_active(active),
 .candidate_valid(valid),.analysis_busy(busy),.processing_error(error));
reg [2:0] timing_history[0:DELAY+1];reg raw_history[0:DELAY+1],edge_history[0:DELAY+1];
integer cycles=0;bit check=0,want;
always @(posedge clk)begin
 timing_history[cycles%(DELAY+2)]={vs,hs,de};
 raw_history[cycles%(DELAY+2)]=current==120;edge_history[cycles%(DELAY+2)]=fg;
 #1;
 if(check&&{ov,oh,oe}!==timing_history[(cycles-DELAY)%(DELAY+2)])$fatal(1,"dual source sync mismatch");
 if(check&&oe)begin
  want=source_active?edge_history[(cycles-DELAY)%(DELAY+2)]:raw_history[(cycles-DELAY)%(DELAY+2)];
  if(rgb!== (want?24'hffffff:24'd0))$fatal(1,"source=%b pixel diff mismatch got=%h want=%b",source_active,rgb,want);
 end
 if(error)$fatal(1,"dual pipeline error");cycles++;
end
task tick;begin hs=cycles%HT>=4;@(negedge clk);end endtask
task frame(input bit request_change);
 begin
 vs=0;de=0;repeat(5*HT)tick();vs=1;repeat(36*HT)tick();
 for(integer y=0;y<H;y++)begin
  for(integer x=0;x<W;x++)begin
   de=1;current=x>=16&&x<40&&y>=8&&y<40?120:40;
   fg=(x==16||x==39)&&y>=8&&y<40 || (y==8||y==39)&&x>=16&&x<40;
   actual_edge=fg||x==4;
   if(request_change&&x==W/2&&y==H/2)edge_req=!edge_req;
   tick();
  end
  de=0;repeat(HT-W)tick();
 end
 repeat(4*HT)tick();
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 frame(0);check=1;frame(0);
 frame(1);if(source_active)$fatal(1,"RAW->E switched inside frame");check=0;
 frame(0);if(!source_active||valid)$fatal(1,"source did not switch/clear old result");check=1;
 frame(0);frame(0);
 frame(1);if(!source_active)$fatal(1,"E->RAW switched inside frame");check=0;
 frame(0);if(source_active)$fatal(1,"RAW source not restored");check=1;frame(0);
 $display("PASS RAW/E dual input: exact RAW filled mask versus full-resolution E thin foreground, matched timing, blanking-only switch and stale ROI reset");$finish;
end
initial begin #300000000;$fatal(1,"dual source timeout");end
endmodule
