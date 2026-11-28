// --------------------------------------------------------------------------
// RACER: the car drawn into the frame: the camera's view recomposed for the car's own space (so the
// model's Q7 vertices go through the very same transform, clip and fill as the track's) and its
// polygons pushed into the frame's list between collect and sort. Since M5 step 3 (the GT car) every
// face of a car takes ONE key (its middle's depth, never below any ground face under its footprint:
// under.zig, or a road quad or a decal would paint over it) and the painter's order inside the car is the model's: the shadow,
// the wheels, the hull, then the cabin and the wing, swapped by which side of the wing the eye is
// on. A non-convex car sorted per face at 1/8 unit buckets mis-sorts; this order is right for every
// eye above the deck, which every POV is. Past LOD1_Z a car is the far model. No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const fx = @import("fx.zig");
const project = @import("project.zig");
const std = @import("std");
const groundmod = @import("ground.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");
const under = @import("under.zig");
const xf = @import("xform.zig");
const wheelspin = @import("wheelspin.zig");
const prof = @import("prof.zig");
const carcull = @import("carcull.zig");
const carlod = @import("carlod.zig");

/// size: the car drawn this many times its model (Q16; an ARCADE track's car scale, FEEL.md; 1 everywhere else); spin, steer:
/// the drawn wheels' turn and steer (u32 turns, wheelspin.zig; 0 = as modelled).
pub const Snap = struct { pos: [3]i32, angle: i32, size: i32 = fix.ONE, spin: u32 = 0, steer: u32 = 0 };

/// A race car's drawn pose (game.zig's snapshot of a tick): its position, heading, size, and its wheels' spin and steer.
pub fn snapOf(c: anytype) Snap {
    const w = wheelspin.ofCar(c.total_r, c.steer_angle);
    return .{ .pos = c.pos, .angle = c.angle, .size = c.size, .spin = w[0], .steer = w[1] };
}

/// The pose half way from a to b (the 60 Hz frame between two 30 Hz ticks).
pub fn midway(a: Snap, b: Snap) Snap {
    const turn: i32 = @as(i16, @truncate(b.angle -% a.angle));
    const p = [3]i32{ a.pos[0] + ((b.pos[0] - a.pos[0]) >> 1), a.pos[1] + ((b.pos[1] - a.pos[1]) >> 1), a.pos[2] + ((b.pos[2] - a.pos[2]) >> 1) };
    const spin: i32 = @bitCast(b.spin -% a.spin);
    const steer: i32 = @bitCast(b.steer -% a.steer);
    return .{ .pos = p, .angle = a.angle +% (turn >> 1), .size = b.size, .spin = a.spin +% @as(u32, @bitCast(spin >> 1)), .steer = a.steer +% @as(u32, @bitCast(steer >> 1)) };
}
/// The view depth (Q16) past which a car is drawn with the far model: 6 units, where the GT (drawn x2 since M5 step 5) is
/// ~26 pixels long (it was ~13; the switch was kept at 6 units: docs M5.md step 5).
pub const LOD1_Z: i32 = 6 << 16;

/// Draw one car of track `t`: model `m` (carmodel.of(k)) in livery `liv` (carmodel.LIVERY: 0 is the player's).
pub fn draw(fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, t: *const trk.Track, s: Snap, ground: ?u16, m: *const carmodel.Model, liv: carmodel.Livery) void {
    prof.begin(6);
    const mv = modelView(v, s);
    const z = mv.t[2] + fx.mulsh16(mv.r[2][1], m.mid_y);
    const centre: ?u16 = if (ground) |g| fr.faceKey(g) else null;
    const floor: ?u16 = if (under.break_under) m5Key(fr, t, m, v, s, ground, centre) else footKey(fr, t, m, s, centre);
    const key = @max(project.depthKey(z), floor orelse 0);
    cache.next();
    prof.end(6);
    if (!carcull.break_cull and carcull.outOfView(&mv, fix.mul(m.rad7 << 9, s.size))) return; // all faces would be rejected
    prof.begin(8);
    defer prof.end(8);
    if (!@import("hide.zig").on(@import("hide.zig").SHADOWS) and !carlod.noShadow(z, s.size)) {
        for (m.range(.shadow)) |*sh| _ = project.build(fr, cache, m.verts, &mv, sh, .{ .fixed = floor orelse key, .shadow = true });
    }
    const k = Look{ .key = key, .body = carmodel.shiftTo(liv.body), .stripe = carmodel.shiftTo(liv.stripe) };
    if (z > carlod.farZ(LOD1_Z, s.size)) return part(fr, cache, m, &mv, .lod1, k);
    if (carlod.stillWheels(z, s.size)) part(fr, cache, m, &mv, .wheels, k) else wheels(fr, cache, m, &mv, s, k);
    part(fr, cache, m, &mv, .hull, k);
    const behind = mv.eye7[2] < m.wing_z;
    part(fr, cache, m, &mv, if (behind) .cabin else .wing, k);
    part(fr, cache, m, &mv, if (behind) .wing else .cabin, k);
}

const Look = struct { key: u16, body: u8, stripe: u8 };

