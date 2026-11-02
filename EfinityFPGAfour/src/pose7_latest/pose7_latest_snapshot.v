`timescale 1ns/1ps
module pose7_latest_snapshot #(parameter WIDTH=1920,HEIGHT=1080,FIFO_BITS=10)(
 input latest_mode,acquire_frame,output [31:0] read_base,
 input clk,input rst_n,input pclk,input enable,input edge_mode,input [1:0] resolution,
 input vs,input de,input [7:0] pixel,
 output available,input release_frame,output stopped,output fault,
 input [20:0] address,output [7:0] byte_data,output byte_valid,
 output [15:0] frame_width,frame_height,
 output [31:0] awaddr,output [7:0] awlen,output awvalid,input awready,
 output [127:0] wdata,output wlast,output wvalid,input wready,input bvalid,input [1:0] bresp,
 output [31:0] araddr,output [7:0] arlen,output arvalid,input arready,
 input [127:0] rdata,input [1:0] rresp,input rlast,input rvalid,output rready
);
// DDR slot0: 01800000..019fffff, slot1: 01a00000..01bfffff.
// The existing model/activation region starts at 02000000. Only a complete
// acknowledged frame becomes READY. Acquisition pins its bank until release.
 localparam IDLE=0,START=1,ACTIVE=2,RELEASE=3;
 reg [1:0] state,ready_banks;
 reg active_latest,write_bank,latest_bank,locked_valid,locked_bank;
 wire capture_available,capture_stopped,capturing;
 wire mode_mismatch=active_latest!=latest_mode;
 wire ready_choice=ready_banks[latest_bank]?latest_bank:!latest_bank;
 assign available=active_latest?(|ready_banks)&&!locked_valid:capture_available&&!latest_mode;
 wire acquire_now=active_latest&&acquire_frame&&available;
 wire [1:0] protected_banks=locked_valid?(locked_bank?2'b10:2'b01):
                              acquire_now?(ready_choice?2'b10:2'b01):2'b00;
 reg allocate_valid,allocate_bank;
 always @*begin
  allocate_valid=1;allocate_bank=0;
  if(!protected_banks[0]&&!ready_banks[0])allocate_bank=0;
  else if(!protected_banks[1]&&!ready_banks[1])allocate_bank=1;
  else if(!protected_banks[!latest_bank])allocate_bank=!latest_bank;
  else if(!protected_banks[latest_bank])allocate_bank=latest_bank;
  else allocate_valid=0;
 end
 wire capture_enable=enable&&!mode_mismatch&&(!active_latest||state==START||state==ACTIVE);
 wire capture_release=active_latest?(state==RELEASE||!enable||mode_mismatch):(release_frame||mode_mismatch);
 assign read_base=!active_latest?32'h01800000:
                  (locked_valid?locked_bank:ready_choice)?32'h01a00000:32'h01800000;
 assign stopped=capture_stopped&&!locked_valid&&(!active_latest||state==IDLE);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;ready_banks<=0;active_latest<=0;write_bank<=0;latest_bank<=0;locked_valid<=0;locked_bank<=0;
  end else begin
   if(!enable||mode_mismatch)ready_banks<=0;
   if(release_frame)locked_valid<=0;
   // Acquisition takes priority over allocation on the same clock edge.
   if(acquire_now)begin locked_valid<=1;locked_bank<=ready_choice;ready_banks[ready_choice]<=0;end
   if(active_latest)case(state)
    IDLE:if(enable&&!mode_mismatch&&capture_stopped&&allocate_valid)begin
     write_bank<=allocate_bank;ready_banks[allocate_bank]<=0;state<=START;
    end
    START:if(!capture_stopped)state<=ACTIVE;else if(!enable||mode_mismatch)state<=IDLE;
    ACTIVE:if(capture_available)begin
     if(enable&&!mode_mismatch)begin ready_banks[write_bank]<=1;latest_bank<=write_bank;end
     state<=RELEASE;
    end else if(capture_stopped)state<=IDLE;
    RELEASE:if(capture_stopped)state<=IDLE;
   endcase
   if(mode_mismatch&&capture_stopped&&!locked_valid&&!acquire_now)begin
    active_latest<=latest_mode;ready_banks<=0;state<=IDLE;
   end
  end
 end
 pose7_capture_bank #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIFO_BITS(FIFO_BITS)) u_capture(
  .clk(clk),
  .rst_n(rst_n),
  .pclk(pclk),
  .edge_mode(edge_mode),
  .resolution(resolution),
  .vs(vs),
  .de(de),
  .pixel(pixel),
  .address(address),
  .byte_data(byte_data),
  .byte_valid(byte_valid),
  .frame_width(frame_width),
  .frame_height(frame_height),
  .awaddr(awaddr),
  .awlen(awlen),
  .awvalid(awvalid),
  .awready(awready),
  .wdata(wdata),
  .wlast(wlast),
  .wvalid(wvalid),
  .wready(wready),
  .bvalid(bvalid),
  .bresp(bresp),
  .araddr(araddr),
  .arlen(arlen),
  .arvalid(arvalid),
  .arready(arready),
  .rdata(rdata),
  .rresp(rresp),
  .rlast(rlast),
  .rvalid(rvalid),
  .rready(rready),
  .base_address(active_latest?(write_bank?32'h01a00000:32'h01800000):32'h01800000),.read_enable(!active_latest),
  .enable(capture_enable),.release_frame(capture_release),.available(capture_available),.stopped(capture_stopped),.fault(fault),.capturing(capturing));
endmodule
