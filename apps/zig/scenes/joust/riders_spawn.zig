// --------------------------------------------------------------------------
// Call 9 continued (the model's a_riders2.py, second half): an inactive rider
// looks for a free spawn pad and starts to materialise on it ($3466..$35BE),
// with its materialise frames $36E4 (the rest is riders_mat.zig).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sub = @import("riders_sub.zig");
const score = @import("riders_score.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;
const setb = State.setb;
const setw = State.setw;

pub fn o_of(st: *St) i64 {
    return st.regs[8] - BASE;
}

// ---------------------------------------------------------------- $3466 inactive / materialise
pub fn L3466(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    var d0 = R[0];
    cy.run(0x3466, 0x346A);
    if (cy.br(0x346A, st.rl(o + 0x14) != 0)) return 0x35C0;
    cy.run(0x346E, 0x3472);
    if (!cy.br(0x3472, d0 & 4 != 0)) {
        cy.run(0x3474, 0x347A);
        if (cy.br(0x347A, st.g(V.materialise_busy) != 0)) return 0x2D94;
        cy.run(0x347E, 0x3486);
        if (!cy.br(0x3486, s8(st.g(V.live_objects)) < 8)) {
            cy.run(0x3488, 0x348E);
            return 0x2D94;
        }
    }
    cy.run(0x348E, 0x34A2);
    const p = (st.g(V.spawn_pad_ptr) + 0x14) & M32;
    st.s(V.spawn_pad_ptr, p);
    if (!cy.br(0x34A2, p != BASE + 0x1A22)) {
        cy.run(0x34A4, 0x34AE);
        st.s(V.spawn_pad_ptr, BASE + 0x19D2);
    }
    cy.run(0x34AE, 0x34B4);
    var a2 = st.g(V.spawn_pad_ptr);
    var d1 = R[1];
    var d2 = R[2];
    while (true) {
        // $34B4: try pad a2
        cy.run(0x34B4, 0x34B6);
        var ok = false;
        if (!cy.br(0x34B6, st.rd(a2, 1) != 0)) {
            cy.run(0x34BA, 0x34C0);
            const a1 = st.rd(a2 + 0x10, 4);
            R[9] = a1;
            if (!cy.br(0x34C0, st.rd(a1, 1) == 0)) {
                cy.run(0x34C4, 0x34CE);
                d1 = 0;
                d2 = 0;
                var s = BASE + 0x0FA4;
                ok = true;
                while (true) {
                    cy.run(0x34CE, 0x34D0);
                    const so = s - BASE;
                    if (!cy.br(0x34D0, s == R[8])) {
                        cy.run(0x34D2, 0x34D6);
                        d1 = setw(d1, st.rw(so));
                        if (!cy.br(0x34D6, st.rw(so) == 0)) {
                            cy.run(0x34D8, 0x34E0);
                            d2 = setw(d2, st.rw(so + 4));
                            if (!cy.br(0x34E0, s16(d2) < s16(st.rd(a2 + 2, 2)))) {
                                cy.run(0x34E2, 0x34E6);
                                if (!cy.br(0x34E6, s16(d2) > s16(st.rd(a2 + 4, 2)))) {
                                    cy.run(0x34E8, 0x34F0);
                                    d2 = setw(d2, st.rw(so + 2));
                                    if (!cy.br(0x34F0, s16(d2) < s16(st.rd(a2 + 6, 2)))) {
                                        cy.run(0x34F2, 0x34F6);
                                        if (cy.br(0x34F6, s16(d2) <= s16(st.rd(a2 + 8, 2)))) {
                                            ok = false;
                                            R[9] = s;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    cy.run(0x34FA, 0x3504);
                    s += 0x4E;
                    if (!cy.br(0x3504, s != BASE + 0x13E8)) {
                        R[9] = s;
                        break;
                    }
                }
            }
        }
        if (ok) break;
        // $359E: next pad
        cy.run(0x359E, 0x35A8);
        a2 = (a2 + 0x14) & M32;
        if (!cy.br(0x35A8, a2 != BASE + 0x1A22)) {
            cy.run(0x35AA, 0x35B0);
            a2 = BASE + 0x19D2;
        }
        cy.run(0x35B0, 0x35B6);
        if (cy.br(0x35B6, a2 != st.g(V.spawn_pad_ptr))) continue;
        R[1] = d1;
        R[2] = d2;
        R[10] = a2;
        cy.run(0x35BA, 0x35C0);
        return 0x2D94;
    }
    // $3506: the pad is free -> materialise here
    cy.run(0x3506, 0x3510);
    const t = d0 & 7;
    d2 = setb(d2, t);
    if (!cy.br(0x3510, t > 3)) {
        cy.run(0x3512, 0x351E);
        st.s(V.materialise_busy, 1);
        if (!cy.br(0x351E, t == 3)) {
            cy.run(0x3520, 0x3526);
            st.s(V.sfx_owner, R[8]);
            sub.sfx_site(st, cy, 4, 0x3526, 0x3532);
        }
    }
    cy.run(0x3532, 0x3574);
    st.s(V.live_objects, st.g(V.live_objects) + 1);
    st.wr(a2, 1, 1);
    st.ww(o + 0xE, 0);
    st.ww(o + 4, st.rd(a2 + 0xA, 2));
    st.ww(o + 2, st.rd(a2 + 0xC, 2));
    st.wb(o + 0xA, 5);
    st.wb(o + 0xB, 0xB);
    st.wb(o + 6, 5);
    st.wb(0x0E64, 1);
    d0 |= 0x200;
    R[0] = d0;
    a2 = (a2 - (BASE + 0x19D2)) & M32;
    st.ww(o + 8, a2);
    R[2] = d2;
    R[10] = a2;
    R[1] = d1;
    choose_mat(st, cy);
    cy.run(0x3578, 0x357E);
    if (!cy.br(0x357E, R[8] != BASE + 0x0FA4)) {
        cy.run(0x3580, 0x3586);
        score.lives_p1(st, cy);
        cy.run(0x3586, 0x358A);
        return 0x302E;
    }
    cy.run(0x358A, 0x3590);
    if (cy.br(0x3590, R[8] != BASE + 0x0FF2)) return 0x302E;
    cy.run(0x3594, 0x359A);
    score.lives_p2(st, cy);
    cy.run(0x359A, 0x359E);
    return 0x302E;
}

/// $36E4 by bsr (counted here): d1 = the materialise frames of this object.
pub fn choose_mat(st: *St, cy: *Cy) void {
    const R = &st.regs;
    cy.add(20);
    cy.run(0x36E4, 0x36EA);
    var d1: i64 = undefined;
    if (!cy.br(0x36EA, R[8] != BASE + 0x0FA4)) {
        cy.run(0x36EC, 0x36F4);
        d1 = st.rl(0x36EE);
    } else {
        cy.run(0x36F4, 0x36FA);
        if (!cy.br(0x36FA, R[8] != BASE + 0x0FF2)) {
            cy.run(0x36FC, 0x3704);
            d1 = st.rl(0x36FE);
        } else {
            cy.run(0x3704, 0x370A);
            d1 = st.rl(0x3706);
        }
    }
    cy.run(0x370A, 0x370E);
    if (!cy.br(0x370E, R[0] & 0x8000 == 0)) {
        cy.run(0x3710, 0x3716);
        d1 += 0x130;
    }
    cy.run(0x3716, 0x3718);
    R[1] = d1 & M32;
}

// ---------------------------------------------------------------- $3718 pad glow
