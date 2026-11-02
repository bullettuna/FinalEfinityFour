`ifndef IMAGE2_MENU_DEFS_VH
`define IMAGE2_MENU_DEFS_VH

// Shared image1 on-screen menu definitions.  The menu is deliberately a
// text-only status/control page: no icons, no framebuffer, no extra clock.
// Item indices double as the control write addresses used by uart_vision_ctrl.

`define MENU_ITEM_VIEW       5'd0
`define MENU_ITEM_SPLIT      5'd1
`define MENU_ITEM_SHAPE      5'd2
`define MENU_ITEM_FREEZE     5'd3
`define MENU_ITEM_TEST       5'd4
`define MENU_ITEM_CANNY      5'd5
`define MENU_ITEM_CANNY_H    5'd6
`define MENU_ITEM_CANNY_L    5'd7
`define MENU_ITEM_CANNY_RST  5'd8
`define MENU_ITEM_MEDIAN     5'd9
`define MENU_ITEM_WB_R       5'd10
`define MENU_ITEM_WB_G       5'd11
`define MENU_ITEM_WB_B       5'd12
`define MENU_ITEM_WB_RST     5'd13
`define MENU_ITEM_GAMMA      5'd14
`define MENU_ITEM_GAMMA_P    5'd15
`define MENU_ITEM_BLACK      5'd16

`define MENU_ITEM_COUNT      22
`define MENU_VISIBLE_ROWS    8
`define MENU_COLS            30
`define MENU_ROWS            12

// menu_ctrl state encoding.
`define MENU_STATE_CLOSED    2'd0
`define MENU_STATE_BROWSE    2'd1
`define MENU_STATE_EDIT      2'd2

// Flat display record sent from clk_sys to clk_pixel_2x.  The whole record is
// sampled only in vertical blanking, matching the existing frame-boundary CDC.
`define MENU_DISP_WIDTH      267
`define MD_STATE_OFF         0    // 2 bits
`define MD_CURSOR_OFF        2    // 5 bits
`define MD_WINDOW_OFF        7    // 5 bits
`define MD_VIEW_OFF          12   // 2 bits
`define MD_FLAGS_OFF         14   // 6 bits
`define MD_HIGH_OFF          20   // 16 bits, four BCD digits
`define MD_LOW_OFF           36   // 16 bits
`define MD_WBR_OFF           52   // 16 bits
`define MD_WBG_OFF           68   // 16 bits
`define MD_WBB_OFF           84   // 16 bits
`define MD_GAMMA_OFF         100  // 12 bits, three BCD digits
`define MD_BLACK_OFF         112  // 12 bits

`define MD_FLAG_SPLIT        0
`define MD_FLAG_SHAPE        1
`define MD_FLAG_FREEZE       2
`define MD_FLAG_TEST         3
`define MD_FLAG_MEDIAN       4
`define MD_FLAG_GAMMA        5

// Image2 action slots: no Flash slot changes are exposed in this profile.
`define MENU_ITEM_CAPTURE   5'd1
`define MENU_ITEM_GALLERY   5'd2
`define MENU_ITEM_CLEANUP   5'd16
`define MENU_ITEM_MINIMUM   5'd17
`define MENU_ITEM_SD        5'd18
`define MENU_ITEM_PREV      5'd19
`define MENU_ITEM_NEXT      5'd20
`define MENU_ITEM_DELETE    5'd21
`define MD_CLEANUP_OFF      124
`define MD_MINIMUM_OFF      128
`define MD_SD_OFF           144
`define MD_STAGE_OFF        146
`define MD_EVENT_OFF        150
`define MD_ERROR_OFF        154
`define MD_DELETE_OFF       162
`define MD_GALLERY_OFF      163
`define MD_FILE_OFF         164
`define MD_BUSY_OFF         192
`define MD_SD_COMMAND_OFF   193
`define MD_SD_REASON_OFF    199
`define MD_HEALTH_OFF       203
`endif
