// --------------------------------------------------------------------------
// Package A's own copies of the score and lives routines (the model's
// a_text.py): $433E/$4350/$4336 lives, $4250 score add, $44F0 a free message
// record, $1FBA lose a life / the GAME OVER messages.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const span = cyc.span;
const back = @import("riders_text.zig");
const E7F: i64 = 0x0E7F;

pub fn lives(st: *St, cy: *Cy, o: i64, icon: i64) void {
    const R = &st.regs;
    const s0 = R[0];
    const s1 = R[1];
    const s8r = R[8];
    cy.add(span(0x4360, 0x439C));
    st.s(V.text_cursor, (st.rl(o + 0x36) + 0x10) & M32);
    st.wb(0x0E7C, st.rb(o + 0x3B) + 0xA);
    st.wb(E7F, st.rb(E7F) | 0x80);
    st.wb(E7F, st.rb(E7F) | 0x10);
    st.wb(0x0E7E, 0xF);
    var d0: i64 = 5;
    while (true) {
        cy.run(0x439C, 0x43A0);
        if (cy.br(0x43A0, d0 <= s8(st.rb(o + 0x4C)))) {
            cy.run(0x43B0, 0x43B8);
            back.text_print(st, cy, icon);
        } else {
            cy.run(0x43A2, 0x43AE);
            back.text_print(st, cy, st.rl(0x43A4));
            cy.run(0x43AE, 0x43B0);
        }
        cy.run(0x43B8, 0x43BE);
        d0 -= 1;
        if (!cy.br(0x43BE, d0 != 0)) break;
    }
    cy.add(span(0x43C0, 0x43CE));
    st.wb(E7F, st.rb(E7F) & ~@as(i64, 0x10));
    R[0] = s0;
    R[1] = s1;
    R[8] = s8r;
}

pub fn lives_p1(st: *St, cy: *Cy) void {
    cy.add(span(0x433E, 0x4350));
    lives(st, cy, 0x0FA4, st.rl(0x434A));
}

pub fn lives_p2(st: *St, cy: *Cy) void {
    cy.add(span(0x4350, 0x4360));
    lives(st, cy, 0x0FF2, st.rl(0x435C));
}

/// $4336: a0 = P2 -> $4350, else $433E.
pub fn lives_both(st: *St, cy: *Cy) void {
    cy.run(0x4336, 0x433C);
    if (cy.br(0x433C, st.regs[8] == BASE + 0x0FF2)) lives_p2(st, cy) else lives_p1(st, cy);
}

/// jsr $4250: movem.l d0/a0,-(a7); bra.b $426C (a0 = the slot).
pub fn score_add_entry(st: *St, cy: *Cy) void {
    cy.add(cyc.cost(0x4256) + 12);
    score(st, cy);
}

pub fn score(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const s0 = R[0];
    const s8r = R[8];
    const o = R[8] - BASE;
    cy.run(0x426C, 0x4272);
    var d0: ?i64 = 0x3E;
    while (true) { // skip the leading blanks
        cy.run(0x4272, 0x4278);
        if (cy.br(0x4278, st.rb(o + d0.?) != 0x20)) break;
        cy.run(0x427A, 0x4280);
        d0 = d0.? + 1;
        if (!cy.br(0x4280, d0.? != 0x44)) {
            cy.run(0x4282, 0x4284);
            d0 = null;
            break;
        }
    }
    if (d0) |d0s| {
        var d = d0s;
        while (true) {
            cy.run(0x4284, 0x428A);
            if (!cy.br(0x428A, s8(st.rb(o + d)) >= 0x30)) {
                cy.run(0x428C, 0x4292);
                st.wb(o + d, st.rb(o + d) + 0x10);
            }
            cy.run(0x4292, 0x4298);
            d += 1;
            if (!cy.br(0x4298, d != 0x44)) break;
        }
    }
    cy.run(0x429A, 0x42A8);
    st.wb(E7F, st.rb(E7F) | 0x80);
    var d: i64 = 0x44;
    while (true) {
        cy.run(0x42A8, 0x42AE);
        if (cy.br(0x42AE, st.rb(o + d) <= 0x39)) {
            cy.run(0x42EA, 0x42F0);
            d -= 1;
            if (cy.br(0x42F0, d != 0x3D)) continue;
            break;
        }
        cy.run(0x42B0, 0x42B6);
        if (!cy.br(0x42B6, st.rb(o + d - 1) != 0x20)) {
            cy.run(0x42B8, 0x42BE);
            st.wb(o + d - 1, 0x30);
        }
        cy.run(0x42BE, 0x42CC);
        st.wb(o + d - 1, st.rb(o + d - 1) + 1);
        st.wb(o + d, st.rb(o + d) - 0xA);
        if (cy.br(0x42CC, d != 0x41)) continue;
        cy.run(0x42CE, 0x42D4);
        if (cy.br(0x42D4, st.rb(o + d - 1) & 1 != 0)) continue;
        cy.run(0x42D6, 0x42DA);
        st.wb(o + 0x4C, st.rb(o + 0x4C) + 1);
        cy.add(20); // bsr.b $4336
        lives_both(st, cy);
        cy.run(0x42DC, 0x42E6);
        sub.sfx_call(st, cy, 1);
        cy.run(0x42E6, 0x42EA);
    }
    cy.run(0x42F2, 0x4322);
    st.wb(E7F, st.rb(E7F) | 0x10);
    st.wb(0x0E7E, 0xF);
    st.wb(0x0E7C, st.rw(o + 0x3A));
    st.s(V.text_cursor, st.rl(o + 0x36));
    back.text_print(st, cy, R[8] + 0x3C);
    cy.run(0x4322, 0x4336);
    st.wb(E7F, st.rb(E7F) & ~@as(i64, 0x10));
    R[0] = s0;
    R[8] = s8r;
}

