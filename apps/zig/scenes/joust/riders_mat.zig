// --------------------------------------------------------------------------
// Call 9 continued (the model's a_riders2.py): materialising on a pad --
// $35C0 the rider grows line by line, $362C the frames, $3698 done -- and the
// pad glow $3718/$378C.
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
const s16 = State.s16;
const setb = State.setb;
const span = cyc.span;
const sh = cyc.sh;
const back = @import("riders_spawn.zig");

pub fn L35C0(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const d0 = R[0];
    cy.run(0x35C0, 0x35CA);
    R[1] = st.rl(o + 0x18);
    if (cy.br(0x35CA, st.rb(o + 0x1C) == 0x13)) {
        cy.run(0x3614, 0x3620);
        st.wb(0x0E64, 0x13);
        if (cy.br(0x3620, d0 & 0x800 != 0)) return 0x3698;
        cy.run(0x3624, 0x3628);
        if (cy.br(0x3628, st.rw(o + 0xC) != 0)) return 0x3698;
        return 0x362C;
    }
    cy.run(0x35CC, 0x35E6);
    const h = (st.rb(o + 0x1C) + 1) & 0xFF;
    st.wb(0x0E64, h);
    st.ww(o + 4, st.rw(o + 4) - 1);
    if (cy.br(0x35E6, h != 0x13)) return 0x362C;
    cy.run(0x35E8, 0x35EC);
    if (!cy.br(0x35EC, d0 & 4 != 0)) {
        cy.run(0x35EE, 0x35FE);
        st.s(V.materialise_busy, 0);
        R[2] = setb(R[2], d0 & 7);
        if (cy.br(0x35FE, (d0 & 7) < 3)) return 0x362C;
    }
    cy.run(0x3600, 0x3606);
    st.s(V.sfx_owner, R[8]);
    sub.sfx_site(st, cy, 4, 0x3606, 0x3612);
    cy.run(0x3612, 0x3614);
    return 0x362C;
}

pub fn L362C(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    const d0 = R[0];
    cy.run(0x362C, 0x3630);
    var v = (st.rb(o + 6) - 1) & 0xFF;
    st.wb(o + 6, v);
    if (!cy.br(0x3630, v == 0)) {
        cy.run(0x3632, 0x3636);
        pad_glow(st, cy);
        cy.run(0x3636, 0x363A);
        return 0x302E;
    }
    cy.run(0x363A, 0x363E);
    if (!cy.br(0x363E, d0 & 4 == 0)) {
        cy.run(0x3640, 0x3646);
        R[1] = (R[1] + 0x260) & M32;
    }
    cy.run(0x3646, 0x3650);
    st.wb(o + 6, st.rb(o + 0xA));
    v = (st.rb(o + 0xB) - 1) & 0xFF;
    st.wb(o + 0xB, v);
    if (cy.br(0x3650, v == 0)) {
        cy.run(0x366E, 0x3672);
        v = (st.rb(o + 0xA) - 1) & 0xFF;
        st.wb(o + 0xA, v);
        if (cy.br(0x3672, v == 0)) return 0x3698;
        cy.run(0x3674, 0x3678);
        pad_glow(st, cy);
        cy.run(0x3678, 0x367E);
        st.wb(o + 0xB, 0xB);
    } else {
        cy.run(0x3652, 0x3656);
        pad_glow(st, cy);
        cy.run(0x3656, 0x365E);
        const d2 = st.rb(o + 0xB);
        R[2] = setb(R[2], d2);
        if (cy.br(0x365E, d2 & 1 != 0)) return 0x302E;
        cy.run(0x3662, 0x3666);
        if (cy.br(0x3666, d2 & 2 != 0)) {
            back.choose_mat(st, cy); // bsr.b $36E4
            cy.run(0x3694, 0x3698);
            return 0x302E;
        }
        cy.run(0x3668, 0x366E);
        st.wb(o + 0xB, st.rb(o + 0xB) - 1);
    }
    cy.run(0x367E, 0x368A);
    st.wb(o + 6, st.rb(o + 0xA));
    if (cy.br(0x368A, s8(st.rb(o + 0xA)) < 2)) return 0x2EDE;
    cy.run(0x368E, 0x3692);
    return 0x302E;
}

