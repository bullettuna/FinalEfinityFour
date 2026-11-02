`timescale 1ns/1ps
module pose6_axi_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;integer cycle=0;
 reg vv=0,vwrite=0,pv=0,pwrite=0;reg [31:0] va=0,pa=0;reg [127:0] vd=0,pd=0;
 wire vready,pready,vrv,prv,vfault,pfault;wire [127:0] vresult,presult;
 wire [31:0] vaw,var_,paw,par_,aw,ar;wire [7:0] vawl,varl,pawl,parl,awl,arl;
 wire vawv,vawr,vwv,vwr,vwl,vbv,varv,varr,vrv_axi,vrr,vrl;
 wire pawv,pawr,pwv,pwr,pwl,pbv,parv,parr,prv_axi,prr,prl;
 wire awv,wv,wl,bready,arv,rready;wire [127:0] vwd,vrd,pwd,prd,wd;
 wire [1:0] vbresp,vrresp,pbresp,prresp;
 reg [1:0] ws=0,rs=0;reg [31:0] wa;reg [127:0] rdata;
 wire awready=ws==0&&cycle%5!=1;
 wire wready=ws==1&&cycle%7!=2;
 wire bvalid=ws==2;
 wire arready=rs==0&&cycle%6!=3;
 wire rvalid=rs==2;
 reg [127:0] memory[0:127];integer delay_count=0;
 pose6_axi_master vm(clk,rst_n,vv,vready,vwrite,va,vd,vrv,vresult,vfault,
  vaw,vawl,vawv,vawr,vwd,vwl,vwv,vwr,vbv,vbresp,var_,varl,varv,varr,vrd,vrresp,vrl,vrv_axi,vrr);
 pose6_axi_master pm(clk,rst_n,pv,pready,pwrite,pa,pd,prv,presult,pfault,
  paw,pawl,pawv,pawr,pwd,pwl,pwv,pwr,pbv,pbresp,par_,parl,parv,parr,prd,prresp,prl,prv_axi,prr);
 photo_axi_mux mux(.clk(clk),.rst_n(rst_n),.v_read_flush(1'b0),.v_read_urgent(cycle%17<4),.read_stalled(),.read_debug(),
  .v_awaddr(vaw),.v_awlen(vawl),.v_awvalid(vawv),.v_awready(vawr),.v_wdata(vwd),.v_wstrb(16'hffff),.v_wlast(vwl),.v_wvalid(vwv),.v_wready(vwr),.v_bvalid(vbv),.v_bresp(vbresp),
  .v_araddr(var_),.v_arlen(varl),.v_arvalid(varv),.v_arready(varr),.v_rdata(vrd),.v_rresp(vrresp),.v_rlast(vrl),.v_rvalid(vrv_axi),.v_rready(vrr),
  .p_awaddr(paw),.p_awlen(pawl),.p_awvalid(pawv),.p_awready(pawr),.p_wdata(pwd),.p_wlast(pwl),.p_wvalid(pwv),.p_wready(pwr),.p_bvalid(pbv),.p_bresp(pbresp),
  .p_araddr(par_),.p_arlen(parl),.p_arvalid(parv),.p_arready(parr),.p_rdata(prd),.p_rresp(prresp),.p_rlast(prl),.p_rvalid(prv_axi),.p_rready(prr),
  .m_awaddr(aw),.m_awlen(awl),.m_awvalid(awv),.m_awready(awready),.m_wdata(wd),.m_wstrb(),.m_wlast(wl),.m_wvalid(wv),.m_wready(wready),.m_bvalid(bvalid),.m_bresp(2'b0),.m_bready(bready),
  .m_araddr(ar),.m_arlen(arl),.m_arvalid(arv),.m_arready(arready),.m_rdata(rdata),.m_rresp(2'b0),.m_rlast(1'b1),.m_rvalid(rvalid),.m_rready(rready));
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(awv&&awready)begin if(awl!=0||aw[3:0]!=0)$fatal(1,"write alignment/length");wa<=aw;ws<=1;end
  if(wv&&wready)begin if(!wl)$fatal(1,"missing WLAST");memory[wa>>4]<=wd;ws<=2;end
  if(bvalid&&bready)ws<=0;
  if(arv&&arready)begin
   if(arl!=0||ar[3:0]!=0)$fatal(1,"read alignment/length");rdata<=memory[ar>>4];rs<=1;delay_count<=cycle%5+1;
  end
  if(rs==1)begin if(delay_count!=0)delay_count<=delay_count-1;else rs<=2;end
  if(rvalid&&rready)rs<=0;
 end
 task vtransaction(input wr,input [31:0] a,input [127:0] d);
  begin
   @(negedge clk);vv=1;vwrite=wr;va=a;vd=d;
   do @(posedge clk);while(!vready);
   @(negedge clk);vv=0;wait(vrv);#1;
   if(vfault||(!wr&&vresult!==d))$fatal(1,"video client response/ownership");
  end
 endtask
 task ptransaction(input wr,input [31:0] a,input [127:0] d);
  begin
   @(negedge clk);pv=1;pwrite=wr;pa=a;pd=d;
   do @(posedge clk);while(!pready);
   @(negedge clk);pv=0;wait(prv);#1;
   if(pfault||(!wr&&presult!==d))$fatal(1,"model client response/ownership");
  end
 endtask
 integer i,n,m;reg [31:0] vp,pp;
 initial begin
  for(i=0;i<128;i=i+1)memory[i]=0;
  #22;rst_n=1;
  fork
   begin for(n=0;n<32;n=n+1)begin vp=32'ha0000000+n;vtransaction(1,n*16,{4{vp}});vtransaction(0,n*16,{4{vp}});end end
   begin for(m=0;m<32;m=m+1)begin pp=32'hb0000000+m;ptransaction(1,1024+m*16,{4{pp}});ptransaction(0,1024+m*16,{4{pp}});end end
  join
  $display("PASS image6 AXI master and shared DDR arbiter: concurrent clients, 128 transactions, independent AW/W/B/AR/R stalls and exact ownership");$finish;
 end
 initial begin #1000000;$fatal(1,"AXI arbitration timeout");end
endmodule
