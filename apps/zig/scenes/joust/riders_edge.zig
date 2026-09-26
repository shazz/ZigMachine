// --------------------------------------------------------------------------
// Call 9 continued (the model's a_riders2.py, first half): the platform edge
// bumps $3126, sinking in the lava $3290, and walking $32F0.
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
const setw = State.setw;

fn o_of(st: *St) i64 {
    return st.regs[8] - BASE;
}

// ---------------------------------------------------------------- $3126 edge bumps
pub fn L3126(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    var d0 = R[0];
    cy.run(0x3126, 0x312E);
    var a1: i64 = 0x1862;
    var d3: i64 = 0;
    while (true) {
        cy.run(0x312E, 0x3134);
        const y = st.rw(o + 4);
        d3 = y;
        var miss = true;
        if (!cy.br(0x3134, s16(y) < s16(st.rw(a1)))) {
            cy.run(0x3138, 0x313C);
            if (!cy.br(0x313C, s16(y) > s16(st.rw(a1 + 2)))) {
                cy.run(0x3140, 0x3148);
                const x = st.rw(o + 2);
                d3 = x;
                if (!cy.br(0x3148, s16(x) < s16(st.rw(a1 + 4)))) {
                    cy.run(0x314C, 0x3150);
                    miss = cy.br(0x3150, s16(x) > s16(st.rw(a1 + 6)));
                }
            }
        }
        if (!miss) break;
        cy.run(0x3274, 0x3280);
        a1 += 0xC;
        if (cy.br(0x3280, a1 != 0x19B2)) continue;
        cy.run(0x3284, 0x3290);
        d0 &= ~@as(i64, 0x4000);
        R[0] = d0;
        st.ww(o, d0);
        R[3] = d3;
        R[9] = BASE + a1;
        return 0x2DA4;
    }
    // a hit on edge box a1
    cy.run(0x3154, 0x3158);
    const b8 = s8(st.rb(a1 + 8));
    if (!cy.br(0x3158, b8 == 0)) {
        if (cy.br(0x315A, b8 < 0)) {
            cy.run(0x317A, 0x317E);
            if (cy.br(0x317E, st.rw(o + 6) != 0)) {} else {
                cy.run(0x3180, 0x3184);
                if (cy.br(0x3184, d0 & 0x8000 != 0)) {
                    cy.run(0x318E, 0x3194);
                    st.ww(o + 6, 1);
                } else {
                    cy.run(0x3186, 0x318E);
                    st.ww(o + 6, 0xFFFF);
                }
            }
            cy.run(0x3194, 0x319C);
            st.ww(o + 4, st.rw(a1) - 2);
        } else {
            cy.run(0x315C, 0x3164);
            st.ww(o + 4, st.rw(o + 4) + 4);
            if (!cy.br(0x3164, st.rb(a1 + 9) != 0)) {
                cy.run(0x3166, 0x3170);
                d3 = setw(d3, d0 & 3);
                if (!cy.br(0x3170, d0 & 3 != 3)) {
                    cy.run(0x3172, 0x317A);
                    st.wb(o + 0x49, 0xB);
                }
            }
        }
        cy.run(0x319C, 0x31A6);
        st.ww(o + 8, 0);
        st.wb(o + 0xB, 5);
    }
    cy.run(0x31A6, 0x31AA);
    const b9 = s8(st.rb(a1 + 9));
    if (!cy.br(0x31AA, b9 == 0)) {
        const neg = cy.br(0x31AE, b9 < 0);
        const base: i64 = if (neg) 0x3200 else 0x31B0;
        cy.run(base, base + 8);
        st.wb(o + 0x4B, st.rb(o + 0x4B) + 1);
        const vy = st.rw(o + 8);
        if (!cy.br(base + 8, s16(vy) >= 0)) {
            cy.run(base + 0xA, base + 0x12);
            d3 = setw(d3, vy);
            st.ww(o + 4, st.rw(o + 4) - vy);
        }
        st.ww(o + 8, 0);
        st.wb(o + 0xB, 5);
        const vx = st.rw(o + 6);
        if (!neg) {
            cy.run(0x31C2, 0x31D6);
            var v = (4 + st.rw(o + 2)) & 0xFFFF;
            if (!cy.br(0x31D6, s16(v) <= 0x13F)) {
                cy.run(0x31D8, 0x31DC);
                v = (v - 0x140) & 0xFFFF;
            }
            d3 = v;
            cy.run(0x31DC, 0x31E4);
            st.ww(o + 2, v);
            if (!cy.br(0x31E4, vx == 0)) {
                if (cy.br(0x31E6, s16(vx) > 0)) {
                    cy.run(0x31F2, 0x31F8);
                    d3 = 4;
                    if (!cy.br(0x31F8, vx == 4)) {
                        cy.run(0x31FA, 0x3200);
                        st.ww(o + 6, vx + 1);
                    }
                } else {
                    cy.run(0x31E8, 0x31F2);
                    st.ww(o + 6, -((vx + 1) & 0xFFFF));
                }
            }
        } else {
            cy.run(0x3212, 0x3224);
            var v = (st.rw(o + 2) - 4) & 0xFFFF;
            if (!cy.br(0x3224, s16(v) >= 0)) {
                cy.run(0x3226, 0x322A);
                v = (v + 0x140) & 0xFFFF;
            }
            d3 = v;
            cy.run(0x322A, 0x3232);
            st.ww(o + 2, v);
            if (!cy.br(0x3232, vx == 0)) {
                if (cy.br(0x3234, s16(vx) > 0)) {
                    cy.run(0x3244, 0x324C);
                    st.ww(o + 6, -((vx - 1) & 0xFFFF));
                } else {
                    cy.run(0x3236, 0x323C);
                    d3 = 0xFFFFFFFC;
                    if (!cy.br(0x323C, vx == 0xFFFC)) {
                        cy.run(0x323E, 0x3244);
                        st.ww(o + 6, vx - 1);
                    }
                }
            }
        }
    }
    cy.run(0x324C, 0x3268);
    d0 &= ~@as(i64, 0x4000);
    R[0] = d0;
    st.wb(0x0E64, st.rb(o + 0x1C));
    R[1] = st.rl(o + 0x18);
    const a2 = BASE + 0x0D38 + s16(st.rw(a1 + 0xA));
    R[3] = d3;
    R[9] = BASE + a1;
    R[10] = a2;
    if (!cy.br(0x3268, st.rd(a2, 1) == 0)) {
        cy.run(0x326C, 0x3274);
        st.wr(a2, 1, 1);
    }
    return 0x302E;
}

