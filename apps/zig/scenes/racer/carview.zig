// --------------------------------------------------------------------------
// RACER: the car drawn into the frame: the camera's view recomposed for the car's own space (so the
// model's Q7 vertices go through the very same transform, clip and fill as the track's) and its
// polygons pushed into the frame's list between collect and sort. Since M5 step 3 (the GT car) every
// face of a car takes ONE key (its middle's depth, never below the ground face under it, or a long
// road quad would paint over it) and the painter's order inside the car is the model's: the shadow,
// the wheels, the hull, then the cabin and the wing, swapped by which side of the wing the eye is
// on. A non-convex car sorted per face at 1/8 unit buckets mis-sorts; this order is right for every
// eye above the deck, which every POV is. Past LOD1_Z a car is the far model. No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const fx = @import("fx.zig");
const groundmod = @import("ground.zig");
const project = @import("project.zig");
const std = @import("std");
const trk = @import("trk.zig");
const types = @import("types.zig");
const xf = @import("xform.zig");

pub const Snap = struct { pos: [3]i32, angle: i32 };
/// The view depth (Q16) past which a car is drawn with the far model: 6 units, where the car is ~13 pixels long.
pub const LOD1_Z: i32 = 6 << 16;

/// Draw one car of track `t`: model `m` (carmodel.of(k)) in livery `liv` (carmodel.LIVERY: 0 is the player's).
pub fn draw(fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, t: *const trk.Track, s: Snap, ground: ?u16, m: *const carmodel.Model, liv: carmodel.Livery) void {
    const mv = modelView(v, s);
    const z = mv.t[2] + fx.mulsh16(mv.r[2][1], m.mid_y);
    const under: ?u16 = if (ground) |g| fr.faceKey(g) else null;
    const floor: ?u16 = if (nearCorner(fr, t, m, &mv, s, ground)) |k| @max(k, under orelse 0) else under;
    const key = @max(project.depthKey(z), floor orelse 0);
    cache.next();
    const sh = &m.range(.shadow)[0];
    _ = project.build(fr, cache, m.verts, &mv, sh, .{ .fixed = floor orelse key, .shadow = true });
    const k = Look{ .key = key, .body = carmodel.shiftTo(liv.body), .stripe = carmodel.shiftTo(liv.stripe) };
    if (z > LOD1_Z) return part(fr, cache, m, &mv, .lod1, k);
    part(fr, cache, m, &mv, .wheels, k);
    part(fr, cache, m, &mv, .hull, k);
    const behind = mv.eye7[2] < m.wing_z;
    part(fr, cache, m, &mv, if (behind) .cabin else .wing, k);
    part(fr, cache, m, &mv, if (behind) .wing else .cabin, k);
}

const Look = struct { key: u16, body: u8, stripe: u8 };

/// The key of the ground face under the shadow's corner nearest the eye. The shadow lies flat on the road, so a road quad
/// nearer than the car's own (the one behind it, seen from the chase POV) would paint over it: the shadow and the car take
/// that quad's key when it is the higher. One face lookup a car, the car's own face tried first (ground.findFace).
fn nearCorner(fr: *const frame.Frame, t: *const trk.Track, m: *const carmodel.Model, mv: *const cam.View, s: Snap, ground: ?u16) ?u16 {
    const sh = &m.range(.shadow)[0];
    var best: trk.Vert = m.verts[sh.v[0]];
    var bd: i64 = std.math.maxInt(i64);
    for (sh.v) |id| {
        const p = m.verts[id];
        const dx: i64 = p[0] - mv.eye7[0];
        const dz: i64 = p[2] - mv.eye7[2];
        if (dx * dx + dz * dz < bd) {
            bd = dx * dx + dz * dz;
            best = p;
        }
    }
    const c = fix.cos(s.angle);
    const d = -fix.sin(s.angle);
    const x: i32 = @as(i32, best[0]) << 9;
    const zz: i32 = @as(i32, best[2]) << 9;
    const w = [3]i32{ s.pos[0] + fix.mul(c, x) + fix.mul(d, zz), s.pos[1], s.pos[2] - fix.mul(d, x) + fix.mul(c, zz) };
    const f = groundmod.findFace(t, w, ground) orelse return null;
    return fr.faceKey(f.face);
}

fn part(fr: *frame.Frame, cache: *xf.Cache, m: *const carmodel.Model, mv: *const cam.View, p: carmodel.Part, k: Look) void {
    for (m.range(p)) |*f| {
        if (types.facing(f, mv) <= f.cp) continue;
        const dc: u8 = if (f.flags & carmodel.FLAG_BODY != 0) k.body else if (f.flags & carmodel.FLAG_STRIPE != 0) k.stripe else 0;
        _ = project.build(fr, cache, m.verts, mv, f, .{ .fixed = k.key, .dc = dc });
    }
}

/// True when the car at `pos` is within `tiles` tiles (8 units each) of the eye: farther cars are not worth transforming.
pub fn inRange(v: *const cam.View, pos: [3]i32, tiles: u32) bool {
    const dx: i64 = v.eye7[0] - (pos[0] >> 9);
    const dz: i64 = v.eye7[2] - (pos[2] >> 9);
    const r: i64 = @as(i64, tiles) * 8 * 128;
    return dx * dx + dz * dz <= r * r;
}

/// The camera's view recomposed for the car's own space: rows right-multiplied by the car's yaw,
/// the translation carrying the car's position, the eye in the car's Q7 space (the back-face test).
pub fn modelView(v: *const cam.View, s: Snap) cam.View {
    const c = fix.cos(s.angle);
    const d = -fix.sin(s.angle);
    var m = v.*;
    for (0..3) |i| {
        const r = v.r[i];
        m.r[i] = .{ fx.mulsh16(r[0], c) + fx.mulsh16(r[2], -d), r[1], fx.mulsh16(r[0], d) + fx.mulsh16(r[2], c) };
        m.t[i] = v.t[i] + @as(i32, @truncate((dot25(r[0], s.pos[0]) + dot25(r[1], s.pos[1]) + dot25(r[2], s.pos[2])) >> 9));
    }
    const dx = v.eye7[0] - (s.pos[0] >> 9);
    const dz = v.eye7[2] - (s.pos[2] >> 9);
    m.eye7 = .{ fx.mulsh16(c, dx) + fx.mulsh16(-d, dz), v.eye7[1] - (s.pos[1] >> 9), fx.mulsh16(d, dx) + fx.mulsh16(c, dz) };
    if (fx.use_f32) cam.floatView(&m);
    return m;
}

/// (a * b) >> 16 kept in 64 bits: a Q25 row times a Q16 position passes 2^31 once the car is 64 units out (the oval is 90 long).
fn dot25(a: i32, b: i32) i64 {
    return (@as(i64, a) * b) >> 16;
}
