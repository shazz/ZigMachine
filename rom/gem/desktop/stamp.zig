// --------------------------------------------------------------------------
// File timestamps. The host FAT (packed in docs/sealed-loader.js) carries a
// date but no time, and a disk built without a descriptor date carries neither.
// Rather than print placeholder dashes, an entry with no stamp reports the epoch
// every Atari owner recognises — 01-01-1987 00:00, the ST's own power-on default
// — so the columns always line up and always parse as a real date.
// --------------------------------------------------------------------------
const std = @import("std");

pub const DEFAULT_DATE: u32 = 19870101; // YYYYMMDD
pub const DEFAULT_TIME: []const u8 = "00:00";

fn parts(d: u32) struct { mm: u32, dd: u32, yy: u32 } {
    const v = if (d == 0) DEFAULT_DATE else d;
    return .{ .mm = (v / 100) % 100, .dd = v % 100, .yy = (v / 10000) % 100 };
}

// "MM-DD-YY" — the TOS text-view DATE column.
pub fn date(buf: []u8, d: u32) []const u8 {
    const p = parts(d);
    return std.fmt.bufPrint(buf, "{d:0>2}-{d:0>2}-{d:0>2}", .{ p.mm, p.dd, p.yy }) catch "?";
}

// "MM/DD/YY 00:00" — the INFORMATION dialog's Last modified value.
pub fn stamp(buf: []u8, d: u32) []const u8 {
    const p = parts(d);
    return std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2}/{d:0>2} {s}", .{ p.mm, p.dd, p.yy, DEFAULT_TIME }) catch "?";
}

test "a missing date reports the ST default, not dashes" {
    var b: [24]u8 = undefined;
    try std.testing.expectEqualStrings("01-01-87", date(&b, 0));
    try std.testing.expectEqualStrings("01/01/87 00:00", stamp(&b, 0));
}

test "a real date is formatted in both column styles" {
    var b: [24]u8 = undefined;
    try std.testing.expectEqualStrings("09-12-26", date(&b, 20260912));
    try std.testing.expectEqualStrings("09/12/26 00:00", stamp(&b, 20260912));
}
