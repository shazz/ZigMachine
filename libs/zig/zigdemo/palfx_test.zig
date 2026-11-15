//! Tests for palfx.zig over a made-up track (not any demo's): selections on a change, the re-arm
//! value, each effect kind's steps, an id outside the table, and the channel / veil maths.
const std = @import("std");
const palfx = @import("palfx.zig");
const expectEqual = std.testing.expectEqual;

const CFG: palfx.Config = .{ .rows_per_s = 10, .vbl_hz = 50, .decay = 4 };
const DEFS = [_]palfx.Def{
    .{}, // 0 plain
    .{ .kind = .fade_in, .toward = .black, .amount = 8 }, // 1
    .{ .kind = .fade_out, .toward = .white, .amount = 16 }, // 2
    .{ .kind = .flash, .amount = 100 }, // 3
    .{ .kind = .add, .amount = 30 }, // 4
    .{ .kind = .flash, .amount = 256 }, // 5: the low byte (starts at 0)
};
// rows at 10 rows/s: row r = r * 100 ms
const KEYS = [_][2]i32{ .{ 0, -1 }, .{ 10, 1 }, .{ 20, 3 }, .{ 21, 3 }, .{ 30, -1 }, .{ 31, 3 }, .{ 40, 2 }, .{ 50, 4 }, .{ 60, 9 }, .{ 70, 5 } };

fn at(t: u32) palfx.Effect {
    return palfx.at(CFG, &KEYS, &DEFS, t);
}

test "before the first selection: the first id (plain)" {
    try expectEqual(palfx.Mode.plain, at(500).mode);
}

test "a fade in steps +amount a VBL, then is plain" {
    const e = at(1000 + 200); // 10 VBLs
    try expectEqual(palfx.Mode.black, e.mode);
    try expectEqual(@as(u16, 80), e.level);
    try expectEqual(palfx.Mode.plain, at(1000 + 700).mode); // 35 VBLs: 280 >= 256
}

test "a repeated value does not select again; after the re-arm it does" {
    const a = at(2100 + 20); // 21's 3 is the same value: still the flash from row 20 (6 VBLs)
    try expectEqual(palfx.Mode.add, a.mode);
    try expectEqual(@as(u8, 100 - 4 * 6), a.add);
    const b = at(3100); // 30 re-arms, 31 selects 3 again: VBL 0
    try expectEqual(@as(u8, 100), b.add);
}

test "a fade out goes to its colour and holds" {
    try expectEqual(palfx.Mode.white, at(4000 + 100).mode);
    try expectEqual(@as(u16, 256 - 16 * 5), at(4000 + 100).level);
    try expectEqual(@as(u16, 0), at(4000 + 900).level);
}

test "add is constant; an id outside the table is plain; a flash of 256 is its low byte" {
    try expectEqual(@as(u8, 30), at(5000 + 900).add);
    try expectEqual(palfx.Mode.plain, at(6000 + 10).mode);
    try expectEqual(@as(u8, 0), at(7000).add);
    try expectEqual(@as(u8, 252), at(7000 + 20).add);
}

test "the channel maths: scale, toward white, saturating add" {
    try expectEqual(@as(u8, 100), palfx.apply(.{ .mode = .black, .level = 128 }, 200));
    try expectEqual(@as(u8, 227), palfx.apply(.{ .mode = .white, .level = 128 }, 200));
    try expectEqual(@as(u8, 255), palfx.apply(.{ .mode = .add, .add = 160 }, 200));
    try expectEqual(@as(u8, 200), palfx.apply(.{}, 200));
}

test "the veil: fades are one alpha colour, plain is transparent" {
    try expectEqual([4]u8{ 0, 0, 0, 0 }, palfx.veil(.{}));
    try expectEqual([4]u8{ 255, 255, 255, 255 }, palfx.veil(.{ .mode = .white, .level = 0 }));
    try expectEqual([4]u8{ 0, 0, 0, 128 }, palfx.veil(.{ .mode = .black, .level = 128 }));
    try std.testing.expect(palfx.Effect.eql(.{}, at(0)));
}
