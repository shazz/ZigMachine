// --------------------------------------------------------------------------
// Package B's own transcriptions of two package A routines it calls (the
// model's b_borrowed.py). Each counts from its first instruction to its rts
// (the caller counts the jsr); a0 is the object's TEXT offset.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const Regs = @import("ai_regs.zig").Regs;
const St = State.St;
const Clk = cyc.Clk;
const shr = State.shr;

/// $38AC: AND-NOT the rider's previous image (+$14 screen, +$18 sprite, +$1C
/// height, +$1D shift); the right group wraps to the line start when prev_x
/// >= $130. Saves d0-d3/a1-a3 but leaves prev_x in d4.w.
pub fn erase_rider_38ac(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x38AC, 0x38C6);
    const shv = st.rb(a0 + 0x1D);
    const scrp = st.rl(a0 + 0x14);
    const spr = st.rl(a0 + 0x18);
    const h = st.rb(a0 + 0x1C);
    var a3 = scrp;
    var a2 = spr;
    var d1 = h;
    while (true) {
        k.i(0x38C6);
        for ([_]i64{ 3, 2, 1, 0 }) |d3| {
            k.r(0x38C8, 0x38CC);
            const d2 = shr(st.rd(a2, 2), shv) & 0xFFFF;
            a2 += 2;
            k.sh(0x38CC, shv);
            k.r(0x38CE, 0x38D4);
            st.wr(a3, 2, st.rd(a3, 2) & ~d2);
            a3 += 2;
            _ = k.b(0x38D4, d3 != 0);
        }
        k.r(0x38D6, 0x38E4);
        a3 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!k.b(0x38E4, d1 != 0)) break;
    }
    k.r(0x38E6, 0x3900);
    d1 = h;
    a2 = spr + 8;
    a3 = scrp + 8;
    const x = st.rw(a0 + 0x10);
    R.setw(4, x);
    if (!k.b(0x3900, (x ^ 0x8000) < (0x130 ^ 0x8000))) {
        k.i(0x3902);
        a3 -= 0xA0;
    }
    while (true) {
        k.i(0x3908);
        for ([_]i64{ 3, 2, 1, 0 }) |d3| {
            k.r(0x390A, 0x3912);
            const d2 = shr((st.rd(a2 - 8, 2) << 16) | st.rd(a2, 2), shv) & 0xFFFF;
            a2 += 2;
            k.sh(0x3912, shv);
            k.r(0x3914, 0x391A);
            st.wr(a3, 2, st.rd(a3, 2) & ~d2);
            a3 += 2;
            _ = k.b(0x391A, d3 != 0);
        }
        k.r(0x391C, 0x392A);
        a3 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!k.b(0x392A, d1 != 0)) break;
    }
    k.r(0x392C, 0x3932);
}

/// $2A96: AND-NOT the aux sprite (+$2A screen, +$2E sprite, +$32 height, +$33
/// shift); the spill group wraps when pad_x (+$20) >= $130. All registers saved.
pub fn erase_aux_2a96(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    _ = R;
    k.r(0x2A96, 0x2AAE);
    const shv = st.rb(a0 + 0x33);
    const scrp = st.rl(a0 + 0x2A);
    const spr = st.rl(a0 + 0x2E);
    const h = st.rb(a0 + 0x32);
    var a1 = scrp;
    var a2 = spr;
    var d1 = h;
    while (true) {
        k.i(0x2AAE);
        for ([_]i64{ 3, 2, 1, 0 }) |d3| {
            k.r(0x2AB0, 0x2AB4);
            const d2 = shr(st.rd(a2, 2), shv) & 0xFFFF;
            a2 += 2;
            k.sh(0x2AB4, shv);
            k.r(0x2AB6, 0x2ABC);
            st.wr(a1, 2, st.rd(a1, 2) & ~d2);
            a1 += 2;
            _ = k.b(0x2ABC, d3 != 0);
        }
        k.r(0x2ABE, 0x2AC8);
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!k.b(0x2AC8, d1 != 0)) break;
    }
    k.r(0x2ACA, 0x2AE0);
    d1 = h;
    a2 = spr;
    a1 = scrp + 8;
    if (!k.b(0x2AE0, (st.rw(a0 + 0x20) ^ 0x8000) < (0x130 ^ 0x8000))) {
        k.i(0x2AE2);
        a1 -= 0xA0;
    }
    while (true) {
        k.i(0x2AE8);
        for ([_]i64{ 3, 2, 1, 0 }) |d3| {
            k.r(0x2AEA, 0x2AF0);
            const d2 = shr(st.rd(a2, 2) << 16, shv) & 0xFFFF;
            a2 += 2;
            k.sh(0x2AF0, shv);
            k.r(0x2AF2, 0x2AF8);
            st.wr(a1, 2, st.rd(a1, 2) & ~d2);
            a1 += 2;
            _ = k.b(0x2AF8, d3 != 0);
        }
        k.r(0x2AFA, 0x2B04);
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!k.b(0x2B04, d1 != 0)) break;
    }
    k.r(0x2B06, 0x2B0C);
}
