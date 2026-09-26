// --------------------------------------------------------------------------
// Call 4 continued (the model's a_eggs.py): the animation table $27F8, the
// hatch $2816, the countdown $2914, and the aux sprite's draw $2936..$29B6.
// --------------------------------------------------------------------------
const std = @import("std");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const aux = @import("riders_aux.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;
const span = cyc.span;
const back = @import("eggs.zig");

pub fn L27F8(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    cy.run(0x27F8, 0x2816);
    const d1 = (((st.rb(o + 0x1E) - 1) & 0xFF) << 3);
    R[1] = d1;
    R[9] = BASE + 0x1AC2;
    st.s(V.tmp_sprite_e5e, st.rl(0x1AC2 + d1));
    const a2 = st.rl(0x1AC2 + d1 + 4);
    R[10] = a2;
    // jmp (a2): a pointer read from RAM. One below the program (a corrupt
    // table entry) must not reach an unchecked cast: it becomes a label the
    // dispatcher does not know, which counts an access and ends the call.
    return std.math.cast(u32, a2 - BASE) orelse NO_LABEL;
}

/// No label of eggs.zig's machine: its step() counts it in st.oob and stops.
const NO_LABEL: u32 = 0xFFFF_FFFF;

pub fn L2816(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const t = st.rb(o + 0x1E);
    cy.run(0x2816, 0x281C);
    if (!cy.br(0x281C, t != 0xB)) {
        cy.run(0x281E, 0x2838);
        st.wb(0x0E64, st.rb(0x0E64) + 4);
        st.s(V.tmp_ptr_e56, (st.g(V.tmp_ptr_e56) - 0x280) & M32);
        st.ww(0x0E5C, st.rw(0x0E5C) - 4);
        return 0x2914;
    }
    cy.run(0x2838, 0x283E);
    if (cy.br(0x283E, s8(t) < 5)) return 0x27F8;
    if (cy.br(0x2840, s8(t) > 5)) return 0x2914;
    // hatched
    cy.run(0x2844, 0x286A);
    st.wb(o + 0x4A, 0xFF);
    st.wb(o + 0xB, 5);
    st.wb(o + 0xA, 3);
    st.ww(o + 8, 0);
    var d0 = st.rb(o + 0x34) | 0x2000;
    if (!cy.br(0x286A, st.rw(o + 0x20) >= 0xA0)) {
        cy.run(0x286C, 0x287E);
        st.ww(o + 6, -st.g(V.speed_bounder));
        st.ww(o + 2, 0);
    } else {
        cy.run(0x287E, 0x2890);
        st.ww(o + 6, st.g(V.speed_bounder));
        st.ww(o + 2, 0x130);
        d0 |= 0x8000;
    }
    R[0] = d0;
    cy.run(0x2890, 0x28A8);
    st.ww(o + 0xC, st.rw(o + 6));
    st.ww(o + 0x46, st.rw(o + 0x22) - 0xE);
    const py = s16(st.rw(o + 0x22));
    if (!cy.br(0x28A8, py > 0x3C)) {
        cy.run(0x28AA, 0x28B2);
        st.ww(o + 4, 0xA);
    } else {
        cy.run(0x28B2, 0x28B8);
        if (cy.br(0x28B8, py > 0x96)) {
            cy.run(0x28D0, 0x28D6);
            st.ww(o + 4, 0x78);
        } else {
            cy.run(0x28BA, 0x28C6);
            st.ww(o + 4, 0x32);
            if (!cy.br(0x28C6, py < 0x6E)) {
                cy.run(0x28C8, 0x28D0);
                st.ww(o + 4, 0xA);
            }
        }
    }
    cy.run(0x28D6, 0x28E6);
    st.ww(o, d0);
    st.wb(o + 0x1E, st.rb(o + 0x34));
    const e = s8(st.rb(o + 0x34));
    if (cy.br(0x28E6, e < 2)) {
        cy.run(0x28F8, 0x2906);
        st.s(V.tmp_sprite_e5e, st.rl(0x28FA));
    } else if (cy.br(0x28E8, e > 2)) {
        cy.run(0x2906, 0x2914);
        st.s(V.tmp_sprite_e5e, st.rl(0x2908));
    } else {
        cy.run(0x28EA, 0x28F8);
        st.s(V.tmp_sprite_e5e, st.rl(0x28EC));
    }
    return 0x29A2;
}

pub fn L2914(st: *St, cy: *Cy) u32 {
    const o = back.o_of(st);
    cy.run(0x2914, 0x291E);
    const t = (st.rb(o + 0x1E) - 1) & 0xFF;
    st.wb(o + 0x1E, t);
    if (!cy.br(0x291E, t == 0x12)) {
        cy.run(0x2920, 0x2926);
        if (cy.br(0x2926, t != 0x19)) return 0x27F8;
    }
    cy.run(0x292A, 0x2932);
    st.wb(o + 0x1E, 0);
    aux.aux_erase(st, cy);
    cy.run(0x2932, 0x2936);
    return 0x26B0;
}

pub fn L2936(st: *St, cy: *Cy) u32 {
    cy.run(0x2936, 0x293A);
    aux.aux_draw(st, cy);
    cy.run(0x293A, 0x293E);
    return 0x26B0;
}

pub fn L293E(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const k0 = R[0];
    const k1 = R[1];
    const k8 = R[8];
    cy.add(span(0x293E, 0x2958));
    const xy = sub.xy_addr(st, cy, st.rw(0x0E5A), st.rw(0x0E5C));
    cy.add(span(0x2958, 0x2970));
    st.s(V.tmp_ptr_e56, xy.addr);
    st.wb(0x0E62, xy.shift);
    R[0] = k0;
    R[1] = k1;
    R[8] = k8;
    cy.run(0x2970, 0x297C);
    R[1] = st.rb(o + 0x33);
    if (cy.br(0x297C, st.rb(o + 0x33) != st.rb(0x0E62))) return 0x29A2;
    cy.run(0x297E, 0x2988);
    R[1] = st.rb(o + 0x32);
    if (cy.br(0x2988, st.rb(o + 0x32) != st.rb(0x0E64))) return 0x29A2;
    cy.run(0x298A, 0x2994);
    R[1] = st.rl(o + 0x2E);
    if (cy.br(0x2994, R[1] != st.g(V.tmp_sprite_e5e))) return 0x29A2;
    cy.run(0x2996, 0x29A0);
    R[1] = st.rl(o + 0x2A);
    if (cy.br(0x29A0, R[1] == st.g(V.tmp_ptr_e56))) return 0x29B6;
    return 0x29A2;
}

pub fn L29A2(st: *St, cy: *Cy) u32 {
    const o = back.o_of(st);
    cy.run(0x29A2, 0x29A8);
    if (!cy.br(0x29A8, st.rb(o + 0x34) & 0x80 == 0)) {
        cy.run(0x29AA, 0x29B2);
        st.wb(o + 0x34, st.rb(o + 0x34) ^ 0x80);
        return 0x29B6;
    }
    cy.run(0x29B2, 0x29B6);
    aux.aux_erase(st, cy);
    return 0x29B6;
}

pub fn L29B6(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    var keep: [7]i64 = undefined;
    @memcpy(keep[0..4], R[0..4]);
    @memcpy(keep[4..7], R[9..12]);
    cy.run(0x29B6, 0x29BC);
    aux.aux_draw(st, cy);
    @memcpy(R[0..4], keep[0..4]);
    @memcpy(R[9..12], keep[4..7]);
    cy.run(0x29BC, 0x29F6);
    st.wl(o + 0x2A, st.g(V.tmp_ptr_e56));
    st.wl(o + 0x2E, st.g(V.tmp_sprite_e5e));
    st.wb(o + 0x32, st.rb(0x0E64));
    st.wb(o + 0x33, st.rb(0x0E62));
    st.ww(o + 0x20, st.rw(0x0E5A));
    st.ww(o + 0x22, st.rw(0x0E5C));
    return 0x26B0;
}
