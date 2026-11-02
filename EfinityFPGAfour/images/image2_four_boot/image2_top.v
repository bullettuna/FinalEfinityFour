`timescale 1ns/1ps
// Fixed compile-time image profile; no runtime feature switch retains hardware.
module image2_top (
`include "src/top/camera_board_ports.vh"
, input cfg_ERROR,output [1:0] cfg_CBSEL,output cfg_CONFIG,cfg_ENA
);
image2_platform #(.MULTIBOOT_BUILD(1'b1),.PHOTO_TF_BUILD(1'b1), .ENABLE_PHOTO_TF(1'b1), .ENABLE_ADC(1'b1), .MENU_BUILD(1'b1),
    .DEFAULT_VIDEO_MODE(2'd0)) u_platform (
`include "src/top/camera_board_connections.vh"
, .cfg_ERROR(cfg_ERROR),.cfg_CBSEL(cfg_CBSEL),.cfg_CONFIG(cfg_CONFIG),.cfg_ENA(cfg_ENA)
);
endmodule
