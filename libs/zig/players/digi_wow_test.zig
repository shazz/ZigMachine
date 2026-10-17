// Native tests for Wow Scroller's native replay (digi_wow.zig): `zig test` this file.
// The fixture is wow_scroller.sndh's first 0xC32 bytes (header, code, table, rows);
// the samples are zeroes here. That the replay writes what Musashi writes, frame
// for frame over the whole tune, is fpga/tests/test_sndh_wow.py's.
const std = @import("std");
const digi = @import("digi.zig");
const wow = digi.wow;

const HEAD = @embedFile("testdata/wow_head.bin");
const FILE_LEN = 60_208; // the real file's length: its last row ends 0x2B8 before it
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE

var image: [FILE_LEN]u8 = undefined;
var ram: [FILE_LEN + 0x20000]u8 = undefined;
var log: [64][2]u32 = undefined; // (address, byte) of each PSG write
var log_n: usize = 0;

fn fresh() []u8 {
    @memset(&image, 0);
    @memcpy(image[0..HEAD.len], HEAD);
    return &image;
}

const Bus = struct {
    pub fn read8(a: u32) u8 {
        const x = a & 0xFFFFFF;
        return if (x < ram.len) ram[x] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        const x = a & 0xFFFFFF;
        if (x >= 0xFF8800 and x < 0xFF8900) {
            if (log_n < log.len) log[log_n] = .{ x, v };
            log_n += 1;
        } else if (x < ram.len) ram[x] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8));
        if (a & 0xFFFFFF < 0xFF8800) write8(a + 1, @truncate(v));
    }
};

test "Wow Scroller is recognised; a changed byte of its code is not; rows past the image are a near miss" {
    try std.testing.expectEqual(digi.Status.wow, digi.recognise(fresh(), BASE).status);
    const img = fresh();
    img[wow.HANDLER + 0x10] ^= 1; // the handler's lsl.l #3 -> another shift
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(img, BASE).status);
    try std.testing.expectEqual(digi.Status.near_miss_data, digi.recognise(fresh()[0 .. FILE_LEN - 0x300], BASE).status);
}

test "an interrupt is one byte through the table: movep.l to $8800-$8806, then movep.w for register 10" {
    const d = digi.recognise(fresh(), BASE).driver.?.wow;
    @memset(&ram, 0);
    @memcpy(ram[BASE..][0..FILE_LEN], &image);
    digi.wow.call(Bus, d, 0); // INIT: the playlist, entry 0
    const pos = std.mem.readInt(u32, ram[BASE + wow.CUR ..][0..4], .big);
    try std.testing.expectEqual(BASE + wow.DATA, pos);
    try std.testing.expectEqual(BASE + wow.HANDLER, std.mem.readInt(u32, ram[0x134..][0..4], .big));
    ram[pos] = 64;
    log_n = 0;
    digi.wow.irq(Bus, d);
    const e = HEAD[wow.TABLE + 64 * 8 ..][0..6];
    const want = [_][2]u32{ .{ 0xFF8800, e[0] }, .{ 0xFF8802, e[1] }, .{ 0xFF8804, e[2] }, .{ 0xFF8806, e[3] }, .{ 0xFF8800, e[4] }, .{ 0xFF8802, e[5] } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
    try std.testing.expectEqual(pos + 1, std.mem.readInt(u32, ram[BASE + wow.CUR ..][0..4], .big));
}

test "its table is Beat Dis's, indexed by the raw byte: mode 3's linear() holds for it too" {
    // byte 0 loudest (15/14/13 on 8/9/10 region), 255 silent: unsigned and inverted
    try std.testing.expectEqual(@as(u8, 0), HEAD[wow.TABLE + 255 * 8 + 1] | HEAD[wow.TABLE + 255 * 8 + 3] | HEAD[wow.TABLE + 255 * 8 + 5]);
    try std.testing.expect(HEAD[wow.TABLE + 1] >= 0x0D);
}
