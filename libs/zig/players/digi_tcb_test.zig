// Native tests for the Swedish New Year Demo's one-byte digi handler (digi_tcb.zig, digi_irq.zig):
// `zig test` this file. The fixture is the TCB 1 tune's handler, its pointer block and its volume
// table as the file holds them. That the handler writes what Musashi writes over the tune is
// fpga/tests/test_sndh_irq.py's.
const std = @import("std");
const digi = @import("digi.zig");
const tcb = digi.irq.tcb;

const FIX = @embedFile("testdata/tcb_handler.bin");
const OFF: u32 = 0x15E; // where the file holds the handler
const BASE: u32 = 0x10002; // sndh_player.zig IMAGE_BASE
const AT: u32 = BASE + OFF;
const PTR: u32 = AT + 0x34; // lea $192(pc): the pointer block after the rte
const TABLE: u32 = AT + 0x4C; // lea $1AA(pc)

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

fn loaded() tcb.Driver {
    @memset(&ram, 0);
    @memcpy(ram[AT..][0..FIX.len], FIX);
    return .{ .addr = AT };
}

test "the handler is recognised in the image; one changed byte of it is not" {
    @memset(&image, 0);
    @memcpy(image[OFF..], FIX);
    const r = digi.recognise(&image, BASE);
    try std.testing.expectEqual(digi.Status.tcb_digi, r.status);
    try std.testing.expectEqual(AT, digi.irq.handlerAddr(r.driver.?.irq));
    image[OFF + 0x10] ^= 1; // lsl.w #3 -> another shift
    try std.testing.expectEqual(digi.Status.musashi, digi.recognise(&image, BASE).status);
}

test "armed, its PC-relative pointer and table resolve where the 68000 finds them; changed code is refused" {
    var d = loaded();
    try std.testing.expect(tcb.arm(Bus, &d));
    try std.testing.expectEqual(PTR, d.ptr);
    try std.testing.expectEqual(TABLE, d.table);
    ram[AT + 0x20] ^= 1; // movep.l -> something else: plays on Musashi
    try std.testing.expect(!tcb.arm(Bus, &d));
}

test "one interrupt: the byte, the pointer on by one, movep.l + movep.w onto $8800, then ISRA bit 5" {
    var d = loaded();
    try std.testing.expect(tcb.arm(Bus, &d));
    std.mem.writeInt(u32, ram[PTR..][0..4], 0x1000, .big);
    ram[0x1000] = 0x42;
    log_n = 0;
    tcb.irq(Bus, d);
    try std.testing.expectEqual(@as(u32, 0x1001), std.mem.readInt(u32, ram[PTR..][0..4], .big));
    const e = FIX[0x4C + 0x42 * 8 ..][0..6];
    const want = [_][2]u32{
        .{ 0xFF8800, e[0] }, .{ 0xFF8802, e[1] }, .{ 0xFF8804, e[2] }, .{ 0xFF8806, e[3] },
        .{ 0xFF8800, e[4] }, .{ 0xFF8802, e[5] }, .{ 0xFFFA0F, 0 }, // bclr #5 of a 0 byte
    };
    try std.testing.expectEqualSlices([2]u32, &want, log[0..log_n]);
}

test "the pointer is read from RAM every interrupt: a rewind by play is followed" {
    var d = loaded();
    try std.testing.expect(tcb.arm(Bus, &d));
    std.mem.writeInt(u32, ram[PTR..][0..4], 0x1000, .big);
    tcb.irq(Bus, d);
    std.mem.writeInt(u32, ram[PTR..][0..4], 0x0800, .big); // play: back by the segment's length
    tcb.irq(Bus, d);
    try std.testing.expectEqual(@as(u32, 0x0801), std.mem.readInt(u32, ram[PTR..][0..4], .big));
}
