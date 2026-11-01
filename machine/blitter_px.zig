// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: the last step of every pixel an op writes
// (CHISEL v2, 1.11.0), the machine's twin of zm_blit_pxq's head stage.
//   - area fill (CON.IFE / CON.EFE, BLIT and FILL only): each row, in the op's
//     walk order, keeps an inside/outside carry PER BIT of the index (the Amiga's
//     eight bitplanes, chunky), starting at CON2.FILL_CARRY (all ones) or 0 at the
//     row's first visible pixel; a written value r toggles it. IFE writes
//     carry | r (the edges included), EFE carry ^ r after the toggle (the
//     trailing edge left out); IFE wins when both are set. A keyed pixel is not
//     written and does not toggle.
//   - collision (CON2.COLL_EN, every op): writing over a non-zero byte sets
//     BLIT_COLL bit 0, which stays set until the program clears it.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");

pub const Writer = struct {
    ife: bool = false,
    efe: bool = false,
    carry0: u8 = 0,
    carry: u8 = 0,
    coll: bool = false,

    /// BLIT and FILL: the area fill from CON, the carry-in and the collision from CON2.
    pub fn init(con: u8) Writer {
        const con2 = regs.r8(memmap.BLIT_CON2);
        var w = Writer.other();
        w.ife = con & memmap.CON_IFE != 0;
        w.efe = !w.ife and con & memmap.CON_EFE != 0;
        w.carry0 = if (con2 & memmap.CON2_FILL_CARRY != 0) 0xFF else 0;
        return w;
    }

    /// Every other op: no area fill, the collision from CON2.
    pub fn other() Writer {
        return .{ .coll = regs.r8(memmap.BLIT_CON2) & memmap.CON2_COLL_EN != 0 };
    }

    /// A new row: the carry starts again.
    pub fn row(w: *Writer) void {
        w.carry = w.carry0;
    }

    pub fn put(w: *Writer, d: [*]u8, di: usize, v: u8) void {
        if (w.coll and d[di] != 0) regs.w8(memmap.BLIT_COLL, regs.r8(memmap.BLIT_COLL) | 1);
        var out = v;
        if (w.ife) out = w.carry | v;
        w.carry ^= v;
        if (w.efe) out = w.carry;
        d[di] = out;
    }
};
