// RACER: the GT car (carmodel.zig, carview.zig): the embedded model, the liveries, and a car pushed into a frame (its
// shadow first, one key for all its faces, the far model past LOD1_Z). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const carview = @import("carview.zig");
const data = @import("data.zig");
const testutil = @import("testutil.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");

test "the embedded GT car: parts in order, one shadow quad on the ground, every face's colour on its material's ramp" {
    var last: u16 = 0;
    for (carmodel.END) |e| {
        try std.testing.expect(e >= last);
        last = e;
    }
    try std.testing.expectEqual(@as(u16, carmodel.NF), last);
    const sh = carmodel.range(.shadow);
    try std.testing.expectEqual(@as(usize, 1), sh.len);
    try std.testing.expectEqual(@as(u8, 4), sh[0].nv);
    try std.testing.expectEqual(carmodel.FLAG_SHADOW, sh[0].flags);
    for (sh[0].v) |id| try std.testing.expect(carmodel.verts[id][1] <= 2);
    try std.testing.expect(carmodel.range(.hull).len > 0 and carmodel.range(.lod1).len > 0);
    for (carmodel.faces) |f| {
        if (f.flags & (carmodel.FLAG_BODY | carmodel.FLAG_STRIPE) != 0) try std.testing.expectEqual(@as(u8, carmodel.RAMP_BODY), (f.colour - 16) / 8);
        if (f.flags != carmodel.FLAG_SHADOW) try std.testing.expect(f.colour >= 16 + 12 * 8 and f.colour < 16 + 19 * 8);
    }
}

test "the eight liveries all differ, each stripe on another ramp than its body, the AI bodies still M3's (the minimap's dots)" {
    for (carmodel.LIVERY, 0..) |a, i| {
        try std.testing.expect(a.body != a.stripe);
        if (i > 0) try std.testing.expectEqual(@as(u8, @intCast(carmodel.RAMP_LIVERY + (i - 1) % carmodel.LIVERIES)), a.body);
        for (carmodel.LIVERY[i + 1 ..]) |b| try std.testing.expect(a.body != b.body or a.stripe != b.stripe);
    }
    try std.testing.expectEqual(@as(u8, 8), carmodel.shiftTo(13));
    try std.testing.expectEqual(@as(u8, 48), carmodel.shiftTo(18));
}

fn drawAt(f: anytype, t: *const trk.Track, back: i32, liv: carmodel.Livery) !usize {
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    const s = carview.Snap{ .pos = .{ 0, 0, 0 }, .angle = 0 };
    const v = cam.view(.{ .pos = .{ 0, 1 << 16, -back }, .yaw = 0, .pitch = 0 }); // behind the car, above it
    const b = f.stats.polys;
    carview.draw(f, &cache, &v, t, s, null, &carmodel.gt, liv);
    return b;
}

test "a car in the frame: the shadow first, flagged, then the faces all on one key; the livery recolours body and stripe" {
    const t = try trk.parse(data.oval);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    f.stats = .{};
    const b = try drawAt(&f, &t, 3 << 16, carmodel.LIVERY[2]);
    const n = f.stats.polys - b;
    try std.testing.expect(n > 12); // near: wheels, hull, cabin, wing
    try std.testing.expect(f.kept[b].n & types.SHADOW != 0);
    var body = false;
    var stripe = false;
    for (f.kept[b + 1 .. f.stats.polys], f.key[b + 1 .. f.stats.polys]) |r, k| {
        try std.testing.expect(r.n & types.SHADOW == 0);
        try std.testing.expectEqual(f.key[b + 1], k);
        body = body or (r.c - 16) / 8 == 16;
        stripe = stripe or (r.c - 16) / 8 == 13;
    }
    try std.testing.expect(body and stripe); // LIVERY[2]: yellow (16) with a dark (13) stripe
}

test "past LOD1_Z the far model: fewer polygons than the near one" {
    const t = try trk.parse(data.oval);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    f.stats = .{};
    const b0 = try drawAt(&f, &t, 3 << 16, carmodel.LIVERY[0]);
    const near = f.stats.polys - b0;
    const b1 = try drawAt(&f, &t, carview.LOD1_Z + (2 << 16), carmodel.LIVERY[0]);
    const far = f.stats.polys - b1;
    try std.testing.expect(far >= 3 and far <= carmodel.range(.lod1).len + 1);
    try std.testing.expect(far < near);
}
