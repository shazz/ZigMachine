// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — the starballs' projection and sprite, in
// Q16.16 integers (screen.js:229-297). The remake does this in JS doubles; an
// ST did it in integers, and so does ZIGGY: no float per frame.
//   x = (px - 160) * 128 / z + 160,  y likewise,  s = 1 - z / 200
// and `ballimage.draw(org, x, y, 1, 0, s, s)` covers [x, x + 8s) x [y, y + 8s),
// point-sampled (Chrome's bilinear blur is the remake's, not the ST's).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const W = zg.WIDTH;
const H = zg.HEIGHT;

const ball_b = @embedFile("../../assets/screens/tlb_spoon/ball.raw");
const BALL_SIZE = 8;
const ONE: i32 = 1 << 16;
const HALF: i32 = 1 << 15;

/// Q16.16; s == 0 = nothing to draw (z = 0, or projected far off screen).
pub const Ball = struct { x: i32, y: i32, s: i32 };
pub const none = Ball{ .x = 0, .y = 0, .s = 0 };

/// px, py, pz: the star's wrapped field position, Q16, pz in [0, 200).
pub fn project(px: i32, py: i32, pz: i32) Ball {
    if (pz <= 0) return none; // z = 0 projects to infinity
    // k = 128 / z in Q16 = 2^39 / pz, as two u32 divides (no i64 divide).
    const z: u32 = @intCast(pz);
    const q = (@as(u32, 1) << 31) / z;
    const r = (@as(u32, 1) << 31) % z;
    if (q >= 1 << 24) return none; // z < 1/512: off screen unless dead centre
    const k: i64 = (@as(i64, q) << 8) + ((r << 8) / z);
    const x = axis(px, 160, k) orelse return none;
    const y = axis(py, 100, k) orelse return none;
    return .{ .x = x, .y = y, .s = ONE - @divTrunc(pz, 200) };
}

// (p - c) * k + c, or null when the ball (at most 8 px) cannot reach the screen.
fn axis(p: i32, comptime c: i32, k: i64) ?i32 {
    const v = ((@as(i64, p - (c << 16)) * k) >> 16) + (c << 16);
    if (v < -16 << 16 or v > (2 * c + 16) << 16) return null;
    return @intCast(v);
}

// ceil(v - 0.5) of a Q16 value, as an integer.
inline fn ceilHalf(v: i32) i32 {
    return (v - HALF + ONE - 1) >> 16;
}

// floor(offset / s) clamped to the sprite, with inv31 = 2^31 / s (rounded up).
inline fn sampleIndex(offset: i32, inv31: u32) usize {
    const i = (@as(i64, offset) * inv31) >> 31;
    return @intCast(@min(BALL_SIZE - 1, @max(0, i)));
}

pub fn draw(fb: *LogicalFB, b: Ball) void {
    if (b.s <= 0) return;
    const span = b.s * BALL_SIZE;
    const x0 = @max(0, ceilHalf(b.x));
    const y0 = @max(0, ceilHalf(b.y));
    const x1 = @min(W, ceilHalf(b.x + span));
    const y1 = @min(H, ceilHalf(b.y + span));
    if (x0 >= x1 or y0 >= y1) return;

    // A ball is at most 8 px wide: its source columns are worked out once, not per row.
    // Rounded UP: offsets that are exact multiples of s must land on their own
    // texel, as 1/s in floating point puts them (a truncated 1/s drops them one).
    const s: u32 = @intCast(b.s);
    const inv31: u32 = ((@as(u32, 1) << 31) + s - 1) / s;
    var cols: [BALL_SIZE + 1]u8 = undefined;
    const nx: usize = @intCast(@min(BALL_SIZE + 1, x1 - x0));
    for (0..nx) |i| {
        const px = (x0 + @as(i32, @intCast(i))) << 16;
        cols[i] = @intCast(sampleIndex(px + HALF - b.x, inv31));
    }

    var y = y0;
    while (y < y1) : (y += 1) {
        const sy = sampleIndex((y << 16) + HALF - b.y, inv31);
        const src = ball_b[sy * BALL_SIZE ..];
        const dst = fb.fb[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x0)) ..];
        for (cols[0..nx], 0..) |c, i| {
            const v = src[c];
            if (v != 0) dst[i] = v;
        }
    }
}

comptime {
    if (ball_b.len != BALL_SIZE * BALL_SIZE) @compileError("ball.raw is not 8x8");
}
