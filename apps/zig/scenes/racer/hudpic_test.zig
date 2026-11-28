// RACER: the race HUD over the picture (hudpic.zig, R82 bug pass): the numbers of a running ARCADE race (place, clock,
// lap time, speed, the revs on the gauge), the overlay's pixels only in its corners, the map's box and the middle (the
// countdown), the rev gauge's segments by the revs. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const arcade = @import("arcade.zig");
const data = @import("data.zig");
const game = @import("game.zig");
const hudpic = @import("hudpic.zig");
const menu = @import("menu.zig");
const racehud = @import("racehud.zig");
const trk = @import("trk.zig");

fn zero() u32 {
    return 0;
}

/// A font of solid 8 x 8 blocks for every character but the space (the pixels' places, not their shapes).
const FONT = blk: {
    var f = [_]u8{1} ** (256 * 64);
    @memset(f[' ' * 64 ..][0..64], 0);
    break :blk f;
};

fn running(t: *const trk.Track) !game.Game {
    var g = try game.Game.init(t, zero);
    arcade.model = .arcade;
    g.setMode(.race);
    g.apilot = true;
    g.go();
    for (0..900) |_| g.update(); // the countdown, then ~12 s of the race on the AI pilot
    return g;
}

test "a running ARCADE race's picture HUD: place of 8, the clock, a lap time, speed, the revs off the bottom" {
    const t = try trk.parse(data.salt);
    var g = try running(&t);
    defer arcade.model = .arcade;
    const i = racehud.picture(&g, "SALT");
    try std.testing.expect(i.state == .race);
    try std.testing.expect(i.place >= 1 and i.place <= 8 and i.cars == 8);
    try std.testing.expect(i.seconds > 0 and i.lap_ticks > 0 and i.lap == 1 and i.laps == 3);
    try std.testing.expect(i.kmh > 100);
    try std.testing.expect(i.rev >= 256 * 3 / 10 and i.rev <= 256); // our gearbox: 30 % .. 100 % of the revs in every gear
    var b: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1:23.4", hudpic.lapTime(&b, 2502));
}

test "the overlay draws only in its places: the four corners, the map's box, nothing in the middle of the road" {
    const t = try trk.parse(data.salt);
    var g = try running(&t);
    var px = [_]u8{0} ** (320 * 200);
    const p = menu.Px{ .px = &px, .stride = 320 };
    var cars: [8][3]i32 = undefined;
    for (&cars, 0..) |*c, k| c.* = g.shown(k).pos;
    const m = hudpic.fitMap(&t);
    hudpic.draw(p, &FONT, racehud.picture(&g, "SALT"), &m, &cars);
    var n: usize = 0;
    for (px, 0..) |c, k| {
        if (c == 0) continue;
        n += 1;
        const x = k % 320;
        const y = k / 320;
        try std.testing.expect(y >= 12 and y < 188); // inside the view, never the bands
        try std.testing.expect(!(x > 100 and x < 220 and y > 60 and y < 150)); // the road ahead stays clear
    }
    try std.testing.expect(n > 500);
}

test "the rev gauge: no segment lit at rest, all at the top, the last three red" {
    var px = [_]u8{0} ** (320 * 200);
    const p = menu.Px{ .px = &px, .stride = 320 };
    hudpic.gauge(p, 0, 8, 154);
    for (px) |c| try std.testing.expect(c == 0 or c == menu.SHADE);
    hudpic.gauge(p, 256, 8, 154);
    var red: usize = 0;
    var lit: usize = 0;
    for (px) |c| {
        red += @intFromBool(c == menu.ALERT);
        lit += @intFromBool(c == menu.LOGO[0]);
    }
    try std.testing.expect(red > 0 and lit > 0);
}

test "the direct glyph path (board optimisation) writes the run path's bytes: labels and big text at scales 1-4" {
    var font: [256 * 64]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(11);
    for (&font) |*b| b.* = @intFromBool(rng.random().int(u8) < 100);
    var a: [320 * 200]u8 = @splat(0);
    var b: [320 * 200]u8 = @splat(0);
    const pa = menu.Px{ .px = &a, .stride = 320 };
    const pb = menu.Px{ .px = &b, .stride = 320 };
    for (1..5) |s| {
        hudpic.label(pa, &font, "POS 8/8 KM/H", 3, @intCast(s * 20));
        pa.big(&font, "0:12.3", @intCast(10 * s), @intCast(100 + s * 3), @intCast(s));
        menu.break_direct = true;
        hudpic.label(pb, &font, "POS 8/8 KM/H", 3, @intCast(s * 20));
        pb.big(&font, "0:12.3", @intCast(10 * s), @intCast(100 + s * 3), @intCast(s));
        menu.break_direct = false;
    }
    try std.testing.expectEqualSlices(u8, &b, &a);
    try std.testing.expect(std.mem.indexOfNone(u8, &a, &.{0}) != null);
}
