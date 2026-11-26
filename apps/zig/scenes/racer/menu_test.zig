// RACER: the front end's drawing kit (menu.zig, M5 step 4). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const menu = @import("menu.zig");

var buf: [menu.W * menu.H]u8 = undefined;

fn px() menu.Px {
    @memset(&buf, 0);
    return .{ .px = &buf, .stride = menu.W };
}

fn count(c: u8) usize {
    var n: usize = 0;
    for (buf) |v| n += @intFromBool(v == c);
    return n;
}

test "a rectangle is clipped to the screen, a panel is its border and its inside" {
    const p = px();
    p.rect(-10, -10, 20, 20, 7); // 10 x 10 on screen
    try std.testing.expectEqual(@as(usize, 100), count(7));
    p.rect(315, 195, 20, 20, 6);
    try std.testing.expectEqual(@as(usize, 25), count(6));
    p.panel(100, 100, 10, 6);
    try std.testing.expectEqual(@as(usize, 8 * 4), count(menu.PANEL));
    try std.testing.expectEqual(@as(usize, 60 - 32), count(menu.SHADE));
}

test "big letters: each ink pixel of the font becomes an s x s block, the shadow under it, the gradient by row" {
    var font = [_]u8{0} ** (256 * 64);
    for (0..8) |r| font['I' * 64 + r * 8 + 3] = 1; // a one-pixel-wide bar
    const p = px();
    p.big(&font, "I", 10, 10, 4);
    var ink: usize = 0;
    for (menu.LOGO) |c| ink += count(c);
    try std.testing.expectEqual(@as(usize, 8 * 4 * 4), ink); // 8 rows of one 4 x 4 block
    try std.testing.expect(count(menu.SHADE) > 0);
    try std.testing.expectEqual(menu.LOGO[0], buf[10 * menu.W + 10 + 12]); // the top row: the first colour
    try std.testing.expectEqual(menu.LOGO[2], buf[(10 + 31) * menu.W + 10 + 12]); // the bottom row: the last
}

test "a line joins its two ends, one pixel a step, clipped off screen" {
    const p = px();
    p.line(.{ 0, 0 }, .{ 9, 3 }, 5);
    try std.testing.expectEqual(@as(usize, 10), count(5));
    try std.testing.expectEqual(@as(u8, 5), buf[0]);
    try std.testing.expectEqual(@as(u8, 5), buf[3 * menu.W + 9]);
    p.line(.{ -5, 10 }, .{ 5, 10 }, 4);
    try std.testing.expectEqual(@as(usize, 6), count(4));
}
