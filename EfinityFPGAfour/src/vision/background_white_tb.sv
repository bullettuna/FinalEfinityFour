`timescale 1ns/1ps
module background_white_tb;
reg clk=0,rst_n=0,start=0,finish=0,valid=0,white_mode=1;
always #5 clk=~clk;
reg [31:0] current_quad=0;
reg [11:0] x=0;reg [9:0] y=0;
wire ov,spix,wpix,ready;wire [7:0] cm,bm;
background_lighting_filter #(.SAMPLE_BITS(4),.WIDTH_CELLS(64),.HEIGHT_CELLS(64),.WHITE_AVAILABLE(1)) dut(
 .clk(clk),.rst_n(rst_n),.model_valid(1'b0),.frame_start(start),.frame_end(finish),
 .in_valid(valid),.source_valid(1'b1),.enabled(1'b0),.binary_mode(1'b0),.binary_pixel(1'b0),.row_end(1'b0),
 .current_quad(current_quad),.background_quad(32'h01020304),.threshold(8'd24),.cell_x(x),.cell_y(y),.white_mode(white_mode),.white_ready(ready),
 .out_valid(ov),.strong_pixel(spix),.weak_pixel(wpix),.current_mean(cm),.background_mean(bm));
integer checked=0;
task sample(input [31:0] quad,input bit want_s,input bit want_w);
 begin
 @(negedge clk);valid=1;current_quad=quad;x=32;y=32;
 @(negedge clk);valid=0;repeat(2)@(negedge clk);
 if(!ov||spix!==want_s||wpix!==want_w)$fatal(1,"white q=%h got strong/weak %b/%b expected %b/%b ready=%b ref=%h",quad,spix,wpix,want_s,want_w,ready,dut.white_quad);
 checked++;
 end
endtask
task learn(input [31:0] quad,input bit expect_ready);
 begin
 @(negedge clk);start=1;@(negedge clk);start=0;
 for(integer cy=0;cy<64;cy++)for(integer cx=0;cx<64;cx++)begin
  valid=1;current_quad=quad;x=cx;y=cy;@(negedge clk);
 end
 valid=0;repeat(4)@(negedge clk);finish=1;@(negedge clk);finish=0;repeat(90)@(negedge clk);
 if(ready!==expect_ready)$fatal(1,"white reference qualification failed");
 if(expect_ready&&dut.white_quad!==quad)$fatal(1,"white average/division got %h expected %h",dut.white_quad,quad);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 sample(32'h3c3c3c3c,0,0); // Never recognize before a white reference exists.
 learn(32'hc8c8c8c8,1);
 sample(32'hc8c8c8c8,0,0); // white cloth
 sample(32'h96969696,0,0); // moderate neutral cast shadow
 sample(32'h3c3c3c3c,1,1); // dark torso/arms
 sample(32'hc88c6e8c,1,1); // colored skin/clothing at shadow-like brightness
 sample(32'hc8b1c8c8,0,1); // weak colored foreground retained for growth
 sample(32'hfafafafa,0,0); // brighter same-color cloth
 learn(32'h96dcd2b4,1);    // RAW white has different gains at its four sites
 sample(32'h70a59e87,0,0); // the same cloth under 0.75x shadow
 sample(32'h28643c50,1,1);
 learn(32'hffffffff,1);    // clipped white must not become a giant shadow blob
 sample(32'hbebebebe,0,0);
 sample(32'h28282828,1,1);
 learn(32'h40404040,0);    // no bright border samples -> explicitly unready
 sample(32'h28282828,0,0);
 learn(32'hc8c8c8c8,1);sample(32'h3c3c3c3c,1,1);
 white_mode=0;repeat(5)@(negedge clk);
 if(ready)$fatal(1,"white model stayed ready after exit");
 $display("PASS white segmentation: %0d classified quads; no background frame, learned RAW white gains, shadows/skin/dark body/weak mask, saturation, invalid-border rejection and reacquisition",checked);$finish;
end
initial begin #1000000;$fatal(1,"white segmentation timeout");end
endmodule
