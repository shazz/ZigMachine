// Native tests for the XM instrument reader (xm_instr.zig): `zig test` this file.
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

/// An XM with one instrument of one sample: the sample's header, then its data.
fn oneSample(b: []u8, frame16: bool, loop: u8, loop_start: u32, loop_len: u32, data: []const u8) usize {
    header(b, .{ .ch = 1, .song_len = 1, .npat = 1, .ninst = 1 });
    @memset(b[HDR_LEN..], 0);
    const o = emptyPattern(b, HDR_LEN, 1, 1);
    put32(b, o, 263);
    put16(b, o + 27, 1);
    put32(b, o + 29, 40);
    put16(b, o + 239, 0);
    const sh = o + 263;
    put32(b, sh, @intCast(data.len));
    put32(b, sh + 4, loop_start);
    put32(b, sh + 8, loop_len);
    b[sh + 12] = 64;
    b[sh + 14] = loop | (if (frame16) @as(u8, 0x10) else 0);
    @memcpy(b[sh + 40 ..][0..data.len], data);
    return sh + 40 + data.len;
}

test "an 8-bit delta-coded sample decodes in place, and a loop is kept" {
    var b: [HDR_LEN + 512]u8 = undefined;
    // deltas 1, 1, 1, -1 decode to 1, 2, 3, 2.
    const deltas = [_]u8{ 1, 1, 1, 0xFF };
    const end = oneSample(&b, false, 1, 0, 2, &deltas);
    var h = try fmt.parse(b[0..end]);
    var pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined;
    const after = try pat.scan(b[0..end], &h, &pats);
    var t: inst.Tables = .{};
    try inst.parseAll(b[0..end], &h, after, &t);
    const s = t.samps[0];
    try std.testing.expectEqual(@as(u32, 4), s.len);
    try std.testing.expectEqual(@as(u8, inst.LOOP_FORWARD), s.loop);
    try std.testing.expectEqual(@as(u32, 2), s.loop_len);
    const off = s.off;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 2 }, b[off..][0..4]);
}

test "a 16-bit sample keeps its top byte, two bytes a frame" {
    var b: [HDR_LEN + 512]u8 = undefined;
    // 16-bit deltas 0x0100 and 0x0100 decode to 256 and 512: top bytes 1 and 2.
    const deltas = [_]u8{ 0x00, 0x01, 0x00, 0x01 };
    const end = oneSample(&b, true, 0, 0, 0, &deltas);
    var h = try fmt.parse(b[0..end]);
    var pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined;
    const after = try pat.scan(b[0..end], &h, &pats);
    var t: inst.Tables = .{};
    try inst.parseAll(b[0..end], &h, after, &t);
    try std.testing.expectEqual(@as(u32, 2), t.samps[0].len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, b[t.samps[0].off..][0..2]);
}

test "a loop that runs past its sample is refused, and so is a sample past the file" {
    var b: [HDR_LEN + 512]u8 = undefined;
    const deltas = [_]u8{ 1, 1, 1, 1 };
    const end = oneSample(&b, false, 1, 0, 9, &deltas);
    var h = try fmt.parse(b[0..end]);
    var pats: [fmt.MAX_PATTERNS]pat.PatInfo = undefined;
    const after = try pat.scan(b[0..end], &h, &pats);
    var t: inst.Tables = .{};
    try std.testing.expectError(error.BadInstrument, inst.parseAll(b[0..end], &h, after, &t));
    const end2 = oneSample(&b, false, 0, 0, 0, &deltas);
    put32(&b, HDR_LEN + 10 + 263, 9999); // the sample's length, past the file
    var h2 = try fmt.parse(b[0..end2]);
    const after2 = try pat.scan(b[0..end2], &h2, &pats);
    try std.testing.expectError(error.Truncated, inst.parseAll(b[0..end2], &h2, after2, &t));
}
