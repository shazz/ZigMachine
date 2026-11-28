// --------------------------------------------------------------------------
// RACER: the wheels turn (R82 board batch, item 3: "wheels are not rotating"). A car model's `wheels` part (the
// 32X cars' two axles, our GT's four tyres) is split once into four groups by side (x) and by axle (z against the
// part's middle), each with its centre (its box's middle, Q7 car space). A frame then draws the part through a
// posed copy: every wheel vertex turned about its group's axle (the x axis through the centre) by the car's SPIN,
// the front groups also turned about the vertical through their centre by its STEER; the faces' normals turn the
// same way and their plane constants are recomputed, so the back-face test stays right. The baked shades ride with
// their faces, so a turning tyre's light bands move: the wheel is seen to roll.
//   spin   the car's wheel turns (car.total_r, Q16 turns) / 64: at full speed a real wheel turns ~1.4 times
//          a 30 Hz tick, far past what an 8-sided tyre can show without spinning backwards (the wagon wheel), so the
//          drawn wheel rolls 1/64 of that: ~8 degrees a tick, ~14 a frame at the board's 17 fps (under the octagon's
//          22.5-degree half period, so it still reads forward), slow at a walk
//   steer  half the physics' steer angle (car.steer_angle, Q16 turns: freds72's 0.15 turn limit would be 54 degrees)
// A pose with no spin and no steer draws the model's own faces (the grid's pins are unchanged). Integer only.
// No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const fx = @import("fx.zig");
const trk = @import("trk.zig");

pub const MAX_VERTS = 256; // carfile.MAX_VERTS
pub const MAX_FACES = 256; // carfile.MAX_FACES
pub const NONE: u8 = 0xFF;
pub const SPIN_SHIFT: u5 = 10; // total_r (Q16 turns) << 10 = (total_r / 64) as a u32 turn
pub const STEER_SHIFT: u5 = 15; // steer_angle (Q16 turns) << 15 = half of it as a u32 turn

/// Group g: bit 0 the right side (x >= 0), bit 1 the front axle (z above the part's middle).
pub const Groups = struct {
    of: [MAX_VERTS]u8 = @splat(NONE), // a vertex id's group, NONE: not a wheel vertex
    centre: [4][3]i32 = @splat(.{ 0, 0, 0 }),
    any: bool = false,
};

/// The four groups of a model's wheel faces (comptime-capable: the built-in GT's are made at compile time).
pub fn groups(verts: []const trk.Vert, wheels: []const trk.Face) Groups {
    var g = Groups{};
    if (wheels.len == 0 or verts.len > MAX_VERTS) return g;
    var zlo: i32 = std.math.maxInt(i32);
    var zhi: i32 = std.math.minInt(i32);
    for (wheels) |f| for (f.v[0..f.nv]) |id| {
        zlo = @min(zlo, verts[id][2]);
        zhi = @max(zhi, verts[id][2]);
    };
    const zmid = (zlo + zhi) >> 1;
    var lo: [4][3]i32 = @splat(@splat(std.math.maxInt(i32)));
    var hi: [4][3]i32 = @splat(@splat(std.math.minInt(i32)));
    for (wheels) |f| for (f.v[0..f.nv]) |id| {
        const v = verts[id];
        const k: u8 = @as(u8, @intFromBool(v[0] >= 0)) | @as(u8, @intFromBool(v[2] > zmid)) << 1;
        g.of[id] = k;
        for (0..3) |a| {
            lo[k][a] = @min(lo[k][a], v[a]);
            hi[k][a] = @max(hi[k][a], v[a]);
        }
    };
    for (&g.centre, lo, hi) |*c, l, h| {
        if (l[0] > h[0]) continue; // an empty group (a three-wheeler, an axle drawn as one piece)
        c.* = .{ (l[0] + h[0]) >> 1, (l[1] + h[1]) >> 1, (l[2] + h[2]) >> 1 };
    }
    g.any = true;
    return g;
}

const Rot = struct { sc: i32, ss: i32, tc: i32, ts: i32 }; // spin cos / sin, steer cos / sin (Q16)

/// A point d (relative to its group's centre) turned: about x by the spin, then (front groups) about y by the steer.
fn turn(d: [3]i32, r: Rot, front: bool) [3]i32 {
    const y = fx.mulsh16(d[1], r.sc) - fx.mulsh16(d[2], r.ss);
    const z = fx.mulsh16(d[1], r.ss) + fx.mulsh16(d[2], r.sc);
    if (!front) return .{ d[0], y, z };
    return .{ fx.mulsh16(d[0], r.tc) + fx.mulsh16(z, r.ts), y, fx.mulsh16(z, r.tc) - fx.mulsh16(d[0], r.ts) };
}

/// The wheels posed into `vs` (a copy of every vertex, the wheel ones turned) and `fs` (the wheel faces, normals turned,
/// plane constants recomputed): the faces to draw with `vs`. Null: draw the model's own (no spin, no steer, no groups).
pub fn pose(g: *const Groups, verts: []const trk.Vert, wheels: []const trk.Face, spin: u32, steer: u32, vs: *[MAX_VERTS]trk.Vert, fs: *[MAX_FACES]trk.Face) ?[]const trk.Face {
    if (!g.any or (spin == 0 and steer == 0) or wheels.len > MAX_FACES) return null;
    const r = Rot{ .sc = fx.cos(spin), .ss = fx.sin(spin), .tc = fx.cos(steer), .ts = fx.sin(steer) };
    @memcpy(vs[0..verts.len], verts);
    for (verts, 0..) |v, id| {
        const k = g.of[id];
        if (k == NONE) continue;
        const c = g.centre[k];
        const t = turn(.{ v[0] - c[0], v[1] - c[1], v[2] - c[2] }, r, k & 2 != 0);
        for (0..3) |a| vs[id][a] = @intCast(std.math.clamp(t[a] + c[a], -32768, 32767));
    }
    for (wheels, fs[0..wheels.len]) |f, *o| {
        o.* = f;
        const k = g.of[f.v[0]];
        const n = turn(.{ f.n[0], f.n[1], f.n[2] }, r, k != NONE and k & 2 != 0);
        for (0..3) |a| o.n[a] = @intCast(std.math.clamp(n[a], -32768, 32767));
        const p = vs[f.v[0]];
        o.cp = @truncate(@as(i64, o.n[0]) * p[0] + @as(i64, o.n[1]) * p[1] + @as(i64, o.n[2]) * p[2]);
    }
    return fs[0..wheels.len];
}

/// A car's spin and steer as drawn (game.zig's snapshot): its wheel turns and its steer angle, both Q16 turns.
pub fn ofCar(total_r: i32, steer_angle: i32) [2]u32 {
    return .{ @as(u32, @bitCast(total_r)) << SPIN_SHIFT, @as(u32, @bitCast(steer_angle)) << STEER_SHIFT };
}