// ---------------------------------------------------------------- $3290 sinking in the lava
pub fn L3290(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x3290, 0x32C2);
    st.ww(o + 4, st.rw(o + 4) + 1);
    st.s(V.tmp_sprite_e5e, st.rl(o + 0x18));
    st.wb(0x0E62, st.rb(o + 0x1D));
    st.wb(0x0E64, st.rb(o + 0x1C));
    const d1 = (st.rl(o + 0x14) + 0xA0) & M32;
    R[1] = d1;
    st.s(V.tmp_ptr_e56, d1);
    if (cy.br(0x32C2, d1 < st.g(V.lava_top))) return 0x30E6;
    cy.run(0x32C6, 0x32CA);
    sub.erase(st, cy);
    cy.run(0x32CA, 0x32D0);
    if (!cy.br(0x32D0, R[8] > BASE + 0x0FF2)) {
        cy.run(0x32D2, 0x32DE);
        st.s(V.survival_lost, 1);
        st.wb(o + 0x43, st.rb(o + 0x43) + 5);
        cy.run(0x32DE, 0x32E4); // jsr $4250.l
        score.score_add_entry(st, cy);
    }
    cy.run(0x32E4, 0x32EA); // jsr $1fba.l
    score.lose_life(st, cy);
    cy.run(0x32EA, 0x32F0); // jmp $2d94.l
    return 0x2D94;
}

