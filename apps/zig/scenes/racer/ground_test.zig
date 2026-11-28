// RACER M5 finish: the height-aware ground lookup (ground.findFace). A synthetic crossing (one road over another in the same
// tile) keeps each car on its own deck, which freds72's x/z-only pick does not; and on every shipped track no point of
// the ground is under two faces more than DECK_Y apart, so there the lookup's face is freds72's (the physics CRCs hold).
// `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const ground = @import("ground.zig");
const trk = @import("trk.zig");
const data = @import("data.zig");

fn embedded(comptime name: []const u8) []align(4) const u8 {
    const raw = @embedFile("../../assets/screens/racer/" ++ name);
    const S = struct {
        const blob: [raw.len]u8 align(16) = raw.*;
    };
    return &S.blob;
}

/// Two 4 x 4 decks crossing in tile (16, 16): the lower along x at y = 0 (listed first), the upper along z at y = 1.2.
fn crossing(verts: *[8]trk.Vert, faces: *[2]trk.Face, tf: *[trk.TILES + 1]u32, list: *[2]u16) trk.Track {
    const lo: i16 = 0;
    const hi: i16 = 154; // 1.2 units (1/128)
    verts.* = .{ .{ -256, lo, -128 }, .{ -256, lo, 128 }, .{ 256, lo, 128 }, .{ 256, lo, -128 }, .{ -128, hi, -256 }, .{ -128, hi, 256 }, .{ 128, hi, 256 }, .{ 128, hi, -256 } };
    for (faces, 0..) |*f, k| {
        const b: u16 = @intCast(4 * k);
        f.* = std.mem.zeroes(trk.Face);
        f.v = .{ b + 3, b + 2, b + 1, b }; // the winding is_inside wants (every edge with the point on its inner side)
        f.nv = 4;
        f.flags = ground.FLAG_GROUND | ground.FLAG_ASPHALT;
    }
    const tile = 16 + 16 * 32; // tileOf((0, y, 0))
    for (tf, 0..) |*e, i| e.* = if (i <= tile) 0 else 2;
    list.* = .{ 0, 1 };
    var t = std.mem.zeroes(trk.Track);
    t.verts = verts;
    t.faces = faces;
    t.tile_first = tf;
    t.tile_faces = list;
    return t;
}

test "a crossing: a car on the upper deck stays on it, one on the lower deck on that; freds72's pick (the mutant) drops to the first" {
    var v: [8]trk.Vert = undefined;
    var f: [2]trk.Face = undefined;
    var tf: [trk.TILES + 1]u32 = undefined;
    var l: [2]u16 = undefined;
    const t = crossing(&v, &f, &tf, &l);
    const up = [3]i32{ 1 << 14, 78643, 1 << 14 }; // 1.2 units up, in the middle: under both decks in x/z
    const down = [3]i32{ 1 << 14, 0, 1 << 14 };
    try std.testing.expectEqual(@as(u16, 1), ground.findFace(&t, up, null).?.face);
    try std.testing.expectEqual(@as(u16, 0), ground.findFace(&t, down, null).?.face);
    try std.testing.expectEqual(@as(u16, 1), ground.findFace(&t, up, 1).?.face); // its own last face first, as freds72's
    const air = [3]i32{ 1 << 14, 5 << 16, 1 << 14 }; // far over both: no deck within DECK_Y, freds72's first face
    try std.testing.expectEqual(@as(u16, 0), ground.findFace(&t, air, null).?.face);
    ground.break_decks = true;
    defer ground.break_decks = false;
    try std.testing.expectEqual(@as(u16, 0), ground.findFace(&t, up, null).?.face); // the mutant: the car falls to the lower deck
}

/// The largest height gap (Q16) between two ground faces over one point, at every half unit of the track. The new lookup can
/// only pick another face than freds72's where the car is more than DECK_Y from the first face under it and within DECK_Y of a
/// later one: the gap there is over DECK_Y minus how far the car can be off its ground. The car is put on its ground face every
/// tick and moves well under 0.1 unit up or down a tick, so a track whose largest gap is under DECK_Y / 4 (0.125) cannot differ.
fn maxGap(t: *const trk.Track) i32 {
    var gap: i32 = 0;
    var x: i32 = -128 << 16;
    while (x < 128 << 16) : (x += 1 << 15) {
        var z: i32 = -128 << 16;
        while (z < 128 << 16) : (z += 1 << 15) {
            var lo: i32 = std.math.maxInt(i32);
            var hi: i32 = std.math.minInt(i32);
            const p = [3]i32{ x, 0, z };
            const tile = 16 + (x >> 19) + 32 * (16 + (z >> 19));
            for (t.tileFaces(@intCast(tile))) |id| {
                if (t.faces[id].flags & ground.FLAG_GROUND == 0) continue;
                const y = ground.isInside(&ground.poly(t, id), p) orelse continue;
                lo = @min(lo, y);
                hi = @max(hi, y);
            }
            if (hi > lo) gap = @max(gap, hi - lo);
        }
    }
    return gap;
}

test "the shipped tracks have no ground over ground: the height-aware lookup is freds72's there (oval, city, Salt Flats, Neon Docks, Glacier Pass)" {
    const blobs = [_][]align(4) const u8{ data.oval, data.city, data.salt, embedded("neon.ktrk"), embedded("glacier.ktrk") };
    for (blobs) |b| { // measured: the oval 0.07 unit (two non-planar quads meeting at an edge), the others under 1/64
        const t = try trk.parse(b);
        try std.testing.expect(maxGap(&t) < ground.DECK_Y / 4);
    }
}

test "the sweep sees a crossing (it would catch a shipped track with one)" {
    var v: [8]trk.Vert = undefined;
    var f: [2]trk.Face = undefined;
    var tf: [trk.TILES + 1]u32 = undefined;
    var l: [2]u16 = undefined;
    const t = crossing(&v, &f, &tf, &l);
    try std.testing.expect(maxGap(&t) > ground.DECK_Y);
}

test "the remembered normals (groundmemo.zig) are the computed ones, on a cold table and a warm one" {
    const memo = @import("groundmemo.zig");
    const vec = @import("vec.zig");
    const t = try @import("trk.zig").parse(@import("data.zig").oval);
    for (0..2) |pass| {
        if (pass == 0) memo.clear();
        for (t.faces, 0..) |f, id| {
            if (f.flags & ground.FLAG_GROUND == 0) continue;
            const g = ground.poly(&t, @intCast(id));
            const want = vec.normz(vec.cross(vec.between(g.p[0], g.p[g.ni - 1]), vec.between(g.p[0], g.p[1])));
            try std.testing.expectEqual(want, g.n);
            for (0..g.ni) |k| try std.testing.expectEqual(ground.borderNormal(&g, k), memo.border(&g, k));
        }
    }
    try std.testing.expect(memo.hits > 0);
}