pub fn L3698(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = back.o_of(st);
    cy.run(0x3698, 0x369E);
    if (!cy.br(0x369E, R[8] != st.g(V.sfx_owner))) {
        cy.run(0x36A0, 0x36A2);
        cy.run(0x36A2, 0x36A8);
        sub.sfx_call(st, cy, 0);
        cy.run(0x36A8, 0x36AA);
    }
    cy.run(0x36AA, 0x36AE);
    st.wb(o + 0xB, 0);
    cy.add(20); // bsr.b $3718
    pad_glow(st, cy);
    cy.run(0x36B0, 0x36E4);
    const a2 = BASE + 0x19D2 + s16(st.rw(o + 8));
    R[10] = a2;
    st.wr(a2, 1, 0);
    st.ww(o + 8, 0);
    st.ww(o + 6, 0);
    st.wb(o + 0xB, 5);
    st.wb(o + 0xA, 3);
    const d0 = R[0] & ~@as(i64, 0x0C80);
    R[0] = d0;
    st.ww(o, d0);
    return 0x2DA4;
}

/// $3718 (the caller counts the bsr): the spawn pad's glow strip in colour $19B2[k].
pub fn pad_glow(st: *St, cy: *Cy) void {
    const R = &st.regs;
    const o = back.o_of(st);
    const d0 = R[0];
    cy.add(span(0x3718, 0x3730));
    var d1 = st.rb(o + 0xB) & 3;
    if (!cy.br(0x3730, d1 & 1 == 0)) {
        cy.run(0x3732, 0x3736);
        if (!cy.br(0x3736, d1 & 2 != 0)) {
            cy.run(0x3738, 0x373C);
            if (!cy.br(0x373C, d0 & 4 == 0)) {
                cy.run(0x373E, 0x3742);
                d1 = d0 & 7;
            }
        }
    }
    cy.add(span(0x3742, 0x3768));
    const d2 = st.rb(0x19B2 + d1);
    const a1 = BASE + 0x19D2 + s16(st.rw(o + 8));
    var a2: i64 = 0x19BA;
    const sh1 = st.rd(a1 + 1, 1);
    var a3 = (st.g(V.screen_base) + s16(st.rd(a1 + 0xE, 2))) & M32;
    const n = sh1 & 63;
    for (0..3) |i| {
        cy.add(span(0x3768, 0x3772) + 3 * sh(n, true) + span(0x3778, 0x377A));
        const d5 = if (n < 32) State.shr(st.rl(a2), n) else 0;
        const d6 = if (n < 32) State.shr(st.rl(a2 + 8), n) else 0;
        const d7 = if (n < 32) State.shr(st.rl(a2 + 0x10), n) else 0;
        cy.add(span(0x378C, 0x378E)); // $378C
        const planes = [_]i64{ 3, 2, 1, 0 };
        for (planes) |d4| {
            cy.add(span(0x378E, 0x3790));
            const off = 2 * d4;
            const vals = [_]i64{ d5, d6, d7 };
            if (!cy.br(0x3790, !State.bit(d2, d4))) {
                cy.add(span(0x3792, 0x37AA));
                for (vals, 0..) |v, k| {
                    const p = a3 + 0xA0 * @as(i64, @intCast(k)) + off;
                    st.wr(p, 2, st.rd(p, 2) | (v & 0xFFFF));
                }
            } else {
                cy.add(span(0x37AA, 0x37CC));
                for (vals, 0..) |v, k| {
                    const p = a3 + 0xA0 * @as(i64, @intCast(k)) + off;
                    st.wr(p, 2, st.rd(p, 2) & ~v & 0xFFFF);
                }
            }
            cy.add(span(0x37CC, 0x37D4));
            _ = cy.br(0x37D4, d4 != 0);
        }
        cy.add(span(0x37D6, 0x37D8));
        a2 += 2;
        a3 += 8;
        cy.add(span(0x377A, 0x3784));
        _ = cy.br(0x3784, i != 2);
    }
    cy.add(span(0x3786, 0x378C));
}
