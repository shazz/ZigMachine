// RACER: the horizon haze (haze.zig, M6): off = identity, band 1 = the exact blend of every track colour, the bands by depth,
// the pool's room, the shadow leaving the pool alone. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const haze = @import("haze.zig");
const shadow = @import("shadow.zig");
const trk = @import("trk.zig");

fn embedded(comptime name: []const u8) []align(4) const u8 {
    const raw = @embedFile("../../assets/screens/racer/" ++ name);
    const S = struct {
        const blob: [raw.len]u8 align(16) = raw.*;
    };
    return &S.blob;
}

/// A palette with a distinct colour in every entry (what palette.install leaves, near enough for the LUT's maths).
fn testPalette() [256]u32 {
    var p: [256]u32 = undefined;
    for (&p, 0..) |*e, i| e.* = 0xFF00_0000 | @as(u32, @intCast(i)) | @as(u32, @intCast((i * 7) & 0xFF)) << 8 | @as(u32, @intCast((255 - i) & 0xFF)) << 16;
    return p;
}

fn withHaze(t: trk.Track, rgb: [3]u8, start: u8, strength: u8) trk.Track {
    var h = t;
    h.mood.haze = rgb;
    h.mood.haze_start = start;
    h.mood.haze_strength = strength;
    return h;
}

fn reset() void {
    haze.on = true;
    haze.break_absent = false;
    haze.break_near = false;
}

test "mix: 0 is the colour, 255 the haze, the middle between; dist is the squared RGB distance" {
    const a: u32 = 0xFF_10_20_30;
    const b: u32 = 0xFF_F0_E0_D0;
    try std.testing.expectEqual(a, haze.mix(a, b, 0));
    try std.testing.expectEqual(b, haze.mix(a, b, 255));
    try std.testing.expectEqual(@as(u32, 0xFF_80_80_80), haze.mix(a, b, 128) & 0xFFF0F0F0 | 0xFF000000);
    try std.testing.expectEqual(@as(u32, 3 * 0x10 * 0x10), haze.dist(0xFF_00_00_00, 0xFF_10_10_10));
}

test "no haze in the mood (every M5 track file): nothing built, identity colours, the shadow's rule untouched" {
    reset();
    const pal = testPalette();
    const t = try trk.parse(embedded("oval.ktrk"));
    try std.testing.expectEqual(haze.Outcome.none, haze.build(&pal, &t, 0));
    try std.testing.expect(!haze.active);
    try std.testing.expectEqual(@as(u32, 256), shadow.keep_from);
    haze.setR(8);
    for (0..haze.KEYS) |k| for (0..256) |c| try std.testing.expectEqual(@as(u8, @intCast(c)), haze.colour(@intCast(k), @intCast(c)));
}

test "haze on: band 1 is the exact blend of each track colour, in the pool; car colours never take an entry; off is identity" {
    reset();
    var pal = testPalette();
    const t = withHaze(try trk.parse(embedded("glacier.ktrk")), .{ 200, 208, 216 }, 96, 176);
    try std.testing.expectEqual(haze.Outcome.on, haze.build(&pal, &t, 0));
    try std.testing.expect(haze.active);
    try std.testing.expectEqual(@as(u32, 16 + 8 * 22), haze.pool_lo);
    try std.testing.expectEqual(haze.pool_lo, shadow.keep_from);
    var fresh = pal;
    haze.paint(&fresh);
    const key0: u16 = 0; // the farthest key: band BANDS at any R
    haze.setR(8);
    try std.testing.expectEqual(@as(u8, haze.BANDS), haze.band(key0));
    for (t.faces) |f| {
        const e = haze.colour(key0, f.colour);
        try std.testing.expect(e >= haze.pool_lo); // a track colour far away is always a pool entry
    }
    // band 1's colours: find a key in band 1 and check each face colour's exact blend
    const k1: u16 = for (0..haze.KEYS) |k| (if (haze.band(@intCast(k)) == 1) break @intCast(k)) else unreachable;
    const haze_rgb: u32 = 0xFF_D8_D0_C8;
    for (t.faces) |f| try std.testing.expectEqual(haze.mix(pal[f.colour], haze_rgb, 176 / haze.BANDS), fresh[haze.colour(k1, f.colour)]);
    for (16 + 12 * 8..16 + 19 * 8) |c| {
        const e = haze.colour(key0, @intCast(c));
        try std.testing.expect(e == c or e >= haze.pool_lo);
    }
    try std.testing.expectEqual(haze.mix(pal[4], haze_rgb, 176), fresh[4]); // the far ground at full strength: no seam
    haze.on = false;
    try std.testing.expectEqual(haze.Outcome.off, haze.build(&pal, &t, 0));
    try std.testing.expect(!haze.active);
    try std.testing.expectEqual(@as(u32, 256), shadow.keep_from);
}

