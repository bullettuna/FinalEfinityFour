`ifndef IMAGE7_MENU_DEFS_VH
`define IMAGE7_MENU_DEFS_VH

// Shared image1 on-screen menu definitions.  The menu is deliberately a
// text-only status/control page: no icons, no framebuffer, no extra clock.
// Item indices double as the control write addresses used by uart_vision_ctrl.

`define M7_MENU_ITEM_VIEW       5'd0
`define M7_MENU_ITEM_INFER      5'd1
`define M7_MENU_ITEM_SKELETON      5'd2
`define M7_MENU_ITEM_FREEZE     5'd3
`define M7_MENU_ITEM_TEST       5'd4
`define M7_MENU_ITEM_CANNY      5'd5
`define M7_MENU_ITEM_CANNY_H    5'd6
`define M7_MENU_ITEM_CANNY_L    5'd7
`define M7_MENU_ITEM_CANNY_RST  5'd8
`define M7_MENU_ITEM_MEDIAN     5'd9
`define M7_MENU_ITEM_WB_R       5'd10
`define M7_MENU_ITEM_WB_G       5'd11
`define M7_MENU_ITEM_WB_B       5'd12
`define M7_MENU_ITEM_WB_RST     5'd13
`define M7_MENU_ITEM_GAMMA      5'd14
`define M7_MENU_ITEM_GAMMA_P    5'd15
`define M7_MENU_ITEM_SD         5'd16
`define M7_MENU_ITEM_BIN        5'd17

`define M7_MENU_ITEM_COUNT      20
`define M7_MENU_VISIBLE_ROWS    8
`define M7_MENU_COLS            30
`define M7_MENU_ROWS            12

// image7_menu_ctrl state encoding.
`define M7_MENU_STATE_CLOSED    2'd0
`define M7_MENU_STATE_BROWSE    2'd1
`define M7_MENU_STATE_EDIT      2'd2

// Flat display record sent from clk_sys to clk_pixel_2x.  The whole record is
// sampled only in vertical blanking, matching the existing frame-boundary CDC.
`define M7_MENU_DISP_WIDTH      154
`define M7_MD_STATE_OFF         0    // 2 bits
`define M7_MD_CURSOR_OFF        2    // 5 bits
`define M7_MD_WINDOW_OFF        7    // 5 bits
`define M7_MD_VIEW_OFF          12   // 2 bits
`define M7_MD_FLAGS_OFF         14   // 6 bits
`define M7_MD_HIGH_OFF          20   // 16 bits, four BCD digits
`define M7_MD_LOW_OFF           36   // 16 bits
`define M7_MD_WBR_OFF           52   // 16 bits
`define M7_MD_WBG_OFF           68   // 16 bits
`define M7_MD_WBB_OFF           84   // 16 bits
`define M7_MD_GAMMA_OFF         100  // 12 bits, three BCD digits
`define M7_MD_BLACK_OFF         112  // 12 bits

`define M7_MD_FLAG_INFER        0
`define M7_MD_FLAG_SKELETON        1
`define M7_MD_FLAG_FREEZE       2
`define M7_MD_FLAG_TEST         3
`define M7_MD_FLAG_MEDIAN       4
`define M7_MD_FLAG_GAMMA        5

`define M7_MD_STATUS_OFF      124  // init,fat,file,header,CRC,self-test,enabled,busy,error[7:0]

`define M7_MENU_ITEM_BOOT      5'd18
`define M7_MENU_ITEM_LOAD      5'd19
`define M7_MD_BOOT_OFF        140
`define M7_MD_BOOT_STATUS_OFF 142
`define M7_MD_CHECK_OFF 146
`endif
