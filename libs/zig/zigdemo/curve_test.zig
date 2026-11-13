//! Tests for curve.zig: linear, step and baked sampling at the edges, at keys, and between them.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const curve = @import("curve.zig");

const Key = curve.Key;

const fade = [_]Key{ .{ .t_ms = 0, .v = 0 }, .{ .t_ms = 1000, .v = 1000 } };
const three = [_]Key{ .{ .t_ms = 0, .v = 0 }, .{ .t_ms = 100, .v = 10 }, .{ .t_ms = 300, .v = 30 } };
const vis = [_]Key{ .{ .t_ms = 100, .v = 1 }, .{ .t_ms = 200, .v = 0 } };

test "linear: before the first key and after the last hold the end values" {
    try expectEqual(@as(i32, 0), curve.sample(.{ .linear = &fade }, 0));
    try expectEqual(@as(i32, 1), curve.sample(.{ .linear = &vis }, 0)); // the first key's value, before it
    try expectEqual(@as(i32, 1000), curve.sample(.{ .linear = &fade }, 5000));
    try expectEqual(@as(i32, 0), curve.sample(.{ .linear = &vis }, 9999));
}

test "linear: exactly at a key is that key's value" {
    try expectEqual(@as(i32, 10), curve.sample(.{ .linear = &three }, 100));
    try expectEqual(@as(i32, 30), curve.sample(.{ .linear = &three }, 300));
}

test "linear: between keys is the Q16 interpolation, rounded down" {
    try expectEqual(@as(i32, 250), curve.sample(.{ .linear = &fade }, 250));
    try expectEqual(@as(i32, 20), curve.sample(.{ .linear = &three }, 200));
    const down = [_]Key{ .{ .t_ms = 0, .v = 0 }, .{ .t_ms = 3, .v = -1 } };
    try expectEqual(@as(i32, -1), curve.sample(.{ .linear = &down }, 1));
}

test "linear: a key span of two i32 extremes does not overflow" {
    const big = [_]Key{
        .{ .t_ms = 0, .v = -2_000_000_000 },
        .{ .t_ms = 0xFFFF_0000, .v = 2_000_000_000 },
    };
    try expectEqual(@as(i32, 0), curve.sample(.{ .linear = &big }, 0x7FFF_8000));
}

test "linear: a single key is a constant" {
    const one = [_]Key{.{ .t_ms = 500, .v = 7 }};
    try expectEqual(@as(i32, 7), curve.sample(.{ .linear = &one }, 0));
    try expectEqual(@as(i32, 7), curve.sample(.{ .linear = &one }, 500));
    try expectEqual(@as(i32, 7), curve.sample(.{ .linear = &one }, 9000));
}

test "step: holds the last key, flips exactly on its key, holds the first before it" {
    try expectEqual(@as(i32, 1), curve.sample(.{ .step = &vis }, 0));
    try expectEqual(@as(i32, 1), curve.sample(.{ .step = &vis }, 150));
    try expectEqual(@as(i32, 0), curve.sample(.{ .step = &vis }, 200));
    try expectEqual(@as(i32, 0), curve.sample(.{ .step = &vis }, 999));
}

test "baked: samples at exact positions, clamped past the last sample" {
    const s = [_]i16{ 5, 7, 9 };
    const c: curve.Curve = .{ .baked = .{ .rate_hz = 1000, .samples = &s } };
    try expectEqual(@as(i32, 5), curve.sample(c, 0));
    try expectEqual(@as(i32, 7), curve.sample(c, 1));
    try expectEqual(@as(i32, 9), curve.sample(c, 2));
    try expectEqual(@as(i32, 9), curve.sample(c, 3));
}

test "baked: between two samples is the Q16 mix, rounded down" {
    const s = [_]i16{ 0, 100, 200 };
    const c: curve.Curve = .{ .baked = .{ .rate_hz = 500, .samples = &s } };
    try expectEqual(@as(i32, 50), curve.sample(c, 1));
    try expectEqual(@as(i32, 100), curve.sample(c, 2));
    try expectEqual(@as(i32, 150), curve.sample(c, 3));
    try expectEqual(@as(i32, 200), curve.sample(c, 5));
}

test "baked at the TBL rate of 30 Hz: between samples is floored, past the end holds the last" {
    const s = [_]i16{ 0, 100, 200 };
    const c: curve.Curve = .{ .baked = .{ .rate_hz = 30, .samples = &s } };
    try expectEqual(@as(i32, 101), curve.sample(c, 34)); // 1.02 samples in: 100 + 100 * 0.02, floored
    try expectEqual(@as(i32, 200), curve.sample(c, 100));
}

test "checkKeys: empty and non-increasing keys are refused" {
    try std.testing.expectError(error.Empty, curve.checkKeys(&[_]Key{}));
    const dup = [_]Key{ .{ .t_ms = 5, .v = 1 }, .{ .t_ms = 5, .v = 2 } };
    try std.testing.expectError(error.NotIncreasing, curve.checkKeys(&dup));
    try curve.checkKeys(&three);
}
