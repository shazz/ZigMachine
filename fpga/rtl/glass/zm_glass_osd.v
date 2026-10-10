// The OSD: a text window laid over the finished picture, MiSTer-style, on the
// pixel stream between the scanout and the DVI encoder. It sits AFTER the
// machine's mixer on purpose: the menu must show whatever the cart CPU is
// doing, including nothing (held in reset), and must never touch the pixels
// the scene-hash oracle checks.
//
// 32 x 16 characters of the machine's own 8x8 system font, drawn 2x, its
// top-left at (x0, y0) on the 800x600 output (REG_OSD_POS; the reset value
// centres it, gen/glass_map.vh: OSD_*). A character word is {inverse, glyph};
// ink is FG, paper is BG, swapped when inverse. Under `stats` (CTRL_OSD_STATS,
// the F11 frame-rate overlay) a cell holding a plain space is transparent: the
// picture shows through everywhere but the text.
//
// The text RAM is written in the register block's clock (`wclk`) and read in
// the pixel clock: a two-clock RAM, as the display buffers cross. `en`,
// `stats`, `fg`, `bg`, `x0` and `y0` are quasi-static (the ARM sets them, then
// a human looks): the flags and the position pass two flip-flops, the colours
// none, and any of them may tear for one frame when it changes.
//
// Position comes from the stream itself: x counts DE clocks, y counts lines
// that had DE, and a rising VSYNC restarts the frame. Every output is three
// clocks behind its input (text RAM, font ROM, pixel), RGB and syncs alike.
`default_nettype none

module zm_glass_osd (
    input  wire        clk,                // pixel clock
    input  wire        rst,
    input  wire        en,                 // async: synchronised here
    input  wire        stats,              // async: plain spaces are transparent
    input  wire [23:0] fg, bg,             // 0xRRGGBB, quasi-static
    input  wire [10:0] x0,                 // the window's top-left, quasi-static
    input  wire [9:0]  y0,
    input  wire        wclk,
    input  wire        we,
    input  wire [8:0]  waddr,
    input  wire [8:0]  wdata,
    input  wire [7:0]  r, g, b,
    input  wire        de, hsync, vsync,
    output reg  [7:0]  r_o, g_o, b_o,
    output reg         de_o, hs_o, vs_o
);
`include "glass_map.vh"

    (* ASYNC_REG = "TRUE" *) reg [1:0] en_s = 2'b00, st_s = 2'b00;
    (* ASYNC_REG = "TRUE" *) reg [10:0] x0_a = 11'd0, x0_s = 11'd0;
    (* ASYNC_REG = "TRUE" *) reg [9:0]  y0_a = 10'd0, y0_s = 10'd0;
    always @(posedge clk) begin
        {en_s, st_s} <= {en_s[0], en, st_s[0], stats};
        {x0_s, x0_a, y0_s, y0_a} <= {x0_a, x0, y0_a, y0};
    end

    // --- where the beam is
    reg [10:0] x = 11'd0;
    reg [9:0]  y = 10'd0;
    reg        de_q = 1'b0, vs_q = 1'b0;
    always @(posedge clk) begin
        de_q <= de;
        vs_q <= vsync;
        if (rst || (vsync && !vs_q)) {x, y} <= 21'd0;
        else if (de) x <= x + 11'd1;
        else if (de_q) {x, y} <= {11'd0, y + 10'd1};
    end

    // One bit wider than the beam, so a beam left of or above the window
    // borrows (top bit set) instead of wrapping into it.
    wire [11:0] ox = {1'b0, x} - {1'b0, x0_s};
    wire [10:0] oy = {1'b0, y} - {1'b0, y0_s};
    wire inside = de && !ox[11] && ox[10:0] < ZG_OSD_WIDTH[10:0] && !oy[10] && oy[9:0] < ZG_OSD_HEIGHT[9:0];

    // --- stage 1: the character under the beam
    wire [8:0] text_q;
    zm_video_dcram #(.AW(9), .DW(9)) u_text (.wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata),
        .rclk(clk), .raddr({oy[7:4], ox[8:4]}), .rdata(text_q));
    reg [2:0] row1, col1;
    reg in1;
    reg [23:0] px1;
    reg [2:0] sync1;
    always @(posedge clk) begin
        {row1, col1, in1} <= {oy[3:1], ox[3:1], inside};
        {px1, sync1} <= {r, g, b, de, hsync, vsync};
    end

    // --- stage 2: its glyph row
    reg [7:0] font [0:2047];
`include "glass_font.vh"
    reg [7:0] glyph_row;
    reg [2:0] col2;
    reg in2, inv2, clear2;
    reg [23:0] px2;
    reg [2:0] sync2;
    always @(posedge clk) begin
        glyph_row <= font[{text_q[7:0], row1}];
        {col2, in2, inv2} <= {col1, in1, text_q[8]};
        clear2 <= st_s[1] && text_q == 9'h020;   // a plain space; an inverse one stays a block
        {px2, sync2} <= {px1, sync1};
    end

    // --- stage 3: the pixel
    wire ink = glyph_row[3'd7 - col2] ^ inv2;
    always @(posedge clk) begin
        {r_o, g_o, b_o} <= (in2 && en_s[1] && !clear2) ? (ink ? fg : bg) : px2;
        {de_o, hs_o, vs_o} <= sync2;
    end
endmodule

`default_nettype wire
