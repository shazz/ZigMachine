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
//
// Per frame it is integers: z, x, y in Q30 from a u64-turns angle, and each
// sampled index floor((d + 0.5 - origin) / z) by an incremental division (one
// real divide a frame). Q30 is ~1e-6 off the doubles, and a floor only differs
// where the quotient is that close to a whole number (the exact angles 0, PI/2,
// PI, where the doubles' last-bit noise decides): those pixels alone run the
// original f64 expression, so every frame is the doubles' frame.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fx = @import("../turns_fix.zig");
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

/// From the RAM arena (zg.mem), once per cart load: as module-scope arrays
/// they were 18 KB of zeros written into the cart binary.
var angle: *[FRAMES]f64 = undefined; // for the near-whole fallback only
var turns: *[FRAMES]u32 = undefined;
var owned = false;

const STEP_FAST: u64 = 1 << 58; // PI/32 in turns
const STEP_SLOW: u64 = 230584300921369395; // PI/40 = 2^64 / 80

pub fn init() void {
    if (!owned) {
        angle = zg.mem.mustAlloc(f64, FRAMES)[0..FRAMES];
        turns = zg.mem.mustAlloc(u32, FRAMES)[0..FRAMES];
        owned = true;
    }
    // The f64 table is init-time only (it keeps the doubles' last-bit noise for the fallback).
    const pi2 = 2.0 * std.math.pi;
    const speed_fast = std.math.pi / 32.0;
    const speed_slow = std.math.pi / 40.0;
    var a: f64 = std.math.pi;
    var t: u64 = 1 << 63;
    var c: usize = 0;
    for (SEGMENTS) |s| {
        for (0..s.frames) |_| {
            switch (s.step) {
                .hold_pi => {
                    a = std.math.pi;
                    t = 1 << 63;
                },
                .hold_0 => {
                    a = 0;
                    t = 0;
                },
                .down_40 => {
                    a -= speed_slow;
                    t -%= STEP_SLOW;
                },
                .down_32 => {
                    a -= speed_fast;
                    t -%= STEP_FAST;
                },
                .up_32 => {
                    a += speed_fast;
                    t +%= STEP_FAST;
                },
            }
            angle[c] = @rem(a, pi2); // JS %: the sign of the dividend
            turns[c] = fx.hi(t);
            c += 1;
        }
    }
}

const TOL: i64 = 8192; // Q30 units of the quotient's fraction trusted as a floor

/// The source index of each destination pixel along one axis (null off the image).
/// `origin` and `z` are Q30; `exact` re-does a pixel in doubles.
fn sampleAxis(out: []?u8, origin: i64, z: i64, comptime n: u8, fb: *Fallback, comptime axis: u8) void {
    const first = (fx.ONE >> 1) - origin; // d = 0
    var q = @divFloor(first, z);
    var r = first - q * z; // 0 <= r < z, in Q30 units of the numerator
    const step = @divFloor(fx.ONE, z);
    const rem = fx.ONE - step * z;
    const tol = (TOL * z) >> 30;
    for (out, 0..) |*o, d| {
        var v = q;
        if (r < tol or r > z - tol) v = fb.exact(d, axis, n);
        o.* = if (v >= 0 and v < n) @intCast(v) else null;
        q += step;
        r += rem;
        if (r >= z) {
            r -= z;
            q += 1;
        }
    }
}

/// The original expression, run only for the rare near-whole pixel.
const Fallback = struct {
    a: f64,
    ready: bool = false,
    z: f64 = 0,
    x: f64 = 0,
    y: f64 = 0,

    fn exact(self: *Fallback, d: usize, comptime axis: u8, comptime n: u8) i64 {
        if (!self.ready) {
            self.z = @cos(self.a) / 4.0 + 0.75;
            self.x = 64.0 - 64.0 * self.z;
            self.y = 45.0 + 40.0 * @sin(self.a);
            self.ready = true;
        }
        const origin = if (axis == 0) self.x else self.y;
        const v = @floor((@as(f64, @floatFromInt(d)) + 0.5 - origin) / self.z);
        if (!(v >= 0 and v < n)) return -1;
        return @intFromFloat(v);
    }
};

/// draw_logo into `view`, the 128x128 logo_canvas window of the plane.
pub fn draw(view: blit.Dst, iteration: u64) void {
    const i: usize = @intCast(iteration % FRAMES);
    const t = turns[i];
    const z = (fx.cos(t) >> 2) + (3 << 28); // cos / 4 + 0.75
    const x = 64 * (fx.ONE - z);
    const y = 45 * fx.ONE + 40 * fx.sin(t);
    var fb = Fallback{ .a = angle[i] };

    var src_x: [CANVAS]?u8 = undefined;
    var src_y: [CANVAS]?u8 = undefined;
    sampleAxis(&src_x, x, z, W, &fb, 0);
    sampleAxis(&src_y, y, z, H, &fb, 1);
    for (0..@min(CANVAS, view.h)) |dy| {
        const sy = src_y[dy] orelse continue;
        const src = logo_b[@as(usize, sy) * W ..][0..W];
        const dst = view.buf[dy * view.stride ..][0..CANVAS];
        for (src_x, dst) |sx, *d| {
            const p = src[sx orelse continue];
            if (p != 0) d.* = p;
        }
    }
}
