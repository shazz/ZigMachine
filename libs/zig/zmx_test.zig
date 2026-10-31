// zmx.zig against a byte-at-a-time / 64-bit reference of the spec, exhaustive
// over a lane's 256 x 256 operand pairs at every lane position, with the other
// lanes random (a carry or borrow leaking across lanes shows there).
const std = @import("std");
const zmx = @import("zmx.zig");
const expectEqual = std.testing.expectEqual;

fn lane(w: u32, i: u5) u8 {
    return @truncate(w >> (8 * i));
}

fn refLanes(comptime op: fn (u8, u8) u8, a: u32, b: u32) u32 {
    var r: u32 = 0;
    for (0..4) |i| r |= @as(u32, op(lane(a, @intCast(i)), lane(b, @intCast(i)))) << @intCast(8 * i);
    return r;
}
fn rAdd8s(a: u8, b: u8) u8 {
    return @intCast(@min(@as(u16, a) + b, 255));
}
fn rSub8s(a: u8, b: u8) u8 {
    return if (a > b) a - b else 0;
}
fn rAvg8(a: u8, b: u8) u8 {
    return @intCast((@as(u16, a) + b) >> 1);
}
fn rAdd8(a: u8, b: u8) u8 {
    return a +% b;
}

fn exhaustive(comptime op: anytype, comptime ref: fn (u8, u8) u8) !void {
    var prng = std.Random.DefaultPrng.init(0x2A5E_0001);
    const rnd = prng.random();
    for (0..4) |li| {
        const sh: u5 = @intCast(8 * li);
        const keep = ~(@as(u32, 0xFF) << sh);
        for (0..256) |x| for (0..256) |y| {
            const a = (rnd.int(u32) & keep) | (@as(u32, @intCast(x)) << sh);
            const b = (rnd.int(u32) & keep) | (@as(u32, @intCast(y)) << sh);
            try expectEqual(refLanes(ref, a, b), op(a, b));
        };
    }
}

test "add8s / sub8s / avg8 / add8: every lane pair, every lane, no leak" {
    try exhaustive(zmx.add8s, rAdd8s);
    try exhaustive(zmx.sub8s, rSub8s);
    try exhaustive(zmx.avg8, rAvg8);
    try exhaustive(zmx.add8, rAdd8);
}

test "lane ops: the edges (saturate both ways, floor average decays to 0)" {
    try expectEqual(@as(u32, 0xFFFFFFFF), zmx.add8s(0xFFFFFFFF, 0x01010101));
    try expectEqual(@as(u32, 0x00000000), zmx.sub8s(0x00000000, 0xFFFFFFFF));
    try expectEqual(@as(u32, 0x00FF7F00), zmx.add8s(0x00807F00, 0x007F0000));
    try expectEqual(@as(u32, 0), zmx.avg8(0x01010101, 0)); // floor: 1 decays to 0
    try expectEqual(@as(u32, 0xFFFFFFFF), zmx.avg8(0xFFFFFFFF, 0xFFFFFFFF));
    try expectEqual(@as(u32, 0x00000000), zmx.add8(0x01010101, 0xFFFFFFFF)); // wraps per lane
    try expectEqual(@as(u32, 0x05050505), zmx.splat8(5));
}

test "mulsh: = the 64-bit product's bits, arithmetic, truncating" {
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    for (0..200_000) |_| {
        const a = rnd.int(i32);
        const b = rnd.int(i32);
        const p: i64 = @as(i64, a) * b;
        try expectEqual(@as(i32, @truncate(p >> 16)), zmx.mulsh16(a, b));
        try expectEqual(@as(i32, @truncate(p >> 15)), zmx.mulsh15(a, b));
    }
}

