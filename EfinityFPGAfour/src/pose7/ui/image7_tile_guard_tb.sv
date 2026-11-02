`timescale 1ns/1ps
module image7_tile_guard_tb;
reg clk=0,rst_n=0;always #5 clk=~clk;
pose7_conv dut(.clk(clk),.rst_n(rst_n),.start(1'b0),.layer_index(4'd0),
 .busy(),.done(),.fault(),.command_valid(),.command_ready(1'b0),.command_write(),.command_address(),.command_data(),
 .response_valid(1'b0),.response_data(128'd0));
reg [3:0] selected_layer;reg [7:0] selected_tile;
integer tested=0,valid_tiles=0;
initial begin
 #20;rst_n=1;
 force dut.layer=selected_layer;force dut.tile_out=selected_tile;
 for(integer l=0;l<10;l=l+1)begin
  selected_layer=l;#1;
  if(dut.tile_row_capacity(l)!==32768/(dut.iw*dut.ci))$fatal(1,"layer capacity table stale");
  for(integer t=0;t<256;t=t+1)begin
   selected_tile=t;#20;
   if(dut.tile_size_fault !== ((dut.last_row-dut.first_row)*dut.iw*dut.ci>32768))
    $fatal(1,"guard equivalence layer=%0d tile=%0d span=%h capacity=%0d",l,t,dut.tile_row_span,dut.tile_row_capacity(l));
   if(t<dut.oh && t%8==0)begin
    if(dut.tile_size_fault || dut.tile_row_span*dut.iw*dut.ci>32768)$fatal(1,"valid tile exceeds RAM");
    valid_tiles=valid_tiles+1;
   end
   tested=tested+1;
  end
 end
 release dut.layer;release dut.tile_out;
 $display("PASS image7_tile_guard: %0d exhaustive layer/tile cases including out-of-range tiles, %0d real tile starts; original multiplication predicate equals lookup predicate",tested,valid_tiles);
 $finish;
end
endmodule
