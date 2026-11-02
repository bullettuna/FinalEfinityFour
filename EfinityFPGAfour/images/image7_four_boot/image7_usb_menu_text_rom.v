`timescale 1ns/1ps
module image7_usb_menu_text_rom(input [4:0] item,input [4:0] col,output reg [7:0] ch);
reg [239:0] line;
always @* begin
 case(item)
 5'd0: line=" VIEW RGB                     ";
 5'd1: line=" INFERENCE                    ";
 5'd2: line=" SKELETON                     ";
 5'd3: line=" FREEZE                       ";
 5'd4: line=" TEST RGB                     ";
 5'd5: line=" CANNY H/L                    ";
 5'd6: line=" CANNY H                      ";
 5'd7: line=" CANNY L                      ";
 5'd8: line=" CANNY RESET                  ";
 5'd9: line=" MEDIAN                       ";
 5'd10: line=" WB R                         ";
 5'd11: line=" WB G                         ";
 5'd12: line=" WB B                         ";
 5'd13: line=" WB RESET                     ";
 5'd14: line=" GAMMA                        ";
 5'd15: line=" GAMMA P                      ";
 5'd16: line=" SD CHECK                     ";
 5'd17: line=" BIN CHECK                    ";
 5'd21: line="K2/K3/KNOB:SCROLL  K1:ENTER   ";
 5'd22: line="HOLD K1:OPEN/CLOSE            ";
 5'd23: line="K2:+1 K3:-1 KNOB:FAST         ";
 5'd24: line="K1:CONFIRM HOLD K1:CLOSE      ";
 5'd18: line=" BOOT IMAGE                   ";
 5'd19: line=" LOAD IMAGE                   ";
 5'd20: line=" USB PTS                      ";
 default:line={30{8'h20}};
 endcase
 ch=col<30 ? line[(29-col)*8+:8] : 8'h20;
end
endmodule
