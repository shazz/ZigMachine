// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; his itch.io page states "Code license: MIT"), re-written in Zig integers.
// Copyright (c) freds72, MIT. The MIT licence:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
//   associated documentation files (the "Software"), to deal in the Software without restriction,
//   including without limitation the rights to use, copy, modify, merge, publish, distribute,
//   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions: the above copyright notice and this
//   permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
//   OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// RACER: vertices to the screen, once a frame each (a frame stamp in the cache entry, as the
// original's per-frame vertex metatable did). A vertex is an i16 triple at 1/128 unit; the view's
// rows are Q25 so `mulsh16(row, v)` is a Q16 view coordinate in one multiply, nine a vertex.
//
// Each entry keeps the view coordinates, two outcode sets (the true frustum, to reject; the
// guard band + near plane, to know a polygon needs clipping) and, for a vertex inside the guard
// band, the screen position in Q4 (1/16 px): sx = CX + (x / z) * F with F = 160 px (90 degrees
// across 320), one `rcp` and two mulsh16 each. y grows down on the screen.
// No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");
const trk = @import("trk.zig");

pub const CX16: i32 = 160 * 16;
pub const CY16: i32 = 100 * 16;
pub const F4: i32 = 160 * 16;
pub const Y0: i32 = 12; // the 3D viewport's rows: [Y0, Y1), HUD bands above and below
pub const Y1: i32 = 188;

pub const Entry = struct {
    v: clip.V3,
    stamp: u32,
    sx: i16,
    sy: i16,
    rej: u8, // frustum: bit 0 near, 1 left, 2 right, 3 below, 4 above
    guard: u8, // clip.outside()
};

pub const Cache = struct {
    e: []Entry,
    stamp: u32 = 0,
    touched: u32 = 0, // vertices transformed since next()

    pub fn next(self: *Cache) void {
        self.touched = 0;
        self.stamp +%= 1;
        if (self.stamp == 0) { // a wrap: no stale entry may match the new stamp
            for (self.e) |*x| x.stamp = 0;
            self.stamp = 1;
        }
    }
};

pub const Screen = struct { x: i32, y: i32 };

/// View-space (z >= NEAR) to Q4 screen.
pub inline fn project(v: clip.V3) Screen {
    const inv: i32 = @intCast(fx.rcp(@intCast(v[2])));
    return .{
        .x = CX16 + fx.mulsh16(fx.mulsh16(v[0], inv), F4),
        .y = CY16 - fx.mulsh16(fx.mulsh16(v[1], inv), F4),
    };
}

fn rejectCodes(v: clip.V3) u8 {
    const x = v[0];
    const y = v[1];
    const z = v[2];
    var m: u8 = 0;
    if (z < clip.NEAR) m |= 1;
    if (x < -z) m |= 2;
    if (x > z) m |= 4;
    if (20 * y + 11 * z < 0) m |= 8;
    if (11 * z - 20 * y < 0) m |= 16;
    return m;
}

/// The A/B transform: nine f32 multiplies and three conversions a vertex (the FPU's 9-10 cycle ops).
fn viewF32(view: *const cam.View, vx: i32, vy: i32, vz: i32) clip.V3 {
    const x: f32 = @floatFromInt(vx);
    const y: f32 = @floatFromInt(vy);
    const z: f32 = @floatFromInt(vz);
    var o: clip.V3 = undefined;
    for (&o, view.rf, view.tf) |*d, row, t| d.* = @intFromFloat(row[0] * x + row[1] * y + row[2] * z + t);
    return o;
}

pub inline fn get(c: *Cache, view: *const cam.View, verts: []const trk.Vert, id: u16) *Entry {
    const e = &c.e[id];
    if (e.stamp == c.stamp) return e;
    c.touched += 1;
    const s = verts[id];
    const vx: i32 = s[0];
    const vy: i32 = s[1];
    const vz: i32 = s[2];
    if (fx.use_f32) {
        e.v = viewF32(view, vx, vy, vz);
    } else e.v = .{
        fx.mulsh16(view.r[0][0], vx) + fx.mulsh16(view.r[0][1], vy) + fx.mulsh16(view.r[0][2], vz) + view.t[0],
        fx.mulsh16(view.r[1][0], vx) + fx.mulsh16(view.r[1][1], vy) + fx.mulsh16(view.r[1][2], vz) + view.t[1],
        fx.mulsh16(view.r[2][0], vx) + fx.mulsh16(view.r[2][1], vy) + fx.mulsh16(view.r[2][2], vz) + view.t[2],
    };
    e.stamp = c.stamp;
    e.rej = rejectCodes(e.v);
    e.guard = clip.outside(e.v);
    if (e.guard == 0) {
        const p = project(e.v);
        e.sx = @intCast(p.x);
        e.sy = @intCast(p.y);
    }
    return e;
}
