// --------------------------------------------------------------------------
// The glenz: a translucent object, every face drawn front AND back by CHISEL's
// TRIANGLE op with the OR minterm (MT_OR_BC), so where a front face lies over
// a back face the pixel is the OR of their palette lanes and the palette gives
// each combination its mixed colour (palette.zig).
//
// THE MATHS run on ZIGGY's FPU, in f32 only: the rotation matrix comes from
// the integer sine table (zg.fixtrig, no libm), then each vertex costs 9
// multiplies, 6 adds and one divide for the perspective -- about 250 f32 ops a
// frame for the 14-vertex star. No f64, no libm, nothing per pixel.
//
// THE ERASE is one CHISEL fill of last frame's bounding box; nothing else
// draws there (the stars come after and only on index 0).
//
// Each object stays OBJECT_TICKS: it flies in from the distance, tumbles on a
// Lissajous path across the middle of the screen, and flies away.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const O = @import("objects.zig");
const P = @import("palette.zig");
const T = @import("timeline.zig");

const CX: f32 = 200;
const CY: f32 = 153;
const FOCAL: f32 = 720; // px at distance 1, a long lens: a vertex is at most 720 / (NEAR - 1) = 62 px from the
const NEAR: f32 = 12.7; // centre and 57 at rest, so the box stays in rows 90..216, between the logo (..87) and scroller (218..)
const FAR: f32 = 60;
const OLD_OBJECTS = 2; // cube, octahedron

comptime {
    // the erase box must never reach the logo's or the scroller's band: those
    // parts skip rows they think unchanged, so a fill there would leave a hole
    const reach = 2.0 + FOCAL / (NEAR - 1.0);
    const logo_end: f32 = @import("logo.zig").TOP + @import("logo.zig").BAND;
    const scroll_top: f32 = @import("scroller.zig").TOP;
    if (CY - reach < logo_end or CY + reach + 1.0 >= scroll_top) @compileError("glenz: box leaves its band");
}
const SWING: f32 = 104; // Lissajous half-width, px

const Box = struct { x0: i16 = 0, y0: i16 = 0, x1: i16 = 0, y1: i16 = 0 };
var last: Box = .{};
var scheme: usize = 0xFFFF;
pub var tris: u32 = 0;

pub fn reset() void {
    last = .{};
    scheme = 0xFFFF;
}

fn q16(v: i32) f32 {
    return @as(f32, @floatFromInt(v)) * (1.0 / 65536.0);
}

fn erase(fb: *zg.LogicalFB, bl: *zg.Blitter) void {
    if (last.x1 > last.x0 and last.y1 > last.y0)
        bl.fill(fb, last.x0, last.y0, @intCast(last.x1 - last.x0), @intCast(last.y1 - last.y0), P.BG);
    last = .{};
}

/// The distance at local tick l of an object's stay: in, rest, out (the last
/// object stays: the gag breaks the screen around it).
fn distance(l: u32, stays: bool) f32 {
    const z = T.ZOOM_TICKS;
    const k: u32 = if (l < z) z - l else if (!stays and l + z > T.OBJECT_TICKS) l + z - T.OBJECT_TICKS else 0;
    const f = @as(f32, @floatFromInt(k * k)) * (1.0 / @as(f32, @floatFromInt(z * z)));
    return NEAR + (FAR - NEAR) * f;
}

/// The oldschool's glenz at tick t: a cube, then an octahedron that stays.
pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32) void {
    tris = 0;
    erase(fb, bl);
    if (t < T.GLENZ) return;
    const e = t - T.GLENZ;
    const n: usize = @min(e / T.OBJECT_TICKS, OLD_OBJECTS - 1); // the oldschool shows two
    object(fb, n, e, e - @as(u32, @intCast(n)) * T.OBJECT_TICKS, n == OLD_OBJECTS - 1, bl);
}

/// The finale's glenz: object n, e ticks of motion, l ticks into its stay.
pub fn finale(fb: *zg.LogicalFB, bl: *zg.Blitter, n: usize, e: u32, l: u32) void {
    tris = 0;
    erase(fb, bl);
    object(fb, n, e, l, false, bl);
}

fn object(fb: *zg.LogicalFB, n: usize, e: u32, l: u32, stays: bool, bl: *zg.Blitter) void {
    if (n != scheme) {
        scheme = n;
        P.glenz(fb.palette, n);
    }
    const obj = &O.ALL[n];
    // a tumble, not a spin: x swings a quarter turn either way while y and z run
    const ax: u32 = @as(u32, @bitCast(trig.sin(e *% (1 << 24)) << 14)) +% e *% (1 << 22);
    const ay: u32 = e *% (5 << 23);
    const az: u32 = e *% (7 << 22);
    const m = matrix(ax, ay, az);
    const d = distance(l, stays);
    const cx = CX + SWING * q16(trig.sin(e *% (1 << 23)));
    const cy = CY + 2.0 * q16(trig.sin(e *% (7 << 22)));
    var pts: [O.MAX_V]zg.BlitVec2 = undefined;
    var box = Box{ .x0 = 400, .y0 = 280, .x1 = 0, .y1 = 0 };
    for (0..obj.nv) |i| {
        const v = obj.v[i];
        const x = m[0] * v[0] + m[1] * v[1] + m[2] * v[2];
        const y = m[3] * v[0] + m[4] * v[1] + m[5] * v[2];
        const z = m[6] * v[0] + m[7] * v[1] + m[8] * v[2];
        const s = FOCAL / (z + d);
        const p = zg.BlitVec2{ .x = @intFromFloat(cx + x * s), .y = @intFromFloat(cy + y * s) };
        pts[i] = p;
        box = .{ .x0 = @min(box.x0, p.x), .y0 = @min(box.y0, p.y), .x1 = @max(box.x1, p.x + 1), .y1 = @max(box.y1, p.y + 1) };
    }
    for (0..obj.nt) |i| {
        const tr = obj.t[i];
        const a = pts[tr[0]];
        const b = pts[tr[1]];
        const c = pts[tr[2]];
        const cross = @as(i32, b.x - a.x) * (c.y - a.y) - @as(i32, b.y - a.y) * (c.x - a.x);
        const face = i >> @intCast(obj.per_face - 1); // a cube's quad is two triangles: one lane for both
        const lane: u8 = if (cross < 0)
            (if (face & 1 == 0) P.FRONT_A else P.FRONT_B)
        else
            (if (face & 1 == 0) P.BACK_A else P.BACK_B);
        bl.triangleEx(fb, a, b, c, lane, 0, .glenz);
        tris += 1;
    }
    last = .{ .x0 = @max(0, box.x0), .y0 = @max(0, box.y0), .x1 = @min(400, box.x1), .y1 = @min(280, box.y1) };
}

/// Rz * Ry * Rx, row-major, from integer-table sines.
fn matrix(ax: u32, ay: u32, az: u32) [9]f32 {
    const sx = q16(trig.sin(ax));
    const cx = q16(trig.cos(ax));
    const sy = q16(trig.sin(ay));
    const cy = q16(trig.cos(ay));
    const sz = q16(trig.sin(az));
    const cz = q16(trig.cos(az));
    return .{
        cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx,
        sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx,
        -sy,     cy * sx,                cy * cx,
    };
}
