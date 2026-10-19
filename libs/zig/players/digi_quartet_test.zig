// Native tests for SingSong's 4-voice handler (digi_quartet.zig, digi_irq.zig): `zig test` this
// file. The fixture is the SNDH glue's wrapper, then SingSong's handler, its table and its wrap
// routine as dune_gen4_quartet.sndh holds them. That the handler writes what Musashi writes over
// whole tunes, with the 68000's registers in between, is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const quartet = digi.irq.quartet;

const FIXTURE = @embedFile("testdata/quartet_handler.bin");
const WRAPPER = FIXTURE[0..0x1C]; // the code, then saved_d0 (ta_orig is set by init)
const SINGSONG = FIXTURE[0x1C..]; // TEXT $DDA..$2ED8: handler, table, wrap
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const W: u32 = BASE + 0x1EA; // where the file holds the wrapper
const OFF: u32 = 0x1128; // ...and SingSong's handler (TEXT at $34E)
// In RAM the tests put SingSong's TEXT at 0: its unrelocated absolute addresses, as the file
// holds them, are then the real ones, so `arm` is read off the instruction stream, not a fixture.
const H: u32 = 0xDDA;
const X: u32 = 0x2E36; // the wrap routine
const SILENCE: u32 = 0x32F4;
const STEP: u32 = 0x3304;
const LOOP: u32 = 0x3324;
const PSG: u32 = 0xFF8800;

var image: [0x4000]u8 = undefined;
var ram: [0x40000]u8 = undefined;
var regs: [16]u32 = undefined; // d0-d7, a0-a7
var log: [16][2]u32 = undefined; // (address, byte) of each PSG write
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
    pub fn getReg(n: u4) u32 {
        return regs[n];
    }
    pub fn setReg(n: u4, v: u32) void {
        regs[n] = v;
    }
};

fn be32(a: u32, v: u32) void {
    std.mem.writeInt(u32, ram[a..][0..4], v, .big);
}

fn rd32(a: u32) u32 {
    return std.mem.readInt(u32, ram[a..][0..4], .big);
}

fn fresh() []u8 {
    @memset(&image, 0);
    @memcpy(image[0x1EA..][0..WRAPPER.len], WRAPPER);
    @memcpy(image[OFF..][0..SINGSONG.len], SINGSONG);
    return &image;
}

/// RAM as the first INIT leaves it: the wrapper's ta_orig set, the voices resting on silence,
/// d4/d5 as the 68000 leaves them.
fn loaded() quartet.Driver {
    @memset(&ram, 0);
    @memcpy(ram[W..][0..WRAPPER.len], WRAPPER);
    @memcpy(ram[H..][0..SINGSONG.len], SINGSONG);
    be32(W + 0x1C, H);
    for (0..4) |i| {
        be32(LOOP + 4 * @as(u32, @intCast(i)), 0x01000000);
        regs[i] = 0xFF000000;
        regs[8 + i] = SILENCE;
    }
    @memset(ram[SILENCE - 0x100 .. SILENCE], 0x80);
    regs[4] = 0;
    regs[5] = 0;
    regs[12] = 0xFFFF8800;
    log_n = 0;
    return .{ .addr = W };
}

test "the wrapper with SingSong's handler is recognised in the image; a changed byte of either is not" {
    const r = digi.recognise(fresh(), BASE);
    try std.testing.expectEqual(digi.Status.quartet_singsong, r.status);
    try std.testing.expectEqual(W, digi.irq.handlerAddr(r.driver.?.irq));
    var img = fresh();
    img[0x1EA + 0x12] ^= 1; // move.l d0,(a5) -> another register
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(img, BASE).status);
    img = fresh();
    img[OFF + 0x28] ^= 0x02; // lsl.w #3 -> #2
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(img, BASE).status);
}

