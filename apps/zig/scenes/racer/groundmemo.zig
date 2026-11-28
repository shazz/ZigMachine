// --------------------------------------------------------------------------
// RACER: the ground's normals remembered (R82 board optimisation, OPTIMIZE.md). The physics asks for a ground face's
// plane normal and its wall normals many times a tick (every car, every sub-step, the wheel corners, the rollback), and
// each is a v_normz: a sqrt and three divides. They are pure functions of the face's vertices, so a small direct-mapped
// table keyed by the vertices THEMSELVES (not the face id: nothing to forget when a track replaces another in the same
// buffer) gives back the very same integers: the race pins hold bit for bit. No ZigOS import.
// --------------------------------------------------------------------------
const ground = @import("ground.zig");
const vec = @import("vec.zig");
const V = vec.V;

const N = 64;
const Entry = struct { p: [4]V = @splat(.{ 0, 0, 0 }), ni: u8 = 0, have: u8 = 0, n: V = .{ 0, 0, 0 }, bn: [4]V = @splat(.{ 0, 0, 0 }) };
var table: [N]Entry = @splat(.{});
pub var hits: u32 = 0; // the native test's counters
pub var misses: u32 = 0;

fn slot(f: *const ground.Poly) *Entry {
    const h: u32 = @bitCast(f.p[0][0] ^ (f.p[0][2] >> 3) ^ (f.p[1][0] >> 5) ^ (f.p[1][2] >> 7));
    const e = &table[(h ^ (h >> 9) ^ (h >> 17)) % N];
    if (e.ni == f.ni and same(e.p[0..f.ni], f.p[0..f.ni])) {
        hits +%= 1;
        return e;
    }
    misses +%= 1;
    e.* = .{ .p = f.p, .ni = f.ni };
    e.n = vec.normz(vec.cross(vec.between(f.p[0], f.p[f.ni - 1]), vec.between(f.p[0], f.p[1])));
    return e;
}

fn same(a: []const V, b: []const V) bool {
    for (a, b) |x, y| if (x[0] != y[0] or x[1] != y[1] or x[2] != y[2]) return false;
    return true;
}

/// The face's plane normal, as ground.poly always computed it: v_normz(v_cross(last - first, second - first)).
pub fn normal(f: *const ground.Poly) *const V {
    return &slot(f).n;
}

/// Wall normal k of the face (ground.borderNormal), computed once.
pub fn border(f: *const ground.Poly, k: usize) V {
    const e = slot(f);
    const bit = @as(u8, 1) << @intCast(k);
    if (e.have & bit == 0) {
        e.bn[k] = ground.borderNormal(f, k);
        e.have |= bit;
    }
    return e.bn[k];
}

/// Forget everything (the native test's A/B).
pub fn clear() void {
    table = @splat(.{});
}
