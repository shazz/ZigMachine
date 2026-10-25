// --------------------------------------------------------------------------
// The squashed dragonball sprite, built ONCE a frame and stamped six times by
// CHISEL. The six balls share one squash (sx, sy) and sit on whole pixels
// (cx = 40 + 64 i, cy rounded), so the inverse map from a destination pixel to
// a ball texel is the same for all six: resample once on the CPU, then six
// colour-keyed CHISEL copies (index 0 = transparent) instead of six CPU
// resamples (~6x fewer CPU stores on the board).
// --------------------------------------------------------------------------
const gm = @import("dragonball_math.zig");

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
    pub fn build(self: *Sprite, ball: *const [BS * BS]u8, sx: f32, sy: f32) void {
        const x0 = @floor(-gm.CENTER * sx);
        const y0 = @floor(-gm.CENTER * sy);
        self.ox = @intFromFloat(x0);
        self.oy = @intFromFloat(y0);
        self.w = @intCast(@min(@as(i32, @intFromFloat(@ceil(gm.CENTER * sx) - x0)), MAX_SPAN));
        self.h = @intCast(@min(@as(i32, @intFromFloat(@ceil(gm.CENTER * sy) - y0)), MAX_SPAN));
        self.stride = (self.w + 3) & ~@as(u16, 3);
        // The texel column of each sprite column. texel() grows with k, so the columns off
        // the ball are a run at each end, [0, lo) and [hi, w): they read column 0 here and
        // are zeroed after each row, which keeps the inner loop free of tests.
        var cols: [MAX_SPAN]u8 = [_]u8{0} ** MAX_SPAN;
        var lo: usize = self.w;
        var hi: usize = 0;
        for (0..self.w) |k| {
            const c = texel(x0, k, sx);
            if (c < 0) continue;
            cols[k] = @intCast(c);
            lo = @min(lo, k);
            hi = k + 1;
        }
        for (0..self.h) |r| self.row(ball, r, texel(y0, r, sy), &cols, lo, hi);
    }

    fn row(self: *Sprite, ball: *const [BS * BS]u8, r: usize, ty: i16, cols: *const [MAX_SPAN]u8, lo: usize, hi: usize) void {
        const out = self.buf[r * self.stride ..][0..self.stride];
        const words: []u32 = @as([*]u32, @ptrCast(@alignCast(out.ptr)))[0 .. self.stride / 4];
        if (ty < 0 or hi <= lo) return @memset(words, 0);
        const src = ball[@as(usize, @intCast(ty)) * BS ..][0..BS];
        for (words, 0..) |*wd, i| {
            const c = cols[i * 4 ..][0..4];
            wd.* = @as(u32, src[c[0]]) | @as(u32, src[c[1]]) << 8 | @as(u32, src[c[2]]) << 16 | @as(u32, src[c[3]]) << 24;
        }
        @memset(out[0..lo], 0);
        @memset(out[hi..self.w], 0);
    }
};

/// The texel index for sprite pixel `k` (origin `o` from the centre), or -1.
fn texel(o: f32, k: usize, s: f32) i16 {
    const v = gm.CENTER + (o + @as(f32, @floatFromInt(k)) + 0.5) / s;
    if (v < 0 or v >= @as(f32, BS)) return -1;
    return @intFromFloat(v);
}

/// Ball `fi`'s centre row at bounce phase `angle`: a whole pixel, so all six share the sprite.
pub fn centreY(angle: f32, fi: f32) i16 {
    return @intFromFloat(@round(307.0 - 64.0 * @abs(@sin(angle + 0.25 * fi))));
}

/// The first row the disc may cover: main.zig's bottom band starts here, and its colour is
/// what dragonball.zig pre-blends the disc over.
pub const DISC_TOP: i16 = 211;

// The disc is pre-blended over the bottom band, so it must never reach above it: every squash
// the f32 accumulator takes as update() runs it, then a fine sweep of the whole range, at the
// highest centre any ball reaches.
test "the disc never leaves the bottom band" {
    const std = @import("std");
    var ball = [_]u8{0} ** (BS * BS);
    for (gm.DISC_SPAN, 0..) |span, y| @memset(ball[y * BS + span[0] ..][0 .. span[1] - span[0]], 1);
    var top: i16 = 1000;
    var angle: f32 = 0;
    for (0..20_000) |_| {
        angle = @mod(angle + 0.05, std.math.pi * 2.0);
        for (0..6) |i| top = @min(top, centreY(angle, @floatFromInt(i)));
    }
    try std.testing.expectEqual(@as(i16, 243), top);
    var s: Sprite = .{};
    var u: f32 = 0;
    for (0..40_000) |k| {
        u = @mod(u + 0.2, std.math.pi * 2.0);
        const sweep = 5.0 / 6.0 + @as(f32, @floatFromInt(k -| 20_000)) / 60_000.0;
        const sy = if (k < 20_000) 1.0 + @sin(u + 10.0) / 6.0 else sweep;
        s.build(&ball, 7.0 / 6.0, sy);
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
