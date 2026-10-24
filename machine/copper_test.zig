// Tests for machine/copper.zig, the copper list's parser: records applied on their line, the next
// HEAD kept, PAL blocks, REG HSCROLL, FLICK, and every rule that stops a list (the RTL's too).
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const copper = @import("copper.zig");
const expectEqual = std.testing.expectEqual;

var region: [memmap.OFF_PFB]u8 = undefined;
var palette: [256]u32 = undefined;

const Pal = struct {
    pub fn pal(_: Pal, i: u8, v: u32) void {
        palette[i] = v;
    }
};

const V: u16 = 4; // the list at OFF_VRAM + 64
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
fn palOp(first: u32, k: u32) u32 {
    return 0x1000_0000 | first << 20 | k << 12;
}
const END = 0xF000_0000 | @as(u32, copper.END_LINE) << 19;

fn run(plane: usize, lines: []const u16, cur: *copper.Cursor) copper.Effects {
    var fx: copper.Effects = .{};
    for (lines) |y| fx = copper.line(&region, cur, plane, y, Pal{});
    return fx;
}

test "no list, and a list applies each record on its own line only" {
    try expectEqual(false, copper.begin(&region, 0).live);
    put(&.{ head(41, 2), palOp(7, 1), 0xFF11_2233, head(43, 3), palOp(1, 2), 0xA, 0xB, END });
    @memset(&palette, 0);
    var cur = copper.begin(&region, V);
    _ = run(0, &.{40}, &cur);
    try expectEqual(@as(u32, 0), palette[7]); // line 40 has no record
    _ = run(0, &.{41}, &cur);
    try expectEqual(@as(u32, 0xFF11_2233), palette[7]);
    _ = run(0, &.{42}, &cur);
    try expectEqual(@as(u32, 0), palette[1]);
    _ = run(0, &.{ 43, 44 }, &cur);
    try expectEqual(@as(u32, 0xA), palette[1]);
    try expectEqual(@as(u32, 0xB), palette[2]);
    try expectEqual(false, cur.live); // END
}

test "REG writes this plane's HSCROLL, FLICK flickers; another register stops the list" {
    const reg1 = 0x2000_0000 | @as(u32, memmap.REG_HSCROLL + 2) << 20 | 77;
    put(&.{ head(0, 2), reg1, 0x3000_0000, END });
    var cur = copper.begin(&region, V);
    const fx = run(1, &.{0}, &cur);
    try expectEqual(@as(?u16, 77), fx.hscroll);
    try expectEqual(true, fx.flick);
    cur = copper.begin(&region, V);
    try expectEqual(@as(?u16, null), run(0, &.{0}, &cur).hscroll); // plane 0 may not write plane 1's
    try expectEqual(false, cur.live);
}

test "a record for a line already passed stops the list" {
    put(&.{ head(10, 1), 0, END });
    var cur = copper.begin(&region, V);
    _ = run(0, &.{11}, &cur); // the plane never covered line 10
    try expectEqual(false, cur.live);
}

test "a PAL past entry 255 or past its record stops the list, earlier words standing" {
    put(&.{ head(5, 4), palOp(9, 1), 0x99, palOp(255, 2), 0x1, END });
    @memset(&palette, 0);
    var cur = copper.begin(&region, V);
    _ = run(0, &.{5}, &cur);
    try expectEqual(@as(u32, 0x99), palette[9]);
    try expectEqual(false, cur.live);
    put(&.{ head(5, 2), palOp(0, 3), 0x1, END });
    cur = copper.begin(&region, V);
    _ = run(0, &.{5}, &cur);
    try expectEqual(false, cur.live);
}

test "PALREF copies k words from a VRAM table; one outside VRAM stops the list" {
    const tab: u32 = memmap.OFF_VRAM + 4096;
    for (0..3) |j| std.mem.writeInt(u32, region[tab + j * 4 ..][0..4], 0x100 + @as(u32, @intCast(j)), .little);
    put(&.{ head(2, 2), 0x4000_0000 | 10 << 20 | 3 << 12, tab, head(3, 2), 0x4000_0000 | 1 << 12, 16, END });
    @memset(&palette, 0);
    var cur = copper.begin(&region, V);
    _ = run(0, &.{2}, &cur);
    try expectEqual(@as(u32, 0x102), palette[12]);
    try expectEqual(true, cur.live);
    _ = run(0, &.{3}, &cur); // offset 16: the register block, not VRAM
    try expectEqual(false, cur.live);
}

test "a reserved op stops the list" {
    put(&.{ head(3, 1), 0x5000_0000, head(4, 0), END });
    var cur = copper.begin(&region, V);
    _ = run(0, &.{3}, &cur);
    try expectEqual(false, cur.live);
}
