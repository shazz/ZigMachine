// Native tests for the POKEY audio model (pokey.zig): `zig test` this file.
// Each checks a documented behaviour (Altirra Hardware Reference Manual,
// "POKEY"; De Re Atari ch. 7), not just the model against itself.
const std = @import("std");
const p = @import("pokey.zig");
const expectEqual = std.testing.expectEqual;

fn running() p.Pokey {
    var k = p.Pokey{};
    k.write(p.SKCTL, 3); // out of init mode, as the OS does at boot
    return k;
}

/// The steady half-period (cycles between two toggles) of channel `ch`, a pure
/// tone at volume 15, measured after a few periods to skip the start-up.
fn halfPeriod(k: *p.Pokey, ch: usize) !u64 {
    var last: ?u64 = null;
    var prev = k.level(ch);
    var gaps: [6]u64 = undefined;
    var n: usize = 0;
    var t: u64 = 0;
    while (n < gaps.len) : (t += 1) {
        if (t > 40_000_000) return error.NoTone;
        k.step();
        const l = k.level(ch);
        if (l == prev) continue;
        prev = l;
        if (last) |s| {
            gaps[n] = t - s;
            n += 1;
        }
        last = t;
    }
    for (gaps[2..]) |g| try expectEqual(gaps[1], g);
    return gaps[1];
}

fn tone(audctl: u8, ch: usize, f: [4]u8) !u64 {
    var k = running();
    k.write(p.AUDCTL, audctl);
    for (0..4) |i| {
        k.write(@intCast(2 * i), f[i]);
        k.write(@intCast(2 * i + 1), 0xAF); // pure tone, volume 15
    }
    k.write(p.STIMER, 0);
    return halfPeriod(&k, ch);
}

test "64 kHz base: a pure tone's half period is 28 (N+1) cycles" {
    for ([_]u8{ 0, 1, 31, 255 }) |n| {
        for (0..4) |ch| try expectEqual(28 * (@as(u64, n) + 1), try tone(0x00, ch, .{ n, n, n, n }));
    }
}

test "15 kHz base (AUDCTL bit 0): 114 (N+1) cycles" {
    for ([_]u8{ 0, 7, 200 }) |n| {
        for (0..4) |ch| try expectEqual(114 * (@as(u64, n) + 1), try tone(0x01, ch, .{ n, n, n, n }));
    }
}

test "1.79 MHz on channel 1 (bit 6) and 3 (bit 5): N+4 cycles, the others stay on the base" {
    for ([_]u8{ 0, 1, 100, 255 }) |n| {
        try expectEqual(@as(u64, n) + 4, try tone(0x40, 0, .{ n, 5, n, 5 }));
        try expectEqual(@as(u64, n) + 4, try tone(0x20, 2, .{ n, 5, n, 5 }));
        try expectEqual(28 * 6, try tone(0x60, 1, .{ n, 5, n, 5 }));
        try expectEqual(28 * 6, try tone(0x60, 3, .{ n, 5, n, 5 }));
    }
}

test "joined pairs (bits 4, 3) at 1.79 MHz: N16+7 cycles, heard on channels 2 and 4" {
    for ([_]u16{ 0, 1, 0x1234, 0xFFFF }) |n| {
        const lo: u8 = @truncate(n);
        const hi: u8 = @truncate(n >> 8);
        try expectEqual(@as(u64, n) + 7, try tone(0x50, 1, .{ lo, hi, 0, 0 }));
        try expectEqual(@as(u64, n) + 7, try tone(0x28, 3, .{ 0, 0, lo, hi }));
    }
}

test "joined pairs on the bases: (N16+1) x 28 and x 114 cycles" {
    try expectEqual(28 * (0x0102 + 1), try tone(0x10, 1, .{ 2, 1, 0, 0 }));
    try expectEqual(114 * (0x0300 + 1), try tone(0x09, 3, .{ 0, 0, 0, 3 }));
}

fn polyPeriod(comptime field: []const u8, nine: bool, mask: u17) u64 {
    var q = p.Poly{};
    const start = @as(u17, @field(q, field)) & mask;
    var n: u64 = 0;
    while (true) {
        q.shift(nine);
        n += 1;
        if (@as(u17, @field(q, field)) & mask == start) return n;
    }
}

