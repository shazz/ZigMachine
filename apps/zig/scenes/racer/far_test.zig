// RACER: the far ring (frame.far, R82 bug pass item 7, key +): off, nothing; on, only TALL faces, only from tiles past R
// within R + ring DDA steps, each at most once; deeper ring, at least as many. DECAL_NEAR (R82 32X look item 5): far faces
// drop their decals, near ones keep them. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const frame = @import("frame.zig");
const pvs = @import("pvs.zig");
const testutil = @import("testutil.zig");
const trk = @import("trk.zig");

fn embedded(comptime name: []const u8) []align(4) const u8 {
    const raw = @embedFile("../../assets/screens/racer/" ++ name);
    const S = struct {
        const blob: [raw.len]u8 align(16) = raw.*;
    };
    return &S.blob;
}

/// The polygons the far ring adds at pose k of the flyby, at R 3.
fn added(fr: *frame.Frame, t: *const trk.Track, k: u32, extra: u32) u32 {
    const v = cam.view(cam.fixedPose(t, k));
    fr.visibility(t, &v, 3);
    fr.collect(t, &v, true);
    const b = fr.stats.polys;
    fr.far(t, &v, 3, extra);
    return fr.stats.polys - b;
}

test "the far ring adds tall faces past R only, more with a deeper ring, nothing when off" {
    const t = try trk.parse(embedded("glacier.ktrk"));
    var fr = try testutil.newFrame(&t);
    defer testutil.freeFrame(&fr);
    var sum = [3]u32{ 0, 0, 0 };
    for (0..cam.POSES) |k| {
        for ([_]u32{ 0, 2, 4 }, 0..) |extra, i| sum[i] += added(&fr, &t, @intCast(k), extra);
    }
    try std.testing.expectEqual(@as(u32, 0), sum[0]);
    try std.testing.expect(sum[1] > 0 and sum[2] >= sum[1]);
    // every face it kept is tall, and none sits only in the PVS' own tiles (those were collected already)
    const v = cam.view(cam.fixedPose(&t, 2));
    fr.visibility(&t, &v, 3);
    fr.collect(&t, &v, true);
    const before = fr.stats.faces;
    fr.far(&t, &v, 3, 4);
    try std.testing.expectEqual(before, fr.stats.faces); // far() does not count as collect's submitted faces
    for (t.faces, 0..) |*f, fid| {
        if (fr.faceKey(@intCast(fid)) == null) continue;
        var in_pvs = false;
        for (fr.list) |e| for (t.tileFaces(pvs.tileOf(e))) |x| {
            in_pvs = in_pvs or x == fid;
        };
        if (in_pvs) continue;
        var lo: i32 = 0x7fff;
        var hi: i32 = -0x7fff;
        for (f.v[0..f.nv]) |id| {
            lo = @min(lo, t.verts[id][1]);
            hi = @max(hi, t.verts[id][1]);
        }
        try std.testing.expect(hi - lo >= frame.TALL);
    }
}

test "DECAL_NEAR (R82 32X look): a face keyed farther than DECAL_KEY drops its decals, nearer ones keep theirs" {
    var t = try trk.parse(embedded("salt.ktrk"));
    var fr = try testutil.newFrame(&t);
    defer testutil.freeFrame(&fr);
    var cut: u32 = 0;
    for (0..cam.POSES) |k| {
        var polys = [2]u32{ 0, 0 };
        var near = [2]u32{ 0, 0 }; // polygons keyed at or past the cut: the same with and without the flag
        var far_decals: u32 = 0; // the decals the flag may drop: those of faces kept farther than the cut
        for (0..2) |on| {
            t.mood.flags = if (on == 1) trk.DECAL_NEAR else 0;
            const v = cam.view(cam.fixedPose(&t, @intCast(k)));
            fr.visibility(&t, &v, 8);
            fr.collect(&t, &v, true);
            polys[on] = fr.stats.polys;
            for (fr.key[0..fr.stats.polys]) |key| near[on] += @intFromBool(key >= frame.DECAL_KEY);
            if (on == 1) for (t.faces, 0..) |f, fid| {
                const key = fr.faceKey(@intCast(fid)) orelse continue;
                if (key < frame.DECAL_KEY) far_decals += f.inner_n;
            };
        }
        try std.testing.expectEqual(near[0], near[1]);
        try std.testing.expect(polys[1] <= polys[0] and polys[0] - polys[1] <= far_decals);
        cut += polys[0] - polys[1];
    }
    try std.testing.expect(cut > 0);
}
