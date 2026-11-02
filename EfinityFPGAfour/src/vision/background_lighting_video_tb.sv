`timescale 1ns/1ps
module background_lighting_video_tb #(parameter W=256,H=256,HT=320,WHITE=0);
localparam TD=12*HT;
reg clk=0,rst_n=0,vs=0,hs=0,de=0,bg_valid=1;reg [7:0] raw=200;
always #5 clk=~clk;
wire ov,oh,oe,mask,weak_mask,error;
background_mask_pipeline #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.REFINE_AVAILABLE(1),.LIGHTING_AVAILABLE(1),.WHITE_AVAILABLE(WHITE)) dut(
 .clk(clk),.rst_n(rst_n),.in_vsync(vs),.in_hsync(hs),.in_href(de),.background_valid(bg_valid),.background_sample_valid(WHITE?de:bg_valid&&de),
 .current_raw(raw),.background_raw(8'd200),.diff_threshold(8'd24),.noise_mode(2'd2),.binary_mode(1'b0),.binary_pixel(1'b0),.original_edge(1'b0),.lighting_enable(1'b1),.white_mode(WHITE!=0),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_raw_mask(mask),.out_weak_mask(weak_mask),.stream_error(error));
reg [2:0] history[0:TD+1];integer cycles=0,output_frame=0,dx=0,dy=-1,checked=0;
reg ov_d=0,oe_d=0;bit expected;
always @(posedge clk)begin
 history[cycles%(TD+2)]={vs,hs,de};#1;
 if(rst_n&&cycles>TD+2&&{ov,oh,oe}!==history[(cycles-TD-1)%(TD+2)])$fatal(1,"lighting changed output video timing");
 if(ov&&!ov_d)begin output_frame++;dy=-1;end
 if(oe)begin
  if(!oe_d)begin dx=0;dy++;end
  if(dx>=W||dy>=H)$fatal(1,"lighting video geometry");
  expected=(WHITE?output_frame>1:output_frame!=4)&&dx>=W/4&&dx<W/2&&dy>=H/4&&dy<H*3/4;
  // A sudden gain change takes one completed input frame to estimate.
  if(output_frame!=2&&(mask!==expected||weak_mask!==expected))
   $fatal(1,"lighting video frame=%0d x/y=%0d/%0d strong/weak=%b/%b expected=%b gain=%0d",output_frame,dx,dy,mask,weak_mask,expected,dut.average.g_lighting.u_lighting.exposure_gain);
  dx++;checked++;
 end
 if(error)$fatal(1,"lighting row serialization overflow");
 cycles++;ov_d=ov;oe_d=oe;
end
task tick;begin hs=cycles%HT>=4;@(negedge clk);end endtask
task frame(input integer number);
 bit body,shadow;
 begin
 vs=0;de=0;repeat(5*HT)tick();bg_valid=!WHITE&&number!=4;vs=1;repeat(36*HT)tick();
 for(integer y=0;y<H;y++)begin
  for(integer x=0;x<W;x++)begin
   body=x>=W/4&&x<W/2&&y>=H/4&&y<H*3/4;
   shadow=x>=W/2&&x<W*3/4&&y>=H/4&&y<H*3/4;
   de=1;raw=body?(number==1?60:45):shadow?(number==1?150:112):(number==1?200:150);tick();
  end
  de=0;repeat(HT-W)tick();
 end
 repeat(4*HT)tick();
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 frame(1);frame(2);frame(3);frame(4);vs=0;de=0;repeat(TD+4*HT)tick();
 if(checked!=4*W*H)$fatal(1,"lighting output size %0d",checked);
 $display("PASS lighting video %0dx%0d white=%0d: four complete frames, fixed sync/pixels, shadow beside dark foreground, brightness-step recovery and invalid background",W,H,WHITE);$finish;
end
initial begin #800000000;$fatal(1,"lighting video timeout");end
endmodule
