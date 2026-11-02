`timescale 1ns/1ps
module person_snapshot_selector_tb;
localparam W=16,H=12,FW=W*4,FH=H*4;
reg clk=0,rst_n=0,valid=1,invalidate=0,vs=0,hs=0,de=0,mask=0;
always #5 clk=~clk;
wire ov,oh,oe,om,oc,bv,busy,err;
wire [11:0] xmin,xmax;wire [10:0] ymin,ymax;wire [31:0] completed;
wire overflow_error,overflow_valid,overflow_mask;
reg overflow_seen=0;
person_snapshot_selector #(.WIDTH(W),.HEIGHT(H),.MIN_AREA(12),.MIN_WIDTH(3),.MIN_HEIGHT(3),
 .FRAGMENT_AREA(2),.MERGE_GAP(2),.PAD(1),.QUEUE_BITS(2)) bounded_queue(
 .clk(clk),.rst_n(rst_n),.source_valid(valid),.invalidate(invalidate),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_mask(mask),
 .out_mask(overflow_mask),.bbox_valid(overflow_valid),.processing_error(overflow_error));
always @(posedge clk)begin
 #1;if(overflow_error)begin
  overflow_seen=1;
  if(overflow_valid||overflow_mask)$fatal(1,"queue overflow published an incomplete target");
 end
end
person_snapshot_selector #(.WIDTH(W),.HEIGHT(H),.MIN_AREA(12),.MIN_WIDTH(3),.MIN_HEIGHT(3),
 .FRAGMENT_AREA(2),.MERGE_GAP(2),.PAD(1),.QUEUE_BITS(6)) dut(
 .clk(clk),.rst_n(rst_n),.source_valid(valid),.invalidate(invalidate),
 .in_vsync(vs),.in_hsync(hs),.in_href(de),.in_mask(mask),
 .out_vsync(ov),.out_hsync(oh),.out_href(oe),.out_mask(om),.out_contour(oc),
 .bbox_valid(bv),.bbox_x_min(xmin),.bbox_x_max(xmax),.bbox_y_min(ymin),.bbox_y_max(ymax),
 .busy(busy),.processing_error(err),.completed_snapshots(completed));
function automatic bit scene(input integer x,y,mode);
 case(mode)
  1:scene=(x>=4&&x<=9&&y>=2&&y<=8)||(x>=11&&x<=12&&y>=3&&y<=4)||(x<=1&&y>=9&&y<=10);
  2:scene=x>=5&&x<=8&&y>=3&&y<=7;
  3:scene=x==0&&y==0;
  4:scene=x>=12&&y>=8; // target at right/bottom image boundary
  default:scene=0;
 endcase
endfunction
function automatic bit selected(input integer x,y,mode);
 if(x<0||x>=W||y<0||y>=H)selected=0;
 else case(mode)
  1:selected=(x>=4&&x<=9&&y>=2&&y<=8)||(x>=11&&x<=12&&y>=3&&y<=4);
  2:selected=x>=5&&x<=8&&y>=3&&y<=7;
  4:selected=x>=12&&y>=8;
  default:selected=0;
 endcase
endfunction
function automatic bit boundary(input integer x,y,mode);
 bit inner;
 begin
  inner=1;
  for(integer a=-1;a<=1;a++)for(integer b=-1;b<=1;b++)inner&=selected(x+a,y+b,mode);
  boundary=selected(x,y,mode)&&!inner;
 end
endfunction
task automatic frame(input integer input_mode,expected_mode,input bit check);
 begin
  @(negedge clk);vs=0;de=0;repeat(4)@(negedge clk);vs=1;
  for(integer y=0;y<FH;y++)begin
   for(integer x=0;x<FW;x++)begin
    @(negedge clk);de=1;mask=scene(x/4,y/4,input_mode);
    @(posedge clk);#1;
    if(check&&(oe!==1||om!==selected(x/4,y/4,expected_mode)||oc!==boundary(x/4,y/4,expected_mode)))
     $fatal(1,"selected snapshot mismatch x=%0d y=%0d mask=%b/%b contour=%b/%b",x,y,om,selected(x/4,y/4,expected_mode),oc,boundary(x/4,y/4,expected_mode));
   end
   @(negedge clk);de=0;repeat(4)@(negedge clk);
  end
  @(negedge clk);vs=0;de=0;
 end
endtask
task automatic finish_analysis;
 integer timeout;
 begin timeout=0;while(!dut.pending&&timeout<100000)begin @(negedge clk);timeout++;end
 if(!dut.pending||err)$fatal(1,"analysis failed state=%0d error=%b",dut.state,err);end
endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 frame(1,0,0);finish_analysis();frame(0,1,1);
 if(!bv||xmin!=12||xmax!=55||ymin!=4||ymax!=39)$fatal(1,"merged/padded box incorrect %0d %0d %0d %0d",xmin,xmax,ymin,ymax);
 // Stable person remains detectable: the same static mask is sufficient.
 frame(1,1,1);finish_analysis();frame(0,1,1);
 frame(0,1,1);finish_analysis();frame(0,0,1);
 if(bv)$fatal(1,"target disappearance retained old ROI");
 frame(3,0,1);finish_analysis();frame(0,0,1);
 if(bv)$fatal(1,"single noise pixel selected");
 frame(4,0,1);finish_analysis();frame(0,4,1);
 if(!bv||xmax!=FW-1||ymax!=FH-1)$fatal(1,"right/bottom boundary clipped");
 @(negedge clk);valid=0;@(posedge clk);#1;if(bv||om||oc||busy)$fatal(1,"invalid background leaked a stale result");
 @(negedge clk);valid=1;invalidate=1;@(posedge clk);#1;if(bv)$fatal(1,"configuration invalidation failed");
 if(!overflow_seen)$fatal(1,"bounded queue failure path not exercised");
 $display("PASS snapshot selector: 8-connected selection, detached limb merge, clutter rejection, exact mask/contour replay, static target, loss, borders and invalidation");$finish;
end
initial begin #10000000;$fatal(1,"snapshot timeout");end
endmodule
