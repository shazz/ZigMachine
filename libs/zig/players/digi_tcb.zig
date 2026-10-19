// --------------------------------------------------------------------------
// The Carebears' one-byte digi handler, natively: the Swedish New Year Demo's
// TCB 1 tune (swedish_newyear_tcb_digi.sndh). A Timer A interrupt at 2457600
// / 4 / 39 = 15,753 Hz plays one sample byte through an 8-byte volume-table
// entry: about 263 interrupts a 60 Hz frame, so ~321 % of BARD on Musashi.
// Wow Scroller's sibling (digi_wow.zig irq), with a software end of interrupt.
// Only the handler is native: init and the 50 Hz play, which moves the pointer
// back by the segment's length past its end, stay on Musashi (digi_irq.zig).
//
// Offsets from the handler (file $15E); its two addresses are PC-relative:
//   $04  lea ptr(pc),a1         the sample pointer (a long), which play rewinds
//   $08  movea.l (a1),a0 / moveq #0,d0 / move.b (a0)+,d0 / move.l a0,(a1)
//   $10  lsl.w #3,d0 / lea table(pc),a0 / adda.w d0,a0
//   $18  move.l (a0)+,d0 / move.w (a0),d1 / lea $8800.w,a0
//   $20  movep.l d0,0(a0) / movep.w d1,0(a0): registers 8, 9 through the
//        PSG's $8804/$8806 mirrors, then 10
//   $28  bclr #5,$FFFA0F (the MFP's ISRA: a software end of interrupt), rte
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x34; // to the rte, inclusive
const PTR_LEA: u32 = 0x04;
const TABLE_LEA: u32 = 0x12;
pub const STEP = [0]u32{}; // nothing in the code is patched: no steps to read
const HOLES = [_][2]u32{ .{ PTR_LEA + 2, PTR_LEA + 4 }, .{ TABLE_LEA + 2, TABLE_LEA + 4 } };
const SIGNATURE: u64 = 0x1212544099BC5819; // digi.maskedHash of [0, LEN), the two displacements zeroed
const FIRST: u32 = 0x48E7C0C0; // movem.l d0-d1/a0-a1,-(a7): the quick reject
const PSG: u32 = 0xFF8800; // lea $8800.w: $FFFF8800 on the 68000's 24-bit bus
const ISRA: u32 = 0xFFFA0F;

pub const Driver = struct {
    addr: u32,
    ptr: u32 = 0, // where the sample pointer is
    table: u32 = 0,
};

/// Mutant 8 (sndh_native.zig, digi_irq.pointer_kept): the pointer kept in Zig
/// from arming on, as if play never rewound it. Its rewind must be caught.
var kept: u32 = 0;

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
    d.ptr = digi.pcRel(d.addr + PTR_LEA, digi.be16(&code, PTR_LEA + 2));
    d.table = digi.pcRel(d.addr + TABLE_LEA, digi.be16(&code, TABLE_LEA + 2));
    kept = digi.Access(Bus).rd32(d.ptr);
    return true;
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    const pos = if (digi.irq.pointer_kept) kept else m.rd32(d.ptr);
    const s = m.rd8(pos);
    m.wr32(d.ptr, pos +% 1);
    kept = pos +% 1;
    // adda.w d0,a0: d0 = byte * 8 is at most $7F8, so its sign extension is a no-op
    const e = d.table +% @as(u32, s) * 8;
    const hi = m.rd32(e);
    const lo = m.rd16(e + 4);
    for (0..4) |i| m.wr8(PSG + 2 * @as(u32, @intCast(i)), @truncate(hi >> @intCast(24 - 8 * i)));
    m.wr8(PSG, @truncate(lo >> 8));
    m.wr8(PSG + 2, @truncate(lo));
    m.bclr(ISRA, 5);
}
