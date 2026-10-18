// Native tests for Hippel's 4-voice mixer handler (digi_mix4.zig, digi_irq.zig): `zig test` this
// file. The fixture is Thalion Forever's handler, table, voices and loop words as the file holds
// them. That the handler writes what Musashi writes over the tune is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const mix4 = digi.irq.mix4;

const FIX = @embedFile("testdata/mix4_handler.bin");
const OFF: u32 = 0x54C; // where the file holds the handler
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const AT: u32 = BASE + OFF;

var image: [OFF + FIX.len]u8 = undefined;
var ram: [0x20000]u8 = undefined;
var log: [16][2]u32 = undefined; // (address, byte) of each hardware write
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

fn loaded() mix4.Driver {
    @memset(&ram, 0);
    @memcpy(ram[AT..][0..FIX.len], FIX);
    return .{ .addr = AT };
}

test "the handler is recognised in the image; one changed byte of it is not" {
    @memset(&image, 0);
    @memcpy(image[OFF..], FIX);
    const r = digi.recognise(&image, BASE);
    try std.testing.expectEqual(digi.Status.hippel_mix4, r.status);
    image[OFF + 0x74] ^= 1; // subi.w #$180 -> #$181
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(&image, BASE).status);
}

test "armed, its PC-relative voices, loop words and table resolve where the 68000 finds them" {
    var d = loaded();
    try std.testing.expect(mix4.arm(Bus, &d));
    try std.testing.expectEqual(AT + 0x44C, d.voices);
    try std.testing.expectEqual(AT + 0x634, d.loop[0]);
    try std.testing.expectEqual(AT + 0x65E, d.loop[3]);
    try std.testing.expectEqual(AT + 0xAC, d.table); // after the rte: d8(pc,Xn) from the extension word
}

test "one interrupt: four bytes summed less $180, quantised, three move.l onto $8800, then ISRA bit 5" {
    var d = loaded();
    try std.testing.expect(mix4.arm(Bus, &d));
    for (0..4) |i| { // every voice at $1000 + i, step 0, byte $70: sum $1C0, less $180 = $40
        const v = d.voices + 6 * @as(u32, @intCast(i));
        std.mem.writeInt(u32, ram[v..][0..4], 0x1000 + @as(u32, @intCast(i)), .big);
        std.mem.writeInt(u16, ram[v + 4 ..][0..2], 0, .big);
        std.mem.writeInt(u32, ram[AT + mix4.STEP[i] ..][0..4], 0, .big);
        ram[0x1000 + i] = 0x70;
    }
    log_n = 0;
    mix4.irq(Bus, d);
    const e = FIX[0xAC + 0x40 * 3 ..][0..12];
    var want: [13][2]u32 = undefined;
    for (0..3) |k| for (0..4) |j| {
        want[4 * k + j] = .{ 0xFF8800 + @as(u32, @intCast(j)), e[4 * k + j] };
    };
    want[12] = .{ 0xFFFA0F, 0 }; // bclr #5 of a 0 byte
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
}
