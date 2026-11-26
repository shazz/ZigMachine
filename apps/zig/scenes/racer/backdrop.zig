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

/// The shapes a track's mood can pick (trk.Mood.backdrop; tools/racer/ref_sky.py draws the same strips).
pub const Shape = enum(u8) { hills = 0, docks = 1, peaks = 2 };

const hills: [W * ROWS]u8 align(16) = blk: {
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

// The strip on show: the hills (built at compile time, the M1 art) or a shape built here once when a track picks it
// (M5 step 2: integer maths only, a few hundred thousand stores at a track change, never per frame).
var strip: *[W * ROWS]u8 = undefined; // carved out of cart RAM by the first select() (init): no 64 KB of zeros in the image
var shown: ?Shape = null;
fn tex() zg.chisel_v2.Texture {
    return .{ .pixels = strip, .stride = W, .umask = W - 1, .vmask = ROWS - 1 };
}

/// A triangle wave 0..amp..0 over `period` texels (periods divide W, so the strip wraps without a seam).
fn tri(x: usize, period: usize, amp: usize) usize {
    const p = x % period;
    const d = if (2 * p > period) 2 * p - period else period - 2 * p;
    return amp - amp * d / period;
}

/// Container stacks on the far quay (12), gantry cranes in front (13), their lights and the stacks' lamps (14).
fn docksColumn(x: usize) [H]u8 {
    var c = [_]u8{0} ** H;
    const block = x / 24;
    const stack = 5 + ((@as(u32, @intCast(block)) *% 2654435761) >> 7) % 9;
    const cx = x % 128;
    const leg = (cx >= 10 and cx < 13) or (cx >= 40 and cx < 43);
    for (0..H) |r| {
        const up = H - 1 - r;
        if (up < stack) c[r] = HILL_FAR;
        if (up == stack - 1 and x % 6 == 0) c[r] = SKYLINE;
        if ((leg and up < 30) or (up >= 26 and up < 30 and cx >= 6 and cx < 62) or (up >= 27 and up < 29 and cx >= 62 and cx < 92)) c[r] = HILL_NEAR;
        if (up == 31 and (cx == 11 or cx == 41)) c[r] = SKYLINE;
    }
    return c;
}

/// Two ranges of jagged peaks (12 far, 13 near) and snow on the far range's tops (14).
fn peaksColumn(x: usize) [H]u8 {
    var c = [_]u8{0} ** H;
    const far = 14 + tri(x, 256, 16) + tri(x + 40, 64, 7) + tri(x + 9, 16, 2);
    const near = 6 + tri(x + 100, 128, 9) + tri(x, 32, 3);
    for (0..H) |r| {
        const up = H - 1 - r;
        if (up < far) c[r] = if (far > 26 and up + 5 >= far) SKYLINE else HILL_FAR;
        if (up < near) c[r] = HILL_NEAR;
    }
    return c;
}

/// Show `shape` (a track change; a no-op when it is already on show).
pub fn select(shape: u8) void {
    const s: Shape = @enumFromInt(shape); // trk.parse refused any other value
    if (shown == null) strip = @ptrCast(std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, W * ROWS / 4)).ptr);
    if (s == shown) return;
    shown = s;
    if (s == .hills) return @memcpy(strip, &hills);
    for (0..W) |x| {
        const c = if (s == .docks) docksColumn(x) else peaksColumn(x);
        for (c, 0..) |v, r| strip[r * W + x] = v;
    }
}

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
    zg.chisel_v2.affine(fb, tex(), list, .{ .key = 0 });
}