test "armed, it follows ta_orig to the handler and reads the table, steps, loops and silence" {
    var d = loaded();
    try std.testing.expect(quartet.arm(Bus, &d));
    try std.testing.expectEqual(H, d.handler);
    try std.testing.expectEqual(X, digi.pcRel(H + 0x56, std.mem.readInt(u16, ram[H + 0x58 ..][0..2], .big)));
    try std.testing.expectEqual(H + 0x5C, d.table);
    try std.testing.expectEqual(STEP, d.step[0]);
    try std.testing.expectEqual(STEP + 12, d.step[3]);
    try std.testing.expectEqual(LOOP + 8, d.loop[2]);
    try std.testing.expectEqual(SILENCE, d.silence);
    be32(W + 0x1C, 0); // before init: no handler yet
    try std.testing.expect(!quartet.arm(Bus, &d));
}

test "one interrupt: four signed-index bytes summed, movep.l then movep.w, registers stepped, d0 saved" {
    var d = loaded();
    try std.testing.expect(quartet.arm(Bus, &d));
    regs[0] = 0x00020000; // voice 0 at +2 of a sample at $20000, voice 1 resting at -256 (silence)
    regs[8] = 0x20000;
    ram[0x20002] = 0x10;
    be32(STEP, 0x00018000);
    be32(STEP + 4, 0x00000001);
    quartet.irq(Bus, d);
    const sum: u32 = 0x10 + 3 * 0x80;
    const e = SINGSONG[0x5C + sum * 8 ..][0..6];
    const want = [_][2]u32{ .{ PSG, e[0] }, .{ PSG + 2, e[1] }, .{ PSG + 4, e[2] }, .{ PSG + 6, e[3] }, .{ PSG, e[4] }, .{ PSG + 2, e[5] } };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
    try std.testing.expectEqual(@as(u32, 0x00038000), regs[0]);
    try std.testing.expectEqual(@as(u32, 0xFF000001), regs[1]);
    try std.testing.expectEqual(std.mem.readInt(u32, e[0..4], .big) & 0xFFFF0000 | std.mem.readInt(u16, e[4..6], .big), regs[4]);
    try std.testing.expectEqual(@as(u32, 0), regs[5]);
    try std.testing.expectEqual(@as(u32, 0x00038000), rd32(W + 0x18));
}

test "a carry out of a voice's offset: back by its loop, or to silence when the loop long has a low word" {
    var d = loaded();
    try std.testing.expect(quartet.arm(Bus, &d));
    regs[2] = 0xFFFF8000; // voice 2 loops: a length of 3 bytes in the high word
    regs[10] = 0x20000;
    be32(LOOP + 8, 0x00030000);
    be32(STEP + 8, 0x00010000);
    regs[3] = 0xFFFF0000; // voice 3 ends: no loop
    regs[11] = 0x20000;
    be32(LOOP + 12, 0xFFFFFFFF);
    be32(STEP + 12, 0x00010000);
    quartet.irq(Bus, d);
    try std.testing.expectEqual(@as(u32, 0x00008000) -% 0x00030000, regs[2]);
    try std.testing.expectEqual(@as(u32, 0x20000), regs[10]);
    try std.testing.expectEqual(@as(u32, 0x00030000), rd32(LOOP + 8));
    try std.testing.expectEqual(SILENCE, regs[11]);
    try std.testing.expectEqual(@as(u32, 0x01000000), rd32(LOOP + 12));
    try std.testing.expectEqual(@as(u32, 0) -% 0x01000000, regs[3]);
    try std.testing.expectEqual(@as(u32, 0), regs[5]);
}

test "mutant 7 reads a resting voice above its silence, not below: the sum changes" {
    var d = loaded();
    try std.testing.expect(quartet.arm(Bus, &d));
    quartet.irq(Bus, d);
    const signed = log[1][1];
    digi.irq.unsigned_index = true;
    defer digi.irq.unsigned_index = false;
    log_n = 0;
    quartet.irq(Bus, d);
    try std.testing.expect(log[1][1] != signed);
}
