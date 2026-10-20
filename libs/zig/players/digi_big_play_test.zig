// Native tests for the B.I.G. digi PLAY (digi_big_play.zig, digi_big_note.zig, digi_big_map.zig):
// `zig test` this file. The fixture is Ace 2's PLAY code as the file holds it, placed at the
// address it was assembled for ($44D26), so its operands need no relocation. That PLAY writes
// what Musashi writes over whole tunes is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const map = @import("digi_big_map.zig");
const big_play = @import("digi_big_play.zig");

const CODE = @embedFile("testdata/big_play.bin");
const PLAY: u32 = 0x44D26;
const HANDLER: u32 = 0x45466;
const V0: u32 = 0x44C02; // the voices, $4A apart
const FREQ: u32 = 0x44A82; // 96 steps: notes past $5F read the voices behind it, as on the 68000
const SILENCE: u32 = 0x45E2E;
const PTRS = [3]u32{ 0x380, 0x386, 0x38C };

var ram: [0x60000]u8 = undefined;

const Bus = struct {
    pub fn read8(a: u32) u8 {
        return if (a < ram.len) ram[a] else 0;
    }
    pub fn write8(a: u32, v: u8) void {
        if (a < ram.len) ram[a] = v;
    }
    pub fn write16(a: u32, v: u16) void {
        write8(a, @truncate(v >> 8));
        write8(a + 1, @truncate(v));
    }
};

fn be32(a: u32, v: u32) void {
    std.mem.writeInt(u32, ram[a..][0..4], v, .big);
}
fn rd32(a: u32) u32 {
    return std.mem.readInt(u32, ram[a..][0..4], .big);
}

/// PLAY in RAM as Grazey's INIT leaves it: the bra over the anti-rip check, the three nops.
fn loaded() map.At {
    @memset(&ram, 0);
    @memcpy(ram[PLAY..][0..CODE.len], CODE);
    ram[PLAY + 0x152] = 0x60;
    for (0..3) |i| std.mem.writeInt(u16, ram[PLAY + 0x452 + 2 * i ..][0..2], 0x4E71, .big);
    for (0..0x60) |n| be32(FREQ + 4 * @as(u32, @intCast(n)), @as(u32, @intCast(n)) * 0x100 + 7);
    return map.arm(Bus, PLAY, HANDLER).?;
}

test "PLAY is found behind the header's third bra; one changed byte of it is not" {
    var image: [0x2000]u8 = .{0} ** 0x2000;
    const off: u32 = 0x11F8;
    std.mem.writeInt(u16, image[8..10], 0x6000, .big);
    std.mem.writeInt(u16, image[10..12], off - 10, .big);
    @memcpy(image[off..][0..CODE.len], CODE);
    try std.testing.expectEqual(@as(?u32, off), map.playOf(&image));
    image[off + 0x300] ^= 1;
    try std.testing.expectEqual(@as(?u32, null), map.playOf(&image));
}

test "it is armed only once INIT has patched it, and reads its variables and commands" {
    const a = loaded();
    try std.testing.expectEqual(@as(u32, 0x44CF6), a.cnt);
    try std.testing.expectEqual([3]u32{ V0, V0 + 0x4A, V0 + 0x94 }, a.v);
    try std.testing.expectEqual([3]u32{ HANDLER + 0x0C, HANDLER + 0x42, HANDLER + 0x7A }, a.step);
    try std.testing.expectEqual(map.Cmd.track, a.cmd[7]);
    try std.testing.expectEqual(map.Cmd.rest, a.cmd[0]);
    // The song's variables sit between the code ($451E2..$451F3): its init writing them is no change.
    @memset(ram[0x451E2..0x451F4], 0xA5);
    try std.testing.expect(map.arm(Bus, PLAY, HANDLER) != null);
    ram[PLAY + 0x152] = 0x67; // the file's beq: the anti-rip check would run
    try std.testing.expectEqual(@as(?map.At, null), map.arm(Bus, PLAY, HANDLER));
    _ = loaded();
    try std.testing.expectEqual(@as(?map.At, null), map.arm(Bus, PLAY, HANDLER + 2)); // not its handler
}

