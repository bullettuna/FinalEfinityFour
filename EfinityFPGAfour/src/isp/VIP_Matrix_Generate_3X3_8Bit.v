`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////////
// Frame-aware streaming 3x3 window generator.
//
// Two project-native synchronous shift RAMs keep the implementation in BRAM.
// The row counter prevents data left in those RAMs by the preceding frame from
// reaching the first two rows. Horizontal borders are replicated explicitly;
// no pixel from the next line is ever used as the right-hand neighbour.
//////////////////////////////////////////////////////////////////////////////////

module VIP_Matrix_Generate_3X3_8Bit
#(
    parameter [13:0] IMG_HDISP = 14'd640,
    parameter [13:0] IMG_VDISP = 14'd480,
    parameter integer DATA_WIDTH = 8
)
(
    input                           clk,
    input                           rst_n,
    input                           per_frame_vsync,
    input                           per_frame_href,
    input                           per_frame_hsync,
    input      [DATA_WIDTH-1:0]     per_img_Y,
    output                          matrix_frame_vsync,
    output                          matrix_frame_href,
    output                          matrix_frame_hsync,
    output reg [DATA_WIDTH-1:0]     matrix_p11,
    output reg [DATA_WIDTH-1:0]     matrix_p12,
    output reg [DATA_WIDTH-1:0]     matrix_p13,
    output reg [DATA_WIDTH-1:0]     matrix_p21,
    output reg [DATA_WIDTH-1:0]     matrix_p22,
    output reg [DATA_WIDTH-1:0]     matrix_p23,
    output reg [DATA_WIDTH-1:0]     matrix_p31,
    output reg [DATA_WIDTH-1:0]     matrix_p32,
    output reg [DATA_WIDTH-1:0]     matrix_p33
);

wire [DATA_WIDTH-1:0] previous_row_pixel;
wire [DATA_WIDTH-1:0] two_rows_before_pixel;
reg  [DATA_WIDTH-1:0] current_row_pixel;

Line_Shift_RAM_8Bit #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(11),
    .DATA_DEPTH(IMG_HDISP),
    .DELAY_NUM (0)
) u_previous_row_ram (
    .clk  (clk),
    .rst_n(rst_n),
    .clken(per_frame_href),
    .din  (per_img_Y),
    .dout (previous_row_pixel)
);

Line_Shift_RAM_8Bit #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(11),
    .DATA_DEPTH(IMG_HDISP),
    .DELAY_NUM (1)
) u_two_rows_before_ram (
    .clk  (clk),
    .rst_n(rst_n),
    .clken(per_frame_href),
    .din  (previous_row_pixel),
    .dout (two_rows_before_pixel)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_row_pixel <= {DATA_WIDTH{1'b0}};
    else if (per_frame_href)
        current_row_pixel <= per_img_Y;
end

reg [2:0] per_frame_vsync_r;
reg [2:0] per_frame_href_r;
reg [2:0] per_frame_hsync_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        per_frame_vsync_r <= 3'b000;
        per_frame_href_r  <= 3'b000;
        per_frame_hsync_r <= 3'b000;
    end else begin
        per_frame_vsync_r <= {per_frame_vsync_r[1:0], per_frame_vsync};
        per_frame_href_r  <= {per_frame_href_r[1:0],  per_frame_href};
        per_frame_hsync_r <= {per_frame_hsync_r[1:0], per_frame_hsync};
    end
end

assign matrix_frame_vsync = per_frame_vsync_r[2];
assign matrix_frame_href  = per_frame_href_r[2];
assign matrix_frame_hsync = per_frame_hsync_r[2];

// The extra read clock emits the rightmost pixel while DE is travelling down
// its three-clock timing pipeline.
wire read_frame_href = per_frame_href_r[0] | per_frame_href_r[1];

reg        per_frame_href_d;
reg [13:0] input_row;
reg [13:0] processing_row;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        per_frame_href_d <= 1'b0;
        input_row        <= 14'd0;
        processing_row   <= 14'd0;
    end else begin
        per_frame_href_d <= per_frame_href;
        if (!per_frame_vsync)
            input_row <= 14'd0;
        else if (per_frame_href_d && !per_frame_href)
            input_row <= (input_row < IMG_VDISP - 1'b1) ? input_row + 1'b1 : 14'd0;

        // Capture once at the first pixel and keep the value through the two
        // blanking clocks used to finish the right border.
        if (per_frame_href && !per_frame_href_d)
            processing_row <= input_row;
    end
end

wire [DATA_WIDTH-1:0] vertical_top =
    (processing_row == 14'd0) ? current_row_pixel :
    (processing_row == 14'd1) ? previous_row_pixel : two_rows_before_pixel;
wire [DATA_WIDTH-1:0] vertical_middle =
    (processing_row == 14'd0) ? current_row_pixel : previous_row_pixel;
wire [DATA_WIDTH-1:0] vertical_bottom = current_row_pixel;

reg [13:0] pixel_count;
reg [DATA_WIDTH-1:0] top_d0, top_d1;
reg [DATA_WIDTH-1:0] middle_d0, middle_d1;
reg [DATA_WIDTH-1:0] bottom_d0, bottom_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pixel_count <= 14'd0;
        top_d0 <= {DATA_WIDTH{1'b0}};
        top_d1 <= {DATA_WIDTH{1'b0}};
        middle_d0 <= {DATA_WIDTH{1'b0}};
        middle_d1 <= {DATA_WIDTH{1'b0}};
        bottom_d0 <= {DATA_WIDTH{1'b0}};
        bottom_d1 <= {DATA_WIDTH{1'b0}};
        matrix_p11 <= {DATA_WIDTH{1'b0}};
        matrix_p12 <= {DATA_WIDTH{1'b0}};
        matrix_p13 <= {DATA_WIDTH{1'b0}};
        matrix_p21 <= {DATA_WIDTH{1'b0}};
        matrix_p22 <= {DATA_WIDTH{1'b0}};
        matrix_p23 <= {DATA_WIDTH{1'b0}};
        matrix_p31 <= {DATA_WIDTH{1'b0}};
        matrix_p32 <= {DATA_WIDTH{1'b0}};
        matrix_p33 <= {DATA_WIDTH{1'b0}};
    end else if (read_frame_href) begin
        pixel_count <= (pixel_count < IMG_HDISP) ? pixel_count + 1'b1 : 14'd0;
        {top_d1, top_d0}       <= {top_d0, vertical_top};
        {middle_d1, middle_d0} <= {middle_d0, vertical_middle};
        {bottom_d1, bottom_d0} <= {bottom_d0, vertical_bottom};

        if (pixel_count == 14'd0) begin
            {matrix_p11, matrix_p12, matrix_p13} <= {3*DATA_WIDTH{1'b0}};
            {matrix_p21, matrix_p22, matrix_p23} <= {3*DATA_WIDTH{1'b0}};
            {matrix_p31, matrix_p32, matrix_p33} <= {3*DATA_WIDTH{1'b0}};
        end else if (pixel_count == 14'd1) begin
            {matrix_p11, matrix_p12, matrix_p13} <=
                {top_d0, top_d0, vertical_top};
            {matrix_p21, matrix_p22, matrix_p23} <=
                {middle_d0, middle_d0, vertical_middle};
            {matrix_p31, matrix_p32, matrix_p33} <=
                {bottom_d0, bottom_d0, vertical_bottom};
        end else if (pixel_count == IMG_HDISP) begin
            {matrix_p11, matrix_p12, matrix_p13} <= {top_d1, top_d0, top_d0};
            {matrix_p21, matrix_p22, matrix_p23} <= {middle_d1, middle_d0, middle_d0};
            {matrix_p31, matrix_p32, matrix_p33} <= {bottom_d1, bottom_d0, bottom_d0};
        end else begin
            {matrix_p11, matrix_p12, matrix_p13} <= {top_d1, top_d0, vertical_top};
            {matrix_p21, matrix_p22, matrix_p23} <= {middle_d1, middle_d0, vertical_middle};
            {matrix_p31, matrix_p32, matrix_p33} <= {bottom_d1, bottom_d0, vertical_bottom};
        end
    end else begin
        pixel_count <= 14'd0;
    end
end

endmodule
