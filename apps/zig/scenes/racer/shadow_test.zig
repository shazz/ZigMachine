// RACER: the car shadow (shadow.zig): one ramp level down for every palette index, the word path = the byte rule, the
// checkerboard, and the --break mutant's two levels. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const shadow = @import("shadow.zig");

test "one level down: index - 1 inside a ramp, a ramp's bottom and the first 16 entries left alone, for all 256 indices" {
    for (0..256) |i| {
        const b: u8 = @intCast(i);
        const want: u8 = if (b < 16 or (b - 16) % 8 == 0) b else b - 1;
        try std.testing.expectEqual(want, shadow.darken(b));
        if (b >= 16) try std.testing.expectEqual((b - 16) / 8, (shadow.darken(b) - 16) / 8); // never into the ramp below
    }
}

test "the word path darkens each of four bytes exactly as the byte rule, whatever its neighbours" {
    var prng = std.Random.DefaultPrng.init(82);
    const r = prng.random();
    for (0..256) |i| for (0..4) |lane| for (0..8) |_| {
        var bs: [4]u8 = undefined;
        r.bytes(&bs);
        bs[lane] = @intCast(i);
        const w = std.mem.readInt(u32, &bs, .little);
        var out: [4]u8 = undefined;
        std.mem.writeInt(u32, &out, shadow.darkenWord(w), .little);
        for (bs, out) |b, o| try std.testing.expectEqual(shadow.darken(b), o);
    };
}

fn rowOf(buf: []u8) usize {
    return @intFromPtr(buf.ptr);
}

test "a REAL span darkens exactly [x0, x1) at any alignment, and the --break two mutant drops two levels (clamped)" {
    var src: [64]u8 align(4) = undefined;
    for (&src, 0..) |*b, i| b.* = @intCast(16 + i * 3 % 240);
    for ([_][2]i32{ .{ 0, 64 }, .{ 1, 2 }, .{ 3, 41 }, .{ 5, 7 }, .{ 13, 13 } }) |s| {
        for ([_]bool{ false, true }) |two| {
            var buf = src;
            shadow.break_two = two;
            defer shadow.break_two = false;
            shadow.span(rowOf(&buf), 7, s[0], s[1]);
            for (buf, src, 0..) |o, b, x| {
                const inside = x >= s[0] and x < s[1];
                const want = if (!inside) b else if (two) shadow.darken(shadow.darken(b)) else shadow.darken(b);
                try std.testing.expectEqual(want, o);
            }
        }
    }
}

test "a FAKE span is the checkerboard: (x + y) even is DITHER, odd is untouched, on even and odd rows" {
    shadow.fake = true;
    defer shadow.fake = false;
    var src: [48]u8 align(4) = undefined;
    for (&src, 0..) |*b, i| b.* = @intCast(40 + i);
    for ([_]i32{ 10, 11 }) |y| for ([_][2]i32{ .{ 0, 48 }, .{ 3, 30 }, .{ 1, 2 } }) |s| {
        var buf = src;
        shadow.span(rowOf(&buf), y, s[0], s[1]);
        for (buf, src, 0..) |o, b, x| {
            const xi: i32 = @intCast(x);
            const dithered = xi >= s[0] and xi < s[1] and @mod(xi + y, 2) == 0;
            try std.testing.expectEqual(if (dithered) shadow.DITHER else b, o);
        }
    };
}

test "the shadow headroom (R82): on, a face's headroom colour (alt byte 2) is drawn and the shadow then darkens it; off, or none stored, the colour" {
    const project = @import("project.zig");
    const trk = @import("trk.zig");
    var f = std.mem.zeroes(trk.Face);
    f.colour = 16 + 3 * 8; // a ramp's bottom: no darker level for the shadow
    f.alt = (16 + 3 * 8 + 1) << 16; // the import's headroom: one level up
    try std.testing.expectEqual(f.colour, project.colourOf(&f));
    project.headroom = true;
    defer project.headroom = false;
    try std.testing.expectEqual(@as(u8, 16 + 3 * 8 + 1), project.colourOf(&f));
    try std.testing.expectEqual(f.colour, shadow.darken(project.colourOf(&f))); // the shadow shows now
    f.alt = 0;
    try std.testing.expectEqual(f.colour, project.colourOf(&f)); // a face with none keeps its colour
}

test "the OSD's state line (R82): every option in 40 columns, the defaults and a changed set" {
    const osd = @import("osdline.zig");
    var b: [48]u8 = undefined;
    const a = osd.line(&b, .{ .cpu = true, .r = 8, .pov = "far", .music = true });
    try std.testing.expectEqualStrings("CPU MS FL RL H1 R8 ARCF far M1 L3", a);
    @import("project.zig").headroom = true;
    defer @import("project.zig").headroom = false;
    const c = osd.line(&b, .{ .cpu = false, .r = 3, .pov = "cockpit", .music = false });
    try std.testing.expectEqualStrings("AFF MS FL HR H1 R3 ARCF coc M0 L3", c);
    try std.testing.expect(c.len <= 40);
}
