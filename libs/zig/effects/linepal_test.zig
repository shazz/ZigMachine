// Tests for effects/linepal.zig against a fake plane: allocation per row,
// reuse of a colour, the HBL replay (logical and physical lines), overflow.
const std = @import("std");
const lp = @import("linepal.zig");
const expectEqual = std.testing.expectEqual;

const FakeOS = struct {};
const FakeFB = struct {
    palette: [*]u32,
    physical: bool = false,
    hbl_pos: u16 = 0xFFFF,

    pub fn hblLinesArePhysical(self: *const FakeFB) bool {
        return self.physical;
    }
    pub fn setFrameBufferHBLHandler(self: *FakeFB, pos: u16, handler: anytype) void {
        _ = handler;
        self.hbl_pos = pos;
    }
};

const P = lp.LinePalette(FakeFB, FakeOS, .{ .rows = 4, .visible_top = 40 }, 3);
var os: FakeOS = .{};
var table: P = undefined; // module scope, as a scene keeps it

test "colours get entries from 1 in order, and a colour keeps its entry on the row" {
    table.init();
    table.beginRow(0);
    try expectEqual(@as(u8, 1), table.entry(lp.rgb(1, 2, 3)));
    try expectEqual(@as(u8, 2), table.entry(lp.rgb(9, 9, 9)));
    try expectEqual(@as(u8, 1), table.entry(lp.rgb(1, 2, 3)));
    try expectEqual(@as(u8, 2), table.used[0]);
}

test "each row starts empty" {
    table.init();
    table.beginRow(0);
    _ = table.entry(lp.rgb(1, 2, 3));
    table.beginRow(1);
    try expectEqual(@as(u8, 1), table.entry(lp.rgb(7, 7, 7)));
    try expectEqual(@as(u8, 2), table.entry(lp.rgb(1, 2, 3))); // not the row above's entry
}

test "the HBL loads the line's colours, logical or physical" {
    var pal = [_]u32{0} ** 256;
    var fb = FakeFB{ .palette = &pal };
    table.init();
    table.install(&fb);
    try expectEqual(@as(u16, 0), fb.hbl_pos);
    table.beginRow(2);
    _ = table.entry(lp.rgb(10, 20, 30));
    _ = table.entry(lp.rgb(40, 50, 60));
    P.hbl(&fb, &os, 2, 0);
    try expectEqual(lp.rgb(10, 20, 30), pal[1]);
    try expectEqual(lp.rgb(40, 50, 60), pal[2]);
    try expectEqual(@as(u32, 0), pal[0]); // entry 0 is never touched
    pal[1] = 0;
    fb.physical = true;
    P.hbl(&fb, &os, 42, 0);
    try expectEqual(lp.rgb(10, 20, 30), pal[1]);
    P.hbl(&fb, &os, 10, 0); // above the visible band: nothing
    P.hbl(&fb, &os, 400, 0); // below it: nothing
}

test "a full row reuses its last entry and counts the overflow" {
    table.init();
    table.beginRow(3);
    for (0..3) |i| _ = table.entry(lp.rgb(@intCast(i), 0, 0));
    try expectEqual(@as(u8, 3), table.entry(lp.rgb(99, 0, 0)));
    try expectEqual(@as(u32, 1), table.overflow);
    try expectEqual(@as(u8, 3), table.peak);
}

test "rows past the table clamp to its last row" {
    table.init();
    table.beginRow(1000);
    try expectEqual(@as(usize, 3), table.line);
}

test "rgb packs like zg.Color.toRGBA" {
    try expectEqual(@as(u32, 0xFF332211), lp.rgb(0x11, 0x22, 0x33));
}
