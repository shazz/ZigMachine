// --------------------------------------------------------------------------
// startup_test.zig — Part 4: the start-up menu (startup.zig).
// --------------------------------------------------------------------------

const std = @import("std");
const dsp = @import("display.zig");
const startup = @import("startup.zig");

var scr: dsp.Screen = .{};

// startupmenu.inc strings are `.enc "screen"`: capitals stay ASCII, a-z -> 1..26.

fn expectAt(row: usize, col: usize, text: []const u8) !void {
    for (text, 0..) |ch, i| {
        try std.testing.expectEqual(startup.screenCode(ch), scr.chars[row][col + i]);
    }
}

test "render shows the title, config result and the six player names" {
    var st = startup.init(false, .pal, 0, 0);
    startup.render(&st, &scr);
    try expectAt(1, 6, "SID-WIZARD 1.X  STARTUP-MENU");
    try expectAt(3, 0, "Configuration file was not (yet) found!");
    try expectAt(5, 2, "Please select your preferred player:");
    for (startup.player_names, 0..) |name, i| {
        try expectAt(6 + i * 2, 16, name);
        try std.testing.expectEqual(@as(u4, if (i == 0) 15 else 11), scr.colours[6 + i * 2][16]);
    }
    try expectAt(21, 15, "$1C ");
    try expectAt(21, 33, "$A57");
    try expectAt(23, 1, "PAL  machine detected,pitches adjusted.");
    try expectAt(24, 13, ": Equal-tempered, A5=440Hz ");

    st = startup.init(true, .ntsc, 1, 3);
    startup.render(&st, &scr);
    try expectAt(3, 0, "Configuration file loaded successfully..");
    try expectAt(23, 0, "NTSC machine detected,pitches adjusted.");
    try expectAt(24, 13, ": Verdi-tuning ,  A5=432Hz ");
    try expectAt(12, 16, "EXTRA!");
}

test "CRSR down/up cycles players, CRSR right cycles tuning, RETURN starts" {
    var st = startup.init(true, .pal, 0, 0);
    for (0..startup.player_count) |i| {
        try std.testing.expectEqual(@as(u8, @intCast(i)), st.selection);
        try std.testing.expectEqual(startup.Action.redraw, startup.key(&st, 7, false));
    }
    try std.testing.expectEqual(@as(u8, 0), st.selection); // wrapped 5 -> 0
    try std.testing.expectEqual(startup.Action.redraw, startup.key(&st, 7, true));
    try std.testing.expectEqual(@as(u8, startup.player_count - 1), st.selection);
    try std.testing.expectEqual(@as(u8, 0), st.scrollcnt); // newmnpt resets the scroll

    try std.testing.expectEqual(startup.Action.redraw, startup.key(&st, 2, false));
    try std.testing.expectEqual(@as(u8, 1), st.tuning);
    for (0..3) |_| _ = startup.key(&st, 2, false);
    try std.testing.expectEqual(@as(u8, 0), st.tuning);

    try std.testing.expectEqual(startup.Action.none, startup.key(&st, 63, false));
    try std.testing.expectEqual(startup.Action.start, startup.key(&st, 1, false));
    try std.testing.expect(!st.open);
    try std.testing.expectEqual(startup.Action.none, startup.key(&st, 7, false));
}

test "the description scrolls one column per frame and stops at 40" {
    var st = startup.init(true, .pal, 0, 0);
    startup.render(&st, &scr);
    try expectAt(18, 0, "The default player which features all   ");
    for (0..10) |_| startup.tick(&st);
    startup.render(&st, &scr);
    try expectAt(18, 0, "t player which features all   ");
    for (0..40) |_| startup.tick(&st);
    try std.testing.expectEqual(@as(u8, 40), st.scrollcnt);
    startup.render(&st, &scr);
    for (0..dsp.COLS) |c| try std.testing.expectEqual(@as(u8, ' '), scr.chars[18][c]);
}

test "screenCode: capitals stay ASCII, lower case maps to 1..26 (.enc \"screen\")" {
    try std.testing.expectEqual(@as(u8, 'C'), startup.screenCode('C'));
    try std.testing.expectEqual(@as(u8, 0x0f), startup.screenCode('o'));
    try std.testing.expectEqual(@as(u8, '1'), startup.screenCode('1'));
}
