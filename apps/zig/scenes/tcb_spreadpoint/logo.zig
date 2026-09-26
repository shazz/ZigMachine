// --------------------------------------------------------------------------
// The TCB logo turning about a horizontal axis (screen.js draw_logo).
//
//   a = angle[iteration % angle.length]
//   z = cos(a) / 4 + 0.75            the zoom, 0.5 (far) .. 1 (near)
//   x = 64 - 64 z, y = 45 + 40 sin(a) the top-left in the 128x128 logo canvas
//
// The angle table is init()'s six loops, run in the same f64 operations so it
// holds the same values: 300 frames far (PI), 40 swinging forward at PI/40,
// 300 near (0), 640 turning at PI/40, 480 turning at PI/32, 512 turning back at
// PI/32 -- 2272 frames, then it starts over.
//
// tcb-in (the inside, one ink the raster recolours) and tcb-out (the outline,
// drawn over it with the same transform) are one image here, logo.raw. The
// canvas smooths the zoom; this samples nearest, as an ST would.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

pub const CANVAS = 128; // logo_canvas = new canvas(128, 128)
const W = 128;
const H = 40;

const logo_b = @embedFile("../../assets/screens/tcb_spreadpoint/logo.raw");
comptime {
    if (logo_b.len != W * H) @compileError("logo.raw is not 128x40");
}

const SEGMENTS = [_]struct { frames: usize, step: enum { hold_pi, hold_0, down_40, down_32, up_32 } }{
    .{ .frames = 60 * 5, .step = .hold_pi },
    .{ .frames = 40 * 1, .step = .down_40 },
    .{ .frames = 60 * 5, .step = .hold_0 },
    .{ .frames = 80 * 8, .step = .down_40 },
    .{ .frames = 64 * 15 / 2, .step = .down_32 }, // 64 * 7.5
    .{ .frames = 64 * 8, .step = .up_32 },
};
pub const FRAMES = blk: {
    var n = 0;
    for (SEGMENTS) |s| n += s.frames;
    break :blk n;
};

var angle: [FRAMES]f64 = undefined;

pub fn init() void {
    const pi2 = 2.0 * std.math.pi;
    const speed_fast = std.math.pi / 32.0;
    const speed_slow = std.math.pi / 40.0;
    var a: f64 = std.math.pi;
    var c: usize = 0;
    for (SEGMENTS) |s| {
        for (0..s.frames) |_| {
            switch (s.step) {
                .hold_pi => a = std.math.pi,
                .hold_0 => a = 0,
                .down_40 => a -= speed_slow,
                .down_32 => a -= speed_fast,
                .up_32 => a += speed_fast,
            }
            angle[c] = @rem(a, pi2); // JS %: the sign of the dividend
            c += 1;
        }
    }
}

/// draw_logo into `view`, the 128x128 logo_canvas window of the plane.
pub fn draw(view: blit.Dst, iteration: u64) void {
    const a = angle[@intCast(iteration % FRAMES)];
    const z = @cos(a) / 4.0 + 0.75;
    const x = 64.0 - 64.0 * z;
    const y = 45.0 + 40.0 * @sin(a);

    // Destination pixel d samples source (d + 0.5 - origin) / z.
    var src_x: [CANVAS]?u8 = undefined;
    for (&src_x, 0..) |*s, d| s.* = sample(d, x, z, W);
    for (0..@min(CANVAS, view.h)) |dy| {
        const sy = sample(dy, y, z, H) orelse continue;
        const src = logo_b[@as(usize, sy) * W ..][0..W];
        const dst = view.buf[dy * view.stride ..][0..CANVAS];
        for (src_x, dst) |sx, *d| {
            const p = src[sx orelse continue];
            if (p != 0) d.* = p;
        }
    }
}

/// The source index destination pixel d samples, null off the image (or on a
/// NaN, which fails both comparisons).
fn sample(d: usize, origin: f64, z: f64, comptime n: u8) ?u8 {
    const v = @floor((@as(f64, @floatFromInt(d)) + 0.5 - origin) / z);
    if (!(v >= 0 and v < n)) return null;
    return @intFromFloat(v);
}
