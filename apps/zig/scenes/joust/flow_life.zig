// --------------------------------------------------------------------------
// Package D: $1FBA lose a life (the lives display, the "PLAYER n GAME OVER" /
// "GAME OVER" messages) -- the model's d_flow.py. The body from $1FBA to its
// rts (the caller counts its jsr/bsr); d2/a0/a1 are movem-preserved.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const popups = @import("flow_popups.zig");
const score = @import("flow_score.zig");
const St = State.St;
const V = State.V;
const BASE = State.BASE;

/// a = TEXT offset of the slot (the caller's a0).
pub fn lose_life(st: *St, cy: anytype, a: i64) void {
    cy.run(0x1FBA, 0x1FC4); // movem, cmpa.l #$ff2,a0
    const save = st.regs;
    if (!cy.br(0x1FC4, a <= 0x0FF2)) {
        st.ww(a, 0);
        cy.run(0x1FC6, 0x1FCE); // clr.w, bra.w
        return out(st, cy, save);
    }
    const lv = (st.rb(a + 0x4C) - 1) & 0xFF;
    st.wb(a + 0x4C, lv);
    cy.run(0x1FCE, 0x1FD8);
    if (!cy.br(0x1FD8, lv == 0xFF)) {
        st.wl(a + 0x14, 0);
        st.wb(a + 0x1C, 0);
        st.ww(a + 6, 0);
        var d2 = st.rw(a);
        d2 = (d2 & ~@as(i64, 0x0110) & ~@as(i64, 0x2000)) | 0x0080;
        st.ww(a, d2);
        cy.run(0x1FDA, 0x2004); // ... jsr $433e
        score.lives(st, cy, 1);
        cy.one(0x2004); // jsr $4350
        score.lives(st, cy, 2);
        cy.one(0x200A); // bra.w
        return out(st, cy, save);
    }
    st.ww(a, 0);
    st.s(V.players, st.g(V.players) - 1);
    cy.run(0x200E, 0x2018);
    if (!cy.br(0x2018, st.g(V.players) != 0)) {
        cy.one(0x201A); // jsr $44f0
        const r = popups.alloc(st, cy);
        cy.run(0x2020, 0x2050);
        if (r) |p| {
            st.wl(p + 4, st.g(V.screen_base) + 0x3238);
            st.wl(p + 8, BASE + 0x8928);
            st.wb(p + 2, 1);
            st.wb(p, 3);
            st.wb(p + 1, 0x64);
            st.wb(p + 3, 0);
        }
        return out(st, cy, save);
    }
    cy.run(0x2050, 0x2058); // movea.l a0,a1; jsr $44f0
    const r = popups.alloc(st, cy);
    cy.run(0x2058, 0x2080);
    if (r) |p| {
        st.wl(p + 4, st.g(V.screen_base) + 0x3910);
        st.wb(p + 3, 4);
        st.wb(p, 3);
        st.wb(p + 1, 0x64);
    }
    if (!cy.br(0x2080, a != 0x0FA4)) {
        cy.run(0x2082, 0x2092);
        if (r) |p| {
            st.wb(p + 2, 7);
            st.wl(p + 8, BASE + 0x893B);
        }
    } else {
        cy.run(0x2092, 0x20A0);
        if (r) |p| {
            st.wb(p + 2, 2);
            st.wl(p + 8, BASE + 0x8950);
        }
    }
    return out(st, cy, save);
}

fn out(st: *St, cy: anytype, regs: [16]i64) void {
    st.regs = regs;
    cy.run(0x20A0, 0x20A6); // movem, rts
}
