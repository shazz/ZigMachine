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
    buf: [MAX_SPAN * MAX_SPAN]u8 = undefined,
    w: u16 = 0,
    h: u16 = 0,
    ox: i16 = 0, // top-left offset from the ball's centre pixel
    oy: i16 = 0,

    pub fn pixels(self: *const Sprite) []const u8 {
        return self.buf[0 .. @as(usize, self.w) * self.h];
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
        var cols: [MAX_SPAN]i16 = undefined; // texel column a sprite column, -1 = off the ball
        for (cols[0..self.w], 0..) |*c, k| c.* = texel(x0, k, sx);
        for (0..self.h) |r| {
            const row = self.buf[r * self.w ..][0..self.w];
            const ty = texel(y0, r, sy);
            if (ty < 0) {
                @memset(row, 0);
                continue;
            }
            const src = ball[@as(usize, @intCast(ty)) * BS ..][0..BS];
            for (row, cols[0..self.w]) |*px, c| px.* = if (c < 0) 0 else src[@intCast(c)];
        }
    }
};

/// The texel index for sprite pixel `k` (origin `o` from the centre), or -1.
fn texel(o: f32, k: usize, s: f32) i16 {
    const v = gm.CENTER + (o + @as(f32, @floatFromInt(k)) + 0.5) / s;
    if (v < 0 or v >= @as(f32, BS)) return -1;
    return @intFromFloat(v);
}
