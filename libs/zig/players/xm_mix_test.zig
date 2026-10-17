// Native tests for the XM mixer, envelope and pitch tables (xm_mix.zig,
// xm_voice.zig, xm_tables.zig): `zig test` this file.
const std = @import("std");
const xmix = @import("xm_mix.zig");
const xv = @import("xm_voice.zig");
const xt = @import("xm_tables.zig");
const inst = @import("xm_instr.zig");

fn voice(step_frames: u32, gain: u32) xmix.Voice {
    return .{ .active = true, .step = step_frames << 16, .gain = gain };
}

test "a forward loop wraps a voice back to its loop start, output unchanged in level" {
    // Frames 10 20 30 40 looped whole: each frame is read at half gain (x 64 >> 7 = x/2).
    const data = [_]i8{ 10, 20, 30, 40 };
    const s = inst.Sample{ .len = 4, .loop = inst.LOOP_FORWARD, .loop_start = 0, .loop_len = 4 };
    var v = voice(2, 64);
    var out = [_]i8{0} ** 4;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 5, 15, 5, 15 }, &out);
    try std.testing.expect(v.active);
}

test "a ping-pong loop turns round at each end and runs back to the start" {
    const data = [_]i8{ 10, 20, 30, 40 };
    const s = inst.Sample{ .len = 4, .loop = inst.LOOP_PINGPONG, .loop_start = 0, .loop_len = 4 };
    var v = voice(1, 64);
    var out = [_]i8{0} ** 8;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 5, 10, 15, 20, 15, 10, 5, 10 }, &out);
}

test "a voice with no loop runs off the end of its sample and goes silent" {
    const data = [_]i8{ 10, 20 };
    const s = inst.Sample{ .len = 2 };
    var v = voice(1, 64);
    var out = [_]i8{0} ** 4;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 5, 10, 0, 0 }, &out);
    try std.testing.expect(!v.active);
}

test "an inactive voice adds nothing to the bus" {
    const data = [_]i8{ 100, 100 };
    const s = inst.Sample{ .len = 2 };
    var v = xmix.Voice{};
    var out = [_]i8{7} ** 2;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 7, 7 }, &out);
}

test "the volume of a voice is volume x envelope x fadeout, as 0..64" {
    try std.testing.expectEqual(@as(u32, 64), xmix.voiceGain(64, 64, 65536));
    try std.testing.expectEqual(@as(u32, 16), xmix.voiceGain(32, 32, 65536));
    try std.testing.expectEqual(@as(u32, 0), xmix.voiceGain(64, 64, 0));
}

fn pt(x: u16, y: u16) inst.Point {
    return .{ .x = x, .y = y };
}

test "an envelope interpolates between its points, and holds its last value" {
    var e = inst.Envelope{ .on = true, .n = 3 };
    e.pts[0] = pt(0, 0);
    e.pts[1] = pt(10, 64);
    e.pts[2] = pt(20, 0);
    try std.testing.expectEqual(@as(u32, 32), xv.envValue(&e, 5, true));
    try std.testing.expectEqual(@as(u32, 32), xv.envValue(&e, 15, true));
    try std.testing.expectEqual(@as(u32, 0), xv.envValue(&e, 25, true));
}

test "an envelope that is off, or has no points, is full volume" {
    const off = inst.Envelope{ .on = false, .n = 3 };
    try std.testing.expectEqual(@as(u32, 64), xv.envValue(&off, 99, true));
    const none = inst.Envelope{ .on = true, .n = 0 };
    try std.testing.expectEqual(@as(u32, 64), xv.envValue(&none, 99, true));
}

test "a sustain point holds while the key is down, and not after key-off" {
    var e = inst.Envelope{ .on = true, .sustain_on = true, .n = 3, .sustain = 1 };
    e.pts[0] = pt(0, 0);
    e.pts[1] = pt(10, 64);
    e.pts[2] = pt(20, 0);
    try std.testing.expectEqual(@as(u32, 64), xv.envValue(&e, 30, true));
    try std.testing.expectEqual(@as(u32, 0), xv.envValue(&e, 30, false));
}

test "an envelope loop wraps its time between two points" {
    var e = inst.Envelope{ .on = true, .loop_on = true, .n = 3, .loop_start = 0, .loop_end = 1 };
    e.pts[0] = pt(0, 0);
    e.pts[1] = pt(10, 64);
    e.pts[2] = pt(20, 0);
    try std.testing.expectEqual(@as(u32, 12), xv.envValue(&e, 12, true));
}

