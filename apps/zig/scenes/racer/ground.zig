// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// is_inside, find_face, face_collide.
//
// RACER: the ground the physics drives on. A ground face (flag 0x10 in the track binary) is
// looked at through its vertices in Q16, its plane normal computed the way the reference does
// (`v_normz(v_cross(last - first, second - first))`, nothing baked) and its wall edges from the
// border mask: the wall normal is the edge turned a quarter in the x/z plane, pointing inside.
// A tile the physics looks up is `x | z << 5` on the 32 x 32 grid; off the grid there is no
// ground (the Lua would alias the key onto another tile: a position there is a bug, not a lap).
// The face id the reference dumps is the 1-based face index.
// No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const V = vec.V;
const memo = @import("groundmemo.zig");

pub const FLAG_ASPHALT: u8 = 4;
pub const FLAG_GROUND: u8 = 0x10;

pub const Poly = struct { p: [4]V, ni: u8, n: V };
pub const Hit = struct { hit: bool = false, force: V = .{ 0, 0, 0 }, n: V = .{ 0, 0, 0 } };
pub const Found = struct { face: u16, y: i32 };

/// A track vertex (1/128 unit) as Q16.
pub fn vertex(t: *const trk.Track, id: u16) V {
    const s = t.verts[id];
    return .{ @as(i32, s[0]) << 9, @as(i32, s[1]) << 9, @as(i32, s[2]) << 9 };
}

pub fn poly(t: *const trk.Track, id: u16) Poly {
    var r = corners(t, id);
    r.n = memo.normal(&r).*; // v_normz(v_cross(last - first, second - first)), remembered (groundmemo.zig)
    return r;
}

/// A face's vertices, its normal not computed yet (the side tests need none: board optimisation).
fn corners(t: *const trk.Track, id: u16) Poly {
    const f = &t.faces[id];
    var r = Poly{ .p = undefined, .ni = f.nv, .n = undefined };
    for (0..f.nv) |i| r.p[i] = vertex(t, f.v[i]);
    return r;
}

fn within(f: *const Poly, p: V) bool {
    var p0 = f.p[f.ni - 1];
    for (f.p[0..f.ni]) |p1| {
        const side = fix.mul(p0[2] -% p1[2], p[0] -% p0[0]) +% fix.mul(p1[0] -% p0[0], p[2] -% p0[2]);
        if (side < 0) return false;
        p0 = p1;
    }
    return true;
}

fn height(f: *const Poly, p: V) i32 {
    const t = fix.div(-vec.dot(vec.between(f.p[0], p), f.n), f.n[1]);
    return p[1] +% t;
}

/// The point-in-polygon test of is_inside (x/z, every edge on its inner side); the ground height below `p`.
pub fn isInside(f: *const Poly, p: V) ?i32 {
    return if (within(f, p)) height(f, p) else null;
}

fn tileOf(p: V) ?usize {
    const x = ((p[0] >> 3) +% (16 << 16)) >> 16;
    const z = ((p[2] >> 3) +% (16 << 16)) >> 16;
    if (x < 0 or x >= trk.GRID or z < 0 or z >= trk.GRID) return null;
    return @intCast(x | (z << 5));
}

fn test1(t: *const trk.Track, id: u16, p: V) ?Found {
    var f = corners(t, id);
    if (!within(&f, p)) return null; // most candidates end here: no normal (a sqrt and three divides) for them
    f.n = memo.normal(&f).*;
    return .{ .face = id, .y = height(&f, p) };
}

/// A ground face more than this above or below the car is another deck (M5 finish; the 32X DXHIGH's figure-8 decks are
/// 1.1-1.2 units apart, a car moves well under 0.1 a tick on any slope).
pub const DECK_Y: i32 = 1 << 15; // 0.5 unit
pub var break_decks = false; // the native test's mutant: freds72's x/z-only pick

/// find_face: the previous face first, then the ground faces of the tile, in the track's order. freds72's lookup takes
/// the first face under the car in x/z; at a crossing (one road over another) that can be the other deck. Now the first
/// face within DECK_Y of the car's height wins, and only if there is none the first face (freds72's) does. On a track
/// with no ground over ground (every shipped one: front_test.zig sweeps them) the two are the same face.
pub fn findFace(t: *const trk.Track, p: V, old: ?u16) ?Found {
    if (old) |o| if (test1(t, o, p)) |f| return f;
    const tile = tileOf(p) orelse return null;
    var first: ?Found = null;
    for (t.tileFaces(tile)) |id| {
        if (t.faces[id].flags & FLAG_GROUND == 0 or id == old) continue;
        const f = test1(t, id, p) orelse continue;
        if (break_decks or @abs(f.y -% p[1]) <= DECK_Y) return f;
        if (first == null) first = f;
    }
    return first;
}

/// The wall normal of border edge `k` of a face: (a - b) flattened, unit, turned a quarter.
pub fn borderNormal(f: *const Poly, k: usize) V {
    const a = f.p[k];
    const b = f.p[(k + 1) % f.ni];
    var d = vec.between(b, a);
    d[1] = 0;
    d = vec.normz(d);
    return .{ d[2], 0, -d[0] };
}

/// face_collide: how far `p` (radius r) is pushed back by the face's walls, and the last wall's normal.
pub fn faceCollide(t: *const trk.Track, id: u16, p: V, r: i32) Hit {
    const f = corners(t, id); // the plane normal unused here
    const mask = t.faces[id].borders;
    var h = Hit{};
    for (0..f.ni) |k| {
        if (mask & (@as(u16, 1) << @intCast(k)) == 0) continue;
        const n = memo.border(&f, k); // borderNormal, remembered
        const dist = vec.dot(vec.between(f.p[k], p), n);
        if (dist >= r) continue;
        h.hit = true;
        h.n = n;
        h.force = vec.add(h.force, n, r -% dist);
    }
    return h;
}
