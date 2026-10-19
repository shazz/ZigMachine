// Native tests for the Swedish New Year Demo's self-modifying 4-voice mixer (digi_sync4.zig,
// digi_irq.zig): `zig test` this file. The fixture is the Sync tune's handler as init relocated it
// in RAM (at $10356), then its volume table. That the handler writes what Musashi writes over the
// tune is fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const sync4 = digi.irq.sync4;

const FIX = @embedFile("testdata/sync4_handler.bin");
const LEN: u32 = 0xF6;
const AT: u32 = 0x10356; // where the tune's init left it
const TABLE: u32 = 0x15302; // lea $4ED8(pc) at $D2
const P = [4]u32{ AT + 0x10, AT + 0x48, AT + 0x7E, AT + 0xB6 }; // each voice's sample operand
const E = [4]u32{ AT + 0x16, AT + 0x4E, AT + 0x84, AT + 0xBC }; // its end
const Q = [3]u32{ AT + 0x28, AT + 0x60, AT + 0x96 }; // its pitch stream
const L = [3]u32{ AT + 0x32, AT + 0x6A, AT + 0xA0 }; // the stream's loop
const FLAGS: u32 = 0x110B7; // a4 + $A4B: the four flag bytes

var ram: [0x20000]u8 = undefined;
var log: [8][2]u32 = undefined; // (address, byte) of each PSG write
var log_n: usize = 0;

const Bus = struct {
    pub var d7_now: u32 = 0;
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
    pub fn d7() u32 {
        return d7_now;
    }
};

fn rd(a: u32) u32 {
    return std.mem.readInt(u32, ram[a..][0..4], .big);
}

fn wr(a: u32, v: u32) void {
    std.mem.writeInt(u32, ram[a..][0..4], v, .big);
}

/// Armed, every voice off, ends far away.
fn armed() !sync4.Driver {
    @memset(&ram, 0);
    @memcpy(ram[AT..][0..LEN], FIX[0..LEN]);
    @memcpy(ram[TABLE..][0 .. FIX.len - LEN], FIX[LEN..]);
    for (E) |e| wr(e, 0x7FFF_0000);
    var d: sync4.Driver = .{ .addr = AT };
    try std.testing.expect(sync4.arm(Bus, &d));
    return d;
}

fn expectPsg(sum: u8) !void {
    const e = FIX[LEN + @as(usize, sum) * 8 ..][0..6]; // low word, then high, then the third
    const want = [_][2]u32{
        .{ 0xFF8800, e[2] }, .{ 0xFF8802, e[3] }, .{ 0xFF8800, e[0] }, .{ 0xFF8802, e[1] },
        .{ 0xFF8800, e[4] }, .{ 0xFF8802, e[5] },
    };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
}

test "the relocated handler is recognised; one changed opcode byte is not" {
    var image: [LEN]u8 = FIX[0..LEN].*;
    try std.testing.expect(sync4.matchAt(&image, 0));
    image[0xCE] ^= 1; // andi.w #$ff -> #$fe
    try std.testing.expect(!sync4.matchAt(&image, 0));
}

test "armed, its d16(a4) and absolute flags and its table resolve where the 68000 finds them" {
    const d = try armed();
    for (0..4) |i| try std.testing.expectEqual(FLAGS + @as(u32, @intCast(i)), d.v[i].flag);
    try std.testing.expectEqual(P[0], d.v[0].cmp);
    try std.testing.expectEqual(Q[0], d.v[0].step);
    try std.testing.expectEqual(P[3], d.v[3].step); // voice 3 steps its own pointer
    try std.testing.expectEqual(TABLE, d.table);
}

test "four voices: their bytes summed through the table; pitch streams of 1 step the pointers" {
    const d = try armed();
    const bytes = [4]u8{ 0x10, 0x21, 0x02, 0x40 };
    for (0..4) |i| {
        ram[FLAGS + i] = 1;
        wr(P[i], 0x2000 + 0x100 * @as(u32, @intCast(i)));
        ram[0x2000 + 0x100 * i] = bytes[i];
    }
    for (Q, 0..) |q, i| {
        wr(q, 0x3000 + 0x10 * @as(u32, @intCast(i)));
        ram[0x3001 + 0x10 * i] = 1; // the byte the addq moves the stream onto
    }
    log_n = 0;
    sync4.irq(Bus, d);
    try expectPsg(0x73);
    for (0..4) |i| try std.testing.expectEqual(0x2001 + 0x100 * @as(u32, @intCast(i)), rd(P[i]));
    try std.testing.expectEqual(@as(u32, 0x3001), rd(Q[0]));
}

test "at its end a voice's flag is cleared; a negative stream byte rewinds the stream to L" {
    const d = try armed();
    ram[FLAGS] = 1;
    wr(P[0], 0x2000);
    wr(E[0], 0x2000); // not below the end: the flag goes
    wr(Q[0], 0x3000);
    ram[0x3001] = 0x80;
    wr(L[0], 0x3456);
    sync4.irq(Bus, d);
    try std.testing.expectEqual(@as(u8, 0), ram[FLAGS]);
    try std.testing.expectEqual(@as(u32, 0x3456), rd(Q[0]));
    try std.testing.expectEqual(@as(u32, 0x2000), rd(P[0])); // a rewind does not step the sample
}

test "with voice 0 off the sum starts from the interrupted code's d7; voice 3 ends by the sign" {
    const d = try armed();
    Bus.d7_now = 0x1234_5633;
    ram[FLAGS + 3] = 1;
    wr(P[3], 0x2000);
    ram[0x2000] = 0x11;
    wr(E[3], 0x2002); // 0x2000 - 0x2002 is negative: it plays on
    log_n = 0;
    sync4.irq(Bus, d);
    try expectPsg(0x44);
    try std.testing.expectEqual(@as(u8, 1), ram[FLAGS + 3]);
    sync4.irq(Bus, d);
    try std.testing.expectEqual(@as(u8, 1), ram[FLAGS + 3]); // $2001 - $2002 still negative
    sync4.irq(Bus, d);
    try std.testing.expectEqual(@as(u8, 0), ram[FLAGS + 3]); // $2002 - $2002 is 0: not minus
}
