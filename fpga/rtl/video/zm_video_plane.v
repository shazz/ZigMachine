// One plane pass over one raster line: work out the line's geometry from the
// plane's latched mode (video.zig renderPlane*), fetch its source bytes, paint.
//
//   mode        lines      source row          columns   into the raster
//   normal      40..239    py - 40             320       doubled from x 80
//   scroll      40..239    py - 40, + HSCROLL  320       doubled from x 80
//   fullscreen  0..279     py, (c + hs) % st   400       doubled from x 0
//   overscan    0..279     py                  400       doubled, borders earned
//   medium      40..239    py - 40             640/320   1:1 or doubled from x 80
//   medium ovs  0..279     py (stride >= 800)  800/400   1:1 or doubled from x 0
// Any other mode is fullscreen when the stride is 400 and normal otherwise
// (video.zig's back-compat rule). Medium re-reads RESOLUTION per line: a
// RES_MEDIUM line is 1:1, anything else doubled.
`default_nettype none

module zm_video_plane (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [8:0]  py,
    input  wire [7:0]  mode,           // latched (zm_video_latch)
    input  wire [31:0] base,
    input  wire [15:0] stride, hpos, hs, seen,
    input  wire [7:0]  seed,
    input  wire        top_open, bot_open,
    input  wire [7:0]  res,            // live: REG_RESOLUTION
    input  wire [15:0] hs_live,        // live: this plane's HSCROLL
    input  wire [15:0] flicker,        // live: REG_RES_FLICKER
    output reg         upd,
    output reg         upd_top, upd_bot,
    output reg         fetch_start,
    output reg  [31:0] fetch_addr,
    output reg  [10:0] fetch_len,
    input  wire        fetch_done,
    output reg         paint_start,
    output reg  [9:0]  ncols, dst0,
    output reg         single, wrap, ov, band, band_open, hit, flick,
    output reg  [15:0] s0,
    output reg  [7:0]  nbase,
    input  wire        paint_done,
    output reg         done
);
`include "zm_video_memmap.vh"

    localparam [2:0] NORMAL = 3'd0, FS = 3'd1, SCROLL = 3'd2, MED = 3'd3, OVS = 3'd4;
    wire [2:0] m = (mode >= 8'd1 && mode <= 8'd4) ? mode[2:0] : (stride == ZM_STRIDE_FULLSCREEN ? FS : NORMAL);
    wire vis = py >= ZM_RASTER_BORDER_Y && py < ZM_RASTER_BORDER_Y + ZM_HEIGHT;
    wire ovm = stride >= ZM_RASTER_WIDTH;
    wire phys = m == FS || m == OVS || (m == MED && ovm);
    wire [8:0] row = phys ? py : py - ZM_RASTER_BORDER_Y[8:0];
    wire med_line = m == MED && res == ZM_RES_MEDIUM;
    wire [10:0] med_len = med_line ? (ovm ? 11'd800 : 11'd640) : (ovm ? 11'd400 : 11'd320);
    // A fullscreen row longer than the fetch buffer asks for 2047 bytes, which
    // the fetcher refuses and flags (`overflow`) instead of wrapping silently.
    wire [10:0] fs_len = stride > 16'd1021 ? 11'h7FF : stride[10:0];
    wire [10:0] len = m == FS ? fs_len : m == OVS ? 11'd400 : m == MED ? med_len : 11'd320;
    wire [31:0] addr = base + row * stride + (m == SCROLL ? {16'd0, hs_live} : 32'd0);
    // Overscan: did this line's HBL flicker, and on the magic column?
    wire flk = flicker != seen;
    wire [15:0] dx = hpos > ZM_OVERSCAN_MAGIC_X ? hpos - ZM_OVERSCAN_MAGIC_X : ZM_OVERSCAN_MAGIC_X - hpos;
    wire hit_now = flk && dx <= ZM_OVERSCAN_X_TOL;
    wire top = py < ZM_RASTER_BORDER_Y, bot = !top && !vis;

    localparam [1:0] IDLE = 2'd0, DIV = 2'd1, FETCH = 2'd2, PAINT = 2'd3;
    reg [1:0] st = IDLE;
    reg [4:0] k;                       // fullscreen: hs mod stride, one bit a clock
    reg [15:0] num;
    wire [16:0] rem_t = {s0, num[15]};

    // The pass's geometry, registered as it starts: the registers it came from
    // may change under the pass once the next handler runs.
    always @(posedge clk) if (st == IDLE && start) begin
        fetch_addr <= addr;
        fetch_len <= len;
        ncols <= m == FS ? ZM_PHYSICAL_WIDTH[9:0] : len[9:0];
        dst0 <= phys ? 10'd0 : ZM_RASTER_BORDER_X[9:0];
        {single, wrap, ov, band, hit, flick} <= {med_line, m == FS, m == OVS, !vis, hit_now, flk};
        band_open <= (top && (top_open || hit_now)) || (bot && (bot_open || hit_now));
        nbase <= py[7:0] * 8'd101 + seed * 8'd7;
    end

    // Fullscreen: s0 = hs % stride by restoring division, one bit a clock.
    always @(posedge clk)
        if (st == IDLE) {s0, num, k} <= {16'd0, hs, 5'd16};
        else if (st == DIV && k != 5'd0) begin
            k <= k - 5'd1;
            num <= num << 1;
            s0 <= rem_t >= {1'b0, stride} ? rem_t[15:0] - stride : rem_t[15:0];
        end

    always @(posedge clk) begin
        {upd, upd_top, upd_bot, fetch_start, paint_start, done} <= 6'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE: if (start) begin
                upd <= 1'b1;
                upd_top <= m == OVS && top && hit_now;
                upd_bot <= m == OVS && bot && hit_now;
                if (!(phys || vis)) done <= 1'b1;   // nothing of this plane on this line
                else if (m == FS) st <= DIV;
                else {st, fetch_start} <= {FETCH, 1'b1};
            end
            DIV: if (k == 5'd0) {st, fetch_start} <= {FETCH, 1'b1};
            FETCH: if (fetch_done) {st, paint_start} <= {PAINT, 1'b1};
            PAINT: if (paint_done) {st, done} <= {IDLE, 1'b1};
        endcase
    end
endmodule

`default_nettype wire
