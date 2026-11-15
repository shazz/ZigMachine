//! Tests for ring.zig over a made-up file: a 16-byte header then length-prefixed records read
//! through a 256-byte ring in 64-byte chunks: every record whole and in order (the ones that wrap
//! the ring's end too), the ring never overwriting what is not released, and each failure.
const std = @import("std");
const ring = @import("ring.zig");
const F = @import("stream_fake_test.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Hdr = struct { count: u32 };
fn parse(b: []const u8, r: u32) ?Hdr {
    _ = r;
    if (!std.mem.eql(u8, b[0..4], "TEST")) return null;
    return .{ .count = std.mem.readInt(u32, b[4..8], .little) };
}
const CFG: ring.Config = .{ .chunk = 64, .spill = 64, .header_len = 16, .min_record = 8 };
const R = ring.Ring(F.Fake, CFG, Hdr, parse);
const N = 40;

/// Record i: length 8 + 4 * (i % 11), then its index, then bytes i + k.
fn file(buf: []u8) []u8 {
    @memcpy(buf[0..4], "TEST");
    F.put32(buf, 4, N);
    var at: u32 = 16;
    for (0..N) |i| {
        const len: u32 = 8 + 4 * @as(u32, @intCast(i % 11));
        F.put32(buf, at, len);
        F.put32(buf, at + 4, @intCast(i));
        for (8..len) |k| buf[at + k] = @truncate(i + k);
        at += len;
    }
    return buf[0..at];
}

var storage: [256 + 64]u8 align(8) = undefined;

fn readAll(fake: *F.Fake) !u32 {
    var s: R = .{ .files = fake, .buf = &storage, .ring = 256 };
    s.open("C:\\BIG.BIN");
    var at: u32 = 16;
    var got: u32 = 0;
    var spins: u32 = 0;
    while (got < N and spins < 10_000) : (spins += 1) {
        s.fill(1);
        if (s.failed) return error.Failed;
        const h = s.hdr orelse continue;
        try expectEqual(@as(u32, N), h.count);
        const rec = s.record(at) orelse continue;
        try expectEqual(got, std.mem.readInt(u32, rec[4..8], .little));
        for (8..rec.len) |k| try expectEqual(@as(u8, @truncate(got + k)), rec[k]);
        at += @intCast(rec.len);
        s.release(at);
        got += 1;
    }
    return got;
}

test "every record comes out whole and in order, wrapped ones too" {
    var buf: [4096]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\BIG.BIN", .data = file(&buf) };
    try expectEqual(@as(u32, N), try readAll(&fake));
}

test "a read shorter than asked is the end of the file (GEMDOS Fread): no more reads" {
    var buf: [4096]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\BIG.BIN", .data = file(&buf), .short = 20 };
    var s: R = .{ .files = &fake, .buf = &storage, .ring = 256 };
    s.open("C:\\BIG.BIN");
    s.fill(3);
    try expect(s.eof);
    try expectEqual(@as(u32, 20), s.tail);
    try expectEqual(@as(u32, 1), fake.reads);
    try expect(s.hdr != null); // the 16-byte header was in
}

test "the ring stops reading while nothing is released" {
    var buf: [4096]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\BIG.BIN", .data = file(&buf) };
    var s: R = .{ .files = &fake, .buf = &storage, .ring = 256 };
    s.open("C:\\BIG.BIN");
    s.fill(100);
    try expectEqual(@as(u32, 256), s.tail); // a full ring, then no more
    try expectEqual(@as(u32, 4), fake.reads);
}

test "a missing file, a wrong header, a bad length and a read error all fail" {
    var buf: [4096]u8 = undefined;
    var fake: F.Fake = .{ .path = "C:\\OTHER.BIN", .data = file(&buf) };
    var s: R = .{ .files = &fake, .buf = &storage, .ring = 256 };
    s.open("C:\\BIG.BIN");
    try expect(s.failed);

    fake.path = "C:\\BIG.BIN";
    buf[0] = 'X';
    s.open("C:\\BIG.BIN");
    s.fill(1);
    try expect(s.failed);

    buf[0] = 'T';
    F.put32(&buf, 16, 2); // record 0's length under min_record
    s.open("C:\\BIG.BIN");
    s.fill(1);
    try expect(!s.failed);
    try expect(s.record(16) == null);
    try expect(s.failed);

    F.put32(&buf, 16, 8);
    fake.fail_at = 64;
    s.open("C:\\BIG.BIN");
    s.fill(2);
    try expect(s.failed);
}
