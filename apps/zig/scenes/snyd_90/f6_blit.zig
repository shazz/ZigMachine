// --------------------------------------------------------------------------
// F6's generated sprite code, read as the tables it is. SYNC's set-up writes
// a routine per ball size and preshift ($39xxx: draw and erase) and one for
// the reflection under the logo ($2C70E); each is a straight run until rts:
//   lea d16(pc),a1                  $43FA  the routine's own mask/ink table
//   movem.l / .w (a1)+,regs         $4CD9 / $4C99  d0-d7 (low byte of the mask)
//   and.l / or.l Dn,d16(a0)         $C1A8|n<<9, $81A8|n<<9 (.w: $C168, $8168)
//   move.l / move.w Dn,d16(a0)      $2140|n, $3140|n (the erase: d0 = 0)
//   move.l d16(a1),d16(a0)          $2169       (the reflection's copy)
// Replayed here instruction by instruction; anything else ends the run and,
// with safety on (the tests), panics: a misread is seen. So does running off
// the part's end (past it every read repeats its last word).
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");

const RTS: u16 = 0x4E75;

/// Run the routine at `pc` with a0 = `a0`, a1 = `a1` and d0 = 0.
pub fn run(r: *const st.Ram, pc: u32, a0: u32, a1_in: u32) void {
    var d = [_]u32{0} ** 8;
    var a1 = a1_in;
    var p = pc;
    while (r.holds(p)) {
        const op = r.w(p);
        const ext = r.w(p + 2);
        const n: u3 = @truncate(op >> 9);
        switch (op) {
            RTS => return,
            0x43FA => a1 = st.add(p + 2, st.sx(ext)),
            0x4CD9 => a1 = movem(r, ext, a1, &d, 4),
            0x4C99 => a1 = movem(r, ext, a1, &d, 2),
            0x2169 => {
                r.sl(st.add(a0, st.sx(r.w(p + 4))), r.l(st.add(a1, st.sx(ext))));
                p += 2;
            },
            0x2140...0x2147 => r.sl(st.add(a0, st.sx(ext)), d[op & 7]),
            0x3140...0x3147 => r.sw(st.add(a0, st.sx(ext)), @truncate(d[op & 7])),
            else => if (!store(r, op, st.add(a0, st.sx(ext)), d[n])) {
                if (std.debug.runtime_safety) std.debug.panic("f6_blit: ${X} at ${X}", .{ op, p });
                return;
            },
        }
        p += 4;
    }
    if (std.debug.runtime_safety) std.debug.panic("f6_blit: the routine at ${X} leaves the part", .{pc});
}

/// movem.l / movem.w (a1)+: longs, or words sign-extended.
fn movem(r: *const st.Ram, mask: u16, from: u32, d: *[8]u32, size: u32) u32 {
    var a = from;
    for (0..8) |k| {
        if (mask & (@as(u16, 1) << @intCast(k)) == 0) continue;
        d[k] = if (size == 4) r.l(a) else @bitCast(st.sx(r.w(a)));
        a +%= size;
    }
    return a;
}

/// and / or .l and .w Dn,d16(a0): the register is in bits 9-11.
fn store(r: *const st.Ram, op: u16, at: u32, v: u32) bool {
    switch (op & 0xF1FF) {
        0xC1A8 => r.sl(at, r.l(at) & v),
        0x81A8 => r.sl(at, r.l(at) | v),
        0xC168 => r.sw(at, r.w(at) & @as(u16, @truncate(v))),
        0x8168 => r.sw(at, r.w(at) | @as(u16, @truncate(v))),
        else => return false,
    }
    return true;
}
