// Tests for effects/copper.zig: the logical/physical line mapping, seeding,
// per-plane independence, the flicker option and uninstalled slots, against a
// fake plane.
const std = @import("std");
const expectEqual = std.testing.expectEqual;

const FakeFB = struct {
    id: u8,
    palette: [*]u32,
    physical: bool = false,
    flickers: u32 = 0,
    hbl_pos: u16 = 0xFFFF,
    list: ?[]u32 = null, // a machine with copper lists (HW 1.9.0) gives this buffer
    published: bool = false,

    pub fn copperList(self: *FakeFB, words: usize) ?[]u32 {
        const l = self.list orelse return null;
        if (l.len < words) return null;
        self.published = true;
        return l;
    }
    pub fn copperBuffer(self: *const FakeFB) ?[]u32 {
        return if (self.published) self.list else null;
    }
    pub fn clearFrameBufferHBLHandler(self: *FakeFB) void {
        self.hbl_pos = 0xFFFF;
    }

    pub fn flickerBorder(self: *FakeFB) void {
        self.flickers += 1;
    }
    pub fn hblLinesArePhysical(self: *const FakeFB) bool {
        return self.physical;
    }
    pub fn setFrameBufferHBLHandlerPure(self: *FakeFB, pos: u16, handler: anytype) void {
        _ = handler;
        self.hbl_pos = pos;
    }
};

const FakeOS = struct { lfbs: [2]FakeFB };
const C = @import("copper.zig").Copper(FakeFB, FakeOS, .{
    .nb_planes = 2,
    .rows = 280,
    .visible_top = 40,
    .visible_rows = 200,
    .magic_x = 13,
});

var os: FakeOS = undefined;

test "install seeds every row with the entry's current colour" {
    var pal = [_]u32{0} ** 256;
    pal[7] = 0xAABBCCDD;
    var fb = FakeFB{ .id = 0, .palette = &pal };
    var store: [2]C.Table = undefined;
    C.install(&fb, &.{ 0, 7 }, &store, .{});
    try expectEqual(@as(u16, 0), fb.hbl_pos);
    try expectEqual(@as(u32, 0xAABBCCDD), C.table(&fb, 1)[279]);
    pal[7] = 0;
    C.hbl(&fb, &os, 123, 0);
    try expectEqual(@as(u32, 0xAABBCCDD), pal[7]); // unchanged table restores it
}

test "normal plane: logical line 0 is physical row 40" {
    var pal = [_]u32{0} ** 256;
    var fb = FakeFB{ .id = 0, .palette = &pal };
    var store: [1]C.Table = undefined;
    C.install(&fb, &.{3}, &store, .{});
    C.table(&fb, 0)[40] = 111;
    C.visible(&fb, 0)[199] = 222; // physical 239
    C.hbl(&fb, &os, 0, 0);
    try expectEqual(@as(u32, 111), pal[3]);
    C.hbl(&fb, &os, 199, 0);
    try expectEqual(@as(u32, 222), pal[3]);
    try expectEqual(@as(u32, 222), store[0][239]);
}

test "overscan plane: lines are physical, and out-of-range lines write nothing" {
    var pal = [_]u32{0} ** 256;
    var fb = FakeFB{ .id = 1, .palette = &pal, .physical = true };
    var store: [1]C.Table = undefined;
    C.install(&fb, &.{9}, &store, .{ .flicker = true });
    try expectEqual(@as(u16, 13), fb.hbl_pos);
    C.table(&fb, 0)[0] = 5;
    C.table(&fb, 0)[40] = 6;
    C.hbl(&fb, &os, 0, 0);
    try expectEqual(@as(u32, 5), pal[9]);
    pal[9] = 77;
    C.hbl(&fb, &os, 280, 0);
    try expectEqual(@as(u32, 77), pal[9]);
    try expectEqual(@as(u32, 2), fb.flickers); // flicker happens on every call
    try expectEqual(@as(usize, 40), C.physicalRow(true, 40));
    try expectEqual(@as(usize, 80), C.physicalRow(false, 40));
}