/// $44F0: the first free message record, or null when all 24 are in use (the
/// original then writes the record at address 0, in low memory).
pub fn popup_alloc(st: *St, cy: *Cy) ?i64 {
    cy.run(0x44F0, 0x44F6);
    var a: i64 = 0x0E84;
    while (true) {
        cy.run(0x44F6, 0x44FA);
        if (cy.br(0x44FA, st.rb(a) != 0)) {
            cy.run(0x44FE, 0x4508);
            a += 0xC;
            if (cy.br(0x4508, a != 0x0FA4)) continue;
            st.oob += 1; // the model raises here: a path no recorded game reached
            return null;
        }
        cy.run(0x44FC, 0x44FE);
        return a;
    }
}

/// $1FBA (a0 = the object): enemies are freed; a player loses a life, or on
/// the last one the GAME OVER / PLAYER n GAME OVER records are allocated.
pub fn lose_life(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const o = R[8] - BASE;
    cy.run(0x1FBA, 0x1FC4);
    if (!cy.br(0x1FC4, R[8] <= BASE + 0x0FF2)) {
        cy.run(0x1FC6, 0x1FCE);
        st.ww(o, 0);
    } else {
        cy.run(0x1FCE, 0x1FD8);
        const lv = (st.rb(o + 0x4C) - 1) & 0xFF;
        st.wb(o + 0x4C, lv);
        if (!cy.br(0x1FD8, lv == 0xFF)) {
            cy.run(0x1FDA, 0x2004);
            st.wl(o + 0x14, 0);
            st.wb(o + 0x1C, 0);
            st.ww(o + 6, 0);
            var f = st.rw(o);
            f = (f & ~@as(i64, 0x0010) & ~@as(i64, 0x2000) & ~@as(i64, 0x0100)) | 0x0080;
            st.ww(o, f);
            lives_p1(st, cy);
            cy.run(0x2004, 0x200A);
            lives_p2(st, cy);
            cy.run(0x200A, 0x200E);
        } else {
            cy.run(0x200E, 0x2018);
            st.ww(o, 0);
            st.s(V.players, st.g(V.players) - 1);
            if (!cy.br(0x2018, st.g(V.players) != 0)) {
                cy.run(0x201A, 0x2020);
                const p = popup_alloc(st, cy);
                cy.run(0x2020, 0x2050);
                if (p) |q| {
                    st.wl(q + 4, st.g(V.screen_base) + 0x3238);
                    st.wl(q + 8, st.rl(0x2032));
                    st.wb(q + 2, 1);
                    st.wb(q, 3);
                    st.wb(q + 1, 0x64);
                    st.wb(q + 3, 0);
                }
            } else {
                cy.run(0x2050, 0x2058);
                const p = popup_alloc(st, cy);
                cy.run(0x2058, 0x2080);
                if (p) |q| {
                    st.wl(q + 4, st.g(V.screen_base) + 0x3910);
                    st.wb(q + 3, 4);
                    st.wb(q, 3);
                    st.wb(q + 1, 0x64);
                }
                if (!cy.br(0x2080, R[8] != BASE + 0x0FA4)) {
                    cy.run(0x2082, 0x2092);
                    if (p) |q| {
                        st.wb(q + 2, 7);
                        st.wl(q + 8, st.rl(0x208A));
                    }
                } else {
                    cy.run(0x2092, 0x20A0);
                    if (p) |q| {
                        st.wb(q + 2, 2);
                        st.wl(q + 8, st.rl(0x209A));
                    }
                }
            }
        }
    }
    cy.run(0x20A0, 0x20A6);
}
