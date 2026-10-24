// The ink fits the field's palette: run the scrolltext through its whole
// cycle, renumber every strip row the way the scene does each frame, and check
// that no row ever needs more than the 141 entries left beside the field's 105
// and the logo's 10, and that every renumbered pixel shows its original colour.
// (The whole design of the one-plane screen rests on this bound: inkpal.zig.)
const std = @import("std");
const inkpal = @import("inkpal.zig");
const strip = @import("strip.zig");

const StripPal = inkpal.StripPal(strip.STRIP_H);
var pal: StripPal = .{};
var before: [strip.STRIP_WU]u8 = undefined;

fn checkFrame(text: *const strip.Text) !void {
    text.build();
    var gy: usize = 0;
    while (gy < strip.STRIP_H) : (gy += 1) {
        const row = strip.row(gy);
        for (&before, row, strip.accRow(gy)) |*b, g, a| b.* = if (a != 0) a else g;
        pal.remapRow(gy, row, strip.accRow(gy));
        for (before, row) |v, p| {
            if (v == 0) {
                try std.testing.expectEqual(@as(u8, 0), p);
                continue;
            }
            try std.testing.expect(p >= inkpal.STRIP_FIRST);
            try std.testing.expectEqual(inkpal.ink_words[v], pal.colours[gy][p - inkpal.STRIP_FIRST]);
        }
    }
}

test "every strip row of the whole scrolltext fits the entries beside the field" {
    pal.reset();
    var text: strip.Text = undefined;
    text.init();
    // A new glyph enters every 35/3 frames: cover the text once and then some.
    const frames = strip.SCROLL_TEXT.len * 12 + 100;
    var f: usize = 0;
    while (f < frames) : (f += 1) {
        try checkFrame(&text);
        text.step();
    }
    try std.testing.expectEqual(@as(u32, 0), pal.overflow);
    try std.testing.expect(pal.peak <= inkpal.STRIP_ENTRIES);
    std.debug.print("strip rows need at most {d} of {d} entries\n", .{ pal.peak, inkpal.STRIP_ENTRIES });
}

test "a row past the entries counts its overflow instead of reading off the table" {
    pal.reset();
    var row: [strip.STRIP_WU]u8 = undefined;
    for (&row, 0..) |*p, i| p.* = @intCast(1 + i % 255);
    const clear = [_]u8{0} ** strip.STRIP_WU;
    pal.remapRow(0, &row, &clear);
    try std.testing.expectEqual(@as(u8, inkpal.STRIP_ENTRIES), pal.used[0]);
    try std.testing.expectEqual(@as(u32, 255 - inkpal.STRIP_ENTRIES), pal.overflow);
}

test "the logo keeps its colours in entries LOGO_FIRST.." {
    const logo_raw = @embedFile("../../assets/screens/tcb_colorshock/logo.raw");
    for (logo_raw, inkpal.logo_pixels) |v, p| {
        if (v == 0) {
            try std.testing.expectEqual(@as(u8, 0), p);
            continue;
        }
        try std.testing.expect(p >= inkpal.LOGO_FIRST and p < inkpal.STRIP_FIRST);
        try std.testing.expectEqual(inkpal.ink_words[v], inkpal.logo_colours[p - inkpal.LOGO_FIRST]);
    }
}
