// blit.stretchY (re-exported there): a vertical stretch as one blit() a
// destination row. Its own file to keep blit.zig under 200 lines.
const std = @import("std");
const b = @import("blit.zig");
const Dst = b.Dst;
const Image = b.Image;
const Ink = b.Ink;
const blit = b.blit;

/// CODEF `image.draw(dst, x, y, alpha, 0, 1, sy)` on a mid-handled image: `src`
/// stretched vertically by `sy` about the row `centre_y`, left edge at `dx`.
/// A negative `sy` flips it; 0 draws nothing. Each destination row takes the
/// source row under its pixel centre (nearest, where the canvas interpolates).
pub fn stretchY(dst: Dst, src: Image, dx: i32, centre_y: f64, sy: f64, key: ?u8, ink: Ink) void {
    if (sy == 0 or src.h == 0 or dst.h == 0) return;
    const half: f64 = @as(f64, @floatFromInt(src.h)) / 2;
    const extent = half * @abs(sy);
    const top: usize = @intFromFloat(std.math.clamp(@floor(centre_y - extent), 0, @as(f64, @floatFromInt(dst.h))));
    const bottom: usize = @intFromFloat(std.math.clamp(@ceil(centre_y + extent), 0, @as(f64, @floatFromInt(dst.h))));
    for (top..bottom) |y| {
        const v = half + (@as(f64, @floatFromInt(y)) + 0.5 - centre_y) / sy;
        if (!(v >= 0 and v < @as(f64, @floatFromInt(src.h)))) continue;
        blit(dst, src, .{ .x = 0, .y = @intFromFloat(v), .w = src.w, .h = 1 }, dx, @intCast(y), key, ink);
    }
}
