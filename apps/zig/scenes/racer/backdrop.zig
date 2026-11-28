// --------------------------------------------------------------------------
// RACER: the backdrop panorama (our own art: two ranges of hills and a skyline, built at compile
// time). One CHISEL AFFINE op replaces a scrolled plane (0.59 Mc of compositing): a 1024 x 48
// strip in cart RAM drawn as 48 spans, one a row, above the horizon. U_MASK 1023 wraps the turn:
// a quarter of the strip (256 texels) is the 90 degree view, so du = 256 / 320 texel a pixel and
// u0 follows the yaw. Index 0 is the colour key: the sky (and its per-line gradient) shows through.
// R82 32X look: a track's own panorama file (pano.zig, panofile.zig) is drawn instead of the shape, from the same
// buffer: any width a turn (a power of two), rows above AND below the horizon (a sea to the skyline), its own u0.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const panofile = @import("panofile.zig");

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
var strip: *[W * ROWS]u8 = undefined; // the buffer's first 64 KB (init): no 64 KB of zeros in the image
var mem: []u8 = &.{}; // the shapes' strip or a panorama file (pano.zig): sized by init to the larger
var shown: ?Shape = null;
pub var break_pixel = false; // racer_look.mjs --break pixel (key |): flag PIXEL ignored (the stretched strip)
pub var pan: ?panofile.Pan = null; // the track's panorama on show (pano.zig), else the mood's shape

/// The buffer, carved once before the track library: the shapes' 64 KB or the disk's largest panorama (pano.largest).
pub fn init(pan_bytes: usize) void {
    const n = std.mem.alignForward(usize, @max(W * ROWS, pan_bytes), 4);
    mem = std.mem.sliceAsBytes(zg.mem.mustAlloc(u32, n / 4));
    strip = mem[0 .. W * ROWS];
}

/// The bytes a panorama file is depacked into.
pub fn panBuffer() []u8 {
    return mem;
}

/// A panorama overwrote the buffer: the next shape is built again.
pub fn lose() void {
    shown = null;
}

fn tex() zg.chisel_v2.Texture {
    if (pan) |p| return .{ .pixels = p.texels, .stride = @intCast(p.width), .umask = @intCast(p.width - 1), .vmask = @intCast(std.math.ceilPowerOfTwoAssert(u32, p.rows) - 1) };
    return .{ .pixels = strip, .stride = W, .umask = W - 1, .vmask = ROWS - 1 };
}

/// The panorama's lower part: its period wide, repeating across (umask), the same texel a pixel as the upper part.
fn lowerTex(p: panofile.Pan) zg.chisel_v2.Texture {
    return .{ .pixels = p.lower, .stride = @intCast(p.lower_w), .umask = @intCast(p.lower_w - 1), .vmask = @intCast(std.math.ceilPowerOfTwoAssert(u32, p.lower_rows) - 1) };
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
    if (mem.len == 0) init(0);
    if (pan != null or s == shown) return;
    shown = s;
    if (s == .hills) return @memcpy(strip, &hills);
    for (0..W) |x| {
        const c = if (s == .docks) docksColumn(x) else peaksColumn(x);
        for (c, 0..) |v, r| strip[r * W + x] = v;
    }
}

pub const Lists = struct { up: []const zg.chisel_v2.Span, low: []const zg.chisel_v2.Span };

/// The spans of the strip for a camera looking along `yaw`, the horizon on row `hz`, rows in [y_min, y_max) only: the
/// upper part's in `up`, a panorama's lower part's in `low`. A panorama's texel is as tall as it is wide (1.25 pixels both
/// ways at 1,024 a turn: dv = du), so the art keeps its aspect; a PIXEL one (the 32X's) is a pixel both ways, as the 32X
/// shows it (a 5:4 resample beat its 1-pixel dither into clumps: board batch, item 5); the shapes keep a row a line.
pub fn spans(up: []zg.chisel_v2.Span, low: []zg.chisel_v2.Span, yaw: u32, hz: i32, y_min: i32, y_max: i32) Lists {
    const g = geometry();
    const ustart: u32 = (yaw >> g.shift) +% (g.u0 << 16) -% g.du *% 160;
    const top: i32 = hz - @as(i32, @intCast((g.horizon << 16) / g.dv));
    var n: usize = 0;
    var m: usize = 0;
    var y: i32 = @max(top, y_min);
    while (y < y_max) : (y += 1) {
        const v: u32 = @as(u32, @intCast(y - top)) * g.dv;
        const row = v >> 16;
        if (row < g.rows and n < up.len) {
            up[n] = .{ .x0 = 0, .x1 = 320, .y = @intCast(y), .u0 = ustart, .v0 = v, .du = g.du, .dv = 0 };
            n += 1;
        } else if (row >= g.rows and row - g.rows < g.lower and m < low.len) {
            low[m] = .{ .x0 = 0, .x1 = 320, .y = @intCast(y), .u0 = ustart, .v0 = v - (g.rows << 16), .du = g.du, .dv = 0 };
            m += 1;
        } else if (row >= g.rows + g.lower) break;
    }
    return .{ .up = up[0..n], .low = low[0..m] };
}

const Geometry = struct { rows: u32, lower: u32, horizon: u32, shift: u5, du: u32, dv: u32, u0: u32 };

/// The strip's rows (upper, lower), its row on the horizon, the yaw's shift to texels (Q16), a texel's step a pixel (a
/// quarter turn is the 90 degree view: width / 4 texels over 320 pixels) and a line's (Q16), the texel ahead at yaw 0.
fn geometry() Geometry {
    const p = pan orelse return .{ .rows = H, .lower = 0, .horizon = H, .shift = 6, .du = DU, .dv = 1 << 16, .u0 = 0 };
    const du = if (p.pixel and !break_pixel) 65536 else p.width * 65536 / 1280; // PIXEL (the 32X's plane B): no 5:4 resample of its dither
    return .{ .rows = p.rows, .lower = p.lower_rows, .horizon = p.horizon, .shift = @intCast(16 - std.math.log2_int(u32, p.width)), .du = du, .dv = du, .u0 = p.u0 }; // square texels: dv = du
}

/// The rows an OPAQUE panorama paints whole (the sky fill under them is skipped): [lo, hi), empty otherwise.
pub fn covers(hz: i32) [2]i32 {
    const p = pan orelse return .{ 0, 0 };
    if (!p.opaque_) return .{ 0, 0 };
    const g = geometry();
    const lo = hz - @as(i32, @intCast((g.horizon << 16) / g.dv));
    return .{ lo, lo + @as(i32, @intCast(((g.rows + g.lower) << 16) / g.dv)) };
}

pub fn draw(fb: *zg.LogicalFB, l: Lists) void {
    zg.chisel_v2.affine(fb, tex(), l.up, .{ .key = 0 });
    if (pan) |p| if (l.low.len != 0) zg.chisel_v2.affine(fb, lowerTex(p), l.low, .{ .key = 0 });
}