test "the bands by depth at R 8: none nearer than the start, then never lighter with distance, the strongest at R's edge" {
    reset();
    const pal = testPalette();
    const t = withHaze(try trk.parse(embedded("glacier.ktrk")), .{ 200, 208, 216 }, 128, 200);
    _ = haze.build(&pal, &t, 0);
    haze.setR(8);
    const edge: u32 = 8 * 64; // eighth units
    var last: u8 = 0;
    var k: usize = haze.KEYS;
    while (k > 0) : (k -= 1) { // near (1023) to far (0)
        const z: u32 = @intCast(haze.KEYS - k);
        const b = haze.band(@intCast(k - 1));
        try std.testing.expect(b >= last);
        if (z <= edge / 2) try std.testing.expectEqual(@as(u8, 0), b);
        if (z >= edge) try std.testing.expectEqual(@as(u8, haze.BANDS), b);
        last = b;
    }
    haze.setR(4); // a nearer R: the same bands, at half the depth
    try std.testing.expectEqual(@as(u8, haze.BANDS), haze.band(@intCast(haze.KEYS - 1 - 4 * 64)));
}

test "the mutants: break_absent builds and never applies; break_near puts every band one nearer" {
    reset();
    const pal = testPalette();
    const t = withHaze(try trk.parse(embedded("glacier.ktrk")), .{ 200, 208, 216 }, 128, 200);
    haze.break_absent = true;
    _ = haze.build(&pal, &t, 0);
    try std.testing.expect(!haze.active);
    reset();
    _ = haze.build(&pal, &t, 0);
    haze.setR(8);
    const near = haze.band(haze.KEYS - 1);
    haze.break_near = true;
    haze.invalidate();
    haze.setR(8);
    try std.testing.expectEqual(near + 1, haze.band(haze.KEYS - 1));
    reset();
}

test "no room: a track whose face colours outnumber the spare entries (Neon Docks' 29 ramps) has no haze" {
    reset();
    const pal = testPalette();
    const t = withHaze(try trk.parse(embedded("neon.ktrk")), .{ 46, 34, 78 }, 128, 160);
    try std.testing.expectEqual(haze.Outcome.no_room, haze.build(&pal, &t, 0));
    try std.testing.expect(!haze.active);
    try std.testing.expectEqual(@as(u32, 256), shadow.keep_from);
}

test "the shadow leaves the haze's pool alone: byte and word paths, every index, at the pool's bottom" {
    defer shadow.keep_from = 256;
    for ([_]u32{ 168, 192, 200, 248, 256 }) |lo| {
        shadow.keep_from = lo;
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            const want: u8 = if (b < 16 or (b - 16) % 8 == 0 or b >= lo) b else b - 1;
            try std.testing.expectEqual(want, shadow.darken(b));
            const w = @as(u32, b) * 0x01010101;
            try std.testing.expectEqual(@as(u32, want) * 0x01010101, shadow.darkenWord(w));
            const mixed = @as(u32, b) | @as(u32, @intCast(lo -% 1 & 0xFF)) << 8 | 0x10 << 16 | @as(u32, 0xFF) << 24;
            var out: [4]u8 = undefined;
            std.mem.writeInt(u32, &out, shadow.darkenWord(mixed), .little);
            var in: [4]u8 = undefined;
            std.mem.writeInt(u32, &in, mixed, .little);
            for (in, out) |x, o| try std.testing.expectEqual(shadow.darken(x), o);
        }
    }
}
