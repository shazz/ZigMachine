// --------------------------------------------------------------------------
// Jochen Hippel's 4-voice digi mixer, natively: "Thalion Forever" (the Union
// Demo's TEX tracker screen, union/thalion_forever.sndh). A Timer A
// interrupt at 2457600 / 4 / 64 = 9600 Hz steps four voices, adds their
// sample bytes and plays the sum through a 3-register volume table: 160
// interrupts a 60 Hz frame. On Musashi it measured 308 % of BARD on the board
// (the OSD, 2026-10-18). Only the handler is native (digi_irq.zig).
//
// Offsets from the handler; every address in it is PC-relative:
//   $08  lea voices(pc),a1      four voices of 6 bytes: pointer, fraction
//   $0C  addi.l #step,2(a1)     the step is patched by play (self-modifying)
//   $14  move.b (a0),d0 / bne   a 0 byte ends the sample: back by the
//   $1A  suba.w loop(pc),a0     voice's loop word, stored, and read again
//   $22  voices 2-4 the same, at $24 / $3E / $58, each added (word) to d0
//   $72  subi.w #$180: below 0 is 0, from $100 up is $FC; andi.w #$FC, x3
//   $8C  movem.l table(pc,d0.w),d0-d2, three move.l onto $8800
//   $A2  bclr #5,$FFFA0F (the MFP's ISRA: a software end of interrupt), rte
// The table follows the rte ($AC): `d8(pc,d0.w)` counts from the movem's
// extension word, after its register mask, as Musashi does.
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0xAC; // to the rte, inclusive
const VOICES_LEA: u32 = 0x08;
pub const STEP = [4]u32{ 0x0E, 0x26, 0x40, 0x5A }; // each voice's addi.l immediate
const LOOP_SUBA = [4]u32{ 0x1A, 0x32, 0x4C, 0x66 }; // each voice's suba.w d16(pc)
const TABLE_MOVEM: u32 = 0x8C; // movem.l d8(pc,d0.w): its extension word at $8E
const HOLES = [_][2]u32{ .{ 0x0E, 0x12 }, .{ 0x26, 0x2A }, .{ 0x40, 0x44 }, .{ 0x5A, 0x5E } };
const SIGNATURE: u64 = 0x4253164B2F11DB73;// digi.maskedHash of [0, LEN), the steps zeroed
const FIRST: u32 = 0x48E7E0C0; // movem.l d0-d2/a0-a1,-(a7): the quick reject
const PSG: u32 = 0xFF8800;
const ISRA: u32 = 0xFFFA0F;

pub const Driver = struct {
    addr: u32,
    voices: u32 = 0, // where the four voices are
    loop: [4]u32 = undefined, // where each voice's loop word is
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
    d.voices = digi.pcRel(d.addr + VOICES_LEA, digi.be16(&code, VOICES_LEA + 2));
    for (&d.loop, LOOP_SUBA) |*l, at| l.* = digi.pcRel(d.addr + at, digi.be16(&code, at + 2));
    // d8(pc,Xn): the base is the extension word's address plus its signed low byte
    const ext = digi.be16(&code, TABLE_MOVEM + 4);
    d.table = d.addr + TABLE_MOVEM + 4 +% @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(ext)))))));
    return true;
}

/// One voice: its step, its byte, and a 0 byte's wrap to the loop.
fn voice(comptime Bus: type, d: Driver, i: usize) u8 {
    const m = digi.Access(Bus);
    const v = d.voices + 6 * @as(u32, @intCast(i));
    m.wr32(v + 2, m.rd32(v + 2) +% digi.irq.step(Bus, d.addr + STEP[i], i));
    var a = m.rd32(v);
    var b = m.rd8(a);
    if (b == 0) {
        a -%= @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(m.rd16(d.loop[i]))))));
        m.wr32(v, a);
        b = m.rd8(a);
    }
    return b;
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var sum: u16 = 0;
    for (0..4) |i| sum +%= voice(Bus, d, i);
    const w: i16 = @bitCast(sum -% 0x180);
    const x: u16 = if (w < 0) 0 else if (w >= 0x100) 0xFC else @as(u16, @bitCast(w)) & 0xFC;
    const e = d.table +% @as(u32, x) * 3;
    const regs = [3]u32{ m.rd32(e), m.rd32(e + 4), m.rd32(e + 8) };
    for (regs) |r| m.wr32(PSG, r);
    m.bclr(ISRA, 5);
}
