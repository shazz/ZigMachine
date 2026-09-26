// --------------------------------------------------------------------------
// Call 9 continued (the model's a_riders.py, second half): the sprite choice
// $2EDE/$2F3C and the position, erase and draw $302E..$3126.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s16 = State.s16;
const setb = State.setb;
const span = cyc.span;
const back = @import("riders_move.zig");

pub fn L2EDE(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    cy.run(0x2EDE, 0x2EEA);
    st.wb(0x0E64, 0xD);
    const d0 = R[0];
    var d1: i64 = undefined;
    if (cy.br(0x2EEA, d0 & 4 == 0)) {
        cy.run(0x2F0E, 0x2F12);
        if (cy.br(0x2F12, d0 & 0x2000 == 0)) {
            cy.run(0x2F1C, 0x2F26);
            d1 = st.rl(0x2F1E);
            if (cy.br(0x2F26, d0 & 1 != 0)) {
                cy.run(0x2F30, 0x2F34);
                if (!cy.br(0x2F34, d0 & 2 != 0)) {
                    cy.run(0x2F36, 0x2F3C);
                    d1 = st.rl(0x2F38);
                }
            } else {
                cy.run(0x2F28, 0x2F30);
                d1 = st.rl(0x2F2A);
            }
        } else {
            cy.run(0x2F14, 0x2F1C);
            d1 = st.rl(0x2F16);
        }
    } else {
        cy.run(0x2EEC, 0x2EF0);
        if (cy.br(0x2EF0, d0 & 2 == 0)) {
            cy.run(0x2EFA, 0x2F00);
            d1 = st.rl(0x2EFC);
        } else {
            cy.run(0x2EF2, 0x2EFA);
            d1 = st.rl(0x2EF4);
        }
        cy.run(0x2F00, 0x2F04);
        if (!cy.br(0x2F04, d0 & 0x2000 == 0)) {
            cy.run(0x2F06, 0x2F0E);
            d1 += 0xF20;
        }
    }
    R[1] = d1 & M32;
    return 0x2F3C;
}

pub fn L2F3C(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const d0 = R[0];
    var d1 = R[1];
    cy.run(0x2F3C, 0x2F40);
    if (cy.br(0x2F40, d0 & 0x200 == 0)) {
        cy.run(0x3002, 0x3006);
        if (cy.br(0x3006, d0 & 0x40 != 0)) {
            cy.run(0x3016, 0x3026);
            st.wb(0x0E64, st.rb(0x0E64) + 1);
            d1 += 0x1A0;
            if (!cy.br(0x3026, d0 & 0x8000 == 0)) {
                cy.run(0x3028, 0x302E);
                d1 += 0xE0;
            }
        } else {
            cy.run(0x3008, 0x300C);
            if (!cy.br(0x300C, d0 & 0x8000 == 0)) {
                cy.run(0x300E, 0x3016);
                d1 += 0xD0;
            }
        }
        R[1] = d1 & M32;
        return 0x302E;
    }
    cy.run(0x2F44, 0x2F64);
    st.wb(0x0E64, 0x13);
    const ws = st.rw(o + 0xE);
    const d2 = (0x260 & 0xFFFF) * ws;
    d1 = (d1 + 0x360 + d2) & M32;
    R[2] = 4;
    if (cy.br(0x2F64, ws == 4)) {
        cy.run(0x2F9E, 0x2FA4);
        if (!cy.br(0x2FA4, R[8] >= BASE + 0x1040)) {
            cy.run(0x2FA6, 0x2FAE);
            if (!cy.br(0x2FAE, st.g(V.sfx_prio) != 9)) {
                cy.run(0x2FB0, 0x2FB8);
                st.s(V.sfx_prio, 0x10);
                sub.sfx_site(st, cy, 0xC, 0x2FB8, 0x2FC4);
                cy.run(0x2FC4, 0x2FCC);
                st.s(V.sfx_owner, R[8]);
            } else {
                sub.sfx_site(st, cy, 9, 0x2FCC, 0x2FD8);
                cy.run(0x2FD8, 0x2FE0);
                if (!cy.br(0x2FE0, st.g(V.sfx_prio) != 9)) {
                    cy.run(0x2FE2, 0x2FE8);
                    st.s(V.sfx_owner, R[8]);
                }
            }
        }
        cy.run(0x2FE8, 0x2FF8);
        st.wb(0x0E64, 0x12);
        st.ww(o + 0xE, 0);
        if (!cy.br(0x2FF8, d0 & 0x8000 == 0)) {
            cy.run(0x2FFA, 0x3002);
            d1 += 0x120;
        }
        R[1] = d1 & M32;
        return 0x302E;
    }
    cy.run(0x2F66, 0x2F6C);
    if (!cy.br(0x2F6C, st.g(V.sfx_owner) != R[8])) {
        cy.run(0x2F6E, 0x2F76);
        const p = st.g(V.sfx_prio);
        var go = cy.br(0x2F76, p == 9);
        if (!go) {
            cy.run(0x2F78, 0x2F80);
            go = !cy.br(0x2F80, p != 0xC);
        }
        if (go) {
            cy.run(0x2F82, 0x2F84); // clr.w -(a7)
            cy.run(0x2F84, 0x2F8A);
            sub.sfx_call(st, cy, 0);
            cy.run(0x2F8A, 0x2F8C);
        }
    }
    cy.run(0x2F8C, 0x2F90);
    if (!cy.br(0x2F90, d0 & 0x8000 == 0)) {
        cy.run(0x2F94, 0x2F9E);
        d1 += 0x130;
    }
    R[1] = d1 & M32;
    return 0x302E;
}