test "the fadeout falls only once the key is up, and the note restarts it" {
    var c = xv.Chan{ .key_on = true };
    xv.tickEnvelope(&c, 4096);
    try std.testing.expectEqual(@as(u32, 65536), c.fade);
    c.key_on = false;
    xv.tickEnvelope(&c, 4096);
    try std.testing.expectEqual(@as(u32, 61440), c.fade);
    xv.keyOn(&c);
    try std.testing.expectEqual(@as(u32, 65536), c.fade);
    try std.testing.expectEqual(@as(u32, 0), c.env_tick);
}

test "linear step: a semitone is 2^(1/12), and C-4 plays at 8363 Hz" {
    const c4 = xt.linearStep(4608);
    try std.testing.expectApproxEqRel(@as(f64, 8363.0 / xt.RATE), @as(f64, @floatFromInt(c4)) / 65536.0, 1e-3);
    const c5 = xt.linearStep(4608 - 768);
    try std.testing.expectApproxEqRel(@as(f64, 2.0), @as(f64, @floatFromInt(c5)) / @as(f64, @floatFromInt(c4)), 1e-3);
}

test "amiga step: C-2 (period 428) is 7093789.2 / 856 Hz" {
    const want = 7093789.2 / 856.0 / xt.RATE;
    try std.testing.expectApproxEqRel(want, @as(f64, @floatFromInt(xt.amigaStep(428))) / 65536.0, 1e-3);
}

test "a note's period: C-4 is 4608 in linear, C-2 is 428 in Amiga, and a period out of range is clamped" {
    try std.testing.expectEqual(@as(i32, 4608), xt.periodOf(48, 0, true));
    try std.testing.expectEqual(@as(i32, 428), xt.periodOf(24, 0, false));
    try std.testing.expectEqual(xt.PERIOD_MAX, xt.clampPeriod(1 << 20));
    try std.testing.expectEqual(xt.PERIOD_MIN, xt.clampPeriod(-5));
}

test "vibrato is a sine of its phase, zero at the start and the middle" {
    try std.testing.expectEqual(@as(i32, 0), xt.vibratoDelta(0, 15));
    try std.testing.expectEqual(@as(i32, 0), xt.vibratoDelta(32, 15));
    try std.testing.expect(xt.vibratoDelta(16, 15) > 0);
    try std.testing.expectEqual(@as(i32, 0), xt.vibratoDelta(16, 0));
}

test "a sample over 65536 frames loops at its own end, past the old 16.16 range" {
    // Frame i holds i % 100; gain 128 makes the output the frame's value exactly.
    var data: [70000]i8 = undefined;
    for (&data, 0..) |*d, i| d.* = @intCast(i % 100);
    const s = inst.Sample{ .len = 70000, .loop = inst.LOOP_FORWARD, .loop_start = 60000, .loop_len = 10000 };
    var v = xmix.Voice{ .active = true, .idx = 69995, .step = 1 << 16, .gain = 128 };
    var out = [_]i8{0} ** 12;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 95, 96, 97, 98, 99, 0, 1, 2, 3, 4, 5, 6 }, &out);
    try std.testing.expect(v.active);
}

test "a fractional step carries into the frame index across 65536" {
    var data: [70000]i8 = undefined;
    for (&data, 0..) |*d, i| d.* = @intCast(i % 100);
    const s = inst.Sample{ .len = 70000 };
    // Step 1.5: frames 65534, 65535.5, 65537, 65538.5, 65540, 65541.5 (the fraction carried).
    var v = xmix.Voice{ .active = true, .idx = 65534, .step = 98304, .gain = 128 };
    var out = [_]i8{0} ** 6;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 34, 35, 37, 38, 40, 41 }, &out);
}

test "a ping-pong sample plays its attack before the loop, not reflected into it" {
    // Loop over frames 2..3: frames 0 and 1 are the attack, then 2 3 2 3 ... at step 1.
    const data = [_]i8{ 10, 20, 30, 40 };
    const s = inst.Sample{ .len = 4, .loop = inst.LOOP_PINGPONG, .loop_start = 2, .loop_len = 2 };
    var v = voice(1, 64);
    var out = [_]i8{0} ** 6;
    xmix.mixVoice(&v, &data, &s, &out);
    try std.testing.expectEqualSlices(i8, &.{ 5, 10, 15, 20, 15, 20 }, &out);
}
