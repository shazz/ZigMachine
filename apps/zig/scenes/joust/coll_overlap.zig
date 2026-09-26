// --------------------------------------------------------------------------
// Package B: $3FE2, the pixel-exact overlap test of the rects $0E0E / $0E1E,
// and its pixel loop $40D6 (the model's b_overlap.py). Also what package C's
// pterodactyl uses. The body from $3FE2 to its rts (the caller counts its
// bsr/jsr); sets coll_hit ($0E2F) = $FF on an overlap; every register is
// movem-preserved.
//
// A rect (16 bytes): +0 screen address.l, +4 image address.l, +8 width in
// 16-px groups, +$A shift.b, +$B height.b, +$C group index.w (scratch), +$E y.w.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const Clk = cyc.Clk;
const s8 = State.s8;
const s16 = State.s16;
const s32 = State.s32;
const shr = State.shr;

pub const RA: i64 = 0x0E0E;
pub const RB: i64 = 0x0E1E;
pub const OVERLAP: i64 = 0x0E2E;
pub const HIT: i64 = 0x0E2F;

pub fn overlap_3fe2(st: *St, k: *Clk) void {
    k.r(0x3FE2, 0x4000); // movem, clr.b, 2x movea, move.l, cmp.l
    st.wb(HIT, 0);
    var a1 = RA;
    var a2 = RB;
    if (!k.b(0x4000, s32(st.rl(a1)) <= s32(st.rl(a2)))) {
        k.i(0x4002); // exg a1,a2: a1 = the upper-left one
        const t = a1;
        a1 = a2;
        a2 = t;
    }
    k.r(0x4004, 0x4012);
    const y1 = st.rw(a1 + 0x0E);
    var d1 = (y1 & 0xFF00) | ((y1 + st.rb(a1 + 0x0B)) & 0xFF); // add.b: the carry is lost
    if (k.b(0x4012, s16(d1) <= s16(st.rw(a2 + 0x0E)))) {
        k.r(0x40D0, 0x40D6);
        return;
    }
    k.r(0x4016, 0x4030); // move.l, sub.l, divu #$a0, clr.w, swap, lsr.l #3, 2x clr.w
    const diff = (st.rl(a2) - st.rl(a1)) & State.M32;
    const q = @divFloor(diff, 0xA0);
    const rem = @mod(diff, 0xA0);
    d1 = if (q > 0xFFFF) diff else (rem << 16) | q; // divu overflow leaves d1
    d1 = (d1 >> 16) & 0xFFFF; // clr.w + swap
    d1 >>= 3;
    st.ww(a1 + 0x0C, 0);
    st.ww(a2 + 0x0C, 0);
    k.i(0x4030); // cmp.w 8(a1),d1
    if (!k.b(0x4034, (d1 & 0xFFFF) >= st.rw(a1 + 8))) {
        k.r(0x4036, 0x403C); // move.w d1,$c(a1); bra
        st.ww(a1 + 0x0C, d1);
    } else {
        k.r(0x403C, 0x4046); // sub.w #$14, neg.w, cmp.w
        d1 = (-(d1 - 0x14)) & 0xFFFF;
        if (k.b(0x4046, d1 >= st.rw(a2 + 8))) {
            k.r(0x40D0, 0x40D6);
            return;
        }
        k.i(0x404A);
        st.ww(a2 + 0x0C, d1);
    }
    k.r(0x404E, 0x409E);
    const h1 = st.rb(a1 + 0x0B);
    const ov = (h1 + st.rw(a1 + 0x0E) - st.rw(a2 + 0x0E)) & 0xFF;
    st.wb(OVERLAP, ov);
    d1 = ((h1 - ov) & 0xFF) * st.rw(a1 + 8);
    st.wl(a1 + 4, st.rl(a1 + 4) + ((d1 << 3) & State.M32));
    st.wl(a1 + 4, st.rl(a1 + 4) + (st.rw(a1 + 0x0C) << 3));
    st.wl(a2 + 4, st.rl(a2 + 4) + (st.rw(a2 + 0x0C) << 3));
    if (!k.b(0x409E, s8(ov) <= s8(st.rb(a2 + 0x0B)))) {
        k.i(0x40A0);
        st.wb(OVERLAP, st.rb(a2 + 0x0B));
    }
    while (true) {
        k.i(0x40A8); // bsr.b $40D6
        pixels_40d6(st, k, a1, a2);
        k.r(0x40AA, 0x40C4);
        st.ww(a1 + 0x0C, st.rw(a1 + 0x0C) + 1);
        st.ww(a2 + 0x0C, st.rw(a2 + 0x0C) + 1);
        st.wl(a1 + 4, st.rl(a1 + 4) + 8);
        st.wl(a2 + 4, st.rl(a2 + 4) + 8);
        if (k.b(0x40C4, st.rw(a1 + 8) == st.rw(a1 + 0x0C))) break;
        k.r(0x40C6, 0x40CE);
        if (!k.b(0x40CE, st.rw(a2 + 8) != st.rw(a2 + 0x0C))) break;
    }
    k.r(0x40D0, 0x40D6); // movem restore, rts
}

