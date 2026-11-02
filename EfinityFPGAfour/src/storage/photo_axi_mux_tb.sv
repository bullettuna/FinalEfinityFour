`timescale 1ns/1ps
module photo_axi_mux_tb;
reg clk=0,rst_n=0;always #5 clk=~clk;
reg [31:0] awaddr[0:1];
reg [7:0] awlen[0:1];
reg awvalid[0:1];
wire awready[0:1];
reg [127:0] wdata[0:1];
reg [15:0] wstrb[0:1];
reg wlast[0:1];
reg wvalid[0:1];
wire wready[0:1];
wire bvalid[0:1];
wire [1:0] bresp[0:1];
reg [31:0] araddr[0:1];
reg [7:0] arlen[0:1];
reg arvalid[0:1];
wire arready[0:1];
wire [127:0] rdata[0:1];
wire [1:0] rresp[0:1];
wire rlast[0:1];
wire rvalid[0:1];
reg rready[0:1];
wire [31:0] m_awaddr;
wire [7:0] m_awlen;
wire m_awvalid;
reg m_awready;
wire [127:0] m_wdata;
wire [15:0] m_wstrb;
wire m_wlast;
wire m_wvalid;
reg m_wready;
reg m_bvalid;
reg [1:0] m_bresp;
wire [31:0] m_araddr;
wire [7:0] m_arlen;
wire m_arvalid;
reg m_arready;
reg [127:0] m_rdata;
reg [1:0] m_rresp;
reg m_rlast;
reg m_rvalid;
wire m_rready;
wire m_bready;
photo_axi_mux dut(.clk(clk),.rst_n(rst_n),
.v_read_flush(1'b0),.v_read_urgent(1'b0),.read_stalled(),.read_debug(),
.v_awaddr(awaddr[0]),
.v_awlen(awlen[0]),
.v_awvalid(awvalid[0]),
.v_awready(awready[0]),
.v_wdata(wdata[0]),
.v_wstrb(wstrb[0]),
.v_wlast(wlast[0]),
.v_wvalid(wvalid[0]),
.v_wready(wready[0]),
.v_bvalid(bvalid[0]),
.v_bresp(bresp[0]),
.v_araddr(araddr[0]),
.v_arlen(arlen[0]),
.v_arvalid(arvalid[0]),
.v_arready(arready[0]),
.v_rdata(rdata[0]),
.v_rresp(rresp[0]),
.v_rlast(rlast[0]),
.v_rvalid(rvalid[0]),
.v_rready(rready[0]),
.p_awaddr(awaddr[1]),
.p_awlen(awlen[1]),
.p_awvalid(awvalid[1]),
.p_awready(awready[1]),
.p_wdata(wdata[1]),
.p_wlast(wlast[1]),
.p_wvalid(wvalid[1]),
.p_wready(wready[1]),
.p_bvalid(bvalid[1]),
.p_bresp(bresp[1]),
.p_araddr(araddr[1]),
.p_arlen(arlen[1]),
.p_arvalid(arvalid[1]),
.p_arready(arready[1]),
.p_rdata(rdata[1]),
.p_rresp(rresp[1]),
.p_rlast(rlast[1]),
.p_rvalid(rvalid[1]),
.p_rready(rready[1]),
.m_awaddr(m_awaddr),
.m_awlen(m_awlen),
.m_awvalid(m_awvalid),
.m_awready(m_awready),
.m_wdata(m_wdata),
.m_wstrb(m_wstrb),
.m_wlast(m_wlast),
.m_wvalid(m_wvalid),
.m_wready(m_wready),
.m_bvalid(m_bvalid),
.m_bresp(m_bresp),
.m_araddr(m_araddr),
.m_arlen(m_arlen),
.m_arvalid(m_arvalid),
.m_arready(m_arready),
.m_rdata(m_rdata),
.m_rresp(m_rresp),
.m_rlast(m_rlast),
.m_rvalid(m_rvalid),
.m_rready(m_rready),
.m_bready(m_bready));

integer cycle=0,wb=0,rb=0,wd=0,bd=0,rd=0,wr_owner=0,rd_owner=0;
integer finished=0,write_total=0,read_total=0;
always @(posedge clk)begin
 cycle<=cycle+1;
 m_awready<=rst_n&&wb==0&&bd==0&&!m_bvalid&&cycle%5!=0;
 m_arready<=rst_n&&rb==0&&!m_rvalid&&cycle%7!=0;
 m_wready<=wb>0&&cycle%3!=0;
 if(m_bvalid&&m_bready)begin m_bvalid<=0;write_total=write_total+1;end
 if(m_awvalid&&m_awready)begin
  if(wb!=0)$fatal(1,"overlapping writes");wb=m_awlen+1;wr_owner=m_awaddr[12];wd=0;m_awready<=0;
 end
 if(m_wvalid&&m_wready)begin
  if(m_wdata!==128'h12340000+wr_owner*256+wd)$fatal(1,"write owner mixed");
  if(m_wstrb!=16'hffff)$fatal(1,"strobe lost");
  wb=wb-1;wd=wd+1;
  if(m_wlast!=(wb==0))$fatal(1,"bad WLAST");
  if(wb==0)begin bd=12;m_wready<=0;end
 end
 if(bd>0)begin bd=bd-1;if(bd==0)begin m_bvalid<=1;m_bresp<=wr_owner?2:0;end end
 if(m_arvalid&&m_arready)begin rb=m_arlen+1;rd_owner=m_araddr[12];rd=0;m_arready<=0;end
 if(m_rvalid&&m_rready)begin rb=rb-1;rd=rd+1;m_rvalid<=0;if(m_rlast)read_total=read_total+1;end
 if(!m_rvalid&&rb>0&&cycle%3!=0)begin
  m_rvalid<=1;m_rdata<=128'h56780000+rd_owner*256+rd;m_rlast<=rb==1;m_rresp<=rd_owner?2:0;
 end
 if(bvalid[0]&&bvalid[1])$fatal(1,"B routed to both owners");
 if(rvalid[0]&&rvalid[1])$fatal(1,"R routed to both owners");
end
task automatic writer(input integer c);
 integer t,k;
 begin
  for(t=0;t<12;t=t+1)begin
   @(negedge clk);awaddr[c]=c*4096;awlen[c]=3;awvalid[c]=1;
   do @(posedge clk);while(!awready[c]);
   @(negedge clk);awvalid[c]=0;
   for(k=0;k<4;k=k+1)begin
    wvalid[c]=1;wdata[c]=128'h12340000+c*256+k;wlast[c]=k==3;
    do @(posedge clk);while(!wready[c]);@(negedge clk);
   end
   wvalid[c]=0;wlast[c]=0;
   do @(posedge clk);while(!bvalid[c]);
   if(bresp[c]!=(c?2:0))$fatal(1,"wrong B response owner");
  end
  finished=finished+1;
 end
endtask
task automatic reader(input integer c);
 integer t,k;
 begin
  for(t=0;t<12;t=t+1)begin
   @(negedge clk);araddr[c]=c*4096;arlen[c]=7;arvalid[c]=1;rready[c]=0;
   do @(posedge clk);while(!arready[c]);
   @(negedge clk);arvalid[c]=0;
   for(k=0;k<8;k=k+1)begin
    repeat(c+1)@(negedge clk);rready[c]=1;
    do @(posedge clk);while(!rvalid[c]);
    if(rdata[c]!==128'h56780000+c*256+k || rresp[c]!=(c?2:0)||rlast[c]!=(k==7))$fatal(1,"read owner mixed");
    @(negedge clk);rready[c]=0;
   end
  end
  finished=finished+1;
 end
endtask
integer i;
initial begin
 m_awready=0;m_wready=0;m_bvalid=0;m_bresp=0;m_arready=0;m_rdata=0;m_rresp=0;m_rlast=0;m_rvalid=0;
 for(i=0;i<2;i=i+1)begin awaddr[i]=0;awlen[i]=0;awvalid[i]=0;wdata[i]=0;wstrb[i]=16'hffff;
 wlast[i]=0;wvalid[i]=0;araddr[i]=0;arlen[i]=0;arvalid[i]=0;rready[i]=0;end
 repeat(5)@(negedge clk);rst_n=1;
 fork writer(0);writer(1);reader(0);reader(1);join
 repeat(5)@(negedge clk);
 if(write_total!=24||read_total!=24)$fatal(1,"transaction lost");
 $display("PASS AXI mux simultaneous video/photo reads/writes, backpressure and error routing");$finish;
end
initial begin #1000000;$fatal(1,"AXI mux timeout %d",finished);end
endmodule
