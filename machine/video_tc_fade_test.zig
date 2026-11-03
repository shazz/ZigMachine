// Tests for the true-colour fade (HW 1.16.0, machine/video_tc_fade.zig): the formula against a
// reference written out with divisions, its edges (coef 0 identity, 31 full, the clamp at 0 and
// 255, offsets alone), a faded line, and the copper REG to a fade register (machine/copper.zig).
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const fade = @import("video_tc_fade.zig");
const tc = @import("video_tc.zig");
const copper = @import("copper.zig");
const expectEqual = std.testing.expectEqual;

// The spec's sentence in another form: weight w of 32, rounded half up, toward black or white,
// then the offset, clamped.
fn reference(x: i32, coef: i32, white: bool, ofs: i32) i32 {
    const w = if (coef >= 16) coef + 1 else coef;
    const in = if (white) 255 - x else x;
    const t = @divFloor(in * (32 - w) + 16, 32);
    const y = if (white) 255 - t else t;
    return std.math.clamp(y + ofs, 0, 255);
}

test "every channel value, coefficient, direction and offset follows the reference" {
    var x: i32 = 0;
    while (x < 256) : (x += 1) {
        var coef: i32 = 0;
        while (coef < 32) : (coef += 1) {
            for ([_]bool{ false, true }) |white| {
                var ofs: i32 = -128;
                while (ofs < 128) : (ofs += 17) {
                    const ctl: u8 = @intCast(coef | (if (white) @as(i32, 0x20) else 0));
                    const got = fade.channel(@intCast(x), fade.mult(ctl), white, @intCast(ofs));
                    try expectEqual(reference(x, coef, white, ofs), @as(i32, got));
                }
            }
        }
    }
}

test "coef 0 is the identity in both directions, and the reset registers change nothing" {
    const px: u32 = 0xFF6B79AD;
    try expectEqual(px, fade.apply(px, .{}));
    try expectEqual(px, fade.apply(px, .{ .ctl = memmap.TC_FADE_WHITE }));
    try expectEqual(px, fade.apply(px, .{ .ctl = 0xC0 })); // bits 6..7 ignored
    try std.testing.expect((fade.Fade{ .ctl = memmap.TC_FADE_WHITE }).identity());
}

test "coef 31 is full black or full white whatever the pixel" {
    for ([_]u32{ 0xFF000000, 0xFFFFFFFF, 0xFF6B79AD, 0xFF0000FF }) |px| {
        try expectEqual(@as(u32, 0xFF000000), fade.apply(px, .{ .ctl = 31 }));
        try expectEqual(@as(u32, 0xFFFFFFFF), fade.apply(px, .{ .ctl = 31 | memmap.TC_FADE_WHITE }));
    }
    try expectEqual(@as(u32, 0), fade.mult(31));
    try expectEqual(@as(u32, 15), fade.mult(16)); // 16 skips to weight 17: 31 lands on 32
}

test "offsets clamp at 0 and 255, per channel, after the fade" {
    const f = fade.Fade{ .r = 127, .g = -128, .b = 10 };
    try expectEqual(@as(u32, 0xFF_0A_00_FF), fade.apply(0xFF_00_40_F0, f)); // r 240+127 -> 255, g 64-128 -> 0
    const flash = fade.Fade{ .ctl = 31, .r = 100, .g = 50, .b = -1 };
    try expectEqual(@as(u32, 0xFF_00_32_64), fade.apply(0xFFFFFFFF, flash)); // black, then the tint
}

test "a faded line: every pixel through the fade, still doubled" {
    const src = [_]u8{ 0xFF, 0xFF, 0x00, 0x00 };
    var out = [_]u64{0} ** 2;
    tc.line(&out, &src, 0, 2, .{ .ctl = 31 | memmap.TC_FADE_WHITE, .b = -128 });
    try expectEqual(@as(u64, 0xFF7FFFFF_FF7FFFFF), out[0]);
    try expectEqual(@as(u64, 0xFF7FFFFF_FF7FFFFF), out[1]);
}

test "read takes plane p's four bytes" {
    var regs = [_]u8{0} ** 0x80;
    regs[memmap.REG_TC_FADE + 2] = 0x25;
    regs[memmap.REG_TC_OFS_R + 2] = 0xFF;
    regs[memmap.REG_TC_OFS_B + 2] = 0x80;
    const f = fade.read(&regs, 2);
    try expectEqual(fade.Fade{ .ctl = 0x25, .r = -1, .g = 0, .b = -128 }, f);
    try expectEqual(fade.Fade{}, fade.read(&regs, 1));
}

// --- the copper REG (1.16.0): this plane's four fade bytes, the value's low byte ---
var region: [memmap.OFF_PFB]u8 = undefined;
const Pal = struct {
    pub fn pal(_: Pal, _: u8, _: u32) void {}
};
const V: u16 = 4;
fn put(words: []const u32) void {
    var at: usize = memmap.OFF_VRAM + @as(usize, V) * 16;
    for (words) |w| {
        std.mem.writeInt(u32, region[at..][0..4], w, .little);
        at += 4;
    }
}
fn reg(off: usize, v: u32) u32 {
    return 0x2000_0000 | @as(u32, @intCast(off)) << 20 | v;
}
const END = 0xF000_0000 | @as(u32, copper.END_LINE) << 19;

test "a REG writes this plane's fade bytes, the high byte ignored" {
    put(&.{ 0xF000_0000 | 9 << 19 | 4, reg(memmap.REG_TC_FADE + 3, 0xAB3F), reg(memmap.REG_TC_OFS_R + 3, 0x80), reg(memmap.REG_TC_OFS_G + 3, 7), reg(memmap.REG_TC_OFS_B + 3, 0xFF), END });
    var cur = copper.begin(&region, V);
    const fx = copper.line(&region, &cur, 3, 9, Pal{});
    try expectEqual([4]?u8{ 0x3F, 0x80, 7, 0xFF }, fx.tc);
    try expectEqual(@as(?u16, null), fx.hscroll);
    try std.testing.expect(cur.live);
}

test "a REG to another plane's fade byte stops the list" {
    put(&.{ 0xF000_0000 | 9 << 19 | 2, reg(memmap.REG_TC_OFS_G + 3, 7), reg(memmap.REG_TC_FADE + 2, 31), END });
    var cur = copper.begin(&region, V);
    const fx = copper.line(&region, &cur, 3, 9, Pal{});
    try expectEqual([4]?u8{ null, null, 7, null }, fx.tc); // the word before it stands
    try expectEqual(false, cur.live);
    put(&.{ 0xF000_0000 | 9 << 19 | 1, reg(0x13, 1), END }); // the gap between the fade blocks
    cur = copper.begin(&region, V);
    _ = copper.line(&region, &cur, 3, 9, Pal{});
    try expectEqual(false, cur.live);
}
