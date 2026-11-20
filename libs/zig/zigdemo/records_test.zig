//! Tests for records.zig over a made-up file (a 16-byte header then 20 records of 48 bytes): a
//! record read on demand, the prefetch going into the other buffer, sequential reads with no seek,
//! a jump with one seek, and each failure (missing file, short header, stride too big, read error).
const std = @import("std");
const records = @import("records.zig");
const F = @import("stream_fake_test.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const R = records.Records(F.Fake);
const N = 20;
const STRIDE = 48;

fn file(buf: []u8) []u8 {
    @memset(buf[0..16], 0);
    @memcpy(buf[0..4], "RECS");
    for (0..N) |i| for (0..STRIDE) |k| {
        buf[16 + i * STRIDE + k] = @truncate(i * 7 + k);
    };
    return buf[0 .. 16 + N * STRIDE];
}

var b0: [64]u8 align(16) = undefined;
var b1: [64]u8 align(16) = undefined;

fn opened(fake: *F.Fake) !R {
    var s: R = .{ .files = fake, .bufs = .{ &b0, &b1 } };
    var hdr: [16]u8 = undefined;
    try expect(s.open("C:\\ANIM.BIN", &hdr));
    try expect(std.mem.eql(u8, hdr[0..4], "RECS"));
    try expect(s.layout(16, STRIDE, N));
    return s;
}

fn isRecord(r: []const u8, f: usize) !void {
    try expectEqual(@as(usize, STRIDE), r.len);
    for (r, 0..) |v, k| try expectEqual(@as(u8, @truncate(f * 7 + k)), v);
}

test "records in order: one read each, no seek; the prefetch is used" {
    var buf: [2048]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\ANIM.BIN", .data = file(&buf) };
    var s = try opened(&fake);
    for (0..N) |f| {
        try isRecord(s.get(@intCast(f)).?, f);
        s.prefetch(@intCast(f + 1));
    }
    try expectEqual(@as(u32, N), s.reads);
    try expectEqual(@as(u32, 0), fake.seeks);
    s.prefetch(N); // past the end: nothing
    try expectEqual(@as(u32, N), s.reads);
}

test "a jump is one seek; a record held is not read again" {
    var buf: [2048]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\ANIM.BIN", .data = file(&buf) };
    var s = try opened(&fake);
    try isRecord(s.get(12).?, 12);
    try expectEqual(@as(u32, 1), fake.seeks);
    try isRecord(s.get(3).?, 3);
    try isRecord(s.get(12).?, 12); // still in the other buffer
    try expectEqual(@as(u32, 2), s.reads);
    try expect(s.get(N) == null); // out of range
}

test "a missing file, a short header, a stride too big and a read error all fail" {
    var buf: [2048]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\OTHER.BIN", .data = file(&buf) };
    var s: R = .{ .files = &fake, .bufs = .{ &b0, &b1 } };
    var hdr: [16]u8 = undefined;
    try expect(!s.open("C:\\ANIM.BIN", &hdr));
    try expect(s.failed);

    var tiny: F.Fake = .{ .path = "C:\\ANIM.BIN", .data = buf[0..8] };
    s = .{ .files = &tiny, .bufs = .{ &b0, &b1 } };
    try expect(!s.open("C:\\ANIM.BIN", &hdr));

    fake.path = "C:\\ANIM.BIN";
    s = try opened(&fake);
    try expect(!s.layout(16, 65, N));
    try expect(s.failed);

    s = try opened(&fake);
    fake.fail_at = 16 + 5 * STRIDE;
    try isRecord(s.get(4).?, 4);
    try expect(s.get(5) == null);
    try expect(s.failed);
}
