// Painter: turns one fetched plane line into line-buffer writes, one column a
// clock, through a 4-stage pipeline:
//   0  column c -> byte index -> fetch-buffer read     (and the overscan choice)
//   1  byte -> palette index (fetched, or overscan noise) -> palette read
//   2  palette RGBA held; a 565 pixel into the fade's multipliers (zm_video_tcfade.v)
//   3  RGBA -> line buffer
// A column is one low-res pixel written as a doubled pair, or one medium pixel
// (`single`) written into one half of a pair. Columns map to the raster from
// `dst0` (raster pixels). Fullscreen (`wrap`) reads source byte (c + s0) mod
// stride, as video.zig's `(lx + hs) % stride`.
//
// True colour (`tc`, HW 1.15.0): column c is the half-word at byte 2c, expanded 565 -> RGBA by
// bit replication (machine/video_tc.zig expand) in place of the palette's answer, a clock behind
// like it. The line address is even (zm_video_plane.v), so `align` is 0 or 2. HW 1.16.0 fades it
// (zm_video_tcfade.v) by the plane's TC_FADE / TC_OFS registers, latched at `start`: the line's
// copper record and handler have run by then, and nothing writes them during a pass.
//
// Overscan (`ov`), video.zig renderPlaneOverscan row for row: the 320-wide window
// of a visible line is always drawn; outside it a column comes from the buffer
// when its border is open (`band_open` in a band, `hit` on a visible line),
// is noise when the line flickered but missed, and is not written otherwise.
`default_nettype none

module zm_video_paint (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [9:0]  ncols,
    input  wire [1:0]  align,
    input  wire        single,
    input  wire [9:0]  dst0,
    input  wire        wrap,
    input  wire        tc,             // a 565 line: byte index 2c, the half-word expanded, no palette
    input  wire [7:0]  fade,           // the plane's TC_FADE: coef [4:0], toward white [5]
    input  wire [23:0] ofs,            // its TC_OFS_B, _G, _R
    input  wire [15:0] stride,
    input  wire [15:0] s0,
    input  wire        ov, band, band_open, hit, flick,
    input  wire [7:0]  nbase,          // noise index of column 0: y*101 + seed*7
    output wire [7:0]  fb_raddr,
    input  wire [31:0] fb_rdata,
    output wire [7:0]  pal_raddr,
    input  wire [31:0] pal_rdata,
    output reg         lb_we_lo, lb_we_hi,
    output reg  [8:0]  lb_addr,
    output reg  [31:0] lb_data,
    output reg         done
);
`include "zm_video_memmap.vh"

    localparam integer L = ZM_HORIZONTAL_BORDERS_WIDTH, R = L + ZM_WIDTH;
    reg        run = 1'b0;
    reg [9:0]  c;
    reg [15:0] s;
    reg [7:0]  noise;                       // noise index of column c (+37 a column)
    // The buffer index align + (wrap ? s : tc ? 2c : c), kept in a register stepped with c and s (from c and
    // s's next values): the add and the select sat between c and the fetch buffer's address
    // (comp -0.77 ns, board_combo7). align and wrap are zm_video_plane's, written only at its `go`,
    // and it stays in PAINT until this paint is done, so they hold from `start` to the last column.
    reg [10:0] bi;
    wire [9:0]  c_n = rst || start ? 10'd0 : run ? c + 10'd1 : c;
    wire [15:0] s_n = rst || start ? s0 : run ? (s + 16'd1 == stride ? 16'd0 : s + 16'd1) : s;
    always @(posedge clk) bi <= {9'd0, align} + (wrap ? s_n[10:0] : tc ? {c_n, 1'b0} : {1'b0, c_n});
    wire inner = !band && c >= L && c < R;
    wire open_c = band ? band_open : hit;
    wire wr0 = !ov || inner || open_c || flick;
    wire nz0 = ov && !(inner || open_c);
    wire [9:0] px0 = single ? dst0 + c : {dst0[9:1] + c[8:0], 1'b0};
    assign fb_raddr = bi[9:2];

    // Stage registers: 1 = fetch-buffer data valid, 2 = palette data valid.
    reg        v1, wr1, nz1, v2, wr2;
    reg [1:0]  sel1;
    reg [7:0]  n1;
    reg [9:0]  px1, px2;
    reg        single1, single2;
    wire [7:0] byte1 = fb_rdata[sel1*8 +: 8];
    wire [15:0] half1 = fb_rdata[sel1[1]*16 +: 16];
    reg  [15:0] h2;                         // the 565 pixel, a clock behind like the palette's answer
    reg  [5:0]  fm;                         // the fade, latched at start: 32 - (coef + coef >> 4)
    reg         fw;
    reg  [23:0] fo;
    always @(posedge clk) if (start) begin
        fm <= 6'd32 - ({1'b0, fade[4:0]} + {5'd0, fade[4]});
        fw <= fade[5];
        fo <= ofs;
    end
    wire [31:0] tc_px;
    zm_video_tcfade u_fade (.clk(clk), .px(h2), .m(fm), .white(fw), .ofs(fo), .rgba(tc_px));
    reg         v3, wr3, single3;
    reg  [9:0]  px3;
    reg  [31:0] pal3;
    assign pal_raddr = nz1 ? n1 : byte1;

    always @(posedge clk) begin
        c <= c_n;
        s <= s_n;
        if (rst || start) begin
            run <= start;
            noise <= nbase;
        end else if (run) begin
            noise <= noise + 8'd37;
            if (c + 10'd1 == ncols) run <= 1'b0;
        end
    end

    always @(posedge clk) begin
        v1 <= run && !rst && !start;
        {wr1, nz1, sel1, n1, px1, single1} <= {wr0, nz0, bi[1:0], noise, px0, single};
        {v2, wr2, px2, single2} <= {v1, wr1, px1, single1};
        {v3, wr3, px3, single3} <= {v2, wr2, px2, single2};
        h2 <= half1;
        pal3 <= pal_rdata;
        lb_we_lo <= v3 && wr3 && !(single3 && px3[0]);
        lb_we_hi <= v3 && wr3 && !(single3 && !px3[0]);
        lb_addr <= px3[9:1];
        lb_data <= tc ? tc_px : pal3;
        done <= v3 && !v2;                  // the last column left stage 3
    end
endmodule

`default_nettype wire
