`timescale 1ns/1ps
`include "src/ui/menu_defs.vh"

// Verifies that the text overlay changes only RGB inside the menu rectangle
// and that VS/HS/DE/RGB all have exactly the same three-clock delay.  The
// generated frame is 640x240 with a 30x12 character menu, so the whole menu
// fits inside the active area.
module menu_text_render_tb;
localparam WIDTH  = 640;
localparam HEIGHT = 360;
localparam HTOTAL = 800;
localparam VTOTAL = 380;

localparam [23:0] BACKDROP = 24'h101020;
localparam [23:0] TEXT     = 24'hFFFFFF;
localparam [23:0] SELECT   = 24'hFFFF00;
localparam [23:0] EDIT     = 24'h00FFFF;

reg clk = 0;
always #5 clk = ~clk;
reg rst_n = 0;

reg [10:0] hc = 0, vc = 0;
reg vs = 0, hs = 0, de = 0;
reg [23:0] rgb = 0;
wire active_pixel = (hc >= 100) && (hc < 100+WIDTH) &&
                    (vc >= 3) && (vc < 3+HEIGHT);

always @(posedge clk) begin
    if (hc == HTOTAL-1) begin
        hc <= 0;
        vc <= (vc == VTOTAL-1) ? 0 : vc + 1;
    end else begin
        hc <= hc + 1;
    end
    hs <= (hc < 44);
    vs <= (vc >= 2);
    de <= active_pixel;
    if (active_pixel)
        rgb <= {hc[7:0], vc[7:0], 8'h5A};
    else
        rgb <= 24'd0;
end

reg [`MENU_DISP_WIDTH-1:0] disp = 0;
wire out_vs, out_hs, out_de;
wire [23:0] out_rgb;

menu_text_render #(.H_DISP(WIDTH), .V_DISP(HEIGHT)) dut (
    .clk(clk), .rst_n(rst_n),
    .in_vsync(vs), .in_hsync(hs), .in_href(de), .in_rgb(rgb),
    .disp(disp),
    .out_vsync(out_vs), .out_hsync(out_hs), .out_href(out_de), .out_rgb(out_rgb)
);

// Input history: hist2 is the input from three clocks ago, matching the DUT.
reg [26:0] hist0 = 0, hist1 = 0, hist2 = 0;
always @(posedge clk) begin
    hist0 <= {vs, hs, de, rgb};
    hist1 <= hist0;
    hist2 <= hist1;
end

// Delayed x/y, replicated from the renderer's input-side counters.
reg [11:0] tx = 0, ty = 0;
reg tde_d = 0;
always @(posedge clk) begin
    tde_d <= de;
    if (!vs)
        ty <= 0;
    else if (!de && tde_d)
        ty <= ty + 1;
    if (!de)
        tx <= 0;
    else
        tx <= tx + 1;
end
reg [11:0] dx0 = 0, dx1 = 0, dx2 = 0;
reg [11:0] dy0 = 0, dy1 = 0, dy2 = 0;
always @(posedge clk) begin
    dx0 <= tx; dx1 <= dx0; dx2 <= dx1;
    dy0 <= ty; dy1 <= dy0; dy2 <= dy1;
end

integer frame_count = 0;
reg vs_d = 0;
always @(posedge clk) begin
    vs_d <= vs;
    if (vs && !vs_d)
        frame_count <= frame_count + 1;
end

reg checking = 0;
integer errs = 0;
integer region_count = 0;
integer backdrop_count = 0;
integer ink_count = 0;
integer outside_count = 0;
integer marker_ink = 0;
integer bracket_ink = 0;

wire out_in_rect = hist2[24] &&
                   (dx2 >= 12'd8) && (dx2 < 12'd548) &&
                   (dy2 >= 12'd8) && (dy2 < 12'd296);
wire out_region = out_in_rect && (disp[`MD_STATE_OFF +: 2] != `MENU_STATE_CLOSED);
wire out_is_ink = (out_rgb == TEXT) || (out_rgb == SELECT) || (out_rgb == EDIT);
wire marker_cell = (dx2 >= 12'd8) && (dx2 < 12'd23) &&
                   (dy2 >= 12'd32) && (dy2 < 12'd54);
wire bracket_cell = (dx2 >= 12'd170) && (dx2 < 12'd186) &&
                    (dy2 >= 12'd176) && (dy2 < 12'd198);

always @(negedge clk) begin
    if (rst_n && checking) begin
        if ({out_vs, out_hs, out_de} !== hist2[26:24]) begin
            errs = errs + 1;
            if (errs < 8)
                $display("FAIL sync delay out=%b%b%b hist=%b%b%b",
                         out_vs, out_hs, out_de, hist2[26], hist2[25], hist2[24]);
        end
        if (out_region) begin
            region_count = region_count + 1;
            if (out_rgb == BACKDROP)
                backdrop_count = backdrop_count + 1;
            else if (out_is_ink)
                ink_count = ink_count + 1;
            else begin
                errs = errs + 1;
                if (errs < 8)
                    $display("FAIL menu colour %h at delayed (%0d,%0d)", out_rgb, dx2, dy2);
            end
            if (marker_cell && out_is_ink)
                marker_ink = marker_ink + 1;
            if (bracket_cell && out_is_ink)
                bracket_ink = bracket_ink + 1;
        end else begin
            outside_count = outside_count + 1;
            if (out_rgb !== hist2[23:0]) begin
                errs = errs + 1;
                if (errs < 8)
                    $display("FAIL outside menu at delivered (%0d,%0d): out=%h in=%h",
                             dx2, dy2, out_rgb, hist2[23:0]);
            end
        end
    end
end

task set_disp;
    input [1:0] st;
    input [4:0] cur;
    input [4:0] win;
    input [1:0] vw;
    input [5:0] flags;
    input [15:0] hi, lo, wr, wg, wb;
    input [11:0] gm, bl;
    begin
        disp = 0;
        disp[`MD_STATE_OFF  +: 2]  = st;
        disp[`MD_CURSOR_OFF +: 5]  = cur;
        disp[`MD_WINDOW_OFF +: 5]  = win;
        disp[`MD_VIEW_OFF   +: 2]  = vw;
        disp[`MD_FLAGS_OFF  +: 6]  = flags;
        disp[`MD_HIGH_OFF   +: 16] = hi;
        disp[`MD_LOW_OFF    +: 16] = lo;
        disp[`MD_WBR_OFF    +: 16] = wr;
        disp[`MD_WBG_OFF    +: 16] = wg;
        disp[`MD_WBB_OFF    +: 16] = wb;
        disp[`MD_GAMMA_OFF  +: 12] = gm;
        disp[`MD_BLACK_OFF  +: 12] = bl;
    end
endtask

task clear_counts;
    begin
        region_count = 0;
        backdrop_count = 0;
        ink_count = 0;
        outside_count = 0;
        marker_ink = 0;
        bracket_ink = 0;
        errs = 0;
    end
endtask

initial begin
    if ($test$plusargs("dump")) begin
        $dumpfile("menu_text_render.vcd");
        $dumpvars(0, menu_text_render_tb);
    end
    repeat (5) @(posedge clk);
    rst_n = 1;

    // Phase 1: menu closed.  Every pixel must be the input delayed by 3.
    wait (frame_count >= 2);
    clear_counts;
    checking = 1;
    wait (frame_count >= 4);
    checking = 0;
    if (errs != 0) $fatal(1, "FAIL closed menu changed %0d pixels", errs);
    if (outside_count < 10000) $fatal(1, "FAIL closed phase saw only %0d pixels", outside_count);
    $display("PASS closed menu is a pure three-clock delay (%0d pixels)", outside_count);

    // Phase 2: BROWSE, cursor on VIEW.  Only the menu rectangle may change.
    @(negedge vs);
    set_disp(`MENU_STATE_BROWSE, 5'd0, 5'd0, 2'd2, 6'b110000,
             16'h0045, 16'h0022, 16'h0335, 16'h0248, 16'h0280, 12'h042, 12'h096);
    repeat (4) @(posedge clk);
    clear_counts;
    checking = 1;
    wait (frame_count >= 6);
    checking = 0;
    if (errs != 0) $fatal(1, "FAIL BROWSE overlay changed %0d pixels outside/inside", errs);
    if (region_count < 150000) $fatal(1, "FAIL menu rectangle not exercised: %0d", region_count);
    if (backdrop_count == 0) $fatal(1, "FAIL no menu backdrop pixels");
    if (ink_count == 0) $fatal(1, "FAIL no menu text pixels");
    if (marker_ink < 60) $fatal(1, "FAIL selected-row marker missing (%0d)", marker_ink);
    $display("PASS BROWSE overlay: %0d menu pixels, %0d backdrop, %0d ink, %0d marker",
             region_count, backdrop_count, ink_count, marker_ink);

    // Phase 3: EDIT on CANNY H.  The brackets must be visible.
    @(negedge vs);
    set_disp(`MENU_STATE_EDIT, 5'd6, 5'd0, 2'd2, 6'b110000,
             16'h0045, 16'h0022, 16'h0335, 16'h0248, 16'h0280, 12'h042, 12'h096);
    repeat (4) @(posedge clk);
    clear_counts;
    checking = 1;
    wait (frame_count >= 8);
    checking = 0;
    if (errs != 0) $fatal(1, "FAIL EDIT overlay changed %0d pixels", errs);
    if (bracket_ink < 90) $fatal(1, "FAIL EDIT brackets missing (%0d)", bracket_ink);
    $display("PASS EDIT overlay: %0d bracket pixels", bracket_ink);

    // Phase 4: close again; the same three-clock path must be transparent.
    @(negedge vs);
    set_disp(`MENU_STATE_CLOSED, 5'd0, 5'd0, 2'd0, 6'b000000,
             16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 12'h000, 12'h000);
    repeat (4) @(posedge clk);
    clear_counts;
    checking = 1;
    wait (frame_count >= 10);
    checking = 0;
    if (errs != 0) $fatal(1, "FAIL reopen/close changed %0d pixels", errs);
    $display("PASS menu close is transparent again (%0d pixels)", outside_count);

    $display("PASS menu_text_render: fixed three-clock VS/HS/DE/RGB alignment");
    $finish;
end

initial begin
    #50_000_000;
    $fatal(1, "FAIL timeout");
end
endmodule
