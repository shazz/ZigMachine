// --------------------------------------------------------------------------
// Call 4 continued: $2B0C, a flying egg against the platforms (the model's
// a_eggs.egg_land, _landed, _bumped). Returns the label to continue at:
// $270A after its rts, or $293E when it drops its return address
// (adda.w #4,a7; bra.w $293E).
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const overlap = @import("riders_overlap.zig");
const St = State.St;
const V = State.V;
const Cy = cyc.Cy;
const BASE = State.BASE;
const M32 = State.M32;
const s8 = State.s8;
const s16 = State.s16;

fn o_of(st: *St) i64 {
    return st.regs[8] - BASE;
}

pub fn egg_land(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2B0C, 0x2B1A);
    var a1: i64 = 0x1822;
    var a2: i64 = 0x0D38;
    var d3: i64 = 0;
    while (true) {
        cy.run(0x2B1A, 0x2B1C);
        const on = st.rb(a2);
        a2 += 1;
        var hit = false;
        if (!cy.br(0x2B1C, on == 0)) {
            cy.run(0x2B20, 0x2B2A);
            d3 = (st.rw(o + 0x22) - 0xC) & 0xFFFF;
            if (!cy.br(0x2B2A, s16(d3) < s16(st.rw(a1)))) {
                cy.run(0x2B2E, 0x2B32);
                if (!cy.br(0x2B32, s16(d3) > s16(st.rw(a1 + 2)))) {
                    cy.run(0x2B36, 0x2B3E);
                    d3 = st.rw(o + 0x20);
                    if (!cy.br(0x2B3E, s16(d3) < s16(st.rw(a1 + 4)))) {
                        cy.run(0x2B42, 0x2B46);
                        hit = !cy.br(0x2B46, s16(d3) > s16(st.rw(a1 + 6)));
                    }
                }
            }
        }
        if (hit) {
            R[3] = d3;
            R[9] = BASE + a1;
            R[10] = BASE + a2;
            return landed(st, cy, a1, a2);
        }
        cy.run(0x2BDA, 0x2BE4);
        a1 += 8;
        if (!cy.br(0x2BE4, a1 != 0x1862)) break;
    }
    R[3] = d3;
    R[9] = BASE + a1;
    R[10] = BASE + a2;
    // no surface: pixel test against every platform piece that is drawn
    cy.run(0x2BE8, 0x2BEE);
    var a3: i64 = 0x1A42;
    while (true) {
        cy.run(0x2BEE, 0x2C22);
        st.wl(0x0E0E, st.rl(o + 0x2A));
        st.wl(0x0E12, st.rl(o + 0x2E));
        st.ww(0x0E16, 2);
        st.wb(0x0E18, st.rb(o + 0x33));
        st.wb(0x0E19, st.rb(o + 0x32));
        st.ww(0x0E1C, st.rw(o + 0x22));
        const a4 = st.rl(a3);
        a3 += 4;
        R[9] = BASE + 0x0E0E;
        R[10] = BASE + 0x0E1E;
        R[12] = a4;
        if (!cy.br(0x2C22, st.rd(a4, 1) != 0)) {
            cy.run(0x2C24, 0x2C2C);
            a3 += 0xC;
        } else {
            cy.run(0x2C2C, 0x2C5C);
            a3 += 1;
            st.wb(0x0E29, st.rb(a3));
            a3 += 1;
            st.ww(0x0E26, st.rw(a3));
            a3 += 2;
            st.wl(0x0E22, st.rl(a3));
            a3 += 4;
            st.wl(0x0E1E, st.rl(a3));
            st.wb(0x0E28, 0);
            const sb = st.g(V.screen_base);
            st.wl(0x0E1E, (st.rl(0x0E1E) + sb) & M32);
            var d1 = st.rl(a3);
            a3 += 4;
            const q = @divFloor(d1, 0xA0);
            const r = @mod(d1, 0xA0);
            d1 = if (q > 0xFFFF) d1 else (r << 16) | q;
            R[1] = d1;
            st.ww(0x0E2C, d1);
            overlap.overlap(st, cy);
            cy.run(0x2C5C, 0x2C62);
            if (cy.br(0x2C62, st.g(V.coll_hit) != 0)) {
                R[11] = BASE + a3;
                return bumped(st, cy);
            }
        }
        cy.run(0x2C64, 0x2C6A);
        if (!cy.br(0x2C6A, a3 != 0x1AC2)) break;
    }
    R[11] = BASE + a3;
    cy.run(0x2C6C, 0x2C6E);
    return 0x270A;
}

