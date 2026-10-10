// --------------------------------------------------------------------------
// The twelve vectorballs projected in INTEGERS: the default cart's half of
// my3d.draw() (balls_f32.zig is the same projection in f32, and says what the
// balls are).
//
// Every ball sits on the x = 0 plane, so three.js's whole matrix chain comes
// down to one rotation about x, the camera's translation and a divide by w:
//
//   y' = 60 (y cos a - z sin a)      z' = 60 (y sin a + z cos a)
//   w  = 800 - z'                    (the camera's distance, always 494..1106)
//   canvas y = 240 - K y' / w        sy = K / w        K = P5 * 240
//
// and what the raster fill really wants is 1/sy = w / K, which needs no divide
// by w at all. sin/cos come out of zigos's fixtrig table; everything is Q16.16;
// three 64-bit divides per ball, 36 a frame, against the f32 cart's matrix
// products and libm calls.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const trig = zg.fixtrig;
const F = @import("balls_f32.zig"); // POINTS, the lens, the camera

pub const ROT_STEP = trig.angle(F.ROT_STEP);
const HALF_H: i32 = F.CANVAS_H / 2;
const ONE: i64 = 1 << 16;

/// A projected bar, Q16.16: canvas y, the program's scale sy, its inverse (bar
/// rows per canvas pixel), and the world z' it is sorted by (larger = nearer).
pub const Part = struct { y: i32, sy: i32, inv: i32, z: i32 };

/// K = P5 * half height, Q16: the only lens figure the x = 0 plane needs.
var k_q16: i64 = 0;

pub fn init() void {
    k_q16 = @intFromFloat(@round(@as(f64, F.lens().projection.e[5]) * HALF_H * 65536.0));
}

/// The visible bars, far to near, as balls_f32.project returns them.
pub fn project(rotation: trig.Angle, out: []Part) []Part {
    const s = trig.sin(rotation);
    const c = trig.cos(rotation);
    var n: usize = 0;
    for (F.POINTS) |pt| {
        const yw: i64 = F.GROUP_SCALE * (pt[0] * c - pt[1] * s); // Q16
        const zw: i32 = F.GROUP_SCALE * (pt[0] * s + pt[1] * c);
        const w: i64 = (F.CAM_Z << 16) - zw;
        // clip z inside (0, 1) <=> near < w < far
        if (w <= F.NEAR * ONE or w >= F.FAR * ONE) continue;
        const ay = @divFloor(k_q16 * yw, w);
        const sy = @divFloor(k_q16 << 16, w);
        // the renderer's box is sy tall, so a bar whose centre leaves is dropped
        if (ay + sy < -HALF_H * ONE or ay - sy > HALF_H * ONE) continue;
        out[n] = .{
            .y = @intCast(HALF_H * ONE - ay),
            .sy = @intCast(sy),
            .inv = @intCast(@divFloor(w << 16, k_q16)),
            .z = zw,
        };
        n += 1;
    }
    std.sort.insertion(Part, out[0..n], {}, farther);
    return out[0..n];
}

fn farther(_: void, a: Part, b: Part) bool {
    return a.z < b.z;
}
