// Native tests for the MOD header check (mod_format.zig): `zig test` this file.
const std = @import("std");
const f = @import("mod_format.zig");

/// A minimal MOD: the header, `patterns` empty patterns, no sample data.
fn image(out: []u8, tag: *const [4]u8, song_len: u8, patterns: u8) []u8 {
    const len = f.HEADER_LEN + @as(usize, patterns) * f.PATTERN_BYTES;
    @memset(out[0..len], 0);
    out[950] = song_len;
    for (0..song_len) |i| out[952 + i] = @intCast(i % patterns);
    @memcpy(out[f.TAG_OFFSET..][0..4], tag);
    return out[0..len];
}

/// A note (period 428) on channel `ch`, row `row` of pattern `pat`.
fn note(m: []u8, pat: usize, row: usize, ch: usize) void {
    const o = f.HEADER_LEN + pat * f.PATTERN_BYTES + row * 16 + ch * 4;
    m[o] = 0x01;
    m[o + 1] = 0xAC;
}

var buf: [f.HEADER_LEN + 4 * f.PATTERN_BYTES]u8 = undefined;

test "every four-channel ProTracker tag loads" {
    for (f.TAGS) |t| {
        const h = try f.parse(image(&buf, t, 1, 1));
        try std.testing.expectEqual(@as(u8, 1), h.song_len);
        try std.testing.expectEqual(@as(u16, 1), h.num_patterns);
    }
}

test "6CHN, 8CHN, 32CH and an untagged 15-sample file are refused, not played as four" {
    for ([_]*const [4]u8{ "6CHN", "8CHN", "32CH", "CD81", "OCTA", "\x00\x00\x00\x00" }) |t|
        try std.testing.expectError(error.NotFourChannel, f.parse(image(&buf, t, 1, 1)));
    try std.testing.expect(!f.isFourChannel(image(&buf, "8CHN", 1, 1)));
    try std.testing.expectEqual(@as(u32, 2), f.code(error.NotFourChannel));
}

test "a file shorter than the header is refused" {
    const m = image(&buf, "M.K.", 1, 1);
    try std.testing.expectError(error.TooShort, f.parse(m[0 .. f.HEADER_LEN - 1]));
    try std.testing.expectError(error.TooShort, f.parse(&.{}));
}

test "a song length of 0 or over 128 is refused" {
    try std.testing.expectError(error.BadSongLength, f.parse(image(&buf, "M.K.", 0, 1)));
    const m = image(&buf, "M.K.", 1, 1);
    m[950] = 129;
    try std.testing.expectError(error.BadSongLength, f.parse(m));
}

test "sample data starts after the highest pattern in the order list" {
    const m = image(&buf, "M.K.", 3, 3);
    m[20 + 22] = 0;
    m[20 + 23] = 8; // sample 1: 16 bytes
    const h = try f.parse(m);
    try std.testing.expectEqual(@as(u16, 3), h.num_patterns);
    try std.testing.expectEqual(@as(u32, f.HEADER_LEN + 3 * f.PATTERN_BYTES), h.samples[1].start);
    try std.testing.expectEqual(h.samples[1].start + 16, h.samples[2].start);
}

test "the quiet channel is the one with the fewest notes, counted per order entry" {
    const m = image(&buf, "M.K.", 2, 2);
    m[952] = 0;
    m[953] = 0; // pattern 0 played twice, pattern 1 never
    for (0..8) |r| note(m, 0, r, 0);
    for (0..4) |r| note(m, 0, r, 1);
    note(m, 0, 0, 2);
    for (0..6) |r| note(m, 0, r, 3);
    for (0..40) |r| note(m, 1, r, 2); // never played: does not count
    const h = try f.parse(m);
    try std.testing.expectEqual(@as(u8, 2), f.quietChannel(&h, m));
}

test "a tie goes to the lowest channel; an empty song lends channel 0" {
    const m = image(&buf, "M.K.", 1, 1);
    const h = try f.parse(m);
    try std.testing.expectEqual(@as(u8, 0), f.quietChannel(&h, m));
}
