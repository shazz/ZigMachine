// RACER: a car is never painted over by a road decal it stands on (under.zig, R82 bug pass). On Salt Flats and Glacier
// Pass, a car is put over every decal (its rear, its middle), headed four ways, with the far chase camera behind it at the
// ARCADE scale; whenever its footprint overlaps the decal, the car's key is at least the decal's parent face's key (the
// stable sort then draws the decal first). --break under (the centre's face only) must fail somewhere.
// `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const carview = @import("carview.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const testutil = @import("testutil.zig");
const trk = @import("trk.zig");
const under = @import("under.zig");

fn embedded(comptime name: []const u8) []align(4) const u8 {
    const raw = @embedFile("../../assets/screens/racer/" ++ name);
    const S = struct {
        const blob: [raw.len]u8 align(16) = raw.*;
    };
    return &S.blob;
}

const Tally = struct { checked: u32 = 0, painted_over: u32 = 0 };

fn centroid(t: *const trk.Track, f: *const trk.Face) under.Pt {
    var s = under.Pt{ 0, 0 };
    for (f.v[0..f.nv]) |id| s = .{ s[0] + t.verts[id][0], s[1] + t.verts[id][2] };
    return .{ @divTrunc(s[0], f.nv), @divTrunc(s[1], f.nv) };
}

fn outline(t: *const trk.Track, f: *const trk.Face, out: *[4]under.Pt) []under.Pt {
    for (f.v[0..f.nv], 0..) |id, i| out[i] = .{ t.verts[id][0], t.verts[id][2] };
    return out[0..f.nv];
}

/// One car over decal `d` of ground face `fid`: its key against the face's, when the footprint covers the decal.
fn one(fr: anytype, cache: anytype, t: *const trk.Track, fid: u16, d: *const trk.Face, angle: i32, off: i32, tally: *Tally) void {
    const size: i32 = @as(i32, t.scale.car) << 8;
    const c = centroid(t, d);
    const fwd = [2]i32{ -fix.sin(angle), fix.cos(angle) };
    var pos = [3]i32{ (c[0] << 9) + fix.mul(fwd[0], off), 0, (c[1] << 9) + fix.mul(fwd[1], off) };
    const g = ground.findFace(t, pos, null) orelse return;
    pos[1] = g.y;
    const back = fix.mul(cam.BACK[0], size);
    const p = cam.Pose{ .pos = .{ pos[0] - fix.mul(fwd[0], back), pos[1] + fix.mul(cam.HEIGHT[0], size), pos[2] - fix.mul(fwd[1], back) }, .yaw = @as(u32, @bitCast(angle)) << 16, .pitch = cam.PITCH[0] };
    const v = cam.view(p);
    fr.visibility(t, &v, 5);
    fr.collect(t, &v, true);
    const fk = fr.faceKey(fid) orelse return;
    const m = &carmodel.gt;
    const foot = under.corners(pos, angle, size, m.foot.x0, m.foot.x1, m.foot.z0, m.foot.z1);
    var o: [4]under.Pt = undefined;
    if (!under.convexOverlap(outline(t, d, &o), &foot)) return;
    const b = fr.stats.polys;
    carview.draw(fr, cache, &v, t, .{ .pos = pos, .angle = angle, .size = size }, g.face, m, carmodel.LIVERY[0]);
    if (fr.stats.polys == b) return;
    tally.checked += 1;
    if (fr.key[fr.stats.polys - 1] < fk) tally.painted_over += 1;
}

fn sweep(t: *const trk.Track) !Tally {
    var fr = try testutil.newFrame(t);
    defer testutil.freeFrame(&fr);
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    const hl = fix.mul(@as(i32, carmodel.gt.foot.z1) << 9, @as(i32, t.scale.car) << 8);
    var tally = Tally{};
    for (t.faces, 0..) |*f, fid| {
        if (f.flags & ground.FLAG_GROUND == 0 or f.inner_n == 0) continue;
        for (t.inner[f.inner_first..][0..f.inner_n]) |*d| {
            for ([_]i32{ 0, 0x4000, 0x8000, 0xC000 }) |angle| for ([_]i32{ 0, hl >> 1, hl - (hl >> 3) }) |off| {
                one(&fr, &cache, t, @intCast(fid), d, angle, off, &tally);
            };
        }
    }
    return tally;
}

test "no road decal paints over a car standing on it (Salt Flats, Glacier Pass); --break under does" {
    for ([_][]align(4) const u8{ data.salt, embedded("glacier.ktrk") }) |bytes| {
        const t = try trk.parse(bytes);
        const good = try sweep(&t);
        try std.testing.expect(good.checked > 50);
        try std.testing.expectEqual(@as(u32, 0), good.painted_over);
    }
    under.break_under = true;
    defer under.break_under = false;
    var bad: u32 = 0;
    for ([_][]align(4) const u8{ data.salt, embedded("glacier.ktrk") }) |bytes| {
        const t = try trk.parse(bytes);
        bad += (try sweep(&t)).painted_over;
    }
    try std.testing.expect(bad > 0);
}
