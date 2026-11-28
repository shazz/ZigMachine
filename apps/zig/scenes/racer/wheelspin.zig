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
pub const SPIN_SHIFT: u5 = 10; // total_r (Q16 turns) << 10 = (total_r / 64) as a u32 turn
pub var break_still = false; // racer_batch.mjs --break still (key &): the wheels never posed (the pre-batch cars)
pub const STEER_SHIFT: u5 = 15; // steer_angle (Q16 turns) << 15 = half of it as a u32 turn

/// Group g: bit 0 the right side (x >= 0), bit 1 the front axle (z above the wheels' middle). Small (a car set holds
/// five models and the cart's RAM window is tight): a vertex's group is found from its position when posed.
/// i32 fields (board optimisation): a [3]i16 element at a 2-mod-4 address was read as one 32-bit load and trapped.
pub const Groups = struct {
    centre: [4][3]i32 = @splat(.{ 0, 0, 0 }),
    zmid: i32 = 0,
    any: bool = false,

    pub fn of(self: *const Groups, v: anytype) u8 { // a trk.Vert or a [3]i32 (vert())
        return @as(u8, @intFromBool(@as(i32, v[0]) >= 0)) | @as(u8, @intFromBool(@as(i32, v[2]) > self.zmid)) << 1;
    }
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
    g.zmid = (zlo + zhi) >> 1;
    var lo: [4][3]i32 = @splat(@splat(std.math.maxInt(i32)));
    var hi: [4][3]i32 = @splat(@splat(std.math.minInt(i32)));
    for (wheels) |f| for (f.v[0..f.nv]) |id| {
        const v = verts[id];
        const k = g.of(v);
        for (0..3) |a| {
            lo[k][a] = @min(lo[k][a], v[a]);
            hi[k][a] = @max(hi[k][a], v[a]);
        }
    };
    for (&g.centre, lo, hi) |*c, l, h| {
        if (l[0] > h[0]) continue; // an empty group (a three-wheeler, an axle drawn as one piece)
        for (0..3) |a| c[a] = (l[a] + h[a]) >> 1;
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
/// plane constants recomputed): the faces to draw with `vs`. Null: draw the model's own (no spin, no steer, no groups, or
/// scratch too small: carview's is carved at init, MAX_VERTS and MAX_FACES).
pub fn pose(g: *const Groups, verts: []const trk.Vert, wheels: []const trk.Face, spin: u32, steer: u32, vs: []trk.Vert, fs: []trk.Face) ?[]const trk.Face {
    if (break_still or !g.any or (spin == 0 and steer == 0) or wheels.len > fs.len or verts.len > vs.len) return null;
    const r = Rot{ .sc = fx.cos(spin), .ss = fx.sin(spin), .tc = fx.cos(steer), .ts = fx.sin(steer) };
    @memcpy(vs[0..verts.len], verts);
    var done: [MAX_VERTS / 8]u8 = @splat(0);
    for (wheels) |f| for (f.v[0..f.nv]) |id| {
        if (done[id >> 3] & (@as(u8, 1) << @intCast(id & 7)) != 0) continue;
        done[id >> 3] |= @as(u8, 1) << @intCast(id & 7);
        const v = vert(verts, id);
        const k = g.of(v);
        const c = g.centre[k];
        const t = turn(.{ v[0] - c[0], v[1] - c[1], v[2] - c[2] }, r, k & 2 != 0);
        for (0..3) |a| vs[id][a] = @intCast(std.math.clamp(t[a] + c[a], -32768, 32767));
    };
    @memcpy(fs[0..wheels.len], wheels); // WHY: a struct copy `o.* = f` was lowered to i64 loads at offsets 2 and 18 (traps)
    for (wheels, fs[0..wheels.len]) |*f, *o| {
        const n = turn(.{ f.n[0], f.n[1], f.n[2] }, r, g.of(vert(verts, f.v[0])) & 2 != 0);
        for (0..3) |a| o.n[a] = @intCast(std.math.clamp(n[a], -32768, 32767));
        const p = vert(vs, f.v[0]);
        o.cp = @truncate(@as(i64, o.n[0]) * p[0] + @as(i64, o.n[1]) * p[1] + @as(i64, o.n[2]) * p[2]);
    }
    return fs[0..wheels.len];
}

/// Vertex `id` read one i16 at a time through volatile pointers: a [3]i16 copy at a 2-mod-4 address became a 32-bit load
/// LLVM merged (wasm allows it; ZIGGY's aligned translation traps on it, ~210 cycles: perf_audit's misaligned probe).
pub inline fn vert(vs: []const trk.Vert, id: u16) [3]i32 {
    const p: [*]const volatile i16 = @ptrCast(&vs[id]);
    return .{ p[0], p[1], p[2] };
}

/// A car's spin and steer as drawn (game.zig's snapshot): its wheel turns and its steer angle, both Q16 turns.
pub fn ofCar(total_r: i32, steer_angle: i32) [2]u32 {
    return .{ @as(u32, @bitCast(total_r)) << SPIN_SHIFT, @as(u32, @bitCast(steer_angle)) << STEER_SHIFT };
}
