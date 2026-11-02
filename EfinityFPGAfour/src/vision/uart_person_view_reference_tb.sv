`timescale 1ns/1ps
module uart_person_view_reference_tb;
reg clk=0,rst_n=0,rx_valid=0,tx_done=0;
reg [7:0] rx_data=0;
always #5 clk=~clk;
wire [7:0] tx_data;
wire tx_start,capture,source,ready,busy,error,reference_valid;
wire [2:0] view;
wire [10:0] high_threshold,low_threshold;
wire [64:0] signature={high_threshold,low_threshold,43'd0};
uart_vision_ctrl #(.PERSON_AVAILABLE(1),.PHOTO_AVAILABLE(0),.SHAPE_AVAILABLE(0),
 .OVERLAY_AVAILABLE(0),.DEFAULT_EDGE_THRESHOLD(45),.DEFAULT_CANNY_LOW_THRESHOLD(22)) uart(
 .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.tx_done(tx_done),.tx_data(tx_data),.tx_start(tx_start),
 .background_capture_req(capture),.person_view_req(view),.person_edge_source_req(source),.person_stats_busy(1'b0),
 .background_ready(reference_valid),.background_busy(busy),.background_fault(error),
 .person_edge_source_active(source),.person_edge_foreground_present(1'b0),.person_edge_frame_fault(1'b0),
 .edge_threshold_req(high_threshold),.canny_low_threshold_req(low_threshold));
reg vs=0,de=0,edge_bit=0,writer_busy=0,commit=0;
wire start,finish,byte_valid,request,oe,foreground;
wire [7:0] byte_data;
wire [19:0] offset;
reg [7:0] memory[0:255];
integer read_ptr=0;
edge_background_capture #(.WIDTH(64),.HEIGHT(32),.TIMEOUT(50000)) background(
 .clk(clk),.rst_n(rst_n),.pclk(clk),.prst_n(rst_n),.capture_req(capture),
 .in_vsync(vs),.in_hsync(1'b0),.in_href(de),.in_edge(edge_bit),.config_signature(signature),.input_frame_fault(1'b0),
 .ready(ready),.busy(busy),.error(error),.writer_start(start),.writer_end(finish),
 .writer_byte_valid(byte_valid),.writer_byte(byte_data),.writer_offset(offset),
 .writer_busy(writer_busy),.writer_commit(commit),.writer_error(1'b0),.reader_error(1'b0),
 .reader_request(request),.reader_byte(memory[read_ptr]),.reader_valid(1'b1),
 .out_href(oe),.out_foreground(foreground),.reference_valid(reference_valid));
always @(posedge clk) begin
 commit<=0;
 if(start)writer_busy<=1;
 if(byte_valid)begin memory[offset]<=byte_data;if(offset[3:0]==15)commit<=1;end
 if(finish)writer_busy<=0;
 if(!vs)read_ptr<=0;else if(request)read_ptr<=read_ptr+1;
end
function automatic bit original_edge(input integer x,y);
 original_edge=x==8||(y==4&&x>=8&&x<=18);
endfunction
task automatic frame(input bit changed,check);
 bit expected;
 begin
 @(negedge clk);vs=0;de=0;repeat(6)@(negedge clk);vs=1;repeat(80)@(negedge clk);
 for(integer y=0;y<32;y++)begin
  for(integer x=0;x<64;x++)begin
   de=1;edge_bit=original_edge(x,y)||(changed&&x==32&&y>8);
   expected=changed&&x==32&&y>8;
   @(posedge clk);#1;
   if(check&&(!oe||foreground!==expected))$fatal(1,"foreground lost after U1 x=%0d y=%0d",x,y);
   @(negedge clk);
  end
  de=0;repeat(16)@(negedge clk);
 end
 vs=0;de=0;repeat(80)@(negedge clk);
 end
endtask
task automatic send(input [7:0] command,reply,input bit response,check);
 begin
 @(negedge clk);rx_data=command;rx_valid=1;@(posedge clk);#2;
 if(check&&(tx_start!==response||(response&&tx_data!==reply)))
  $fatal(1,"UART %02x response=%b/%02x expected=%b/%02x",command,tx_start,tx_data,response,reply);
 $display("RX=%02x TX_VALID=%b TX=%02x H=%0d L=%0d view=%0d",command,tx_start,tx_data,high_threshold,low_threshold,view);
 @(negedge clk);rx_valid=0;tx_done=tx_start;@(posedge clk);#2;@(negedge clk);tx_done=0;
 end
endtask
task automatic intact;
 begin
 repeat(6)@(negedge clk);
 if(high_threshold!=45||low_threshold!=22||!reference_valid||!ready)
  $fatal(1,"view command changed capture parameters: H=%0d L=%0d reference_valid=%b ready=%b",high_threshold,low_threshold,reference_valid,ready);
 end
endtask
initial begin
 repeat(6)@(negedge clk);rst_n=1;repeat(6)@(negedge clk);
 send("x","E",1,1);send("b","K",1,1);frame(0,0);wait(!busy);intact();send("q","1",1,1);
 // Exact reported sequence; don't stop at a differing ACK, so the pre-fix
 // run exposes the changed thresholds and invalidated captured reference.
 send("u",0,0,0);send("1",0,0,0);send(13,0,0,0);intact();
 send(10,0,0,1);send("q","1",1,1);frame(1,1);
 for(integer i=0;i<=5;i++)begin
  send("U",view==5?"0":"1"+view,1,1);send("0"+i,"0"+i,1,1);
  if(view!=i)$fatal(1,"explicit view selection");
  intact();send(13,0,0,1);send(10,0,0,1);intact();
 end
 send("u","0",1,1);intact();send("u","1",1,1);send("0","0",1,1);intact();
 send("U","1",1,1);send("6","!",1,1);send(13,"!",1,1);intact();
 send("U","2",1,1);send("1","1",1,1);send("0","!",1,1);send(13,"!",1,1);intact();
 // Reject the whole malformed numeric tail instead of leaking a later digit.
 send("U","2",1,1);send("9","!",1,1);send("1",0,0,1);send(13,"!",1,1);intact();
 send("U","3",1,1);send(13,0,0,1);send(10,0,0,1);intact();
 // Numeric tolerance selectors must not repeat the former U1 threshold bug.
 send("O","0",1,1);send("0","0",1,1);send(13,0,0,1);send(10,0,0,1);intact();
 send("O","1",1,1);send("1","1",1,1);send(13,0,0,1);intact();
 // Legitimate H/L commands still invalidate the saved reference.
 send("H",0,0,1);send("6",0,0,1);send("0",0,0,1);send(13,"K",1,1);
 repeat(6)@(negedge clk);if(reference_valid||high_threshold!=60)$fatal(1,"real H change must invalidate reference");
 send("R","R",1,1);intact();
 $display("PASS UART U0-U5: exact x/b/q/u1/CR sequence keeps 45/22 E reference and foreground; cycling, CRLF, malformed suffix rejection, explicit H invalidation");$finish;
end
initial begin #10000000;$fatal(1,"UART view/reference timeout");end
endmodule
