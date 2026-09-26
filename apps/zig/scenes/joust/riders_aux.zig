// --------------------------------------------------------------------------
// Package A (the model's a_sub.py): the aux sprite -- an egg, a hatching
// knight, the sparks of a fall: $2A96 erase and $29F6 draw.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s16 = State.s16;
const span = cyc.span;
const sh = cyc.sh;
const shr = State.shr;
pub const XY = struct { addr: i64, shift: i64 };
const back = @import("riders_sub.zig");

/// $2A96 by bsr (the caller counts the bsr); all registers restored.
pub fn aux_erase(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const a0 = R[8] - BASE;
    cy.add(span(0x2A96, 0x2AAE));
    const d0 = st.rb(a0 + 0x33);
    var a1 = st.rl(a0 + 0x2A);
    var a2 = st.rl(a0 + 0x2E);
    var d1 = st.rb(a0 + 0x32);
    while (true) {
        cy.add(span(0x2AAE, 0x2AB0));
        for (0..4) |k| {
            const v = shr(st.rd(a2, 2), d0) & 0xFFFF;
            a2 += 2;
            back.wordAndNot(st, a1, v);
            a1 += 2;
            cy.add(span(0x2AB0, 0x2AB4) + sh(d0, true) + span(0x2AB6, 0x2ABC));
            _ = cy.br(0x2ABC, k != 3);
        }
        cy.add(span(0x2ABE, 0x2AC8));
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(0x2AC8, d1 != 0)) break;
    }
    cy.add(span(0x2ACA, 0x2AE0));
    d1 = st.rb(a0 + 0x32);
    a2 = st.rl(a0 + 0x2E);
    a1 = st.rl(a0 + 0x2A) + 8;
    if (!cy.br(0x2AE0, s16(st.rw(a0 + 0x20)) < 0x130)) {
        cy.run(0x2AE2, 0x2AE8);
        a1 -= 0xA0;
    }
    while (true) {
        cy.add(span(0x2AE8, 0x2AEA));
        for (0..4) |k| {
            const v = shr(st.rd(a2, 2) << 16, d0) & 0xFFFF;
            a2 += 2;
            back.wordAndNot(st, a1, v);
            a1 += 2;
            cy.add(span(0x2AEA, 0x2AF0) + sh(d0, true) + span(0x2AF2, 0x2AF8));
            _ = cy.br(0x2AF8, k != 3);
        }
        cy.add(span(0x2AFA, 0x2B04));
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(0x2B04, d1 != 0)) break;
    }
    cy.add(span(0x2B06, 0x2B0C));
}

/// $29F6 by bsr (the caller counts the bsr). Leaves d0-d3/a1/a2 as the 68000 does.
pub fn aux_draw(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const a0 = R[8] - BASE;
    cy.run(0x29F6, 0x29FA);
    if (!cy.br(0x29FA, st.rb(a0 + 0x1E) != 0)) {
        cy.add(span(0x29FC, 0x29FE));
        return;
    }
    cy.add(span(0x29FE, 0x2A1A));
    const d0 = st.rb(0x0E62);
    var a1 = st.g(V.tmp_ptr_e56);
    var a2 = st.g(V.tmp_sprite_e5e);
    var d1 = st.rb(0x0E64);
    var d2 = R[2];
    var d3 = R[3];
    const lava = st.g(V.lava_top);
    while (true) {
        cy.add(span(0x2A1A, 0x2A20));
        if (!cy.br(0x2A20, a1 < lava)) {
            cy.add(span(0x2A22, 0x2A38));
            st.wb(a0 + 0x1E, 0x24);
            d1 = (-(d1 - st.rb(0x0E64))) & 0xFF;
            st.wb(0x0E64, d1);
            break;
        }
        cy.add(span(0x2A38, 0x2A3A));
        d3 = 4;
        for (0..4) |k| {
            d2 = shr(st.rd(a2, 2), d0) & M32;
            a2 += 2;
            back.wordOr(st, a1, d2 & 0xFFFF);
            a1 += 2;
            d3 -= 1;
            cy.add(span(0x2A3A, 0x2A3E) + sh(d0, true) + span(0x2A40, 0x2A44));
            _ = cy.br(0x2A44, k != 3);
        }
        cy.add(span(0x2A46, 0x2A50));
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(0x2A50, d1 != 0)) break;
    }
    cy.add(span(0x2A52, 0x2A70));
    d1 = st.rb(0x0E64);
    a2 = st.g(V.tmp_sprite_e5e);
    a1 = st.g(V.tmp_ptr_e56) + 8;
    if (!cy.br(0x2A70, s16(st.rw(0x0E5A)) < 0x130)) {
        cy.run(0x2A72, 0x2A78);
        a1 -= 0xA0;
    }
    while (true) {
        cy.add(span(0x2A78, 0x2A7A));
        d3 = 4;
        for (0..4) |k| {
            d2 = shr(st.rd(a2, 2) << 16, d0) & M32;
            a2 += 2;
            back.wordOr(st, a1, d2 & 0xFFFF);
            a1 += 2;
            d3 -= 1;
            cy.add(span(0x2A7A, 0x2A80) + sh(d0, true) + span(0x2A82, 0x2A86));
            _ = cy.br(0x2A86, k != 3);
        }
        cy.add(span(0x2A88, 0x2A92));
        a1 += 0x98;
        a2 += 8;
        d1 = (d1 - 1) & 0xFF;
        if (!cy.br(0x2A92, d1 != 0)) break;
    }
    cy.add(span(0x2A94, 0x2A96));
    R[0] = d0;
    R[1] = d1;
    R[2] = d2;
    R[3] = d3;
    R[9] = a1;
    R[10] = a2;
}