test "mulsh: edges" {
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    try expectEqual(@as(i32, 0), zmx.mulsh16(min, min)); // 2^62: bits 47..16 are 0
    try expectEqual(@as(i32, -1), zmx.mulsh16(-1, 1)); // floors toward -inf, not 0
    try expectEqual(@as(i32, -1), zmx.mulsh15(-1, 1));
    try expectEqual(@as(i32, @bitCast(@as(u32, 0xFFFF0000))), zmx.mulsh16(max, max)); // (2^62 - 2^32 + 1) >> 16, low 32 bits
    try expectEqual(@as(i32, 1 << 16), zmx.mulsh16(1 << 16, 1 << 16)); // 1.0 * 1.0
    try expectEqual(@as(i32, 1 << 15), zmx.mulsh15(1 << 15, 1 << 15)); // Q15 1.0 (as 2^15) squared
    try expectEqual(@as(i32, -3 << 15), zmx.mulsh16(3 << 16, -1 << 15)); // 3 * -0.5
}

test "tex2d: masks, shifts, wraps (logical), every size" {
    try expectEqual(@as(u32, 0), zmx.tex2d(8, 8, 0, 0));
    try expectEqual(@as(u32, 255 * 256 + 255), zmx.tex2d(8, 8, 0xFFFF_FFFF, 0xFFFF_FFFF));
    const neg: u32 = @bitCast(@as(i32, -1 << 16)); // -1.0: the texel left of 0 wraps to the last
    try expectEqual(@as(u32, 63), zmx.tex2d(6, 6, neg, 0));
    try expectEqual(@as(u32, (5 << 7) | 3), zmx.tex2d(7, 3, 3 << 16 | 0xFFFF, 13 << 16)); // 13 & 7 = 5
    try expectEqual(@as(u32, 1023 << 10 | 1023), zmx.tex2d(10, 10, 0xFFFF_FFFF, 0xFFFF_FFFF));
    try expectEqual(@as(u7, 0), zmx.texDims(3, 3));
    try expectEqual(@as(u7, 5 | (7 << 3)), zmx.texDims(8, 10));
    var prng = std.Random.DefaultPrng.init(9);
    const rnd = prng.random();
    inline for (3..11) |lw| inline for (3..11) |lh| for (0..64) |_| {
        const u = rnd.int(u32);
        const v = rnd.int(u32);
        const want = ((v >> 16) % (1 << lh)) * (1 << lw) + (u >> 16) % (1 << lw);
        try expectEqual(want, zmx.tex2d(lw, lh, u, v));
    };
}

test "funnel: the unaligned word of a little-endian pair" {
    const bytes = [8]u8{ 0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23 };
    const lo = std.mem.readInt(u32, bytes[0..4], .little);
    const hi = std.mem.readInt(u32, bytes[4..8], .little);
    inline for (1..4) |k| try expectEqual(std.mem.readInt(u32, bytes[k..][0..4], .little), zmx.funnel(k, lo, hi));
    try expectEqual(@as(u32, 0x000000FF), zmx.funnel(3, 0xFFFFFFFF, 0));
    try expectEqual(@as(u32, 0xFFFFFF00), zmx.funnel(3, 0, 0xFFFFFFFF));
}

test "rcp: table pinned, within 2^-14 of 2^32/d" {
    try expectEqual(@as(u16, 65408), zmx.RCP[0]); // round(2^25 / 513)
    try expectEqual(@as(u16, 32800), zmx.RCP[255]); // round(2^25 / 1023)
    try expectEqual(@as(u32, 0xFFFF_FFFF), zmx.rcp(0));
    try expectEqual(@as(u32, 0xFFFF_FFFF), zmx.rcp(1));
    var prng = std.Random.DefaultPrng.init(3);
    const rnd = prng.random();
    var d: u64 = 2;
    while (d <= 0xFFFF_FFFF) : (d += 1 + (d >> 6) + (rnd.int(u32) & 63)) try checkRcp(@intCast(d));
    try checkRcp(0xFFFF_FFFF);
    try checkRcp(1 << 16); // z = 1.0 -> 1.0
}

fn checkRcp(d: u32) !void {
    const exact: f64 = 4294967296.0 / @as(f64, @floatFromInt(d));
    const got: f64 = @floatFromInt(zmx.rcp(d));
    try std.testing.expect(@abs(exact - got) < exact / 16384.0 + 1.0);
}
