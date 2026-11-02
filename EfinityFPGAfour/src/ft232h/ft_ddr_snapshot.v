`timescale 1ns/1ps
// One immutable snapshot at 0x01800000..0x019FA3FF (2,073,600 bytes max).
// The existing video AXI arbiter owns DDR arbitration. Never reset an AXI
// transaction on a UART stop: finish/drain it before declaring stopped.
module ft_ddr_snapshot #(parameter WIDTH=1920,HEIGHT=1080,FIFO_BITS=10)(
 input clk,input rst_n,input pclk,input enable,input edge_mode,input [1:0] resolution,
 input vs,input de,input [7:0] pixel,
 output available,input release_frame,output stopped,output reg fault,
 input [20:0] address,output reg [7:0] byte_data,output byte_valid,
 output [15:0] frame_width,frame_height,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output reg [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
 localparam [31:0] BASE=32'h01800000;
 wire [3:0] scale=resolution==0?6:resolution==1?3:1;
 assign frame_width=resolution==0?WIDTH/6:resolution==1?WIDTH/3:WIDTH;
 assign frame_height=resolution==0?HEIGHT/6:resolution==1?HEIGHT/3:HEIGHT;
 wire [31:0] total_bytes=frame_width*frame_height;
 (* async_reg="true" *) reg [2:0] pixel_reset;
 always @(posedge pclk or negedge rst_n)if(!rst_n)pixel_reset<=0;else pixel_reset<={pixel_reset[1:0],1'b1};
 wire prst_n=pixel_reset[2];
 reg request;
 (* async_reg="true" *)reg req_meta,req_sync;
 reg finished;
 (* async_reg="true" *)reg fin_meta,fin_sync,bad_meta,bad_sync;
 reg capturing,vs_d,de_d,group_or,pixel_bad;
 (* ram_style="block" *) reg row_or[0:WIDTH/3-1];
 reg row_value;
 reg [1:0] rs;
 reg [11:0] x,block_x;reg [10:0] y;
 reg [3:0] xp,yp,pack_n;
 reg [20:0] count;
 reg [119:0] pack;
 reg push;reg [127:0] packed_data;
 wire fifo_ready,head_valid;wire [127:0] head;
 wire [FIFO_BITS:0] occupancy;wire pop;
 wire selected=edge_mode?(xp==scale-1&&yp==scale-1):(xp==scale/2&&yp==scale/2);
 wire pooled=(scale==1)?(pixel!=0):((yp==0?1'b0:row_value)||group_or||pixel!=0);
 wire [7:0] value=edge_mode?(pooled?8'hff:0):pixel;
 always @(posedge pclk)begin
  row_value<=row_or[block_x];
  if(capturing&&de&&edge_mode&&scale!=1&&xp==scale-1)
   row_or[block_x]<=(yp==0?1'b0:row_value)||group_or||pixel!=0;
 end
 // Mode and dimensions remain constant from request until the completed
 // frame is released; request crosses only after configuration has settled.
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin req_meta<=0;req_sync<=0;finished<=0;capturing<=0;vs_d<=0;de_d<=0;
   x<=0;y<=0;block_x<=0;xp<=0;yp<=0;pack_n<=0;count<=0;pack<=0;
   push<=0;packed_data<=0;pixel_bad<=0;group_or<=0;end
  else begin
   req_meta<=request;req_sync<=req_meta;vs_d<=vs;de_d<=de;push<=0;
   if(push&&!fifo_ready)pixel_bad<=1;
   if(!vs)begin x<=0;y<=0;block_x<=0;xp<=0;yp<=0;group_or<=0;end
   if(vs&&!vs_d&&!capturing&&req_sync!=finished)begin
    capturing<=1;count<=0;pack_n<=0;pixel_bad<=0;
   end
   if(vs_d&&!vs&&capturing)begin
    capturing<=0;finished<=req_sync;
    if(count!=total_bytes||pack_n!=0||y!=HEIGHT)pixel_bad<=1;
   end
   if(de)begin
    x<=x+1'b1;
    if(x>=WIDTH||y>=HEIGHT)pixel_bad<=1;
    if(xp==scale-1)begin
     xp<=0;block_x<=block_x+1'b1;group_or<=0;
    end else begin xp<=xp+1'b1;group_or<=group_or||pixel!=0;end
    if(capturing&&selected&&x<WIDTH&&y<HEIGHT)begin
     count<=count+1'b1;pack<={value,pack[119:8]};pack_n<=pack_n+1'b1;
     if(pack_n==15)begin packed_data<={value,pack};push<=1;end
    end
   end
   if(de_d&&!de)begin
    if(capturing&&x!=WIDTH)pixel_bad<=1;
    x<=0;block_x<=0;xp<=0;group_or<=0;y<=y+1'b1;
    yp<=yp==scale-1?0:yp+1'b1;
   end
  end
 end
 photo_async_fifo #(.WIDTH(128),.ABITS(FIFO_BITS)) u_capture_fifo(
  .wclk(pclk),.wrst_n(prst_n),.wvalid(push),.wready(fifo_ready),.wdata(packed_data),
  .rclk(clk),.rrst_n(rst_n),.rvalid(head_valid),.rready(pop),.rdata(head),.rcount(occupancy));
 localparam IDLE=0,CAPTURE=1,OWNED=2;
 reg [1:0] capture_state,ws;reg [2:0] beat;
 reg [20:0] written;reg bad;reg [3:0] settled;
 wire source_done=fin_sync==request;
 assign awaddr=BASE+written;
 assign awlen=7;assign awvalid=ws==1;
 assign wdata=head;assign wvalid=ws==2&&head_valid;assign wlast=beat==7;
 assign pop=(ws==2&&wready)||(capture_state==CAPTURE&&source_done&&settled==15&&ws==0&&occupancy<8);
 assign available=capture_state==OWNED&&!fault;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin request<=0;fin_meta<=0;fin_sync<=0;bad_meta<=0;bad_sync<=0;
   capture_state<=IDLE;ws<=0;beat<=0;written<=0;bad<=0;settled<=0;fault<=0;end
  else begin
   fin_meta<=finished;fin_sync<=fin_meta;bad_meta<=pixel_bad;bad_sync<=bad_meta;
   if(capture_state==IDLE&&enable&&rs==0&&!head_valid&&occupancy==0)begin
    request<=!request;capture_state<=CAPTURE;written<=0;bad<=0;fault<=0;settled<=0;
   end
   if(capture_state==CAPTURE&&source_done)begin if(settled!=15)settled<=settled+1'b1;end
   case(ws)
    0:if(capture_state==CAPTURE)begin
     if(occupancy>=8)begin ws<=1;beat<=0;end
     else if(source_done&&settled==15&&!head_valid&&occupancy==0)begin
      if(!bad&&!bad_sync&&written==total_bytes&&enable)capture_state<=OWNED;
      else begin fault<=enable;capture_state<=IDLE;end
     end
    end
    1:if(awready)ws<=2;
    2:if(wvalid&&wready)begin beat<=beat+1'b1;if(beat==7)ws<=3;end
    3:if(bvalid)begin if(bresp!=0)bad<=1;written<=written+128;ws<=0;end
   endcase
   if(capture_state==OWNED&&(release_frame||!enable)&&rs==0)capture_state<=IDLE;
  end
 end
 // Fetch only eight beats, then release DDR before serializing bytes. Video
 // never waits for a USB receiver holding RREADY low for seconds.
 reg [2:0] rd_beat;reg [13:0] cache_block;
 reg cache_valid,read_bad;reg [127:0] cache[0:7];
 assign arlen=7;assign arvalid=rs==1;assign rready=rs==2;
 assign byte_valid=available&&cache_valid&&cache_block==address[20:7];
 assign stopped=capture_state==IDLE&&ws==0&&rs==0&&!head_valid&&occupancy==0;
 always @(posedge clk)begin
  if(rs==2&&rvalid)cache[rd_beat]<=rdata;
  byte_data<=cache[address[6:4]][address[3:0]*8 +:8];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rs<=0;rd_beat<=0;cache_block<=0;cache_valid<=0;read_bad<=0;araddr<=0;end
  else begin
   if(!available)cache_valid<=0;
   case(rs)
    0:if(available&&enable&&(!cache_valid||cache_block!=address[20:7]))begin
     araddr<=BASE+{address[20:7],7'b0};cache_block<=address[20:7];
     cache_valid<=0;read_bad<=0;rd_beat<=0;rs<=1;
    end
    1:if(arready)rs<=2;
    2:if(rvalid)begin
     if(rresp!=0||((rd_beat==7)!=rlast))read_bad<=1;
     rd_beat<=rd_beat+1'b1;
     if(rlast)begin rs<=0;cache_valid<=!read_bad&&rresp==0&&rd_beat==7;end
    end
   endcase
  end
 end
endmodule
