`timescale 1ns/1ps
// image7: image5 camera/Canny front end with DDR INT16 four-point inference.
module image7_top (
`include "src/top/camera_board_ports.vh"
,
 input ft_txe_n,input [7:0] ft_data_i,output [7:0] ft_data_o,output [7:0] ft_data_oe,output ft_wr_n,output ft_wr_oe,input ft_wr_i,
 input cfg_ERROR,output [1:0] cfg_CBSEL,output cfg_CONFIG,cfg_ENA
);
image7_platform #(
 .PHOTO_TF_BUILD(1'b0),.ENABLE_PHOTO_TF(1'b0),.ENABLE_KEY_UART(1'b1),.ENABLE_ADC(1'b1),
 .SHAPE_BUILD(1'b0),.COLOR_OVERLAY_BUILD(1'b0),.GRAY_EDGE_SPLIT_BUILD(1'b0),
 .PERSON_BUILD(1'b0),.DEFAULT_VIDEO_MODE(2'd0)
) u_platform (
`include "src/top/camera_board_connections.vh"
,
 .ft_txe_n(ft_txe_n),.ft_data_i(ft_data_i),.ft_data_o(ft_data_o),.ft_data_oe(ft_data_oe),.ft_wr_n(ft_wr_n),.ft_wr_oe(ft_wr_oe),.ft_wr_i(ft_wr_i),
 .cfg_ERROR(cfg_ERROR),.cfg_CBSEL(cfg_CBSEL),.cfg_CONFIG(cfg_CONFIG),.cfg_ENA(cfg_ENA)
);
endmodule
