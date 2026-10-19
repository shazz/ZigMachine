// Native tests for Mad Max's 3-voice mixer handler (digi_big.zig, digi_irq.zig): `zig test` this
// file. The fixture is Ace 2's handler and volume table as the file holds them. That the handler
// writes what Musashi writes over whole tunes is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const big = digi.irq.big;

const HANDLER = @embedFile("testdata/big_handler.bin");
const OFF: u32 = 0x1938; // where Ace 2's file holds it
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const AT: u32 = BASE + OFF;

var image: [OFF + HANDLER.len + 16]u8 = undefined;
var ram: [0x40000]u8 = undefined;
var log: [16][2]u32 = undefined; // (address, byte) of each PSG write
var log_n: usize = 0;

fn fresh() []u8 {
    @memset(&image, 0);
    @memcpy(image[OFF..][0..HANDLER.len], HANDLER);
    return &image;
}

const Bus = struct {
    pub fn read8(a: u32) u8 {
        return if (a < ram.len) ram[a] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        if (a >= 0xFF8800 and a < 0xFF8900) {
            if (log_n < log.len) log[log_n] = .{ a, v };
            log_n += 1;
        } else if (a < ram.len) ram[a] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8));
        write8(a + 1, @truncate(v));
    }
};

fn be32(a: u32, v: u32) void {
    std.mem.writeInt(u32, ram[a..][0..4], v, .big);
}

/// The handler in RAM as init leaves it: relocated to F/L at $3000.., its tail an rte.
fn loaded() big.Driver {
    @memset(&ram, 0);
    @memcpy(ram[AT..][0..HANDLER.len], HANDLER);
    std.mem.writeInt(u16, ram[AT + 0xE2 ..][0..2], 0x4E73, .big);
    for ([_][3]u32{ .{ 0x1C, 0x2C, 0x36 }, .{ 0x52, 0x62, 0x6C }, .{ 0x98, 0xA8, 0xB2 } }, 0..) |s, i| {
        const f: u32 = 0x3000 + 0x10 * @as(u32, @intCast(i));
        be32(AT + s[0], f);
        be32(AT + s[1], f);
        be32(AT + s[2], f + 2);
    }
    return .{ .addr = AT };
}

test "the handler is recognised in the image; one changed byte of it is not" {
    const r = digi.recognise(fresh(), BASE);
    try std.testing.expectEqual(digi.Status.big_digital, r.status);
    try std.testing.expectEqual(AT, digi.irq.handlerAddr(r.driver.?.irq));
    const img = fresh();
    img[OFF + 0xC6] ^= 1; // asl.w #3 -> another shift
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(img, BASE).status);
}

test "it is armed only once init has written the rte over the bclr, and reads its addresses then" {
    var d = loaded();
    try std.testing.expect(big.arm(Bus, &d));
    try std.testing.expectEqual(@as(u32, 0x380), d.v[0].ptr);
    try std.testing.expectEqual(@as(u32, 0x38C), d.v[2].ptr);
    try std.testing.expectEqual(@as(u32, 0x3012), d.v[1].loop);
    std.mem.writeInt(u16, ram[AT + 0xE2 ..][0..2], 0x08B9, .big); // the file's bclr
    try std.testing.expect(!big.arm(Bus, &d));
}

test "one interrupt: three steps, the sum through the table, movep.l then movep.w" {
    var d = loaded();
    try std.testing.expect(big.arm(Bus, &d));
    for ([_]u32{ 0x0C, 0x42, 0x7A }, [_]u32{ 0x10000, 0x8000, 0 }) |imm, step| be32(AT + imm, step);
    for ([_]u32{ 0x380, 0x386, 0x38C }, [_]u32{ 0x2000, 0x2100, 0x2200 }) |p, a| be32(p, a);
    ram[0x2001] = 0x10; // voice 1 steps one byte on
    ram[0x2100] = 0x20;
    ram[0x2200] = 0x05;
    log_n = 0;
    big.irq(Bus, d);
    try std.testing.expectEqual(@as(u32, 0x2001), std.mem.readInt(u32, ram[0x380..][0..4], .big));
    const e = HANDLER[0xEC + 0x35 * 8 ..][0..6]; // 0x10 + 0x20 + 0x05
    const want = [_][2]u32{ .{ 0xFF8800, e[0] }, .{ 0xFF8802, e[1] }, .{ 0xFF8804, e[2] }, .{ 0xFF8806, e[3] }, .{ 0xFF8800, e[4] }, .{ 0xFF8802, e[5] } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
}

test "a voice-1 byte with bit 7 set ends its sample: back by the loop's length, then its byte" {
    var d = loaded();
    try std.testing.expect(big.arm(Bus, &d));
    be32(0x380, 0x2000);
    ram[0x2000] = 0x80;
    be32(0x3002, 0x100); // L1
    ram[0x1F00] = 0x07;
    big.irq(Bus, d);
    try std.testing.expectEqual(@as(u32, 0x1F00), std.mem.readInt(u32, ram[0x380..][0..4], .big));
}