test "the polynomial counters run from init (all zero) with periods 15, 31, 511, 131071" {
    try expectEqual(@as(u64, 15), polyPeriod("p4", false, 0xF));
    try expectEqual(@as(u64, 31), polyPeriod("p5", false, 0x1F));
    try expectEqual(@as(u64, 511), polyPeriod("p17", true, 0x1FF));
    try expectEqual(@as(u64, 131071), polyPeriod("p17", false, 0x1FFFF));
}

// An XNOR m-sequence of 31 holds 15 ones and 16 zeros (the XOR one inverted).
test "the 5-bit poly passes 15 borrows of 31 (its ones), so 5-bit + pure toggles 15 times" {
    var k = running();
    k.write(p.AUDCTL, 0x40);
    k.write(p.AUDF1, 0); // a borrow every 4 cycles: 4 and 31 are coprime
    k.write(p.AUDC1, 0x2F); // 5-bit poly, then pure
    k.write(p.STIMER, 0);
    for (0..4 * 31 * 10) |_| k.step(); // settle
    var toggles: u32 = 0;
    var prev = k.level(0);
    for (0..4 * 31 * 100) |_| {
        k.step();
        if (k.level(0) != prev) toggles += 1;
        prev = k.level(0);
    }
    try expectEqual(@as(u32, 15 * 100), toggles);
}

test "volume-only (AUDC bit 4) holds the level at the volume, the counter ignored" {
    var k = running();
    k.write(p.AUDC1 + 2, 0x19);
    for (0..1000) |_| {
        k.step();
        try expectEqual(@as(u4, 9), k.level(1));
    }
    try expectEqual(@as(u8, 9), k.mix());
}

test "init mode (SKCTL bits 0-1 clear) stops the bases and holds the polys, 1.79 MHz runs on" {
    var k = p.Pokey{}; // power-up: init mode
    k.write(p.AUDCTL, 0x40);
    k.write(p.AUDC1, 0xAF);
    k.write(p.AUDC1 + 2, 0xAF);
    k.write(p.STIMER, 0);
    var t1: u32 = 0;
    var t2: u32 = 0;
    for (0..10_000) |_| {
        const a = k.level(0);
        const b = k.level(1);
        k.step();
        if (k.level(0) != a) t1 += 1;
        if (k.level(1) != b) t2 += 1;
    }
    try expectEqual(@as(u32, 2500), t1);
    try expectEqual(@as(u32, 0), t2);
    try expectEqual(p.Poly{}, k.poly);
}

test "high-pass 1 by 3 at the same rate passes nothing: the level sits at DC" {
    var k = running();
    k.write(p.AUDCTL, 0x64); // ch1 and ch3 at 1.79 MHz, filter 1 by 3
    k.write(p.AUDF1, 10);
    k.write(p.AUDF1 + 4, 10);
    k.write(p.AUDC1, 0xAF);
    k.write(p.STIMER, 0);
    for (0..100) |_| k.step();
    for (0..5000) |_| {
        k.step();
        try expectEqual(@as(u4, 15), k.level(0));
    }
}

test "render: a 50 % square wave at full volume averages 15/60 of full scale" {
    var k = running();
    k.write(p.AUDC1, 0xAF);
    k.write(p.AUDF1, 9);
    var buf: [4410]f32 = undefined;
    var frac: u64 = 0;
    k.render(&buf, 44100, p.Clock.ntsc, &frac);
    var sum: f64 = 0;
    for (buf) |s| sum += s;
    try std.testing.expectApproxEqAbs(@as(f64, 0.125), sum / buf.len, 0.002);
}

test "an unmapped register write (POTGO, SKREST) changes nothing" {
    var k = running();
    k.write(0xA, 0xFF);
    k.write(0xB, 0xFF);
    try expectEqual(running(), k);
}

test "the two clocks are the RTL's enables: NTSC 315/176 MHz, PAL 1773447.5 Hz to 0.01 ppm" {
    try expectEqual(@as(u64, 1_789_772), p.Clock.ntsc.num / p.Clock.ntsc.den);
    try expectEqual(@as(u64, 315_000_000 * p.Clock.ntsc.den), 176 * p.Clock.ntsc.num);
    const pal = @as(f64, @floatFromInt(p.Clock.pal.num)) / @as(f64, @floatFromInt(p.Clock.pal.den));
    try std.testing.expectApproxEqRel(@as(f64, 1_773_447.5), pal, 1e-8);
}
