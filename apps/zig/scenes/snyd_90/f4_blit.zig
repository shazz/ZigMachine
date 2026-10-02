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
// safety on (the tests) an unknown word is a panic, so a misread is seen.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");

pub const Regs = struct { d: [8]u32 = .{0} ** 8, a0: u32 = 0, a1: u32 = 0, a2: u32 = 0 };

const RTS: u16 = 0x4E75;
const CMPI_L: u16 = 0x0CB9;

/// Replay the run at `pc` on `regs` until rts (or the cmpi that ends a
/// section of the clears).
pub fn run(r: *const st.Ram, pc: u32, regs: *Regs) void {
    var p = pc;
    while (true) {
        const op = r.w(p);
        if (op == RTS or op == CMPI_L) return;
        if (op == 0x1368) { // two displacements
            r.sb(st.add(regs.a1, st.sx(r.w(p + 4))), r.b(st.add(regs.a0, st.sx(r.w(p + 2)))));
            p += 6;
            continue;
        }
        if (!step(r, op, r.w(p + 2), regs)) {
            if (std.debug.runtime_safety) std.debug.panic("f4_blit: ${X} at ${X}", .{ op, p });
            return;
        }
        p += if ((op & 0xF1FF) == 0x2011) 2 else 4;
    }
}

/// One instruction of the long forms.
fn step(r: *const st.Ram, op: u16, ext: u16, regs: *Regs) bool {
    const n: u3 = @truncate(op >> 9);
    const at = st.add(regs.a2, st.sx(ext));
    switch (op & 0xF1FF) {
        0x2011 => regs.d[n] = r.l(regs.a1),
        0x2029 => regs.d[n] = r.l(st.add(regs.a1, st.sx(ext))),
        0x2028 => regs.d[n] = r.l(st.add(regs.a0, st.sx(ext))),
        0x81AA => r.sl(at, r.l(at) | regs.d[n]),
        0xC1AA => r.sl(at, r.l(at) & regs.d[n]),
        else => switch (op) {
            0x2540...0x2547 => r.sl(at, regs.d[op & 7]),
            else => return false,
        },
    }
    return true;
}
