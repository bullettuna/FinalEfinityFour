`timescale 1ns/1ps
module ft_edge_pack_tb;
 reg clk=0,rst_n=0,enable=1;
 reg [20:0] address=0;
 wire [20:0] pixel_address;reg [7:0] pixel_data;
 wire [7:0] data;wire valid;
 integer cycle=0;
 always #5 clk=~clk;
 wire pixel_valid=cycle%13>4;
 function [7:0] pixel(input integer a);
  pixel=(((a*13)^(a>>3)^(a>>9))&7)==0?8'hff:0;
 endfunction
 function [7:0] expected(input integer a);
  integer b;begin for(b=0;b<8;b=b+1)expected[7-b]=pixel(a*8+b)!=0;end
 endfunction
 always @(posedge clk)begin cycle<=cycle+1;pixel_data<=pixel(pixel_address);end
 ft_edge_pack dut(.clk(clk),.rst_n(rst_n),.enable(enable),.byte_address(address),
  .pixel_address(pixel_address),.pixel_data(pixel_data),.pixel_valid(pixel_valid),
  .packed_data(data),.packed_valid(valid));
 task read_byte(input integer a);
  reg [7:0] saved;integer n;
  begin
   @(negedge clk);address=a;#1;
   if(valid&&dut.current!=address)$fatal(1,"old packed byte advertised after address change");
   wait(valid);#1;
   if(data!==expected(a))$fatal(1,"MSB-first packed byte mismatch addr=%d got=%h want=%h",a,data,expected(a));
   saved=data;
   for(n=0;n<43;n=n+1)begin @(negedge clk);if(!valid||data!==saved)$fatal(1,"packed data changed during USB stall");end
  end
 endtask
 integer i;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<40;i=i+1)read_byte(i);
  read_byte(8191);read_byte(8192);read_byte(259199);read_byte(0);
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;read_byte(32);
  @(negedge clk);enable=0;address=2073599;
  repeat(4)@(negedge clk);
  if(pixel_address!=address||data!==pixel(address)||valid!==pixel_valid)$fatal(1,"8bpp bypass changed");
  $display("PASS 1bpp packer: MSB-first, DDR wait states, 128-byte boundaries, 1080p final byte, restart, arbitrary seeks, held output and byte bypass");$finish;
 end
 initial begin #1000000;$fatal(1,"packed byte never completed");end
endmodule