fn or4(st: *St, a: i64) i64 {
    return st.rd(a, 2) | st.rd(a + 2, 2) | st.rd(a + 4, 2) | st.rd(a + 6, 2);
}

/// $40D6: for each overlapping row, the 4-plane OR mask of one group of each
/// image (plus the group to its left when shifted), shifted into place; AND
/// them: any bit = a hit.
fn pixels_40d6(st: *St, k: *Clk, a1: i64, a2: i64) void {
    k.r(0x40D6, 0x40F2);
    var a3 = st.rl(a1 + 4);
    var a4 = st.rl(a2 + 4);
    var d1 = st.rb(OVERLAP);
    const d2 = st.rb(a1 + 0x0A);
    const d3 = st.rb(a2 + 0x0A);
    const c1 = st.rw(a1 + 0x0C);
    const c2 = st.rw(a2 + 0x0C);
    const step1 = s16((st.rw(a1 + 8) << 3) & 0xFFFF);
    const step2 = s16((st.rw(a2 + 8) << 3) & 0xFFFF);
    while (true) {
        k.r(0x40F2, 0x40FA);
        var d4: i64 = 0;
        if (!k.b(0x40FA, c1 == 0)) {
            k.i(0x40FC);
            if (!k.b(0x4100, d2 == 0)) {
                k.r(0x4102, 0x4114);
                d4 = or4(st, a3 - 8) << 16;
            }
        }
        k.r(0x4114, 0x4126);
        d4 |= or4(st, a3);
        var d5: i64 = 0;
        if (!k.b(0x4126, c2 == 0)) {
            k.i(0x4128);
            if (!k.b(0x412C, d3 == 0)) {
                k.r(0x412E, 0x4140);
                d5 = or4(st, a4 - 8) << 16;
            }
        }
        k.r(0x4140, 0x414E);
        d5 |= or4(st, a4);
        k.sh(0x414E, d2);
        k.sh(0x4150, d3);
        d4 = shr(d4, d2 & 63);
        d5 = shr(d5, d3 & 63);
        k.r(0x4152, 0x415C); // 2x swap, 2x clr.w, and.l
        if (k.b(0x415C, (d4 & d5 & 0xFFFF) != 0)) {
            k.r(0x4174, 0x4188); // move.b #$ff, move.w, subq.w, rts
            st.wb(HIT, 0xFF);
            st.ww(a1 + 0x0C, st.rw(a1 + 8) - 1);
            return;
        }
        k.r(0x415E, 0x4170);
        a3 = (a3 + step1) & State.M32;
        a4 = (a4 + step2) & State.M32;
        d1 = (d1 - 1) & 0xFF;
        if (!k.b(0x4170, d1 != 0)) {
            k.i(0x4172); // rts
            return;
        }
    }
}
