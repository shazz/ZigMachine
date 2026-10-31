// Tests for the copper list's LBASE (HW 1.10.0, fpga/review/COPPER_LINEBASE.md): the line source a
// record sets, the VRAM check that stops a list, the last of several winning, and the persistence
// rule (row r reads off + (r - r0) * stride) the renderers and the RTL share.
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const copper = @import("copper.zig");
const expectEqual = std.testing.expectEqual;

var region: [memmap.OFF_PFB]u8 = undefined;

const NoPal = struct {
    pub fn pal(_: NoPal, _: u8, _: u32) void {}
};

const V: u16 = 4;
const END = 0xF000_0000 | @as(u32, copper.END_LINE) << 19;
const VRAM_END: u32 = memmap.OFF_VRAM + memmap.VRAM_BYTES;

fn put(words: []const u32) void {
    var at: usize = memmap.OFF_VRAM + @as(usize, V) * 16;
    for (words) |w| {
        std.mem.writeInt(u32, region[at..][0..4], w, .little);
        at += 4;
    }
}
fn head(y: u32, n: u32) u32 {
    return 0xF000_0000 | y << 19 | n;
}
fn lbase(v: u32) u32 {
    return 0x5000_0000 | v;
}
fn one(y: u16, cur: *copper.Cursor) copper.Effects {
    return copper.line(&region, cur, 0, y, NoPal{});
}

test "an LBASE sets the line's source, any byte in VRAM" {
    const odd: u32 = memmap.OFF_VRAM + 12_345;
    put(&.{ head(5, 1), lbase(odd), head(9, 1), lbase(VRAM_END - 1), END });
    var cur = copper.begin(&region, V);
    try expectEqual(@as(?u32, null), one(4, &cur).lbase);
    try expectEqual(@as(?u32, odd), one(5, &cur).lbase);
    try expectEqual(@as(?u32, null), one(6, &cur).lbase); // a line without a record moves nothing
    try expectEqual(@as(?u32, VRAM_END - 1), one(9, &cur).lbase);
    try expectEqual(true, cur.live);
}

test "the last LBASE of a record wins" {
    put(&.{ head(0, 2), lbase(memmap.OFF_VRAM), lbase(memmap.OFF_VRAM + 400), END });
    var cur = copper.begin(&region, V);
    try expectEqual(@as(?u32, memmap.OFF_VRAM + 400), one(0, &cur).lbase);
}

test "an LBASE outside VRAM stops the list, what came before standing" {
    const bad = [_]u32{ memmap.OFF_VRAM - 1, VRAM_END, 0x1F_FFFF, 0x0020_1100 | memmap.OFF_VRAM };
    for (bad) |v| {
        put(&.{ head(0, 2), 0x2000_0000 | memmap.REG_HSCROLL << 20 | 7, lbase(v), head(1, 0), END });
        var cur = copper.begin(&region, V);
        const fx = one(0, &cur);
        try expectEqual(false, cur.live);
        try expectEqual(@as(?u16, 7), fx.hscroll);
        try expectEqual(@as(?u32, null), fx.lbase);
    }
}

test "rows after an LBASE run on from it by the stride; a frame starts at FB_BASE" {
    var lb = copper.LineBase{ .off = memmap.OFF_VRAM };
    try expectEqual(@as(usize, memmap.OFF_VRAM + 3 * 400), lb.at(3, 400));
    lb = .{ .off = memmap.OFF_VRAM + 77, .row = 10 }; // set on row 10
    try expectEqual(@as(usize, memmap.OFF_VRAM + 77), lb.at(10, 400));
    try expectEqual(@as(usize, memmap.OFF_VRAM + 77 + 2 * 400), lb.at(12, 400));
}
