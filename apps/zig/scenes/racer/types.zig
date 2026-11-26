// --------------------------------------------------------------------------
// RACER: the frame's plain types and two small tests on them (no ZigOS import).
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");

pub const MAXV = clip.MAXV;

pub const Rec = struct { n: u8, c: u8, x: [MAXV]i16, y: [MAXV]i16 }; // n | SHADOW: a car's shadow (frame.emit)
/// Rec.n's top bit: the polygon is a shadow, drawn by darkening what is under it (shadow.zig), its colour unused.
pub const SHADOW: u8 = 0x80;
pub const Stats = struct {
    tiles: u32 = 0, // PVS entries drawn
    faces: u32 = 0, // submitted: first sight this frame
    back: u32 = 0, // back-face culled
    rejected: u32 = 0, // frustum reject (and clipped away)
    clipped: u32 = 0,
    verts: u32 = 0, // transformed
    polys: u32 = 0, // kept: faces and decals
    dropped: u32 = 0,
};

pub inline fn facing(f: *const trk.Face, v: *const cam.View) i32 {
    return f.n[0] * v.eye7[0] + f.n[1] * v.eye7[1] + f.n[2] * v.eye7[2];
}

pub fn offScreen(r: *const Rec) bool {
    var x0: i16 = r.x[0];
    var x1: i16 = x0;
    var y0: i16 = r.y[0];
    var y1: i16 = y0;
    for (1..r.n) |i| {
        x0 = @min(x0, r.x[i]);
        x1 = @max(x1, r.x[i]);
        y0 = @min(y0, r.y[i]);
        y1 = @max(y1, r.y[i]);
    }
    return x1 < 0 or x0 >= 320 * 16 or y1 < xf.Y0 * 16 or y0 >= xf.Y1 * 16;
}
