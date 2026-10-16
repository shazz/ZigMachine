// Native tests for the XM reader (xm_format.zig, xm_pattern.zig, xm_instr.zig):
// `zig test` this file. Every test builds its own tiny XM image in memory.
const std = @import("std");
const fmt = @import("xm_format.zig");
const pat = @import("xm_pattern.zig");
const inst = @import("xm_instr.zig");

const HDR_LEN: usize = 336; // 60 + the 276-byte header: patterns start here

fn put16(b: []u8, o: usize, v: u16) void {
    b[o] = @truncate(v);
    b[o + 1] = @truncate(v >> 8);
}

fn put32(b: []u8, o: usize, v: u32) void {
    put16(b, o, @truncate(v));
    put16(b, o + 2, @truncate(v >> 16));
}

const Hdr = struct { ch: u16 = 2, song_len: u16 = 1, npat: u16 = 1, ninst: u16 = 0, speed: u16 = 6, bpm: u16 = 125 };

/// The 336-byte header of a `h` song, orders 0,1,2.. (each pattern `i`).
fn header(b: []u8, h: Hdr) void {
    @memset(b[0..HDR_LEN], 0);
    @memcpy(b[0..17], fmt.MAGIC);
    b[37] = 0x1A;
    put16(b, 58, 0x0104);
    put32(b, 60, 276);
    put16(b, 64, h.song_len);
    put16(b, 68, h.ch);
    put16(b, 70, h.npat);
    put16(b, 72, h.ninst);
    put16(b, 76, h.speed);
    put16(b, 78, h.bpm);
    for (0..h.song_len) |i| b[80 + i] = @intCast(i % @max(h.npat, 1));
}

/// A pattern of `rows` empty rows (flag bytes 0x80) for `ch` channels.
fn emptyPattern(b: []u8, o: usize, rows: u16, ch: u16) usize {
    put32(b, o, 9);
    b[o + 4] = 0;
    put16(b, o + 5, rows);
    const packed_len: u16 = rows * ch;
    put16(b, o + 7, packed_len);
    @memset(b[o + 9 ..][0..packed_len], 0x80);
    return o + 9 + packed_len;
}

test "a four-channel XM header parses, and its fields are the ones the file holds" {
    var b: [HDR_LEN + 64]u8 = undefined;
    header(&b, .{ .ch = 4, .song_len = 2, .npat = 2, .speed = 3, .bpm = 150 });
    const h = try fmt.parse(&b);
    try std.testing.expectEqual(@as(u8, 4), h.channels);
    try std.testing.expectEqual(@as(u16, 2), h.song_len);
    try std.testing.expectEqual(@as(u8, 3), h.speed);
    try std.testing.expectEqual(@as(u8, 150), h.bpm);
    try std.testing.expectEqual(@as(u8, 1), h.orders[1]);
    try std.testing.expectEqual(@as(u32, HDR_LEN), h.pattern_data);
}

test "a file that is not an XM, or is too short for its header, is refused" {
    var b: [HDR_LEN + 64]u8 = undefined;
    header(&b, .{});
    b[0] = 'X';
    try std.testing.expectError(error.NotXm, fmt.parse(&b));
    try std.testing.expectError(error.TooShort, fmt.parse(b[0..100]));
}

test "more than eight channels, a version before 1.02, or a speed of 0 is refused" {
    var b: [HDR_LEN + 64]u8 = undefined;
    header(&b, .{ .ch = 9 });
    try std.testing.expectError(error.TooManyChannels, fmt.parse(&b));
    header(&b, .{ .speed = 0 });
    try std.testing.expectError(error.BadTempo, fmt.parse(&b));
    header(&b, .{});
    put16(&b, 58, 0x0101);
    try std.testing.expectError(error.BadVersion, fmt.parse(&b));
}

test "an order naming a pattern the file does not hold is refused" {
    var b: [HDR_LEN + 64]u8 = undefined;
    header(&b, .{ .song_len = 2, .npat = 1 });
    b[81] = 5;
    try std.testing.expectError(error.BadOrder, fmt.parse(&b));
}

test "every reason has its own number for the host" {
    const errs = [_]fmt.Error{ error.TooShort, error.NotXm, error.BadVersion, error.BadHeaderSize, error.TooManyChannels, error.BadSongLength, error.TooManyPatterns, error.TooManyInstruments, error.TooManySamples, error.BadPattern, error.Truncated, error.BadTempo, error.BadInstrument, error.BadOrder, error.TooLarge };
    for (errs, 0..) |e, i| try std.testing.expectEqual(@as(u32, @intCast(i + 1)), fmt.code(e));
    try std.testing.expectEqual(@as(u32, 15), fmt.code(error.TooLarge));
}

test "a packed cell reads only the fields its flag byte names" {
    // Channel 0: flag 0x83 = note + instrument; channel 1: five bytes, unpacked.
    const row = [_]u8{ 0x83, 0x31, 0x02, 0x10, 0x05, 0x10, 0x0C, 0x20 };
    var cells: [fmt.MAX_CH]pat.Cell = undefined;
    const next = pat.readRow(&row, 0, 2, &cells);
    try std.testing.expectEqual(@as(usize, 8), next);
    try std.testing.expectEqual(@as(u8, 0x31), cells[0].note);
    try std.testing.expectEqual(@as(u8, 2), cells[0].inst);
    try std.testing.expectEqual(@as(u8, 0x10), cells[1].note);
    try std.testing.expectEqual(@as(u8, 0x0C), cells[1].eff);
    try std.testing.expectEqual(@as(u8, 0x20), cells[1].param);
}

test "a row cut short by the end of its data stops at the end, never past it" {
    const row = [_]u8{ 0x88, 0x07 };
    var cells: [fmt.MAX_CH]pat.Cell = undefined;
    const next = pat.readRow(&row, 0, 2, &cells);
    try std.testing.expect(next > row.len);
    try std.testing.expectEqual(@as(u8, 0x07), cells[0].eff);
}

test "scan finds every pattern and returns where the instruments begin" {
    var b: [HDR_LEN + 64 + 64]u8 = undefined;
    header(&b, .{ .ch = 2, .song_len = 2, .npat = 2 });
    var o = emptyPattern(&b, HDR_LEN, 4, 2);
    o = emptyPattern(&b, o, 4, 2);
    var h = try fmt.parse(&b);
    var pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined;
    const after = try pat.scan(&b, &h, &pats);
    try std.testing.expectEqual(o, after);
    try std.testing.expectEqual(@as(u16, 4), pats[1].rows);
    try std.testing.expectEqual(@as(u32, HDR_LEN + 9), pats[0].off);
}

test "a pattern that is not packing type 0, or runs past the file, is refused" {
    var b: [HDR_LEN + 64]u8 = undefined;
    header(&b, .{ .ch = 2 });
    _ = emptyPattern(&b, HDR_LEN, 4, 2);
    b[HDR_LEN + 4] = 1;
    var h = try fmt.parse(&b);
    var pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined;
    try std.testing.expectError(error.BadPattern, pat.scan(&b, &h, &pats));
    _ = emptyPattern(&b, HDR_LEN, 4, 2);
    put16(&b, HDR_LEN + 7, 200);
    try std.testing.expectError(error.Truncated, pat.scan(&b, &h, &pats));
}