// ---------------------------------------------------------------- $32F0 walking
pub fn L32F0(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    var d0 = R[0];
    cy.run(0x32F0, 0x32F4);
    if (!cy.br(0x32F4, d0 & 0x800 == 0)) {
        cy.run(0x32F6, 0x32FA);
        if (!cy.br(0x32FA, d0 & 0x400 != 0)) {
            cy.run(0x32FC, 0x3324); // take off: bra.w $2E88
            d0 = (d0 & ~@as(i64, 0x200) & ~@as(i64, 0x400)) | 0x40;
            R[0] = d0;
            st.ww(o + 4, st.rw(o + 4) - 1);
            st.ww(o + 8, 0);
            st.wb(o + 0xB, 5);
            st.ww(o + 0xE, 0);
            return 0x2E88;
        }
    } else {
        cy.run(0x3324, 0x3328);
        d0 &= ~@as(i64, 0x400);
        R[0] = d0;
    }
    cy.run(0x3328, 0x3332);
    const tv = st.rw(o + 0xC);
    R[1] = tv;
    if (!cy.br(0x3332, tv != st.rw(o + 6))) {
        cy.run(0x3334, 0x333C);
        st.wb(o + 0xA, 3);
    } else {
        cy.run(0x333C, 0x3340);
        const v = (st.rb(o + 0xA) - 1) & 0xFF;
        st.wb(o + 0xA, v);
        if (!cy.br(0x3340, v != 0)) {
            cy.run(0x3342, 0x3352);
            st.wb(o + 0xA, 3);
            const vx = st.rw(o + 6);
            if (cy.br(0x3352, s16(tv) < s16(vx))) {
                cy.run(0x335A, 0x335E);
                st.ww(o + 6, vx - 1);
            } else {
                cy.run(0x3354, 0x335A);
                st.ww(o + 6, vx + 1);
            }
        }
    }
    cy.run(0x335E, 0x3362);
    const vx = st.rw(o + 6);
    if (!cy.br(0x3362, vx != 0)) {
        cy.run(0x3364, 0x336C);
        st.ww(o + 0xE, 0);
        return 0x2EB6;
    }
    cy.run(0x336C, 0x3370);
    if (cy.br(0x3370, s16(vx) < 0)) {
        cy.run(0x3378, 0x337C);
        d0 &= ~@as(i64, 0x8000);
    } else {
        cy.run(0x3372, 0x3378);
        d0 |= 0x8000;
    }
    R[0] = d0;
    cy.run(0x337C, 0x338A);
    const d1 = st.rw(o + 0xC);
    const d2 = st.rw(o + 6) ^ d1;
    R[1] = setw(R[1], d1);
    R[2] = setw(R[2], d2);
    if (!cy.br(0x338A, d2 & 0x8000 == 0)) {
        cy.run(0x338C, 0x3396);
        st.ww(o + 0xE, 4);
        return 0x2EB6;
    }
    cy.run(0x3396, 0x33A0);
    const ws = (st.rw(o + 0xE) + 1) & 0xFFFF;
    st.ww(o + 0xE, ws);
    if (!cy.br(0x33A0, R[8] >= BASE + 0x1040)) {
        cy.run(0x33A2, 0x33A8);
        if (!cy.br(0x33A8, ws & 1 == 0)) {
            cy.run(0x33AA, 0x33B0);
            if (!cy.br(0x33B0, ws & 2 == 0)) {
                sub.sfx_site(st, cy, 0xD, 0x33B2, 0x33BE);
                cy.run(0x33BE, 0x33C0);
            } else {
                cy.run(0x33C0, 0x33C8);
                if (!cy.br(0x33C8, s16(st.g(V.sfx_prio)) < 0xD)) {
                    cy.run(0x33CA, 0x33D2);
                    st.s(V.sfx_prio, 0x10);
                    sub.sfx_site(st, cy, 0xF, 0x33D2, 0x33DE);
                }
            }
        }
    }
    cy.run(0x33DE, 0x33E4);
    R[1] = 4;
    if (cy.br(0x33E4, ws != 4)) return 0x2EB6;
    cy.run(0x33E8, 0x33F0);
    st.ww(o + 0xE, 0);
    return 0x2EB6;
}
