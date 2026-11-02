`timescale 1ns/1ps
module background_lighting_tb;
reg clk=0,rst_n=0,model=1,start=0,finish=0,valid=0,source=1,enable=1,bin=0,bpix=0,last=0;
always #5 clk=~clk;
reg [31:0] c=0,b=0;reg [11:0] x=0;reg [9:0] y=0;
wire ov,spix,wpix,olast;wire [7:0] cm,bm;wire [11:0] ox;wire [9:0] oy;wire [5:0] gain;
background_lighting_filter #(.SAMPLE_BITS(4),.WIDTH_CELLS(64),.HEIGHT_CELLS(64)) dut(.clk(clk),.rst_n(rst_n),.model_valid(model),.frame_start(start),.frame_end(finish),
 .in_valid(valid),.source_valid(source),.enabled(enable),.binary_mode(bin),.binary_pixel(bpix),.row_end(last),
 .current_quad(c),.background_quad(b),.threshold(8'd24),.cell_x(x),.cell_y(y),
 .out_valid(ov),.strong_pixel(spix),.weak_pixel(wpix),.current_mean(cm),.background_mean(bm),.out_x(ox),.out_y(oy),.out_row_end(olast),.exposure_gain(gain));
bit want_s[0:65535],want_w[0:65535],check_pixel[0:65535],want_last[0:65535];
integer want_x[0:65535],want_y[0:65535],want_cm[0:65535],want_bm[0:65535];
integer sent=0,received=0;
function automatic integer mean(input reg[31:0] q);
 return (int'(q[31:24])+int'(q[23:16])+int'(q[15:8])+int'(q[7:0])+2)/4;
endfunction
always @(posedge clk)begin
 #1;
 if(rst_n&&ov)begin
  if(received>=sent)$fatal(1,"unexpected lighting output");
  if(cm!=want_cm[received]||bm!=want_bm[received]||ox!=want_x[received]||oy!=want_y[received]||olast!=want_last[received])
   $fatal(1,"lighting quad/coordinate/row alignment failed at sample %0d",received);
  if(check_pixel[received]&&(spix!==want_s[received]||wpix!==want_w[received]))
   $fatal(1,"lighting sample=%0d x/y=%0d/%0d spix/wpix=%b/%b expected=%b/%b gain=%0d",received,ox,oy,spix,wpix,want_s[received],want_w[received],gain);
  received++;
 end
end
task emit(input reg[31:0] cq,bq,input integer xx,yy,input bit s,w,check);
 begin
 @(negedge clk);valid=1;c=cq;b=bq;x=xx;y=yy;last=xx==63;
 want_s[sent]=s;want_w[sent]=w;check_pixel[sent]=check;want_x[sent]=xx;want_y[sent]=yy;
 want_cm[sent]=mean(cq);want_bm[sent]=mean(bq);want_last[sent]=last;sent++;
 @(negedge clk);valid=0;
 end
endtask
task frame(input integer mode,input bit on,check);
 reg[31:0] cq,bq;bit person,shadow,expected;
 begin
 enable=on;@(negedge clk);start=1;@(negedge clk);start=0;
 for(integer yy=0;yy<64;yy++)for(integer xx=0;xx<64;xx++)begin
  bq={8'd160,8'd120,8'd80,8'd120};cq=bq;expected=0;
  person=xx>=8&&xx<24&&yy>=16&&yy<48;
  shadow=xx>=24&&xx<48&&yy>=16&&yy<48;
  case(mode)
   1:cq={8'd200,8'd150,8'd100,8'd150}; // global x1.25, no object
   2:cq={8'd120,8'd90,8'd60,8'd90};   // global x0.75, no object
   3:begin
    // Different color with exactly the same brightness as the background.
    if(person)cq={8'd60,8'd120,8'd180,8'd120};
    if(shadow)cq={8'd120,8'd90,8'd60,8'd90};
    expected=on?person:shadow;
   end
   4:begin
    bq={4{8'd200}};cq=bq;
    if(person)cq={4{8'd60}};if(shadow)cq={4{8'd150}};
    expected=person;
   end
  endcase
  emit(cq,bq,xx,yy,expected,expected,check);
 end
 repeat(4)@(negedge clk);finish=1;@(negedge clk);finish=0;repeat(80)@(negedge clk);
 end
endtask
task reset_model;
 begin @(negedge clk);model=0;repeat(4)@(negedge clk);model=1;repeat(4)@(negedge clk);if(gain!=32)$fatal(1,"background recapture retained stale gain");end
endtask
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 frame(0,1,1);
 frame(1,1,0);if(gain!=40)$fatal(1,"global bright gain not learned: %0d",gain);
 frame(1,1,1);
 frame(2,1,0);if(gain!=24)$fatal(1,"global dim gain not learned: %0d",gain);
 frame(2,1,1);
 reset_model();frame(3,1,1);if(gain!=32)$fatal(1,"local shadow replaced global reference");
 frame(3,0,1);
 reset_model();frame(4,1,1);
 // Saturated references and very dark backgrounds must not be trusted as
 // shadow evidence. Invalid background samples and binary bypass are explicit.
 enable=1;emit({4{8'd190}},{4{8'd255}},1,1,1,1,1);
 emit({4{8'd70}},{8'd4,8'd6,8'd4,8'd6},1,1,1,1,1);
 source=0;emit({4{8'd60}},{4{8'd200}},1,1,0,0,1);
 source=1;bin=1;bpix=1;emit({4{8'd150}},{4{8'd200}},1,1,1,0,1);
 repeat(12)@(negedge clk);
 if(received!=sent)$fatal(1,"lighting output lost samples %0d/%0d",received,sent);
 $display("PASS lighting: %0d quads, global bright/dim compensation, colored background/local shadows, equal-luma colored foreground, deep-dark object, wpix-mask suppression, bypass, saturation/dark guards and validity",received);$finish;
end
initial begin #2000000;$fatal(1,"lighting test timeout");end
endmodule
