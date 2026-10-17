// --------------------------------------------------------------------------
// blit.stretchY in integers: the same nearest-row mapping, with no f64 divide
// per row (blit's version does one each, soft-float on the board).
//
// The scale arrives as the f64 the caller computed (one cos or one height a
// frame) and is taken EXACTLY as a Q60 integer: an f64 of magnitude >= 2^-8 has
// an ulp of 2^-60 or coarser. Each row's source row is then floor(H/2 +
// (y + 1/2 - centre) / sy), the exact rational value: rows step by a constant,
// so one 128-bit divide starts the walk and a quotient/remainder pair carries
// it (a Bresenham line), a few adds a row. That reproduces the f64 path wherever
// its own rounding does not decide the row, including the exact ties a
// 1 - 0.035k logo height produces (sy = 0.16: a 0.5 row boundary the f64 value
// misses by 6e-16 and Q30 would not).
//
// A scale under 2^-8 (a cos at a quarter turn) is a sliver of a row: it takes
// the f64 path. Centres are Q16: every Union screen's is a half-integer.
// --------------------------------------------------------------------------
const std = @import("std");
const blit = @import("zigos").blit;

const SLIVER: f64 = 1.0 / 256.0;
const Q60: f64 = 1152921504606846976.0;

/// CODEF image.draw(..., sy) on a mid-handled image: `src` stretched about row
/// `centre_q16` (Q16) by `sy`, left edge at `dx`.
pub fn stretchY(dst: blit.Dst, src: blit.Image, dx: i32, centre_q16: i32, sy: f64, key: ?u8, ink: blit.Ink) void {
    if (sy == 0 or src.h == 0 or dst.h == 0) return;
    if (!(@abs(sy) >= SLIVER) or @abs(sy) > 4) {
        return blit.stretchY(dst, src, dx, @as(f64, @floatFromInt(centre_q16)) / 65536.0, sy, key, ink);
    }
    const s: i64 = @intFromFloat(sy * Q60); // exact
    const h: i64 = @intCast(src.h);
    const mag: i128 = @abs(s);
    const centre: i64 = centre_q16;
    const extent_q16: i64 = @intCast((@as(i128, h) * (1 << 15) * mag) >> 60); // (H/2) |sy| in Q16
    const rows: i64 = @intCast(dst.h);
    const lo = std.math.clamp(((centre - extent_q16) >> 16) - 1, 0, rows);
    const hi = std.math.clamp(((centre + extent_q16 + 65535) >> 16) + 1, 0, rows);
    if (hi <= lo) return;
    // v(y) = (H|S| + sign * N(y) 2^45) / (2|S|), N(y) = (y << 16) + 32768 - centre
    const den: i128 = 2 * mag;
    const sign: i128 = if (s < 0) -1 else 1;
    const n0: i128 = (lo << 16) + 32768 - centre;
    const num0 = @as(i128, h) * mag + sign * n0 * (1 << 45);
    const step = sign * (1 << 61); // N grows 2^16 a row
    var q = @divFloor(num0, den);
    var r = num0 - q * den;
    const qd = @divFloor(step, den);
    const rd = step - qd * den;
    var y: i64 = lo;
    while (y < hi) : (y += 1) {
        if (q >= 0 and q < h) {
            blit.blit(dst, src, .{ .x = 0, .y = @intCast(q), .w = src.w, .h = 1 }, dx, @intCast(y), key, ink);
        }
        q += qd;
        r += rd;
        if (r >= den) {
            r -= den;
            q += 1;
        }
    }
}
