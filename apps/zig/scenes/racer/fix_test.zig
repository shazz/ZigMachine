// RACER: fix.zig against PICO-8's numbers. The CRC pins are the Lua reference's own (z8lua)
// over whole input ranges: tools/racer/fix_pin.py prints them. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const fix = @import("fix.zig");

const Crc = std.hash.crc.Crc32IsoHdlc;

fn feed(c: *Crc, v: i32) void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(i32, &b, v, .little);
    c.update(&b);
}

fn trigCrc(comptime f: fn (i32) i32) u32 {
    var c = Crc.init();
    var k: i32 = 0;
    while (k <= 32767) : (k += 1) feed(&c, f(k));
    k = 1;
    while (k <= 32767) : (k += 1) feed(&c, f(-k));
    feed(&c, f(-32768));
    return c.final();
}

test "sin over all 65,536 angles equals PICO-8's" {
    try std.testing.expectEqual(@as(u32, 0x4c218418), trigCrc(fix.sin));
}

test "cos over all 65,536 angles equals PICO-8's" {
    try std.testing.expectEqual(@as(u32, 0x73cae021), trigCrc(fix.cos));
}

test "atan2 on a 301 x 301 grid equals PICO-8's" {
    var c = Crc.init();
    for (0..301) |i| for (0..301) |j| {
        const x = fix.mul((@as(i32, @intCast(i)) - 150) << 16, fix.lit(0.0371));
        const y = fix.mul((@as(i32, @intCast(j)) - 150) << 16, fix.lit(0.0371));
        feed(&c, fix.atan2(x, y));
    };
    try std.testing.expectEqual(@as(u32, 0xbbd0696c), c.final());
}

test "sqrt is the floor of the root, equal to PICO-8's x^0.5 on 32,768 values" {
    var c = Crc.init();
    for (0..32768) |k| feed(&c, fix.sqrt(@as(i32, @intCast(k)) * 517));
    try std.testing.expectEqual(@as(u32, 0xf4dbb970), c.final());
}

test "div saturates on zero and overflow, truncates toward zero, and 1.0 is the identity" {
    try std.testing.expectEqual(fix.MAX, fix.div(5 << 16, 0));
    try std.testing.expectEqual(-fix.MAX, fix.div(-(5 << 16), 0));
    try std.testing.expectEqual(fix.MAX, fix.div(30000 << 16, 1));
    try std.testing.expectEqual(@as(i32, -21845), fix.div(-(1 << 16), 3 << 16));
    try std.testing.expectEqual(@as(i32, 12345), fix.div(12345, fix.ONE));
}

test "mod is positive, abs of the smallest number is the largest, mid is the median" {
    try std.testing.expectEqual(@as(i32, 0x8000), fix.mod(-0x8000, fix.ONE));
    try std.testing.expectEqual(@as(i32, 0), fix.mod(7, 0));
    try std.testing.expectEqual(fix.MAX, fix.abs(std.math.minInt(i32)));
    try std.testing.expectEqual(@as(i32, 2), fix.mid(1, 3, 2));
    try std.testing.expectEqual(@as(i32, 2), fix.mid(3, 1, 2));
    try std.testing.expectEqual(@as(i32, 2), fix.mid(2, 3, 1));
}

test "literals truncate toward zero like the PICO-8 lexer" {
    try std.testing.expectEqual(@as(i32, 0x41), fix.lit(0.001));
    try std.testing.expectEqual(@as(i32, -0x2666), fix.lit(-0.15));
    try std.testing.expectEqual(@as(i32, 1092), fix.lit(0.5 / 30.0));
}
