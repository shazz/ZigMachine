// --------------------------------------------------------------------------
// The squashed dragonball sprite, built ONCE a frame and stamped six times by
// CHISEL. The six balls share one squash (sx, sy) and sit on whole pixels
// (cx = 40 + 64 i, cy rounded), so the inverse map from a destination pixel to
// a ball texel is the same for all six: resample once on the CPU, then six
// colour-keyed CHISEL copies (index 0 = transparent) instead of six CPU
// resamples (~6x fewer CPU stores on the board).
// --------------------------------------------------------------------------
const gm = @import("dragonball_math.zig");
const fixsin = @import("fixsin.zig");
// Fixed point since 2026-10-25 (no float a frame on ZIGGY): scales in Q16, angles u32 turns.
const C: i32 = 32; // gm.CENTER

const BS = gm.BALL_SIZE; // 64
// The widest squashed ball: 64 * (1 + 1/6) = 74.7, plus the floor/ceil pixel.
pub const MAX_SPAN: usize = 80;

pub const Sprite = struct {
    buf: [MAX_SPAN * MAX_SPAN]u8 align(4) = undefined,
    w: u16 = 0,
    h: u16 = 0,
    stride: u16 = 0, // w rounded up to whole words: each row is written a word at a time
    ox: i16 = 0, // top-left offset from the ball's centre pixel
    oy: i16 = 0,

    /// h rows of `stride` bytes, the first w of each the sprite (blit with src_w = stride).
    pub fn pixels(self: *const Sprite) []const u8 {
        return self.buf[0 .. @as(usize, self.stride) * self.h];
    }

    /// Resample `ball` (BS x BS, index 0 transparent) scaled by (sx, sy) about
    /// its centre, for a ball centred on a whole pixel. Same texel test as the
    /// old per-ball CPU blit: a destination pixel samples at its centre (+0.5).
    /// `spans`: where each ball row is not 0 (dragonball_raster.renderBall's).
    /// `sx`, `sy`: the squash, Q16.
    pub fn build(self: *Sprite, ball: *const [BS * BS]u8, spans: *const [BS][2]u8, sx: i32, sy: i32) void {
        const x0: i32 = (-C * sx) >> 16; // floor
        const y0: i32 = (-C * sy) >> 16;
        self.ox = @intCast(x0);
        self.oy = @intCast(y0);
        self.w = @intCast(@min(((C * sx + 0xFFFF) >> 16) - x0, MAX_SPAN)); // ceil
        self.h = @intCast(@min(((C * sy + 0xFFFF) >> 16) - y0, MAX_SPAN));
        self.stride = (self.w + 3) & ~@as(u16, 3);
        // The texel column of each sprite column. texel() grows with k, so the columns off
        // the ball are a run at each end, [0, lo) and [hi, w): they read column 0 here and
        // are zeroed after each row, which keeps the inner loop free of tests.
        var m = Map{};
        var tx = Texels.init(x0, sx);
        for (0..self.w) |k| {
            const c = tx.next();
            if (c < 0) continue;
            m.cols[k] = @intCast(c);
            m.lo = @min(m.lo, k);
            m.hi = k + 1;
        }
        // first[c]: the first sprite column on the ball reading texel column c or right of it.
        var k: usize = m.lo;
        for (&m.first, 0..) |*f, c| {
            while (k < m.hi and m.cols[k] < c) k += 1;
            f.* = @intCast(k);
        }
        var ty = Texels.init(y0, sy);
        for (0..self.h) |r| self.row(ball, spans, r, ty.next(), &m);
    }

    const Map = struct {
        cols: [MAX_SPAN]u8 = [_]u8{0} ** MAX_SPAN,
        first: [BS + 1]u8 = undefined,
        lo: usize = MAX_SPAN,
        hi: usize = 0,
    };

    // Only the words whose texels can be non-zero (the row's span) are gathered.
    fn row(self: *Sprite, ball: *const [BS * BS]u8, spans: *const [BS][2]u8, r: usize, ty: i16, m: *const Map) void {
        const out = self.buf[r * self.stride ..][0..self.stride];
        const words: []u32 = @as([*]u32, @ptrCast(@alignCast(out.ptr)))[0 .. self.stride / 4];
        if (ty < 0) return @memset(words, 0);
        const span = spans[@intCast(ty)];
        const k0: usize = m.first[span[0]];
        const k1: usize = if (span[1] > span[0]) m.first[span[1]] else k0;
        if (k1 <= k0) return @memset(words, 0);
        const w0 = k0 / 4;
        const w1 = (k1 + 3) / 4;
        @memset(words[0..w0], 0);
        @memset(words[w1..], 0);
        const src = ball[@as(usize, @intCast(ty)) * BS ..][0..BS];
        for (words[w0..w1], w0..) |*wd, i| {
            const c = m.cols[i * 4 ..][0..4];
            wd.* = @as(u32, src[c[0]]) | @as(u32, src[c[1]]) << 8 | @as(u32, src[c[2]]) << 16 | @as(u32, src[c[3]]) << 24;
        }
        if (w0 * 4 < m.lo) @memset(out[w0 * 4 .. m.lo], 0);
        if (w1 * 4 > m.hi) @memset(out[m.hi..@min(w1 * 4, self.w)], 0);
    }
};

