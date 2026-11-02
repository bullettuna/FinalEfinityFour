`timescale 1ns/1ps
module edge_background_capture_tb;
reg clk=0,rst=0,capture=0,vs=0,hs=0,de=0,edge_bit=0;
reg [64:0] signature=0;
always #5 clk=~clk;
wire ready,busy,error,start,finish,byte_valid,request,ov,oh,oe,original,foreground,reference_valid,fault;
wire [7:0] byte_data;wire [19:0] offset;
reg [7:0] memory[0:255];integer read_ptr=0,bytes=0,words=0;
reg writer_active=0,commit=0,write_error=0,read_error=0,available=1,input_fault=0;
edge_background_capture #(.WIDTH(64),.HEIGHT(32),.TIMEOUT(50000),.CHECK_INPUT_FAULT(1)) dut(
 .clk(clk),.rst_n(rst),.pclk(clk),.prst_n(rst),.capture_req(capture),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_edge(edge_bit),.config_signature(signature),.input_frame_fault(input_fault),
 .ready(ready),.busy(busy),.error(error),.writer_start(start),.writer_end(finish),
 .writer_byte_valid(byte_valid),.writer_byte(byte_data),.writer_offset(offset),
 .writer_busy(writer_active),.writer_commit(commit),.writer_error(write_error),.reader_error(read_error),
 .reader_request(request),.reader_byte(memory[read_ptr]),.reader_valid(available),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_edge(original),.out_foreground(foreground),
 .reference_valid(reference_valid),.frame_fault(fault));
always @(posedge clk)begin
 commit<=0;
 if(start)begin writer_active<=1;bytes=0;words=0;end
 if(byte_valid)begin
  if(offset!=bytes)$fatal(1,"packed edge byte order offset=%0d expected=%0d",offset,bytes);
  memory[offset]<=byte_data;bytes++;
  if(bytes%16==0)begin commit<=1;words++;end
 end
 if(finish)writer_active<=0;
 if(!vs)read_ptr<=0;else if(request)read_ptr<=read_ptr+1;
end
function automatic bit a(input integer x,y);
 a=x==8||(y==4&&x>=8&&x<=18);
endfunction
function automatic bit b(input integer x,y);
 // Some old edges disappear; others persist, and a new outline is added.
 b=(a(x,y)&&y<16)||((x==32||x==47)&&y>=8&&y<28)||((y==8||y==27)&&x>=32&&x<=47);
endfunction
task automatic frame(input integer mode,input bit check);
 bit expected;
 begin
 @(negedge clk);vs=0;de=0;repeat(6)@(negedge clk);vs=1;repeat(80)@(negedge clk);
 for(integer y=0;y<32;y++)begin
  for(integer x=0;x<64;x++)begin
   de=1;edge_bit=mode==1?b(x,y):a(x,y);input_fault=mode==2&&x==32&&y==16;expected=check&&b(x,y)&&!a(x,y);
   @(posedge clk);#1;
   if(oe!==1||original!==edge_bit)$fatal(1,"edge/DE registration mismatch");
   if(check&&foreground!==expected)$fatal(1,"B-A mismatch x=%0d y=%0d got=%b expected=%b",x,y,foreground,expected);
   @(negedge clk);
  end
  de=0;repeat(16)@(negedge clk);
 end
 vs=0;de=0;input_fault=0;repeat(80)@(negedge clk);
 end
endtask
initial begin
 repeat(6)@(negedge clk);rst=1;repeat(6)@(negedge clk);
 capture=1;@(negedge clk);capture=0;frame(0,0);
 wait(!busy);if(!ready||error||bytes!=256||words!=16)$fatal(1,"edge capture not committed ready=%b error=%b bytes=%0d words=%0d",ready,error,bytes,words);
 for(integer y=0;y<32;y++)for(integer x=0;x<64;x++)
  if(memory[y*8+x/8][7-x%8]!==a(x,y))$fatal(1,"edge packing mismatch");
 frame(1,1);frame(1,1);
 signature=1;repeat(4)@(negedge clk);if(reference_valid)$fatal(1,"old edge background survived changed Canny parameters");
 signature=0;available=0;frame(1,0);if(!fault&&dut.read_fault!==0)$fatal(1,"reader fault state");available=1;
 frame(1,1);
 read_error=1;@(posedge clk);#1;if(ready||!error)$fatal(1,"read error did not invalidate reference");read_error=0;
 @(negedge clk);capture=1;@(negedge clk);capture=0;frame(0,0);wait(!busy);
 if(!ready||error)$fatal(1,"edge capture retry failed");
 @(negedge clk);capture=1;@(negedge clk);capture=0;frame(2,0);wait(!busy);
 if(ready||!error)$fatal(1,"corrupt input frame became E reference");
 @(negedge clk);capture=1;@(negedge clk);capture=0;frame(0,0);wait(!busy);
 if(!ready||error)$fatal(1,"input fault retry failed");
 $display("PASS E background: full-frame 1-bit packing, writer commit gating, exact B AND NOT A, disappearing edges excluded, parameter invalidation, underflow/RRESP and recapture");$finish;
end
initial begin #10000000;$fatal(1,"edge background timeout");end
endmodule
