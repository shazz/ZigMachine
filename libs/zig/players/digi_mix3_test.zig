// Native tests for two handler-only drivers (digi_irq.zig): snyd_90's Timer C 3-voice mixer
// (digi_mix3.zig) and TCB's three volume streams (digi_tcb3.zig). `zig test` this file. That
// they write what Musashi writes over the tunes is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const mix3 = digi.irq.mix3;
const tcb3 = digi.irq.tcb3;

const MIX3 = @embedFile("testdata/mix3_handler.bin"); // from 0x18 before the handler
const TCB3 = @embedFile("testdata/tcb3_handler.bin");
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const AT: u32 = 0x12000; // where the handler sits in these tests

var ram: [0x20000]u8 = undefined;
var log: [16][2]u32 = undefined; // (address, byte) of each hardware write
var log_n: usize = 0;
var a6: u32 = 0;

const Bus = struct {
    pub fn read8(a: u32) u8 {
        return if (a < ram.len) ram[a] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        if (a >= 0xFF0000) {
            if (log_n < log.len) log[log_n] = .{ a, v };
            log_n += 1;
        } else if (a < ram.len) ram[a] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8));
        write8(a + 1, @truncate(v));
    }
    pub fn setA6(v: u32) void {
        a6 = v;
    }
};

fn be32(a: u32, v: u32) void {
    std.mem.writeInt(u32, ram[a..][0..4], v, .big);
}

test "both handlers are recognised in an image, and a changed byte is not" {
    var img: [0x3000]u8 = .{0} ** 0x3000;
    @memcpy(img[0x100..][0..MIX3.len], MIX3);
    try std.testing.expectEqual(digi.Status.mix3_timer_c, digi.recognise(&img, BASE).status);
    img[0x100 + 0x18 + 0x3E + 2] ^= 1; // andi.w #$3FC -> #$3FD
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(&img, BASE).status);
    @memset(&img, 0);
    @memcpy(img[0x100..][0..TCB3.len], TCB3);
    try std.testing.expectEqual(digi.Status.tcb_streams, digi.recognise(&img, BASE).status);
}

test "mix3: three steps, the first byte doubled, x3 into the table, three longs onto $8848, a6 left" {
    @memset(&ram, 0);
    @memcpy(ram[AT - 0x18 ..][0..MIX3.len], MIX3);
    var d = mix3.Driver{ .addr = AT };
    try std.testing.expect(mix3.arm(Bus, &d));
    try std.testing.expectEqual(AT - 0x18, d.voice[0]);
    try std.testing.expectEqual(AT + 0x62, d.table); // d8(pc,Xn) from the extension word
    for (d.voice, [_]u32{ 0x1000, 0x1100, 0x1200 }, mix3.STEP) |v, p, s| {
        be32(v, p);
        be32(AT + s, 0);
    }
    ram[0x1000] = 0x40; // 0x80 + 0x10 + 0x04 = 0x94, & 0x3FC = 0x94
    ram[0x1100] = 0x10;
    ram[0x1200] = 0x04;
    log_n = 0;
    mix3.irq(Bus, d);
    const e = MIX3[0x18 + 0x62 + 0x94 * 3 ..][0..12];
    for (0..12) |k| try std.testing.expectEqual([2]u32{ 0xFF8848 + @as(u32, @intCast(k)), e[k] }, log[k]);
    try std.testing.expectEqual(std.mem.readInt(u32, e[8..12], .big), a6);
}

test "tcb3: one byte of each stream onto 8, 9 and 10, the pointers stored one on" {
    @memset(&ram, 0);
    @memcpy(ram[AT..][0..TCB3.len], TCB3);
    for ([_]u32{ 0x08, 0x2E }) |at| be32(AT + at, 0x3000); // as init relocates it
    var d = tcb3.Driver{ .addr = AT };
    try std.testing.expect(tcb3.arm(Bus, &d));
    for (0..3) |i| {
        be32(0x3000 + 4 * @as(u32, @intCast(i)), 0x4000 + 0x10 * @as(u32, @intCast(i)));
        ram[0x4000 + 0x10 * i] = @intCast(0xA0 + i);
    }
    log_n = 0;
    tcb3.irq(Bus, d);
    const want = [_][2]u32{ .{ 0xFF8800, 8 }, .{ 0xFF8802, 0xA0 }, .{ 0xFF8800, 9 }, .{ 0xFF8802, 0xA1 }, .{ 0xFF8800, 10 }, .{ 0xFF8802, 0xA2 } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
    try std.testing.expectEqual(@as(u32, 0x4021), std.mem.readInt(u32, ram[0x3008..][0..4], .big));
}
