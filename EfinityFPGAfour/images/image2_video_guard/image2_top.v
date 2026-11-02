`timescale 1ns/1ps
// Fixed compile-time image profile; no runtime feature switch retains hardware.
module image2_top (
`include "src/top/camera_board_ports.vh"
);
image2_platform #(.PHOTO_TF_BUILD(1'b1), .ENABLE_PHOTO_TF(1'b1), .ENABLE_ADC(1'b1), .MENU_BUILD(1'b1),
    .DEFAULT_VIDEO_MODE(2'd0)) u_platform (
`include "src/top/camera_board_connections.vh"
);
endmodule
