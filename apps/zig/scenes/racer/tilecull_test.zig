// RACER: the tile cull (tilecull.zig, board optimisation) keeps every pixel: on the oval and Salt Flats, along the flyby
// lap at R 8 in the three POVs, the kept polygons (records, keys, in order) and every face's faceKey are the same with
// the cull as without it, and some tiles were skipped. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const data = @import("data.zig");
const frame = @import("frame.zig");
const pvs = @import("pvs.zig");
const testutil = @import("testutil.zig");
const tilecull = @import("tilecull.zig");
const trk = @import("trk.zig");

fn run(f: *frame.Frame, t: *const trk.Track, v: *const cam.View, cull: bool) void {
    tilecull.break_cull = !cull;
    defer tilecull.break_cull = false;
    f.visibility(t, v, 8);
    f.collect(t, v, true);
}

test "the tile cull changes no kept polygon and no face key" {
    var skipped: u32 = 0;
    for ([_][]align(4) const u8{ data.oval, data.salt }) |blob| {
        const t = try trk.parse(blob);
        var a = try testutil.newFrame(&t);
        defer testutil.freeFrame(&a);
        var b = try testutil.newFrame(&t);
        defer testutil.freeFrame(&b);
        var fr: u32 = 0;
        while (fr < cam.LAP_FRAMES) : (fr += 9) {
            const v = cam.view(cam.lapPose(&t, fr, @enumFromInt(fr % 3)));
            run(&a, &t, &v, false);
            run(&b, &t, &v, true);
            try std.testing.expectEqual(a.stats.polys, b.stats.polys);
            for (a.kept[0..a.stats.polys], b.kept[0..b.stats.polys], a.key[0..a.stats.polys], b.key[0..b.stats.polys]) |ra, rb, ka, kb| {
                try std.testing.expectEqual(ka, kb);
                try std.testing.expectEqual(ra.n, rb.n);
                try std.testing.expectEqual(ra.c, rb.c);
                try std.testing.expectEqualSlices(i16, ra.x[0 .. ra.n & 0x3F], rb.x[0 .. rb.n & 0x3F]);
                try std.testing.expectEqualSlices(i16, ra.y[0 .. ra.n & 0x3F], rb.y[0 .. rb.n & 0x3F]);
            }
            for (0..t.faces.len) |id| try std.testing.expectEqual(a.faceKey(@intCast(id)), b.faceKey(@intCast(id)));
            for (b.list) |e| skipped += @intFromBool(tilecull.outside(&v, pvs.tileOf(e)));
        }
    }
    try std.testing.expect(skipped > 0);
}
