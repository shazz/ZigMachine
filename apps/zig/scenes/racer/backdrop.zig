// --------------------------------------------------------------------------
// RACER: the backdrop panorama (our own art: two ranges of hills and a skyline, built at compile
// time). One CHISEL AFFINE op replaces a scrolled plane (0.59 Mc of compositing): a 1024 x 48
// strip in cart RAM drawn as 48 spans, one a row, above the horizon. U_MASK 1023 wraps the turn:
// a quarter of the strip (256 texels) is the 90 degree view, so du = 256 / 320 texel a pixel and
// u0 follows the yaw. Index 0 is the colour key: the sky (and its per-line gradient) shows through.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const W = 1024;
pub const H = 48;
pub const ROWS = 64; // the texture's height (a power of two, the mask); rows past H are index 0
pub const HILL_FAR: u8 = 12;
pub const HILL_NEAR: u8 = 13;
pub const SKYLINE: u8 = 14;
const DU: u32 = 52429; // 256 * 65536 / 320

const strip: [W * ROWS]u8 align(16) = blk: {
    @setEvalBranchQuota(W * ROWS * 40);
    var t = [_]u8{0} ** (W * ROWS);
    for (0..W) |x| {
        const a = @as(f64, @floatFromInt(x)) * (2.0 * std.math.pi / @as(f64, W));
        const far = 18.0 + 8.0 * @sin(a * 3.0) + 4.0 * @sin(a * 7.0 + 1.0);
        const near = 9.0 + 5.0 * @sin(a * 5.0 + 2.0) + 2.5 * @sin(a * 11.0);
        const tower = if (@mod(x / 8, 7) == 3) 6.0 + @as(f64, @floatFromInt((x / 8) % 5)) else 0.0;
        for (0..H) |r| {
            const up: f64 = @floatFromInt(H - 1 - r); // rows above the horizon
            if (up < far) t[r * W + x] = HILL_FAR;
            if (up < near + tower) t[r * W + x] = if (tower > 0 and up >= near) SKYLINE else HILL_NEAR;
        }
    }
    break :blk t;
};

const TEX = zg.chisel_v2.Texture{ .pixels = &strip, .stride = W, .umask = W - 1, .vmask = ROWS - 1 };

/// The spans of the strip for a camera looking along `yaw`, the horizon on row `hz`, rows >= y_min only.
pub fn spans(out: *[H]zg.chisel_v2.Span, yaw: u32, hz: i32, y_min: i32) []const zg.chisel_v2.Span {
    const ustart: u32 = (yaw >> 6) -% DU *% 160;
    var n: usize = 0;
    for (0..H) |r| {
        const y: i32 = hz - H + @as(i32, @intCast(r));
        if (y < y_min or y >= hz) continue;
        out[n] = .{ .x0 = 0, .x1 = 320, .y = @intCast(y), .u0 = ustart, .v0 = @as(u32, @intCast(r)) << 16, .du = DU, .dv = 0 };
        n += 1;
    }
    return out[0..n];
}

pub fn draw(fb: *zg.LogicalFB, list: []const zg.chisel_v2.Span) void {
    zg.chisel_v2.affine(fb, TEX, list, .{ .key = 0 });
}
