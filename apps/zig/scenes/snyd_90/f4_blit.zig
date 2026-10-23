// --------------------------------------------------------------------------
// F4's unrolled blits, read as the tables they are. TCB draw (and clear) the
// three logo letters with long straight runs of code -- the set-up even
// GENERATES the scroller's ($C564: one `move.b d16(a0),d16(a1)` per byte of
// the distorted scroller). Each run is nothing but loads of the source into
// registers and stores of registers into the screen, so it is replayed here
// from the part's memory, instruction by instruction, until its rts:
//   move.l (a1),Dn / d16(a1),Dn / d16(a0),Dn     $2011|n<<9, $2029.., $2028..
//   move.l Dn,d16(a2)                             $2540|n
//   or.l Dn,d16(a2) / and.l Dn,d16(a2)            $81AA|n<<9, $C1AA|n<<9
//   move.b d16(a0),d16(a1)                        $1368
// Anything else ends the run (the clears' sections end on a cmpi); with
// safety on (the tests) an unknown word is a panic, so a misread is seen. So
// does running off the code (CODE_LO..CODE_HI: where every run lies).
//
// The code never changes once the part is loaded, so each instruction is
// DECODED ONCE, the first time a run reaches it, into a table indexed by its
// address (f4_ops.zig): a frame walks ~4,300 decoded entries instead of
// re-reading and re-parsing the 68000 words.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");
const ops = @import("f4_ops.zig");

pub const Regs = struct { d: [8]u32 = .{0} ** 8, a0: u32 = 0, a1: u32 = 0, a2: u32 = 0 };
pub const Op = ops.Op;
pub const SLOTS = ops.SLOTS;

var table: []Op = &.{};

/// Each time the part is loaded: `buf` (SLOTS entries) becomes the decode
/// table, every entry not yet decoded.
pub fn attach(buf: []Op) void {
    std.debug.assert(buf.len == SLOTS);
    @memset(buf, .{});
    table = buf;
}

/// Replay the run at `pc` on `regs` until rts (or the cmpi that ends a
/// section of the clears), or until `end` (the scroller's run stops where
/// the original patches in an rts; 0: no such stop).
pub fn run(r: *const st.Ram, pc: u32, end: u32, regs: *Regs) void {
    var p = pc;
    while (p != end) {
        const o = ops.at(r, table, p) orelse return;
        switch (o.kind) {
            .stop => return,
            .move_b => r.sb(st.add(regs.a1, o.d2), r.b(st.add(regs.a0, o.d1))),
            .ld_a1 => regs.d[o.n] = r.l(regs.a1),
            .ld_a1_d => regs.d[o.n] = r.l(st.add(regs.a1, o.d1)),
            .ld_a0_d => regs.d[o.n] = r.l(st.add(regs.a0, o.d1)),
            .or_l => r.sl(st.add(regs.a2, o.d1), r.l(st.add(regs.a2, o.d1)) | regs.d[o.n]),
            .and_l => r.sl(st.add(regs.a2, o.d1), r.l(st.add(regs.a2, o.d1)) & regs.d[o.n]),
            .st_l => r.sl(st.add(regs.a2, o.d1), regs.d[o.n]),
            .none => unreachable,
        }
        p += o.len;
    }
}