/// $2B4A: the egg rests on surface a1.
fn landed(st: *St, cy: *Cy, a1: i64, a2: i64) u32 {
    const o = o_of(st);
    cy.run(0x2B4A, 0x2B72);
    st.s(V.tmp_sprite_e5e, st.rl(0x2B4C));
    st.wb(o + 0x1E, 0x22);
    st.wb(a2 - 1, 1);
    st.ww(0x0E5C, st.rw(a1) + 0xC);
    if (cy.br(0x2B72, s16(st.rw(o + 0x26)) < 0)) {
        cy.run(0x2BD8, 0x2BDA);
        return 0x270A;
    }
    cy.run(0x2B74, 0x2B78);
    var v = (st.rb(o + 0x28) - 1) & 0xFF;
    st.wb(o + 0x28, v);
    if (!cy.br(0x2B78, v != 0)) {
        cy.run(0x2B7A, 0x2B84);
        st.wb(o + 0x28, 4);
        const ex = st.rw(o + 0x24);
        if (!cy.br(0x2B84, ex == 0)) {
            if (cy.br(0x2B86, s16(ex) < 0)) {
                cy.run(0x2B8E, 0x2B92);
                st.ww(o + 0x24, ex + 1);
            } else {
                cy.run(0x2B88, 0x2B8E);
                st.ww(o + 0x24, ex - 1);
            }
        }
    }
    cy.run(0x2B92, 0x2B9C);
    st.wb(o + 0x29, 6);
    if (!cy.br(0x2B9C, st.rw(o + 0x26) == 0)) {
        cy.run(0x2B9E, 0x2BAA);
        v = -((st.rw(o + 0x26) - 1) & 0xFFFF) & 0xFFFF;
        st.ww(o + 0x26, v);
        if (cy.br(0x2BAA, v != 0)) {
            cy.run(0x2BD8, 0x2BDA);
            return 0x270A;
        }
    }
    cy.run(0x2BAC, 0x2BB0);
    if (cy.br(0x2BB0, st.rw(o + 0x24) != 0)) {
        cy.run(0x2BD8, 0x2BDA);
        return 0x270A;
    }
    cy.run(0x2BB2, 0x2BB8);
    var special = false;
    if (!cy.br(0x2BB8, st.rw(o + 0x22) != 0x65)) {
        cy.run(0x2BBA, 0x2BC0);
        const x = s16(st.rw(o + 0x20));
        if (!cy.br(0x2BC0, x < 0x10E)) {
            cy.run(0x2BC2, 0x2BC8);
            special = !cy.br(0x2BC8, x > 0x118);
        }
    }
    if (special) {
        cy.run(0x2BCA, 0x2BD2);
        st.ww(o + 0x24, 0xFFFF);
        return 0x270A;
    }
    cy.run(0x2BD2, 0x2BDA);
    st.wb(o + 0x1E, 0x21);
    return 0x270A;
}

