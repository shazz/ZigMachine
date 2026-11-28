// --------------------------------------------------------------------------
// RACER: a PVS tile out of the view is not walked (R82 board optimisation, OPTIMIZE.md). A third of the track faces a
// race frame transforms are then rejected by the frustum; a tile whose faces all lie past one plane of the view gives
// only such faces. Each tile keeps the bounding sphere of its faces' vertices (built once a track, on its first frame:
// keyed by the track's slices, so a track loaded into the same buffer is rebuilt); collect skips a tile whose sphere
// is wholly past a plane (carcull.sphereOut). Every skipped face would have been rejected (all its vertices past that
// plane): the picture, the kept faces' keys and faceKey's answers are the same. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const cam = @import("cam.zig");
const carcull = @import("carcull.zig");
const fx = @import("fx.zig");
const trk = @import("trk.zig");

const Sphere = struct { c: [3]i16 = .{ 0, 0, 0 }, r: u16 = 0 }; // Q7; r = 0: an empty tile
var spheres: [trk.TILES]Sphere = @splat(.{});
var key: [4]usize = .{ 0, 0, 0, 0 };
pub var break_cull = false; // the native test's A/B: every tile walked

/// Rebuild the spheres when `t` is not the track they were built for.
pub fn ensure(t: *const trk.Track) void {
    const k = [4]usize{ @intFromPtr(t.verts.ptr), t.verts.len, @intFromPtr(t.faces.ptr), t.tile_faces.len ^ (@as(usize, t.faces.len) << 16) };
    if (std.mem.eql(usize, &k, &key)) return;
    key = k;
    for (&spheres, 0..) |*s, tile| s.* = sphereOf(t, tile);
}

/// Forget the table (a track was loaded: trackset.setTrack), so the next frame rebuilds it even in the same buffer.
pub fn forget() void {
    key = .{ 0, 0, 0, 0 };
}

fn sphereOf(t: *const trk.Track, tile: usize) Sphere {
    var lo = [3]i32{ std.math.maxInt(i32), std.math.maxInt(i32), std.math.maxInt(i32) };
    var hi = [3]i32{ std.math.minInt(i32), std.math.minInt(i32), std.math.minInt(i32) };
    var any = false;
    for (t.tileFaces(tile)) |fid| {
        const f = &t.faces[fid];
        for (f.v[0..f.nv]) |id| for (0..3) |a| {
            lo[a] = @min(lo[a], t.verts[id][a]);
            hi[a] = @max(hi[a], t.verts[id][a]);
        };
        for (t.inner[f.inner_first..][0..f.inner_n]) |*d| for (d.v[0..d.nv]) |id| for (0..3) |a| { // its decals too
            lo[a] = @min(lo[a], t.verts[id][a]);
            hi[a] = @max(hi[a], t.verts[id][a]);
        };
        any = true;
    }
    if (!any) return .{};
    var c: [3]i16 = undefined;
    var r2: u64 = 0;
    for (0..3) |a| {
        c[a] = @intCast((lo[a] + hi[a]) >> 1);
        const h: u64 = @intCast(@max(hi[a] - c[a], c[a] - lo[a]));
        r2 += h * h;
    }
    return .{ .c = c, .r = @intCast(@min(std.math.sqrt(r2) + 2, 0xFFFF)) };
}

/// True when every face of `tile` is past one plane of the view `v` (the tile can be skipped).
pub fn outside(v: *const cam.View, tile: usize) bool {
    const s = spheres[tile];
    if (break_cull or s.r == 0) return false;
    const z = fx.use_zmx;
    var c: [3]i32 = undefined;
    for (&c, v.r, v.t) |*o, row, tt| o.* = fx.mulshK(z, row[0], s.c[0]) + fx.mulshK(z, row[1], s.c[1]) + fx.mulshK(z, row[2], s.c[2]) + tt;
    return carcull.sphereOut(c, @as(i32, s.r) << 9);
}
