// --------------------------------------------------------------------------
// The three volume streams, natively: tcb_spreadpoint.sndh (TCB's Spreadpoint
// screen). Play premixes each voice's volumes into its own stream; the Timer A
// interrupt, at 7,680 Hz (128 a 60 Hz frame), writes one byte of each onto
// YM registers 8, 9 and 10. Only the handler is native (digi_irq.zig).
//
//   $00  movem.l a0-a2,-(a7)
//   $04  movem.l P.l,a0-a2          the three stream pointers (relocated by init)
//   $0C  move.b #8,$8800.w / move.b (a0)+,$8802.w, then 9 (a1) and 10 (a2)
//   $2A  movem.l a0-a2,P.l          stored back, one byte on each
//   $32  movem.l (a7)+,a0-a2 / rte
//
// Every access is the 68000's, in its order; the pushes and pops are left
// out, as nothing reads that stack.
// --------------------------------------------------------------------------
const digi = @import("digi.zig");

pub const LEN: u32 = 0x38; // to the rte, inclusive
const LOAD: u32 = 0x08; // movem.l P.l,a0-a2: P
const STORE: u32 = 0x2E; // movem.l a0-a2,P.l: the same P
const HOLES = [_][2]u32{ .{ LOAD, LOAD + 4 }, .{ STORE, STORE + 4 } };
const SIGNATURE: u64 = 0xA83D350141003CC3; // digi.maskedHash of [0, LEN), P zeroed
const FIRST: u32 = 0x48E700E0; // movem.l a0-a2,-(a7): the quick reject
pub const STEP = [0]u32{}; // nothing in this handler is patched by play
const PSG: u32 = 0xFF8800;

pub const Driver = struct {
    addr: u32,
    p: u32 = 0, // the three pointers
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

/// The handler in RAM, checked again, and its pointers' address read.
pub fn arm(comptime Bus: type, d: *Driver) bool {
    var code: [LEN]u8 = undefined;
    for (&code, 0..) |*b, i| b.* = Bus.read8(d.addr + @as(u32, @intCast(i)));
    if (!matchAt(&code, 0) or digi.be32(&code, LOAD) != digi.be32(&code, STORE)) return false;
    d.p = digi.be32(&code, LOAD);
    return true;
}

pub fn irq(comptime Bus: type, d: Driver) void {
    const m = digi.Access(Bus);
    var a: [3]u32 = undefined;
    for (&a, 0..) |*x, i| x.* = m.rd32(d.p + 4 * @as(u32, @intCast(i)));
    for (&a, 0..) |*x, i| {
        const voice: u8 = @intCast(i);
        m.wr8(PSG, 8 + if (digi.irq.swapped and voice != 0) 3 - voice else voice);
        m.wr8(PSG + 2, m.rd8(x.*));
        x.* +%= 1;
    }
    for (a, 0..) |x, i| m.wr32(d.p + 4 * @as(u32, @intCast(i)), x);
}
