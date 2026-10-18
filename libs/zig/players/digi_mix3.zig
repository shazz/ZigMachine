// --------------------------------------------------------------------------
// A 3-voice digi mixer on Timer C, natively: snyd_90's part-6 tune
// (snyd90_f6.sndh). The interrupt, at 7,402 Hz (123 a 60 Hz frame), steps
// three voices, adds their bytes (the first doubled) and stores three table
// longs onto the PSG's $8848 mirror. Only the handler is native (digi_irq.zig).
//
// Offsets from the handler; every address in it is PC-relative:
//   $08  lea voice(pc),a6 / addi.l #step,2(a6) / movea.l (a6),a6 / move.b
//        (a6),d7 / add.w d7,d7     voice 1: pointer, fraction; step patched by play
//   $1A  the same for voice 2, its byte added; $2C voice 3, added
//   $3E  andi.w #$3FC, x3: movem.l table(pc,d7.w),d6-d7/a6
//   $4E  movem.l d6-d7/a6,$8848.w: select, value, select, value... on the
//        PSG's mirrors, three longs
// The handler saves d6 and d7 but not a6: it leaves the table's third long
// in a6, and the native handler puts it there too (Bus.setA6).
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack. Voices never end here: play loops them.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x5A; // to the rte, inclusive
const VOICE_LEA = [3]u32{ 0x08, 0x1A, 0x2C };
pub const STEP = [3]u32{ 0x0E, 0x20, 0x32 }; // each voice's addi.l immediate
const TABLE_MOVEM: u32 = 0x48; // movem.l d8(pc,d7.w): its extension word at $4C
const HOLES = [_][2]u32{ .{ 0x0E, 0x12 }, .{ 0x20, 0x24 }, .{ 0x32, 0x36 } };
const SIGNATURE: u64 = 0x7F821E47900723E7; // digi.maskedHash of [0, LEN), the steps zeroed
const FIRST: u32 = 0x2F072F06; // move.l d7,-(a7); move.l d6,-(a7): the quick reject
const PSG_MIRROR: u32 = 0xFF8848; // movem.l ...,$8848.w on a 24-bit bus

pub const Driver = struct {
    addr: u32,
    voice: [3]u32 = undefined, // each voice's pointer (its fraction follows)
    table: u32 = 0,
};

pub fn matchAt(image: []const u8, off: usize) bool {
    if (off + LEN > image.len or digi.be32(image, off) != FIRST) return false;
    return digi.maskedHash(image[off..][0..LEN], &HOLES) == SIGNATURE;
}

pub fn match(image: []const u8, base: u32) ?Driver {
    var off: usize = 0;
    while (off + LEN <= image.len) : (off += 2) {
        if (matchAt(image, off)) return .{ .addr = base + @as(u32, @intCast(off)) };
    }
    return null;
}

/// The handler in RAM, checked again, and its PC-relative addresses resolved.
pub fn arm(comptime Bus: type, d: *Driver) bool {
    var code: [LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = Bus.read8(d.addr + @as(u32, @intCast(i)));
    if (!matchAt(&code, 0)) return false;
    for (&d.voice, VOICE_LEA) |*v, at| v.* = digi.pcRel(d.addr + at, digi.be16(&code, at + 2));
    const ext = digi.be16(&code, TABLE_MOVEM + 4); // d8(pc,Xn) counts from the extension word
    d.table = d.addr + TABLE_MOVEM + 4 +% @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(ext)))))));
    return true;
}

fn voice(comptime Bus: type, d: Driver, i: usize) u16 {
    const m = digi.Access(Bus);
    const v = d.voice[i];
    m.wr32(v + 2, m.rd32(v + 2) +% digi.irq.step(Bus, d.addr + STEP[i], i));
    return m.rd8(m.rd32(v));
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var sum: u16 = voice(Bus, d, 0) * 2;
    sum +%= voice(Bus, d, 1);
    sum +%= voice(Bus, d, 2);
    const e = d.table +% @as(u32, sum & 0x3FC) * 3;
    const regs = [3]u32{ m.rd32(e), m.rd32(e + 4), m.rd32(e + 8) };
    for (regs, 0..) |r, k| m.wr32(PSG_MIRROR + 4 * @as(u32, @intCast(k)), r);
    Bus.setA6(regs[2]);
}