/// The texel of sprite pixel k = 0, 1, ... (origin `o` from the centre) at scale `sc` (Q16):
/// floor(32 + (o + k + 0.5) / sc), or -1 off the ball. One divide for 1/sc (Q32), then an add
/// a pixel.
const Texels = struct {
    v: i64, // pixel k's 32 + (o + k + 0.5) / sc, Q32
    step: i64, // 1 / sc, Q32

    fn init(o: i32, sc: i32) Texels {
        const step = @divFloor(@as(i64, 1) << 48, sc);
        return .{ .v = (@as(i64, C) << 32) + @divFloor((2 * @as(i64, o) + 1) * step, 2), .step = step };
    }

    fn next(t: *Texels) i16 {
        defer t.v += t.step;
        if (t.v < 0 or t.v >= @as(i64, BS) << 32) return -1;
        return @intCast(t.v >> 32);
    }
};

/// A ball's centre row at bounce angle `a` (its phase + 0.25 i): round(307 - 64 |sin a|), a
/// whole pixel, so all six share the sprite.
pub fn centreY(a: u32) i16 {
    const s: i64 = @abs(fixsin.sin(a)); // Q30
    return @intCast(307 - ((64 * s + (1 << 29)) >> 30));
}

/// 1 + sin(a) / 6 in Q16 (the squash's scale).
pub fn squash(a: u32) i32 {
    return (1 << 16) + @divTrunc(fixsin.sin(a) >> 14, 6);
}

/// The first row the disc may cover: main.zig's bottom band starts here, and its colour is
/// what dragonball.zig pre-blends the disc over.
pub const DISC_TOP: i16 = 211;

// The disc is pre-blended over the bottom band, so it must never reach above it: every squash
// the accumulator takes as update() runs it, then a fine sweep of the whole range, at the
// highest centre any ball reaches.
test "the disc never leaves the bottom band" {
    const std = @import("std");
    var ball = [_]u8{0} ** (BS * BS);
    const spans = gm.DISC_SPAN; // the disc is all this ball holds
    for (gm.DISC_SPAN, 0..) |span, y| @memset(ball[y * BS + span[0] ..][0 .. span[1] - span[0]], 1);
    var top: i16 = 1000;
    var angle: u32 = 0;
    for (0..20_000) |_| {
        angle +%= fixsin.rad(0.05);
        for (0..6) |i| top = @min(top, centreY(angle +% fixsin.rad(0.25) *% @as(u32, @intCast(i))));
    }
    try std.testing.expectEqual(@as(i16, 243), top);
    var s: Sprite = .{};
    var u: u32 = 0;
    for (0..40_000) |k| {
        u +%= fixsin.rad(0.2);
        const lo: i32 = @divTrunc(5 << 16, 6); // the sweep: every Q16 squash from 5/6 to 7/6
        const sweep: i32 = lo + @as(i32, @intCast((k -| 20_000) * 21846 / 20_000));
        const sy = if (k < 20_000) squash(u +% fixsin.rad(10.0)) else sweep;
        s.build(&ball, &spans, squash(1 << 30), sy);
        var first: usize = s.h;
        for (0..s.h) |r| {
            if (std.mem.indexOfScalar(u8, s.pixels()[r * s.stride ..][0..s.w], 1) != null) {
                first = r;
                break;
            }
        }
        try std.testing.expect(top + s.oy + @as(i16, @intCast(first)) >= DISC_TOP);
    }
}