/// The song on, one row due; voice 0 reads [length $E3, note $30], the others are silent.
fn oneRow() map.At {
    const a = loaded();
    ram[0x451E8] = 1; // on
    ram[0x44CE0] = 1; // a row this frame
    ram[0x44CE1] = 3; // speed
    be32(V0 + 0x02, 0x50000);
    ram[0x50000] = 0xE3;
    ram[0x50001] = 0x30;
    ram[V0 + 0x1B] = 1;
    be32(V0 + 0x10, 0x51000);
    ram[0x51000] = 0x02; // the arpeggio's first step
    be32(V0 + 0x40, 0x380);
    be32(V0 + 0x44, 0x52000); // the sample's start
    for (1..3) |i| ram[a.v[i] + 0x1B] = 2;
    return a;
}

test "a row: its length and note, the sample restarted, the step through the arpeggio" {
    const a = oneRow();
    big_play.play(Bus, &a);
    try std.testing.expectEqual(@as(u8, 1), ram[0x44CF6]);
    try std.testing.expectEqual(@as(u8, 3), ram[0x44CE0]); // reloaded from the speed
    try std.testing.expectEqual(@as(u8, 4), ram[V0 + 0x1B]); // $E3 + $21
    try std.testing.expectEqual(@as(u8, 0x30), ram[V0 + 0x1D]);
    try std.testing.expectEqual(@as(u32, 0x50002), rd32(V0 + 0x02));
    try std.testing.expectEqual(@as(u32, 0x52000), rd32(0x380));
    try std.testing.expectEqual(@as(u32, 0x32 * 0x100 + 7), rd32(HANDLER + 0x0C)); // note $30 + arpeggio 2
    try std.testing.expectEqual(@as(u8, 0x21), ram[V0]); // b5 new note, b0 toggled
    for (1..3) |i| { // $1E clear: silent
        try std.testing.expectEqual(SILENCE, rd32(PTRS[i]));
        try std.testing.expectEqual(@as(u32, 0), rd32(a.step[i]));
        try std.testing.expectEqual(@as(u8, 1), ram[a.v[i] + 0x1B]);
    }
}

test "mutant 12 plays every length a frame short" {
    const a = oneRow();
    big_play.short_note = true;
    defer big_play.short_note = false;
    big_play.play(Bus, &a);
    try std.testing.expectEqual(@as(u8, 3), ram[V0 + 0x1B]);
}

test "the song off: only the frame counter moves, and the steps are cleared" {
    const a = oneRow();
    ram[0x451E8] = 0;
    be32(HANDLER + 0x0C, 0x1234);
    big_play.play(Bus, &a);
    try std.testing.expectEqual(@as(u8, 1), ram[0x44CF6]);
    try std.testing.expectEqual(@as(u8, 1), ram[0x44CE0]);
    try std.testing.expectEqual(@as(u32, 0), rd32(HANDLER + 0x0C));
}

test "command 7: the track's next entry, a transpose on the way, then that pattern" {
    const a = oneRow();
    ram[0x50000] = 0x87;
    be32(V0 + 0x06, 0x53000);
    @memcpy(ram[0x53000..][0..3], &[_]u8{ 0x80, 0x05, 0x02 });
    be32(0x451EC, 0x54000);
    be32(0x54000 + 2 * 4, 0x55000);
    @memcpy(ram[0x55000..][0..2], &[_]u8{ 0xE0, 0x10 });
    big_play.play(Bus, &a);
    try std.testing.expectEqual(@as(u8, 5), ram[V0 + 0x28]);
    try std.testing.expectEqual(@as(u32, 3), rd32(V0 + 0x0A));
    try std.testing.expectEqual(@as(u32, 0x55002), rd32(V0 + 0x02));
    try std.testing.expectEqual(@as(u8, 1), ram[V0 + 0x1B]);
    try std.testing.expectEqual(@as(u8, 0x10), ram[V0 + 0x1D]);
}

test "a command past the table is not guessed: the play is lost" {
    const a = oneRow();
    ram[0x50000] = 0x91; // index 17
    big_play.play(Bus, &a);
    try std.testing.expect(big_play.lost);
    big_play.lost = false;
}
