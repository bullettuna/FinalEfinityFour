`timescale 1ns/1ps
module edge_background_tolerance_tb #(parameter W=64,H=32,HT=80);
reg clk=0,rst_n=0,capture=0,vs=0,hs=0,de=0,edge_bit=0,input_fault=0,tolerance=1;
reg [64:0] signature=0;
always #5 clk=~clk;
wire ready,busy,error,start,finish,byte_valid,request,oe,original,foreground,reference_valid,fault;
wire [7:0] byte_data;wire [19:0] offset;
localparam BYTES=W*H/4;
reg [7:0] memory[0:BYTES-1];
integer read_ptr=0,bytes=0,words=0,foreground_count=0;
reg writer_active=0,commit=0,switch_during_frame=0;
edge_background_capture #(.WIDTH(W),.HEIGHT(H),.H_TOTAL(HT),.TIMEOUT(5000000),.CHECK_INPUT_FAULT(1),.TOLERANCE_AVAILABLE(1)) dut(
 .clk(clk),.rst_n(rst_n),.pclk(clk),.prst_n(rst_n),.capture_req(capture),.tolerance_enable(tolerance),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_edge(edge_bit),.config_signature(signature),.input_frame_fault(input_fault),
 .ready(ready),.busy(busy),.error(error),.writer_start(start),.writer_end(finish),
 .writer_byte_valid(byte_valid),.writer_byte(byte_data),.writer_offset(offset),
 .writer_busy(writer_active),.writer_commit(commit),.writer_error(1'b0),.reader_error(1'b0),
 .reader_request(request),.reader_byte(memory[read_ptr]),.reader_valid(1'b1),
 .out_href(oe),.out_edge(original),.out_foreground(foreground),.reference_valid(reference_valid),.frame_fault(fault));
always @(posedge clk)begin
 commit<=0;
 if(start)begin writer_active<=1;bytes=0;words=0;end
 if(byte_valid)begin
  if(offset!=bytes)$fatal(1,"paired reference byte order offset=%0d expected=%0d",offset,bytes);
  memory[offset]<=byte_data;bytes++;
  if(bytes%16==0)begin commit<=1;words++;end
 end
 if(finish)writer_active<=0;
 if(!vs)read_ptr<=0;else if(request)read_ptr<=read_ptr+1;
end
function automatic bit a(input integer x,y);
 a=x>=0&&x<W&&y>=0&&y<H&&
  (x==8||(y==4&&x>=8&&x<=18)||
   (x==W-1&&y==H/2)||(x==0&&y==0)||(x==0&&y==H-1)||
   (x==W-1&&y==0)||(x==W-1&&y==H-1));
endfunction
function automatic bit expanded(input integer x,y);
 begin expanded=0;for(integer dy=-1;dy<=1;dy++)for(integer dx=-1;dx<=1;dx++)expanded|=a(x+dx,y+dy);end
endfunction
function automatic bit current(input integer mode,x,y);
 case(mode)
  1:current=a(x-1,y);2:current=a(x+1,y);3:current=a(x,y-1);4:current=a(x,y+1);
  5:current=a(x-1,y-1);7:current=a(x-2,y);8:current=0;
  6:current=a(x,y)||((x==W/2||x==W/2+5)&&y>=H/3&&y<=H/3+6);
  9:current=a(x,y)||(y==H-1&&x>=W/2&&x<=W/2+5);
  default:current=a(x,y);
 endcase
endfunction
task automatic frame(input integer mode,input bit check,want_tolerance);
 bit expected;
 begin
 foreground_count=0;
 @(negedge clk);vs=0;de=0;repeat(4*HT)@(negedge clk);vs=1;repeat(2*HT)@(negedge clk);
 for(integer y=0;y<H;y++)begin
  for(integer x=0;x<W;x++)begin
   de=1;edge_bit=current(mode,x,y);input_fault=mode==10&&x==W/2&&y==H/2;
   if(switch_during_frame&&x==W/2&&y==H/2)tolerance=0;
   expected=edge_bit&&!(want_tolerance?expanded(x,y):a(x,y));
   @(posedge clk);#1;
   if(oe!==1||original!==edge_bit)$fatal(1,"live edge timing changed");
   if(check&&(foreground!==expected||fault))$fatal(1,"tolerance mismatch mode=%0d x=%0d y=%0d got=%b expected=%b fault=%b",mode,x,y,foreground,expected,fault);
   if(check&&foreground)foreground_count++;
   @(negedge clk);
  end
  de=0;input_fault=0;repeat(HT-W)@(negedge clk);
 end
 repeat(2*HT)@(negedge clk);vs=0;de=0;repeat(4*HT)@(negedge clk);
 end
endtask
task automatic capture_frame(input integer mode);
 begin @(negedge clk);capture=1;@(negedge clk);capture=0;frame(mode,0,1);wait(!busy);repeat(8)@(negedge clk);end
endtask
initial begin
 repeat(6)@(negedge clk);rst_n=1;repeat(6)@(negedge clk);
 capture_frame(0);
 if(!ready||error||bytes!=BYTES||words!=BYTES/16)$fatal(1,"paired capture incomplete bytes=%0d words=%0d ready=%b error=%b",bytes,words,ready,error);
 for(integer y=0;y<H;y++)for(integer x=0;x<W;x++)begin
  if(memory[y*(W/4)+x/4][7-2*(x%4)]!==a(x,y))$fatal(1,"exact reference lost x=%0d y=%0d",x,y);
  if(memory[y*(W/4)+x/4][6-2*(x%4)]!==expanded(x,y))$fatal(1,"3x3 neighbourhood/border mismatch x=%0d y=%0d got=%b expected=%b",x,y,memory[y*(W/4)+x/4][6-2*(x%4)],expanded(x,y));
 end
 frame(0,1,1);if(foreground_count)$fatal(1,"identical image is foreground");
 frame(1,1,1);if(foreground_count)$fatal(1,"one-pixel right shift is foreground");
 if(W<1920)begin
  for(integer mode=2;mode<=5;mode++)begin frame(mode,1,1);if(foreground_count)$fatal(1,"one-pixel shift is foreground mode=%0d",mode);end
  frame(7,1,1);if(!foreground_count)$fatal(1,"two-pixel shift must exceed tolerance");
  frame(8,1,1);if(foreground_count)$fatal(1,"disappearing edges became foreground");
 end
 frame(6,1,1);if(!foreground_count)$fatal(1,"new remote person outline suppressed");
 frame(9,1,1);if(!foreground_count)$fatal(1,"last-row foreground lost");
 switch_during_frame=1;frame(1,1,1);switch_during_frame=0;
 if(foreground_count)$fatal(1,"mid-frame switch changed matching");
 frame(1,1,0);if(!foreground_count)$fatal(1,"exact comparison did not restore jitter");
 $display("MEASURE %0dx%0d one-pixel shifted background: exact false pixels=%0d, 3x3 false pixels=0",W,H,foreground_count);
 tolerance=1;frame(1,1,1);if(foreground_count||!reference_valid)$fatal(1,"mode switch requires unexpected recapture");
 signature=1;repeat(4)@(negedge clk);if(reference_valid)$fatal(1,"parameter mismatch not rejected");signature=0;
 if(W<1920)begin
  capture_frame(10);if(ready||!error)$fatal(1,"delayed input fault published reference");
  capture_frame(0);if(!ready||error)$fatal(1,"recapture after fault failed");frame(1,1,1);
 end
 $display("PASS paired E reference %0dx%0d: symmetric 3x3 and all borders/last row, identical input zero foreground, +/-1 pixel jitter rejected, new outlines retained, exact mode restored without recapture, frame-boundary switching, parameter/fault invalidation",W,H);$finish;
end
initial begin #1500000000;$fatal(1,"tolerant edge background timeout");end
endmodule
