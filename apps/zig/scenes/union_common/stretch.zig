// --------------------------------------------------------------------------
// blit.stretchY in integers: the same nearest-row mapping, one 64-bit divide a
// call and a multiply a row, where blit's f64 version divides per row.
//
// The board's cart CPU has only a single-precision FPU, so every f64 op is a
// soft-float call. The scale is taken once a frame as a Q30 (the caller makes it
// from one f64 cos) and the rows then step in Q32, so frames match the f64 path
// except where a row sits within ~1e-9 of a source-row boundary.
// --------------------------------------------------------------------------
const std = @import("std");
const blit = @import("zigos").blit;

pub const ONE_Q30: i32 = 1 << 30;
const MIN_SY_Q30: i64 = 1 << 20; // below this the reciprocal would overflow: f64 path

pub fn toQ30(sy: f64) i32 {
    return @intFromFloat(@round(sy * 1073741824.0));
}

pub fn toQ16(v: f64) i32 {
    return @intFromFloat(@round(v * 65536.0));
}

/// CODEF image.draw(..., sy) on a mid-handled image: `src` stretched about row
/// `centre_q16` (Q16) by `sy_q30` (Q30), left edge at `dx`.
pub fn stretchY(dst: blit.Dst, src: blit.Image, dx: i32, centre_q16: i32, sy_q30: i32, key: ?u8, ink: blit.Ink) void {
    if (sy_q30 == 0 or src.h == 0 or dst.h == 0) return;
    const mag: i64 = @intCast(@abs(sy_q30));
    if (mag < MIN_SY_Q30) {
        const f = 1.0 / 1073741824.0;
        return blit.stretchY(dst, src, dx, @as(f64, @floatFromInt(centre_q16)) / 65536.0, @as(f64, @floatFromInt(sy_q30)) * f, key, ink);
    }
    const h: i64 = @intCast(src.h);
    const half_q16: i64 = h << 15;
    const extent_q16 = (half_q16 * mag) >> 30;
    const lo = std.math.clamp(((@as(i64, centre_q16) - extent_q16) >> 16) - 1, 0, @as(i64, @intCast(dst.h)));
    const hi = std.math.clamp(((@as(i64, centre_q16) + extent_q16 + 65535) >> 16) + 1, 0, @as(i64, @intCast(dst.h)));
    const inv_q32: i64 = @divTrunc(@as(i64, 1) << 62, sy_q30); // 1/sy
    const origin_q32: i64 = half_q16 << 16;
    const limit_q32: i64 = h << 32;
    var y: i64 = lo;
    while (y < hi) : (y += 1) {
        const num_q16: i64 = (y << 16) + 32768 - centre_q16;
        const v = origin_q32 + ((num_q16 * inv_q32) >> 16);
        if (v < 0 or v >= limit_q32) continue;
        blit.blit(dst, src, .{ .x = 0, .y = @intCast(v >> 32), .w = src.w, .h = 1 }, dx, @intCast(y), key, ink);
    }
}
