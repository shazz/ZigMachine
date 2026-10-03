// Tests for machine/audio/ym.zig's envelope generator: every one of the 16
// shapes, step by step over five 32-step periods, against the YM2149
// datasheet's drawings (the same blocks as Hatari's YmEnvDef and jt49's jt49_eg:
// a first ramp, then two blocks that repeat). The trap these pin is the hold
// level of shapes 11 and 15 (CONT ALT HOLD): the hold takes the ALTERNATED
// level, so 11 (\---) decays once and holds HIGH, 15 (/___) attacks once and
// holds LOW. ym.zig once held both at the end of the ramp instead.
const std = @import("std");
const Ym2149 = @import("ym.zig").Ym2149;

const Block = enum { up, down, high, low }; // ramp 0->31, ramp 31->0, hold 31, hold 0

// [first period, then periods 2, 4, ...; periods 3, 5, ...], per shape (R13 0..15).
const SHAPES = [16][3]Block{
    .{ .down, .low, .low }, .{ .down, .low, .low }, .{ .down, .low, .low }, .{ .down, .low, .low }, // 0-3 \___
    .{ .up, .low, .low }, .{ .up, .low, .low }, .{ .up, .low, .low }, .{ .up, .low, .low }, // 4-7 /___
    .{ .down, .down, .down }, // 8 \\\\
    .{ .down, .low, .low }, // 9 \___
    .{ .down, .up, .down }, // 10 \/\/
    .{ .down, .high, .high }, // 11 \--- (holds HIGH)
    .{ .up, .up, .up }, // 12 ////
    .{ .up, .high, .high }, // 13 /---
    .{ .up, .down, .up }, // 14 /\/\
    .{ .up, .low, .low }, // 15 /___ (holds LOW)
};

fn level(b: Block, i: usize) u5 {
    return switch (b) {
        .up => @intCast(i),
        .down => @intCast(31 - i),
        .high => 31,
        .low => 0,
    };
}

fn expected(shape: usize, step: usize) u5 {
    const period = step / 32;
    const blk = if (period == 0) 0 else 1 + (period - 1) % 2;
    return level(SHAPES[shape][blk], step % 32);
}

test "all 16 envelope shapes follow the datasheet over five periods" {
    for (0..16) |shape| {
        var ym: Ym2149 = .{};
        ym.init(44100.0);
        ym.writeReg(13, @intCast(shape));
        for (0..160) |step| {
            const want = expected(shape, step);
            if (ym.env_pos != want) {
                std.debug.print("shape {d} step {d}: level {d}, want {d}\n", .{ shape, step, ym.env_pos, want });
                return error.EnvelopeShape;
            }
            ym.envStep();
        }
    }
}

test "shape 11 holds high and shape 15 holds low, whatever the step count" {
    for ([_]struct { u8, u5 }{ .{ 11, 31 }, .{ 15, 0 } }) |c| {
        var ym: Ym2149 = .{};
        ym.init(44100.0);
        ym.writeReg(13, c[0]);
        for (0..1000) |_| ym.envStep();
        try std.testing.expectEqual(c[1], ym.env_pos);
    }
}

test "R13 = 0xFF does not retrigger the envelope" {
    var ym: Ym2149 = .{};
    ym.init(44100.0);
    ym.writeReg(13, 8);
    for (0..5) |_| ym.envStep();
    ym.writeReg(13, 0xFF);
    try std.testing.expectEqual(@as(u5, 26), ym.env_pos);
}