/// The highest key of the kept ground faces under the car's footprint (under.zig, R82 bug pass): a road decal (the start
/// line, a skid puff's face) or a road quad nearer than the car's middle never paints over the car standing on it.
fn footKey(fr: *const frame.Frame, t: *const trk.Track, m: *const carmodel.Model, s: Snap, centre: ?u16) ?u16 {
    const f = m.foot;
    const q = under.corners(s.pos, s.angle, s.size, f.x0, f.x1, f.z0, f.z1);
    return under.key(fr, t, q, s.pos[1], centre);
}

/// The M5 rule, kept as the harness' mutant (--break under, key O): the centre's face and the face under the footprint's
/// corner nearest the eye, nothing else.
fn m5Key(fr: *const frame.Frame, t: *const trk.Track, m: *const carmodel.Model, v: *const cam.View, s: Snap, ground: ?u16, centre: ?u16) ?u16 {
    const f = m.foot;
    const q = under.corners(s.pos, s.angle, s.size, f.x0, f.x1, f.z0, f.z1);
    var best = q[0];
    var bd: i64 = std.math.maxInt(i64);
    for (q) |p| {
        const dx: i64 = p[0] - v.eye7[0];
        const dz: i64 = p[1] - v.eye7[2];
        if (dx * dx + dz * dz < bd) {
            bd = dx * dx + dz * dz;
            best = p;
        }
    }
    const g = groundmod.findFace(t, .{ best[0] << 9, s.pos[1], best[1] << 9 }, ground) orelse return centre;
    const k = fr.faceKey(g.face) orelse return centre;
    return @max(k, centre orelse 0);
}

fn part(fr: *frame.Frame, cache: *xf.Cache, m: *const carmodel.Model, mv: *const cam.View, p: carmodel.Part, k: Look) void {
    faces(fr, cache, m.verts, mv, m.range(p), k);
}

fn faces(fr: *frame.Frame, cache: *xf.Cache, verts: []const trk.Vert, mv: *const cam.View, fs: []const trk.Face, k: Look) void {
    for (fs) |*f| {
        if (types.facing(f, mv) <= f.cp) continue;
        const dc: u8 = if (f.flags & carmodel.FLAG_BODY != 0) k.body else if (f.flags & carmodel.FLAG_STRIPE != 0) k.stripe else 0;
        _ = project.build(fr, cache, verts, mv, f, .{ .fixed = k.key, .dc = dc });
    }
}

pub var posed_vs: []trk.Vert = &.{}; // one car's posed wheels at a time (wheelspin.pose); carved at init (setup.zig)
pub var posed_fs: []trk.Face = &.{};

/// The wheels turned by the car's spin and steer (wheelspin.zig); a pose at rest draws the model's own faces.
fn wheels(fr: *frame.Frame, cache: *xf.Cache, m: *const carmodel.Model, mv: *const cam.View, s: Snap, k: Look) void {
    prof.begin(9);
    const posed = wheelspin.pose(&m.spin, m.verts, m.range(.wheels), s.spin, s.steer, posed_vs, posed_fs);
    prof.end(9);
    const fs = posed orelse return part(fr, cache, m, mv, .wheels, k);
    cache.next(); // WHY: the posed vertices share the model's ids: no transform cached from the model's may be reused
    faces(fr, cache, posed_vs[0..m.verts.len], mv, fs, k);
    cache.next(); // ... nor theirs by the hull after them
}

/// The race's cars (car 0 the player's; `skip0` in the cockpit) in range, pushed FAR TO NEAR (R82 bug pass): cars on one
/// ground face now share its key (a footprint raises a car to it), and a tie is drawn in push order, so the farther car
/// must go first, as the painter's order does for faces.
pub fn drawRace(fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, t: *const trk.Track, snaps: []const Snap, under_: []const ?u16, skip0: bool, tiles: u32) void {
    var order: [16]usize = undefined;
    var d: [16]i64 = undefined;
    var n: usize = 0;
    for (snaps, 0..) |s, k| {
        if ((k == 0 and skip0) or !inRange(v, s.pos, tiles + 1)) continue;
        const dx: i64 = v.eye7[0] - (s.pos[0] >> 9);
        const dz: i64 = v.eye7[2] - (s.pos[2] >> 9);
        var i = n; // insertion, farthest first
        while (i > 0 and d[i - 1] < dx * dx + dz * dz) : (i -= 1) {
            d[i] = d[i - 1];
            order[i] = order[i - 1];
        }
        d[i] = dx * dx + dz * dz;
        order[i] = k;
        n += 1;
    }
    defer carlod.ai = false;
    for (order[0..n]) |k| {
        carlod.ai = k != 0;
        draw(fr, cache, v, t, snaps[k], under_[k], carmodel.of(k), carmodel.LIVERY[k]);
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
    if (s.size != fix.ONE) sized(&m, s.size);
    if (fx.use_f32) cam.floatView(&m);
    return m;
}

/// A model drawn `size` times bigger: the rows scaled, the eye brought into the model's own (smaller) space.
fn sized(m: *cam.View, size: i32) void {
    for (&m.r) |*r| {
        for (r) |*e| e.* = @truncate((@as(i64, e.*) * size) >> 16);
    }
    for (&m.eye7) |*e| e.* = fix.div(e.*, size);
}

/// (a * b) >> 16 kept in 64 bits: a Q25 row times a Q16 position passes 2^31 once the car is 64 units out (the oval is 90 long).
fn dot25(a: i32, b: i32) i64 {
    return (@as(i64, a) * b) >> 16;
}