test "planes keep independent tables and entries" {
    var pal0 = [_]u32{0} ** 256;
    var pal1 = [_]u32{0} ** 256;
    var a = FakeFB{ .id = 0, .palette = &pal0 };
    var b = FakeFB{ .id = 1, .palette = &pal1 };
    var sa: [4]C.Table = undefined;
    var sb: [1]C.Table = undefined;
    C.install(&a, &.{ 1, 2, 3, 4 }, &sa, .{});
    C.install(&b, &.{5}, &sb, .{});
    for (0..4) |s| C.visible(&a, @intCast(s))[10] = @intCast(s + 100);
    C.visible(&b, 0)[10] = 55;
    C.hbl(&a, &os, 10, 0);
    C.hbl(&b, &os, 10, 0);
    try expectEqual(@as(u32, 100), pal0[1]);
    try expectEqual(@as(u32, 103), pal0[4]);
    try expectEqual(@as(u32, 0), pal0[5]);
    try expectEqual(@as(u32, 55), pal1[5]);
    try expectEqual(@as(u32, 0), a.flickers);
}

test "a slot past the installed entries is scratch: written, never played" {
    var pal = [_]u32{0} ** 256;
    var fb = FakeFB{ .id = 0, .palette = &pal };
    var store: [1]C.Table = undefined;
    C.install(&fb, &.{2}, &store, .{});
    C.table(&fb, 3)[60] = 999; // slot 3 was not installed
    C.visible(&fb, 0)[10] = 7; // physical row 50
    C.hbl(&fb, &os, 10, 0);
    try expectEqual(@as(u32, 7), pal[2]);
    for (pal, 0..) |c, i| if (i != 2) try expectEqual(@as(u32, 0), c);
    try expectEqual(@as(u32, 0), store[0][60]); // the real table is untouched
    C.hbl(&fb, &os, 20, 0); // physical row 60
    try expectEqual(@as(u32, 0), pal[2]);
}

test "with copper lists: no handler, and endFrame writes the rows that change, FLICK on every row" {
    var pal = [_]u32{0} ** 256;
    var buf = [_]u32{0} ** C.LIST_WORDS;
    var o = FakeOS{ .lfbs = .{
        FakeFB{ .id = 0, .palette = &pal, .physical = true, .list = &buf },
        FakeFB{ .id = 1, .palette = &pal },
    } };
    var store: [1]C.Table = undefined;
    C.install(&o.lfbs[0], &.{9}, &store, .{ .flicker = true });
    try expectEqual(@as(u16, 0xFFFF), o.lfbs[0].hbl_pos); // the handler was taken away again
    @memset(&store[0], 0x55);
    store[0][100] = 0x77;
    C.endFrame(&o);
    const head0: u32 = 0xF000_0000 | 3; // row 0: FLICK + PAL 9 + its word
    try expectEqual(head0, buf[0]);
    try expectEqual(@as(u32, 0x3000_0000), buf[1]);
    try expectEqual(@as(u32, 0x1090_1000), buf[2]);
    try expectEqual(@as(u32, 0x55), buf[3]);
    try expectEqual(@as(u32, 0xF000_0000 | 1 << 19 | 1), buf[4]); // row 1: FLICK only
    try expectEqual(@as(u32, 0x3000_0000), buf[5]);
    const row100 = 4 + 2 * 99; // rows 1..99 are 2 words each
    try expectEqual(@as(u32, 0xF000_0000 | 100 << 19 | 3), buf[row100]);
    try expectEqual(@as(u32, 0x77), buf[row100 + 3]);
    try expectEqual(@as(u32, 0xF000_0000 | 101 << 19 | 3), buf[row100 + 4]); // back to 0x55
}

test "no list on this machine: the handler stays" {
    var pal = [_]u32{0} ** 256;
    var fb = FakeFB{ .id = 1, .palette = &pal };
    var store: [1]C.Table = undefined;
    C.install(&fb, &.{2}, &store, .{});
    try expectEqual(@as(u16, 0), fb.hbl_pos);
}
