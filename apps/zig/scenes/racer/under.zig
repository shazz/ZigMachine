// --------------------------------------------------------------------------
// RACER: the ground under a car's footprint (R82 bug pass, Matt 27 Nov: "the start/finish line and the
// skidmarks sometimes paint over the car"). A road decal is keyed to its parent ground face and the car
// takes ONE key, so a decal whose parent face is nearer than the car's middle painted over the car
// standing on it. A flat thing on the ground can only be seen over a car if the car stands on it, so the
// rule is: a car's key is never below the key of ANY kept ground face its footprint (the shadow's box,
// carfile.Foot, at the car's scale) overlaps in x/z on the car's own deck. Ties go to the car: it is
// pushed after collect, and the sort is stable. Exact by a separating-axis test (two convex polygons),
// a face's box tried first. No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const ground = @import("ground.zig");
const trk = @import("trk.zig");

pub const Pt = [2]i32; // x, z: Q7 world units
pub var break_under = false; // the harness' --break under: only the face under the centre (M5's rule, without its corner)

/// The footprint's four corners in the world (Q7), from the car's Q16 position, its yaw and its Q7 box at `size` (Q16).
pub fn corners(pos: [3]i32, angle: i32, size: i32, x0: i32, x1: i32, z0: i32, z1: i32) [4]Pt {
    const c = fix.cos(angle);
    const d = -fix.sin(angle);
    const xs = [4]i32{ x0, x1, x1, x0 };
    const zs = [4]i32{ z0, z0, z1, z1 };
    var out: [4]Pt = undefined;
    for (&out, xs, zs) |*o, lx, lz| {
        const x = fix.mul(lx << 9, size);
        const z = fix.mul(lz << 9, size);
        o.* = .{ (pos[0] + fix.mul(c, x) + fix.mul(d, z)) >> 9, (pos[2] - fix.mul(d, x) + fix.mul(c, z)) >> 9 };
    }
    return out;
}

/// The highest key of a kept ground face the footprint `q` overlaps within DECK_Y of height `y` (Q16), at least `floor`.
pub fn key(fr: *const frame.Frame, t: *const trk.Track, q: [4]Pt, y: i32, floor: ?u16) ?u16 {
    var lo = q[0];
    var hi = q[0];
    for (q[1..]) |p| {
        lo = .{ @min(lo[0], p[0]), @min(lo[1], p[1]) };
        hi = .{ @max(hi[0], p[0]), @max(hi[1], p[1]) };
    }
    const tx0 = tile(lo[0]);
    const tx1 = tile(hi[0]);
    const tz0 = tile(lo[1]);
    const tz1 = tile(hi[1]);
    var best: ?u16 = floor; // a face at or under it needs no test (the centre face's key, known already)
    var tz = tz0;
    while (tz <= tz1) : (tz += 1) {
        var tx = tx0;
        while (tx <= tx1) : (tx += 1) {
            for (t.tileFaces(@intCast(tx | tz << 5))) |id| {
                if (t.faces[id].flags & ground.FLAG_GROUND == 0) continue;
                const k = fr.faceKey(id) orelse continue;
                if (best != null and k <= best.?) continue;
                if (overlaps(t, &t.faces[id], q, lo, hi, y >> 9)) best = k;
            }
        }
    }
    return best;
}

fn tile(v: i32) u32 {
    return @intCast(@min(@max((v >> 10) + 16, 0), trk.GRID - 1)); // 8 units = 1024 Q7 a tile, tile 0 at -128 units
}

const DECK7: i32 = ground.DECK_Y >> 9;

fn overlaps(t: *const trk.Track, f: *const trk.Face, q: [4]Pt, lo: Pt, hi: Pt, y7: i32) bool {
    var p: [4]Pt = undefined;
    var flo = Pt{ 0x7fff_ffff, 0x7fff_ffff };
    var fhi = Pt{ -0x7fff_ffff, -0x7fff_ffff };
    var ylo: i32 = 0x7fff_ffff;
    var yhi: i32 = -0x7fff_ffff;
    for (f.v[0..f.nv], 0..) |id, i| {
        const v = t.verts[id];
        p[i] = .{ v[0], v[2] };
        flo = .{ @min(flo[0], v[0]), @min(flo[1], v[2]) };
        fhi = .{ @max(fhi[0], v[0]), @max(fhi[1], v[2]) };
        ylo = @min(ylo, v[1]);
        yhi = @max(yhi, v[1]);
    }
    if (fhi[0] < lo[0] or flo[0] > hi[0] or fhi[1] < lo[1] or flo[1] > hi[1]) return false;
    if (yhi < y7 - DECK7 or ylo > y7 + DECK7) return false; // another deck (a crossing)
    return convexOverlap(p[0..f.nv], &q);
}

/// Two convex polygons (x/z) share area or an edge: no separating axis among their edges.
pub fn convexOverlap(a: []const Pt, b: []const Pt) bool {
    return !separated(a, b) and !separated(b, a);
}

/// True when one of `a`'s edges is a separating axis of the two convex polygons (touching is not separated).
fn separated(a: []const Pt, b: []const Pt) bool {
    for (a, 0..) |p0, i| {
        const p1 = a[(i + 1) % a.len];
        const ax: i64 = p1[1] - p0[1];
        const az: i64 = p0[0] - p1[0];
        var amin: i64 = std.math.maxInt(i64);
        var amax: i64 = std.math.minInt(i64);
        for (a) |p| {
            const d = ax * p[0] + az * p[1];
            amin = @min(amin, d);
            amax = @max(amax, d);
        }
        var bmin: i64 = std.math.maxInt(i64);
        var bmax: i64 = std.math.minInt(i64);
        for (b) |p| {
            const d = ax * p[0] + az * p[1];
            bmin = @min(bmin, d);
            bmax = @max(bmax, d);
        }
        if (amax < bmin or bmax < amin) return true;
    }
    return false;
}

const std = @import("std");