/// $2C6E: the egg hit a platform piece: bounce off the edge boxes $1862.
fn bumped(st: *St, cy: *Cy) u32 {
    const R = &st.regs;
    const o = o_of(st);
    cy.run(0x2C6E, 0x2C7C);
    st.wb(o + 0x1E, 0x22);
    var a1: i64 = 0x1862;
    var d3: i64 = 0;
    while (true) {
        cy.run(0x2C7C, 0x2C84);
        d3 = (st.rw(o + 0x22) - 7) & 0xFFFF;
        var miss = true;
        if (!cy.br(0x2C84, s16(d3) < s16(st.rw(a1)))) {
            cy.run(0x2C88, 0x2C8C);
            if (!cy.br(0x2C8C, s16(d3) > s16(st.rw(a1 + 2)))) {
                cy.run(0x2C90, 0x2C98);
                d3 = st.rw(o + 0x20);
                if (!cy.br(0x2C98, s16(d3) < s16(st.rw(a1 + 4)))) {
                    cy.run(0x2C9C, 0x2CA0);
                    miss = cy.br(0x2CA0, s16(d3) > s16(st.rw(a1 + 6)));
                }
            }
        }
        if (!miss) break;
        cy.run(0x2D7A, 0x2D86);
        a1 += 0xC;
        if (!cy.br(0x2D86, a1 != 0x19B2)) {
            R[3] = d3;
            R[9] = BASE + a1;
            cy.run(0x2D8A, 0x2D8C);
            return 0x270A;
        }
    }
    cy.run(0x2CA4, 0x2CB2);
    st.ww(o + 0x26, 0);
    st.wb(o + 0x29, 6);
    const b8 = s8(st.rb(a1 + 8));
    if (!cy.br(0x2CB2, b8 == 0)) {
        if (cy.br(0x2CB4, b8 < 0)) {
            cy.run(0x2CC8, 0x2CDE);
            st.s(V.tmp_sprite_e5e, st.rl(0x2CCA));
            st.ww(0x0E5C, st.rw(a1) + 5);
        } else {
            cy.run(0x2CB6, 0x2CC8);
            st.s(V.tmp_sprite_e5e, st.rl(0x2CB8));
            st.ww(0x0E5C, st.rw(0x0E5C) + 4);
        }
    }
    cy.run(0x2CDE, 0x2CE2);
    const b9 = s8(st.rb(a1 + 9));
    if (!cy.br(0x2CE2, b9 == 0)) {
        const ex = st.rw(o + 0x24);
        if (!cy.br(0x2CE6, b9 < 0)) {
            cy.run(0x2CE8, 0x2CFC);
            st.s(V.tmp_sprite_e5e, st.rl(0x2CEA));
            var v = (4 + st.rw(o + 0x20)) & 0xFFFF;
            if (!cy.br(0x2CFC, s16(v) <= 0x13F)) {
                cy.run(0x2CFE, 0x2D02);
                v = (v - 0x140) & 0xFFFF;
            }
            d3 = v;
            cy.run(0x2D02, 0x2D0C);
            st.ww(0x0E5A, v);
            if (!cy.br(0x2D0C, ex == 0)) {
                if (cy.br(0x2D0E, s16(ex) > 0)) {
                    cy.run(0x2D1A, 0x2D20);
                    d3 = 4;
                    if (!cy.br(0x2D20, ex == 4)) {
                        cy.run(0x2D22, 0x2D28);
                        st.ww(o + 0x24, ex + 1);
                    }
                } else {
                    cy.run(0x2D10, 0x2D1A);
                    st.ww(o + 0x24, -((ex + 1) & 0xFFFF));
                }
            }
        } else {
            cy.run(0x2D28, 0x2D3A);
            st.s(V.tmp_sprite_e5e, st.rl(0x2D2A));
            var v = (st.rw(o + 0x20) - 4) & 0xFFFF;
            if (!cy.br(0x2D3A, s16(v) >= 0)) {
                cy.run(0x2D3C, 0x2D40);
                v = (v + 0x140) & 0xFFFF;
            }
            d3 = v;
            cy.run(0x2D40, 0x2D4A);
            st.ww(0x0E5A, v);
            if (!cy.br(0x2D4A, ex == 0)) {
                if (cy.br(0x2D4C, s16(ex) > 0)) {
                    cy.run(0x2D5C, 0x2D64);
                    st.ww(o + 0x24, -((ex - 1) & 0xFFFF));
                } else {
                    cy.run(0x2D4E, 0x2D54);
                    d3 = 0xFFFFFFFC;
                    if (!cy.br(0x2D54, ex == 0xFFFC)) {
                        cy.run(0x2D56, 0x2D5C);
                        st.ww(o + 0x24, ex - 1);
                    }
                }
            }
        }
    }
    cy.run(0x2D64, 0x2D7A);
    const a2 = BASE + 0x0D38 + s16(st.rw(a1 + 0xA));
    st.wr(a2, 1, 1);
    R[3] = d3;
    R[9] = BASE + a1;
    R[10] = a2;
    return 0x293E;
}
