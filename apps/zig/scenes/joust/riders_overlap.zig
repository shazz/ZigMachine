// --------------------------------------------------------------------------
// Package A's copy of $3FE2, the pixel-exact overlap test of the two rects at
// $0E0E and $0E1E (+ its pixel loop $40D6) -- the model's a_overlap.py.
// Rect: +0 screen address.l, +4 sprite.l, +8 width in groups.w, +$A shift.b,
// +$B height.b, +$C column.w (scratch), +$E y.w. Result: $0E2F = $FF on an
// overlap; $0E2E = rows compared. Counts from the first instruction to the rts.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;
const shr = State.shr;
const span = cyc.span;
const sh = cyc.sh;

fn mask(st: *St, a: i64) i64 {
    return st.rd(a, 2) | st.rd(a + 2, 2) | st.rd(a + 4, 2) | st.rd(a + 6, 2);
}

/// $40D6 (the bsr.b is counted by the caller).
fn pixels(st: *St, cy: *Cy, a1: i64, a2: i64) void {
    cy.add(span(0x40D6, 0x40F2));
    var a3 = st.rl(a1 + 4);
    var a4 = st.rl(a2 + 4);
    var d1 = st.rb(0x0E2E);
    const d2 = st.rb(a1 + 0xA);
    const d3 = st.rb(a2 + 0xA);
    while (true) {
        cy.add(span(0x40F2, 0x40FA));
        var d4: i64 = 0;
        var d5: i64 = 0;
        if (!cy.br(0x40FA, st.rw(a1 + 0xC) == 0)) {
            cy.add(span(0x40FC, 0x4100));
            if (!cy.br(0x4100, st.rb(a1 + 0xA) == 0)) {
                cy.add(span(0x4102, 0x4114));
                d4 = mask(st, a3 - 8) << 16;
            }
        }
        cy.add(span(0x4114, 0x4122));
        d4 = (d4 & 0xFFFF0000) | mask(st, a3);
        cy.add(span(0x4122, 0x4126));
        if (!cy.br(0x4126, st.rw(a2 + 0xC) == 0)) {
            cy.add(span(0x4128, 0x412C));
            if (!cy.br(0x412C, st.rb(a2 + 0xA) == 0)) {
                cy.add(span(0x412E, 0x4140));
                d5 = mask(st, a4 - 8) << 16;
            }
        }
        cy.add(span(0x4140, 0x414E));
        d5 = (d5 & 0xFFFF0000) | mask(st, a4);
        const n2 = d2 & 63;
        const n3 = d3 & 63;
        d4 = if (n2 < 32) shr(d4, n2) else 0;
        d5 = if (n3 < 32) shr(d5, n3) else 0;
        cy.add(sh(n2, true) + sh(n3, true) + span(0x4152, 0x415C));
        d4 = (d4 & 0xFFFF) << 16;
        d5 = (d5 & 0xFFFF) << 16;
        if (cy.br(0x415C, d4 & d5 != 0)) {
            cy.add(span(0x4174, 0x4188));
            st.wb(0x0E2F, 0xFF);
            st.put(a1 + 0xC, 2, st.rw(a1 + 8) - 1);
            return;
        }
        cy.add(span(0x415E, 0x4170));
        a3 = (a3 + s16(st.rw(a1 + 8) << 3)) & M32;
        a4 = (a4 + s16(st.rw(a2 + 8) << 3)) & M32;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(0x4170, d1 != 0)) {
            cy.add(span(0x4172, 0x4174));
            return;
        }
    }
}

/// $3FE2 on the rects $0E0E / $0E1E.
pub fn overlap(st: *St, cy: *Cy) void {
    cy.add(span(0x3FE2, 0x4000));
    st.s(V.coll_hit, 0);
    var a1: i64 = 0x0E0E;
    var a2: i64 = 0x0E1E;
    const sa = State.s32(st.rl(a1));
    const sb = State.s32(st.rl(a2));
    if (!cy.br(0x4000, sa <= sb)) {
        cy.add(span(0x4002, 0x4004)); // exg a1,a2
        const t = a1;
        a1 = a2;
        a2 = t;
    }
    cy.add(span(0x4004, 0x4012));
    const y1 = st.rw(a1 + 0xE);
    var d1 = (y1 & 0xFF00) | ((y1 + st.rb(a1 + 0xB)) & 0xFF);
    if (cy.br(0x4012, s16(d1) <= s16(st.rw(a2 + 0xE)))) {
        cy.add(span(0x40D0, 0x40D6));
        return;
    }
    cy.add(span(0x4016, 0x4034));
    const diff = (st.rl(a2) - st.rl(a1)) & M32;
    const q = @divFloor(diff, 0xA0);
    const r = @mod(diff, 0xA0);
    d1 = if (q > 0xFFFF) diff else (r << 16) | q; // divu overflow: d1 unchanged
    d1 = (d1 & 0xFFFF0000) >> 16; // clr.w d1; swap d1
    d1 >>= 3;
    st.put(a1 + 0xC, 2, 0);
    st.put(a2 + 0xC, 2, 0);
    if (!cy.br(0x4034, (d1 & 0xFFFF) >= st.rw(a1 + 8))) {
        cy.add(span(0x4036, 0x403C));
        st.put(a1 + 0xC, 2, d1);
    } else {
        cy.add(span(0x403C, 0x4046));
        d1 = (-((d1 - 0x14) & 0xFFFF)) & 0xFFFF;
        if (cy.br(0x4046, d1 >= st.rw(a2 + 8))) {
            cy.add(span(0x40D0, 0x40D6));
            return;
        }
        cy.add(span(0x404A, 0x404E));
        st.put(a2 + 0xC, 2, d1);
    }
    cy.add(span(0x404E, 0x409E));
    const v = (st.rb(a1 + 0xB) + st.rw(a1 + 0xE) - st.rw(a2 + 0xE)) & 0xFF;
    st.wb(0x0E2E, v);
    d1 = ((st.rb(a1 + 0xB) - v) & 0xFF) * st.rw(a1 + 8);
    st.put(a1 + 4, 4, st.rl(a1 + 4) + ((d1 << 3) & M32));
    st.put(a1 + 4, 4, st.rl(a1 + 4) + (st.rw(a1 + 0xC) << 3));
    st.put(a2 + 4, 4, st.rl(a2 + 4) + (st.rw(a2 + 0xC) << 3));
    if (!cy.br(0x409E, s8(v) <= s8(st.rb(a2 + 0xB)))) {
        cy.add(span(0x40A0, 0x40A8));
        st.wb(0x0E2E, st.rb(a2 + 0xB));
    }
    while (true) {
        cy.add(20); // bsr.b $40D6
        pixels(st, cy, a1, a2);
        cy.add(span(0x40AA, 0x40C4));
        st.put(a1 + 0xC, 2, st.rw(a1 + 0xC) + 1);
        st.put(a2 + 0xC, 2, st.rw(a2 + 0xC) + 1);
        st.put(a1 + 4, 4, st.rl(a1 + 4) + 8);
        st.put(a2 + 4, 4, st.rl(a2 + 4) + 8);
        if (cy.br(0x40C4, st.rw(a1 + 8) == st.rw(a1 + 0xC))) break;
        cy.add(span(0x40C6, 0x40CE));
        if (!cy.br(0x40CE, st.rw(a2 + 8) != st.rw(a2 + 0xC))) break;
    }
    cy.add(span(0x40D0, 0x40D6));
}
