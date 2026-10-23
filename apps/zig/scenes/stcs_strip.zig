// --------------------------------------------------------------------------
// STCS STARGOOSE — the scroller strip copied onto plane 1 in each period's shape.
//
// Each shape moves whole 16-pixel column groups (x / 16) by whole lines. The
// CPU used to copy it row by row (8,160 word stores a frame, each a blocking
// DDR write on the board); CHISEL now copies each (write, column group) as ONE
// rectangle from a source strip in a disabled plane (stcs_scratch.zig): straight
// (N), upside down (F), or one line in two (G, FG: keyed, the KEY rows between
// skipped). A shape whose lines do not depend on the group is one full-width blit;
// the big fonts' second wave (stcs_wave.zig) makes theirs one blit per run of
// groups at the same offset (18 runs: 36 blits in big_font, 18 interlaced).
//
// Byte-identical to the row loops: a plane address is one (line, x) pair, so
// only writes of the same column group meet, and where two writes of a group
// land on one line the later one in the old order (strip row y, then write k)
// must win. The shapes below were checked line by line: only `inverted` (group
// 19, line 138: a tie, k = 1 wins), `interlaced_steam` (k = 1 always later) and
// `inverted_mirror` overlap; the last one changes winner at line 117/118, so the
// rows of write 0 below line 118 are copied again after write 1. Lines past
// 199 (the big font's lowest, wave included) are clipped by CHISEL: the CPU wrote them into the
// next plane's memory, which nothing shows.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const sc = @import("stcs_scratch.zig");
const logo = @import("stcs_logo.zig");
const wave = @import("stcs_wave.zig");

const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;
const GROUPS: i16 = sc.W / 16;
const H: i16 = sc.GH;

pub const Period = enum { threelines, big_font, interlaced_mirror, interlaced_big_font, inverted, interlaced_steam, inverted_mirror };

/// The strips a period copies from (built before draw).
pub fn needs(period: Period) []const sc.Kind {
    return switch (period) {
        .threelines => &.{.n},
        .big_font, .interlaced_big_font => &.{.g},
        .interlaced_mirror => &.{ .n, .fg },
        .interlaced_steam => &.{ .n, .g },
        .inverted, .inverted_mirror => &.{ .n, .f },
    };
}

const Copy = struct {
    c: *Blitter,
    dst: *LogicalFB,
    s: *sc.Scratch,

    /// Strip `k` rows y0..y0+h of group g (or all groups: g = null) onto line `line` + y0.
    fn rows(self: Copy, k: sc.Kind, g: ?i16, line: i16, y0: i16, h: i16) void {
        self.span(k, g orelse 0, if (g != null) 1 else GROUPS, line, y0, h);
    }
    /// The same for groups g .. g + n - 1 at once.
    fn span(self: Copy, k: sc.Kind, g: i16, n: i16, line: i16, y0: i16, h: i16) void {
        if (h <= 0) return;
        const x: i16 = g * 16;
        const w: u16 = @intCast(n * 16);
        const src = &self.s.src[@intFromEnum(k)];
        if (k == .g or k == .fg) {
            self.c.bob(self.dst, x, line + y0, src, x, y0, w, @intCast(h), sc.KEY);
        } else if (line + y0 < logo.ROWS) {
            // Over the logo's last rows (stcs_logo.zig): its pixels show where
            // the strip's are 0. Only interlaced_mirror's write k0 of groups
            // 16..19 gets here, the first write to those pixels this frame, onto
            // a band holding only the logo and 0: keying 0 changes nothing else.
            self.c.bob(self.dst, x, line + y0, src, x, y0, w, @intCast(h), 0);
        } else {
            self.c.blitCopy(self.dst, x, line + y0, src, x, y0, w, @intCast(h));
        }
    }
    fn all(self: Copy, k: sc.Kind, g: ?i16, line: i16) void {
        const h: i16 = if (k == .g or k == .fg) 2 * H - 1 else H;
        self.rows(k, g, line, 0, h);
    }
};

/// Draw the strips onto `dst` as `period` does; `yp` is the big fonts' bounce.
pub fn draw(c: *Blitter, dst: *LogicalFB, s: *sc.Scratch, period: Period, yp: i16) void {
    const cp = Copy{ .c = c, .dst = dst, .s = s };
    var g: i16 = 0;
    switch (period) {
        // lines 84 + y, + 78, + 39
        .threelines => for ([_]i16{ 84, 84 + 2 * H + 10, 84 + H + 5 }) |l| cp.all(.n, null, l),
        // 78 + yp + wave[g] + 2y + k: G at 2y, k = 0 and 1; one blit per run of
        // groups with the same wave offset (stcs_wave.zig). k0 and k1 fill
        // opposite lines of a group and groups never meet: order cannot matter.
        .big_font => for (wave.runs) |r| {
            cp.span(.g, r.g, r.n, 78 + yp + r.off, 0, 2 * H - 1);
            cp.span(.g, r.g, r.n, 79 + yp + r.off, 0, 2 * H - 1);
        },
        // the interlaced font steps two lines per wave step (CONFO.S `160*2`)
        .interlaced_big_font => for (wave.runs) |r| cp.span(.g, r.g, r.n, 78 + yp + 2 * r.off, 0, 2 * H - 1),
        // k0: 88 + y - g; k1: 88 + 39 + 2H - 2y - g = (129 - g) + 2(33 - y): FG
        .interlaced_mirror => while (g < GROUPS) : (g += 1) {
            cp.all(.n, g, 88 - g);
            cp.all(.fg, g, 129 - g);
        },
        // k0: 164 + y; k1: 76 + 2y + 2g (G), always later than k0 where they meet
        .interlaced_steam => {
            cp.all(.n, null, 164);
            while (g < GROUPS) : (g += 1) cp.all(.g, g, 76 + 2 * g);
        },
        // k0: 86 + y + g; k1: 156 + H - y - g = (157 - g) + (33 - y): F
        .inverted => while (g < GROUPS) : (g += 1) {
            cp.all(.n, g, 86 + g);
            cp.all(.f, g, 157 - g);
        },
        .inverted_mirror => {
            while (g < GROUPS) : (g += 1) invertedMirror(cp, g);
            cp.all(.n, null, 160); // k2: 160 + y
        },
    }
}

// left (g < 10, h = g): k0 90 + y - h, k1 110 + (H - y) + h = (111 + h) + (33 - y)
// right (h = g - 10):   k0 80 + y + h, k1 120 + (H - y) - h = (121 - h) + (33 - y)
// Where k0 and k1 share a line L, the larger strip row wins (k1 on a tie): that is
// k1 for L <= 117 and k0 for L >= 118, on both sides.
fn invertedMirror(cp: Copy, g: i16) void {
    const left = g < 10;
    const h = if (left) g else g - 10;
    const l0: i16 = if (left) 90 - h else 80 + h;
    const l1: i16 = if (left) 111 + h else 121 - h;
    cp.all(.n, g, l0);
    cp.all(.f, g, l1);
    // k0's rows on lines 118 .. its last, where k1 also wrote, go back on top
    const top: i16 = @max(118, l1);
    const end: i16 = @min(l0 + H, l1 + H); // exclusive
    cp.rows(.n, g, l0, top - l0, end - top);
}
