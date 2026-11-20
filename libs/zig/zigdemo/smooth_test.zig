//! Tests for smooth.zig: the picture's clock runs on the VBL, ignores a decoder's bursts and steps,
//! follows a lasting lag gently, takes a real jump at once, and honours its Config.
const std = @import("std");
const smooth = @import("smooth.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const Smooth = smooth.Smooth(.{});

/// A decoder's position in MP3 frames of 1,152 samples at 44.1 kHz (26.1 ms steps).
fn decoded(us: i64) i64 {
    const frames = @divFloor(us * 44_100, 1_152 * 1_000_000);
    return @divFloor(frames * 1_152 * 1_000_000, 44_100);
}

fn vbl(f: usize) i64 {
    return @divFloor(@as(i64, @intCast(f)) * 1_000_000, 60);
}

test "a steady 60 Hz picture from a 26 ms-step decoder: every frame +16 or +17 ms" {
    var s: Smooth = .{};
    var last = s.at(decoded(0));
    for (1..600) |f| {
        const now = s.at(decoded(vbl(f)));
        const d = @as(i64, now) - last;
        try expect(d == 16 or d == 17);
        last = now;
    }
}

test "three frames are exactly 50 ms" {
    var s: Smooth = .{};
    _ = s.at(0);
    _ = s.at(vbl(1));
    _ = s.at(vbl(2));
    try expectEqual(@as(u32, 50), s.at(vbl(3)));
}

test "the decoder stalls one second then catches up: the picture never stops nor jumps" {
    var s: Smooth = .{};
    var last = s.at(0);
    var held: i64 = 0;
    for (1..240) |f| {
        if (f < 60 or f >= 120) held = decoded(vbl(f)); // frames 60..119: no decode, the position holds
        const now = s.at(held);
        const d = @as(i64, now) - last;
        try expect(d >= 13 and d <= 19);
        last = now;
    }
}

test "a real jump of the music (a re-seek) is taken at once" {
    var s: Smooth = .{};
    _ = s.at(0);
    _ = s.at(16_667);
    try expectEqual(@as(u32, 10_033), s.at(10_033_000));
}

test "reset re-anchors on the music; a negative position reads as 0" {
    var s: Smooth = .{};
    _ = s.at(5_000_000);
    s.reset();
    try expectEqual(@as(u32, 1_000), s.at(1_000_000));
    s.reset();
    try expectEqual(@as(u32, 0), s.at(-5_000));
}

test "a Config with no dead band and a big step follows a lag faster" {
    var tight: smooth.Smooth(.{ .dead_us = 0, .pull = 2, .step_us = 100_000 }) = .{};
    var soft: Smooth = .{};
    _ = tight.at(0);
    _ = soft.at(0);
    // the music runs 200 ms ahead from frame 1 on (under the snap)
    const a = tight.at(vbl(1) + 200_000);
    const b = soft.at(vbl(1) + 200_000);
    try expect(a > b);
    try expectEqual(@as(u32, 18), b); // 16.667 + 2 ms
}
