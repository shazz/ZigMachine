// Native tests for maxYMiser's digidrum routines (digi_mym.zig, digi_irq.zig): `zig test` this
// file. The fixture is crystallized's two routines as play leaves them in RAM. That they write what
// Musashi writes over the tune is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const mym = digi.irq.mym;

const FIX = @embedFile("testdata/mym_routines.bin");
const FOUR: u32 = 0x17E30; // where they were
const EIGHT: u32 = 0x17E54;

var ram: [0x30000]u8 = undefined;
var log: [8][2]u32 = undefined; // (address, byte) of each hardware write
var log_n: usize = 0;

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
};

fn be32(a: u32) u32 {
    return std.mem.readInt(u32, ram[a..][0..4], .big);
}

fn loaded() mym.Driver {
    @memset(&ram, 0);
    @memcpy(ram[FOUR..][0..FIX.len], FIX);
    var d = mym.Driver{ .addr = FOUR };
    _ = mym.arm(Bus, &d);
    return d;
}

test "both routines are recognised in an image; an address that is neither plays on Musashi" {
    var d = loaded();
    try std.testing.expectEqual(digi.Status.mym_drums, digi.recognise(ram[0x10000..0x20000], 0x10000).status);
    try std.testing.expect(!mym.irq(Bus, &d, FOUR + 2));
}

test "the 8-bit routine: register 9, the byte plus its offset through the table, the operand bumped" {
    var d = loaded();
    const p = be32(EIGHT + 0x0C);
    ram[p] = 0x05;
    log_n = 0;
    try std.testing.expect(mym.irq(Bus, &d, EIGHT));
    const want = [_][2]u32{ .{ 0xFF8800, 9 }, .{ 0xFF8802, ram[EIGHT + 0x34 + 0x05 + ram[EIGHT + 0x15]] } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
    try std.testing.expectEqual(p + 1, be32(EIGHT + 0x0C));
}

test "the 4-bit routine at a drum's end: the byte, the end value, and the timer's control cleared" {
    var d = loaded();
    const p = be32(FOUR + 0x08);
    ram[p] = 0x80;
    log_n = 0;
    try std.testing.expect(mym.irq(Bus, &d, FOUR));
    const want = [_][2]u32{ .{ 0xFF8800, 9 }, .{ 0xFF8802, 0x80 }, .{ 0xFF8802, 0x0D }, .{ 0xFFFA1B, 0 } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
    try std.testing.expectEqual(p, be32(FOUR + 0x08)); // not bumped
}
