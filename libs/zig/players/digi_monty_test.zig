// Native tests for Monty's native replay (digi_monty*.zig): `zig test` this file.
// Recognition, the first INIT's relocation, and the Timer D handler on a
// recording bus. That the whole replay writes what Musashi writes, frame for
// frame over the whole song, is fpga/tests/test_sndh_native.py's.
const std = @import("std");
const digi = @import("digi.zig");
const at = digi.monty.at;

const FILE = @embedFile("testdata/monty.sndh");
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE

var ram: [0x40000]u8 = undefined;
var psg_latch: u8 = 0;
var psg: [16]u8 = undefined;
var log: [64][2]u8 = undefined;
var log_n: usize = 0;
var timer: [4]u32 = undefined; // what Xbtimer was asked, for timer D

const Bus = struct {
    pub fn read8(a: u32) u8 {
        const x = a & 0xFFFFFF;
        if (x == 0xFF8800) return psg[psg_latch];
        return if (x < ram.len) ram[x] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        const x = a & 0xFFFFFF;
        if (x == 0xFF8800) {
            psg_latch = v & 15;
        } else if (x == 0xFF8802) {
            psg[psg_latch] = v;
            if (log_n < log.len) log[log_n] = .{ psg_latch, v };
            log_n += 1;
        } else if (x < ram.len) ram[x] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8));
        if (a & 0xFFFFFF < 0xFF8800) write8(a + 1, @truncate(v));
    }
    pub fn xbtimer(t: u16, ctrl: u8, data: u8, vector: u32) void {
        timer = .{ t, ctrl, data, vector };
    }
};

fn long(a: u32) u32 {
    return std.mem.readInt(u32, ram[a..][0..4], .big);
}

fn loaded() digi.monty.Driver {
    @memset(&ram, 0);
    @memcpy(ram[BASE..][0..FILE.len], FILE);
    psg = [_]u8{0} ** 16;
    log_n = 0;
    return digi.recognise(ram[BASE..][0..FILE.len], BASE).driver.?.monty;
}

test "Monty is recognised whole; one byte of its code changed is not, and Beat Dis's handler is not looked for" {
    var img: [FILE.len]u8 = FILE.*;
    try std.testing.expectEqual(digi.Status.monty, digi.recognise(&img, BASE).status);
    img[at.HANDLER + 0x52] ^= 1; // the handler's lsr.w #1 -> another shift
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(&img, BASE).status);
    img = FILE.*;
    img[at.VOICES + 0x2F] ^= 0xFF; // a voice's data: the song, not the driver
    try std.testing.expectEqual(digi.Status.monty, digi.recognise(&img, BASE).status);
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(img[0 .. at.MUSIC + 0x400], BASE).status);
}

test "the first INIT relocates the driver, its drums and its song, starts Timer D, and writes the YM's 13 registers" {
    const d = loaded();
    digi.monty.call(Bus, d, 0);
    try std.testing.expectEqual(BASE + at.DRV, long(BASE + at.OLD_BASE));
    try std.testing.expectEqual(BASE + at.SAMPLES, long(BASE + at.DRUM_START + 9 * 4));
    try std.testing.expectEqual(BASE + at.MUSIC + 0x200, long(BASE + at.PATTERNS));
    try std.testing.expectEqual(BASE + at.MUSIC + 0x20, long(BASE + at.ENVS)); // the song's $60010
    try std.testing.expectEqual([4]u32{ 3, 1, 0x3A, BASE + at.HANDLER }, timer);
    try std.testing.expectEqual(@as(usize, 13), log_n);
    try std.testing.expectEqual([2]u8{ 7, 0xF8 }, log[5]);
    try std.testing.expectEqual(@as(u8, 1), ram[BASE + at.RUNNING]);
    const again = ram;
    digi.monty.call(Bus, d, 0); // a second INIT (zg.sndhCall) must not relocate twice
    try std.testing.expectEqualSlices(u8, again[BASE..][0..at.SAMPLES], ram[BASE..][0..at.SAMPLES]);
}

test "Timer D writes nothing idle; with a drum on, one sample a tick onto volume C as (s >> 1) + 8, then idles at its end" {
    const d = loaded();
    digi.monty.call(Bus, d, 0);
    log_n = 0;
    digi.monty.irq(Bus, d);
    try std.testing.expectEqual(@as(usize, 0), log_n);
    const s = BASE + at.SAMPLES + 0x100;
    ram[s] = 13;
    ram[s + 1] = 2;
    std.mem.writeInt(u32, ram[BASE + at.DRUM_CUR ..][0..4], s, .big);
    std.mem.writeInt(u32, ram[BASE + at.DRUM_END ..][0..4], s + 2, .big);
    std.mem.writeInt(u16, ram[BASE + at.DRUM_IDLE ..][0..2], 0, .big);
    for (0..3) |_| digi.monty.irq(Bus, d);
    try std.testing.expectEqualSlices([2]u8, &.{ .{ 10, 14 }, .{ 10, 9 } }, log[0..log_n]);
    try std.testing.expectEqual(@as(u16, 0xFFFF), std.mem.readInt(u16, ram[BASE + at.DRUM_IDLE ..][0..2], .big));
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, ram[BASE + at.BUSY ..][0..2], .big));
}

test "PLAY keeps volume C off the YM loop once the drums own channel C, and zeroes C's period" {
    const d = loaded();
    digi.monty.call(Bus, d, 0);
    digi.monty.call(Bus, d, 8); // the first rows: their $92 sets the flag, so set it after them
    try std.testing.expect(ram[BASE + at.TICK] > 1); // and no row on the next PLAY
    ram[BASE + at.DRUMS_ON_C] = 1;
    log_n = 0;
    psg_latch = 0;
    digi.monty.call(Bus, d, 8);
    try std.testing.expectEqual(@as(usize, 12), log_n);
    for (log[0..log_n]) |w| try std.testing.expect(w[0] != 10);
    try std.testing.expectEqual(@as(u8, 0), psg[4]);
    try std.testing.expectEqual(@as(u8, 0), psg[5]);
}