pub fn L302E(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const d0 = R[0];
    const d1 = R[1];
    st.s(V.tmp_sprite_e5e, d1);
    st.ww(o, d0);
    st.s(V.tmp_ptr_e56, R[8]);
    cy.add(span(0x302E, 0x3054) - 20); // the jsr is counted by xy_addr's caller below
    cy.add(20);
    const a0 = R[8];
    const xy = sub.xy_addr(st, cy, st.rw(o + 2), st.rw(o + 4));
    cy.add(span(0x3054, 0x3072));
    R[8] = a0;
    st.s(V.tmp_ptr_e56, xy.addr);
    st.wb(0x0E62, xy.shift);
    R[0] = d0;
    R[1] = d1;
    cy.run(0x3072, 0x307C);
    st.s(V.draw_wrap, 0);
    if (cy.br(0x307C, d0 & 0x2000 == 0)) return 0x30B4;
    cy.run(0x307E, 0x3082);
    if (cy.br(0x3082, d0 & 0x20 != 0)) return 0x30B4;
    cy.run(0x3084, 0x308A);
    if (cy.br(0x308A, s16(st.rw(o + 2)) <= 0x12F)) return 0x30B4;
    cy.run(0x308C, 0x3090);
    const vx = s16(st.rw(o + 6));
    var right: bool = undefined;
    if (cy.br(0x3090, d0 & 0x1000 != 0)) {
        cy.run(0x30AC, 0x30B0);
        right = !cy.br(0x30B0, vx < 0);
        if (right) _ = cy.br(0x30B2, true);
    } else {
        cy.run(0x3092, 0x3096);
        right = cy.br(0x3096, vx < 0);
    }
    if (right) {
        cy.run(0x30A2, 0x30AC);
        st.s(V.draw_wrap, st.g(V.draw_wrap) | 1);
    } else {
        cy.run(0x3098, 0x30A2);
        st.s(V.draw_wrap, st.g(V.draw_wrap) | 2);
    }
    return 0x30B4;
}

pub fn L30B4(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    var same = false;
    cy.run(0x30B4, 0x30C0);
    R[1] = st.rb(o + 0x1D);
    if (!cy.br(0x30C0, st.rb(o + 0x1D) != st.rb(0x0E62))) {
        cy.run(0x30C2, 0x30CC);
        R[1] = setb(R[1], st.rb(o + 0x1C));
        if (!cy.br(0x30CC, st.rb(o + 0x1C) != st.rb(0x0E64))) {
            cy.run(0x30CE, 0x30D8);
            R[1] = st.rl(o + 0x18);
            if (!cy.br(0x30D8, R[1] != st.g(V.tmp_sprite_e5e))) {
                cy.run(0x30DA, 0x30E4);
                R[1] = st.rl(o + 0x14);
                same = cy.br(0x30E4, R[1] == st.g(V.tmp_ptr_e56));
            }
        }
    }
    if (same) return 0x30F0;
    return 0x30E6;
}

pub fn L30E6(st: *St, cy: *Cy) u32 {
    const o = back.o_of(st);
    cy.run(0x30E6, 0x30EA);
    if (cy.br(0x30EA, st.rl(o + 0x14) == 0)) return 0x30F0;
    cy.run(0x30EC, 0x30F0);
    sub.erase(st, cy);
    return 0x30F0;
}

pub fn L30F0(st: *St, cy: *Cy) u32 {
    const o = back.o_of(st);
    cy.run(0x30F0, 0x30F4);
    sub.draw(st, cy);
    cy.run(0x30F4, 0x3126);
    st.wl(o + 0x14, st.g(V.tmp_ptr_e56));
    st.wl(o + 0x18, st.g(V.tmp_sprite_e5e));
    st.wb(o + 0x1C, st.rb(0x0E64));
    st.wb(o + 0x1D, st.rb(0x0E62));
    st.ww(o + 0x10, st.rw(o + 2));
    st.ww(o + 0x12, st.rw(o + 4));
    return 0x2D94;
}
