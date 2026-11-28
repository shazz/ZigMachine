// --------------------------------------------------------------------------
// RACER: the visibility oracle (R82 bug pass, Matt 27 Nov: "track faces sometimes disappear"). Key 2:
// the frame draws, besides the baked PVS list, every non-empty tile the camera's REAL view wedge (from the
// eye itself, not its tile's centre; the projection's 45 degrees each side) crosses within the PVS' own
// distance (R steps of the DDA: a Manhattan distance from the camera's tile), and after the fill counts
// the faces that were kept (in the frustum, on screen) but that no tile of the PVS list holds: the faces
// the PVS lost. view.zig logs `racer,pvs,<lost>,<kept>,<blinks>,<dropped>,<buried>` every frame (blinks: faces kept two frames ago and now but not
// in between; buried: kept non-ground faces keyed under the ground face below their foot: the painter's order) while it is on (racer_bugpass.mjs).
// Debug only: the default frame never runs it. No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const pvs = @import("pvs.zig");
const ground = @import("ground.zig");
const trk = @import("trk.zig");
const under = @import("under.zig");

pub var all_tiles = false; // key 2
var hist: [10240]u8 = [_]u8{0} ** 10240; // per face: kept last frame (bit 0), the frame before (bit 1): blinks

/// The PVS list `base` (far to near) plus every non-empty tile within `r` Manhattan steps of the camera's tile that the
/// view wedge crosses, into `out` (far to near by that distance).
pub fn allTiles(t: *const trk.Track, v: *const cam.View, r: u32, base: []const u16, out: *[pvs.MAX_ENTRIES]u16) []const u16 {
    const w = wedge(v, r);
    const ox: i32 = @intCast(v.tile % trk.GRID);
    const oz: i32 = @intCast(v.tile / trk.GRID);
    const ri: i32 = @intCast(r);
    var n: usize = 0;
    var d: i32 = ri;
    while (d >= 0) : (d -= 1) {
        for (base) |e| if (pvs.distOf(e) == d and n < out.len) {
            out[n] = e;
            n += 1;
        };
        var z = oz - d;
        while (z <= oz + d) : (z += 1) {
            const dx = d - @as(i32, @intCast(@abs(z - oz)));
            for ([2]i32{ ox - dx, ox + dx }, 0..) |x, k| {
                if (k == 1 and dx == 0) continue;
                if (x < 0 or z < 0 or x >= trk.GRID or z >= trk.GRID or n == out.len) continue;
                const i: u16 = @intCast(z * trk.GRID + x);
                if (t.tile_first[i + 1] == t.tile_first[i] or inList(base, i) or !crosses(&w, x, z)) continue;
                out[n] = i | @as(u16, @intCast(d)) << 10;
                n += 1;
            }
        }
    }
    return out[0..n];
}

fn inList(l: []const u16, tile: u16) bool {
    for (l) |e| if (pvs.tileOf(e) == tile) return true;
    return false;
}

/// The view's 2D wedge as a long triangle (Q7 world x/z): the eye and two points 45 degrees either side of the yaw.
fn wedge(v: *const cam.View, r: u32) [3]under.Pt {
    const fx: i64 = v.r[2][0];
    const fz: i64 = v.r[2][2];
    const len: i64 = std.math.sqrt(@as(u64, @intCast(fx * fx + fz * fz)));
    const l: i64 = (@as(i64, r) + 2) * 1024 * 2; // Q7: past R tiles, the wedge's sides 1.41 x that
    const e = under.Pt{ v.eye7[0], v.eye7[2] };
    return .{ e, .{ e[0] + @as(i32, @intCast(@divTrunc((fx - fz) * l, len))), e[1] + @as(i32, @intCast(@divTrunc((fz + fx) * l, len))) }, .{ e[0] + @as(i32, @intCast(@divTrunc((fx + fz) * l, len))), e[1] + @as(i32, @intCast(@divTrunc((fz - fx) * l, len))) } };
}

fn crosses(w: *const [3]under.Pt, x: i32, z: i32) bool {
    const x0 = (x - 16) * 1024;
    const z0 = (z - 16) * 1024;
    const sq = [4]under.Pt{ .{ x0, z0 }, .{ x0 + 1024, z0 }, .{ x0 + 1024, z0 + 1024 }, .{ x0, z0 + 1024 } };
    return under.convexOverlap(w, &sq);
}

/// After the frame: faces kept this frame (faceKey non-null) that no tile of `list` (the PVS) holds. Clears those faces'
/// frame stamps in `seen` to tell them apart, so it must run after everything that reads faceKey.
pub fn missed(t: *const trk.Track, list: []const u16, seen: []u16, stamp: u16, fr: anytype) [4]u32 {
    var kept: u32 = 0;
    var blinks: u32 = 0;
    var buried: u32 = 0;
    for (t.faces, 0..) |*f, fid| {
        const fk = fr.faceKey(@intCast(fid));
        const k = fk != null;
        kept += @intFromBool(k);
        if (fk) |key| buried += @intFromBool(buriedFace(t, f, key, fr));
        if (fid >= hist.len) continue;
        blinks += @intFromBool(k and hist[fid] == 2); // kept two frames ago, not last frame, kept now: a face that blinked out
        hist[fid] = (hist[fid] << 1 & 2) | @intFromBool(k);
    }
    for (list) |e| for (t.tileFaces(pvs.tileOf(e))) |fid| {
        seen[fid] = 0;
    };
    var lost: u32 = 0;
    for (seen, 0..) |s, fid| lost += @intFromBool(s == stamp and fr.fkey[fid] != 0xFFFF);
    return .{ lost, kept, blinks, buried };
}

/// A kept face that is not ground, whose key is below the key of the kept ground face under its lowest vertex: that
/// ground face is drawn after it (the painter's order by mean depth) and may paint over its foot. A count, not a proof.
fn buriedFace(t: *const trk.Track, f: *const trk.Face, key: u16, fr: anytype) bool {
    if (f.flags & ground.FLAG_GROUND != 0) return false;
    var low = t.verts[f.v[0]];
    for (f.v[1..f.nv]) |id| {
        if (t.verts[id][1] < low[1]) low = t.verts[id];
    }
    const g = ground.findFace(t, .{ @as(i32, low[0]) << 9, @as(i32, low[1]) << 9, @as(i32, low[2]) << 9 }, null) orelse return false;
    const gk = fr.faceKey(g.face) orelse return false;
    return gk > key;
}

const std = @import("std");
