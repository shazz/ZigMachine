// --------------------------------------------------------------------------
// form_alert's three icons, the built-in set (the build with no -Dgem_assets):
// 1 NOTE (a "!" in a diamond road sign), 2 QUESTION (a "?" in a ring), 3 STOP (a
// stop octagon with the word). Our own drawing, generated here from shapes at
// compile time: 32 x 32, 1 bpp, rows of 4 bytes MSB first, the data only (an
// alert draws them in black on its white face, as a BITBLK). The shapes are
// TOS 1.0's ideas; no bitmap of TOS's is in the tree (docs/GEM5_PLAN.md licence).
// A local asset set's NOTE / QUES / STOP images replace them (assets.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: i16 = 32;
pub const H: i16 = 32;
pub const BPR: usize = 4;
pub const Bits = [32 * BPR]u8;

// 5 x 7 glyphs, a row a byte (bit 4 the leftmost): drawn twice the size.
const BANG = [7]u8{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100 };
const QMARK = [7]u8{ 0b01110, 0b10001, 0b00001, 0b00110, 0b00100, 0b00000, 0b00100 };
// 3 x 5 letters for STOP, a row a byte (bit 2 the leftmost).
const LETTERS = [4][5]u8{
    .{ 0b111, 0b100, 0b111, 0b001, 0b111 }, // S
    .{ 0b111, 0b010, 0b010, 0b010, 0b010 }, // T
    .{ 0b111, 0b101, 0b101, 0b101, 0b111 }, // O
    .{ 0b111, 0b101, 0b111, 0b100, 0b100 }, // P
};

fn set(b: *Bits, x: i32, y: i32, on: bool) void {
    if (x < 0 or y < 0 or x >= W or y >= H) return;
    const i: usize = @intCast(y * 4 + @divTrunc(x, 8));
    const m: u8 = @as(u8, 0x80) >> @intCast(@mod(x, 8));
    if (on) b[i] |= m else b[i] &= ~m;
}

// A 5 x 7 glyph at (x, y), each pixel 2 x 2.
fn glyph(b: *Bits, g: [7]u8, x: i32, y: i32, on: bool) void {
    for (g, 0..) |row, r| for (0..5) |c| {
        if ((row >> @intCast(4 - c)) & 1 == 0) continue;
        const px = x + @as(i32, @intCast(c)) * 2;
        const py = y + @as(i32, @intCast(r)) * 2;
        set(b, px, py, on);
        set(b, px + 1, py, on);
        set(b, px, py + 1, on);
        set(b, px + 1, py + 1, on);
    };
}

// Twice the distance from the centre (15.5, 15.5): integers only.
fn d2(v: usize) i32 {
    return @as(i32, @intCast(v)) * 2 - 31;
}

fn note() Bits {
    var b: Bits = @splat(0);
    for (0..32) |y| for (0..32) |x| {
        const d = @abs(d2(x)) + @abs(d2(y)); // a diamond, its rim 2 px wide
        set(&b, @intCast(x), @intCast(y), d <= 32 and d >= 26);
    };
    glyph(&b, BANG, 11, 8, true);
    return b;
}

fn question() Bits {
    var b: Bits = @splat(0);
    for (0..32) |y| for (0..32) |x| {
        const r = d2(x) * d2(x) + d2(y) * d2(y); // a ring, 2 px wide
        set(&b, @intCast(x), @intCast(y), r <= 31 * 31 and r >= 26 * 26);
    };
    glyph(&b, QMARK, 11, 9, true);
    return b;
}

fn stop() Bits {
    var b: Bits = @splat(0);
    for (0..32) |y| for (0..32) |x| {
        const ax = @abs(d2(x));
        const ay = @abs(d2(y));
        set(&b, @intCast(x), @intCast(y), ax <= 31 and ay <= 31 and ax + ay <= 44); // a solid octagon
    };
    for (LETTERS, 0..) |l, k| for (l, 0..) |row, r| for (0..3) |c| {
        if ((row >> @intCast(2 - c)) & 1 == 0) continue;
        const x: i32 = 7 + @as(i32, @intCast(k)) * 5 + @as(i32, @intCast(c));
        const y: i32 = 13 + @as(i32, @intCast(r));
        set(&b, x, y, false); // the word in white on black
    };
    return b;
}

pub const NOTE: Bits = blk: {
    @setEvalBranchQuota(100000);
    break :blk note();
};
pub const QUESTION: Bits = blk: {
    @setEvalBranchQuota(100000);
    break :blk question();
};
pub const STOP: Bits = blk: {
    @setEvalBranchQuota(100000);
    break :blk stop();
};

/// form_alert's icon 1..3, null for 0 (none) or anything else.
pub fn of(icon: u8) ?*const Bits {
    return switch (icon) {
        1 => &NOTE,
        2 => &QUESTION,
        3 => &STOP,
        else => null,
    };
}

fn inked(b: *const Bits, x: usize, y: usize) bool {
    return (b[y * 4 + x / 8] >> @intCast(7 - x % 8)) & 1 != 0;
}

test "the three icons are distinct, inked, and inside their 32 x 32" {
    try std.testing.expect(!std.mem.eql(u8, &NOTE, &QUESTION));
    try std.testing.expect(!std.mem.eql(u8, &QUESTION, &STOP));
    try std.testing.expect(inked(&NOTE, 16, 0)); // the diamond's top point
    try std.testing.expect(!inked(&NOTE, 0, 0)); // its corners are clear
    try std.testing.expect(inked(&NOTE, 15, 10)); // the "!" stem
    try std.testing.expect(!inked(&STOP, 7, 13) and inked(&STOP, 6, 13)); // the S, white on black
    try std.testing.expect(inked(&QUESTION, 16, 1) and !inked(&QUESTION, 8, 16));
    try std.testing.expect(of(0) == null and of(4) == null);
}
