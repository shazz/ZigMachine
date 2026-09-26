// --------------------------------------------------------------------------
// Call 10 continued ($3E0E..$3FE2, the model's b_coll.py): after the eggs
// (coll_eggs.zig) a player meets the pterodactyls ($1428, 4 x 32 bytes): a
// lance in the open mouth kills it, anything else eats the player.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const Regs = @import("ai_regs.zig").Regs;
const ov = @import("coll_overlap.zig");
const score = @import("flow_score.zig");
const coll = @import("coll.zig");
const St = State.St;
const V = State.V;
const Clk = cyc.Clk;
const BASE = State.BASE;
const s16 = State.s16;
const s32 = State.s32;
const P1 = State.P1;
const RA = ov.RA;
const RB = ov.RB;
const HIT = ov.HIT;

/// $3E0E: the player a0 against the four pterodactyls.
pub fn j3e0e(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x3E0E);
    if (k.b(0x3E12, R.d[0] & 4 == 0)) return j3fda(k);
    k.i(0x3E16);
    if (k.b(0x3E1A, R.d[0] & 0x2000 != 0)) return j3fda(k);
    k.r(0x3E1E, 0x3E30);
    R.a[1] = BASE + RA;
    R.a[2] = BASE + RB;
    var a3: i64 = 0x1428;
    while (true) {
        R.a[3] = BASE + a3;
        k.r(0x3E30, 0x3E34);
        var d1 = st.rw(a3);
        R.setw(1, d1);
        var hit = false;
        if (!k.b(0x3E34, d1 == 0)) {
            k.i(0x3E38);
            if (!k.b(0x3E3C, d1 & 1 != 0)) {
                k.i(0x3E3E);
                if (!k.b(0x3E42, d1 & 0x20 != 0)) {
                    k.r(0x3E44, 0x3EA6);
                    coll.rect_obj(st, RA, a0);
                    var a4 = (st.rl(a3 + 2) + st.g(V.screen_base)) & State.M32;
                    a4 = (a4 + s16(st.rw(a3 + 0x16))) & State.M32;
                    R.a[4] = a4;
                    st.wl(RB, a4);
                    st.wl(RB + 4, st.rl(a3 + 6));
                    st.ww(RB + 8, 3);
                    st.wb(RB + 0x0A, st.rb(a3 + 0x0B));
                    st.wb(RB + 0x0B, st.rb(a3 + 0x19));
                    st.ww(RB + 0x0E, st.rw(a3 + 0x0E));
                    const v = st.rw(a3 + 0x16);
                    const q = @divFloor(v, 0xA0);
                    const rem = @mod(v, 0xA0);
                    d1 = (rem << 16) | q;
                    R.d[1] = d1;
                    st.ww(RB + 0x0E, st.rw(RB + 0x0E) + q);
                    k.i(0x3EA6);
                    ov.overlap_3fe2(st, k);
                    k.i(0x3EAA);
                    hit = k.b(0x3EB0, st.rb(HIT) != 0);
                }
            }
        }
        if (hit) return ptero_hit(st, k, R, a0, a3);
        k.r(0x3EB2, 0x3EBC);
        a3 += 0x20;
        R.a[3] = BASE + a3;
        if (!k.b(0x3EBC, a3 != 0x14A8)) {
            k.i(0x3EC0);
            return j3fda(k);
        }
    }
}

fn ptero_hit(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.r(0x3EC4, 0x3ED0);
    const d2 = (st.rw(a3 + 0x0E) - st.rw(a0 + 4)) & 0xFFFF;
    R.setw(2, d2);
    if (!k.b(0x3ED0, d2 != 0xFFFF)) {
        k.r(0x3ED4, 0x3EDC);
        const d3 = st.rw(a3);
        R.setw(3, d3);
        var kill = false;
        if (!k.b(0x3EDC, d3 & 4 != 0)) {
            k.i(0x3EDE);
            if (!k.b(0x3EE2, R.d[0] & 0x8000 == 0)) {
                k.r(0x3EE6, 0x3EF2);
                const d5 = (st.rw(a3 + 0x0C) - st.rw(a0 + 2)) & 0xFFFF;
                R.setw(5, d5);
                if (!k.b(0x3EF2, s16(d5) > 0x11)) {
                    k.i(0x3EF4);
                    if (!k.b(0x3EF8, d5 > 0xFED1)) {
                        k.i(0x3EFA);
                        kill = true;
                    }
                }
            }
        } else {
            k.i(0x3EFC);
            if (!k.b(0x3F00, R.d[0] & 0x8000 != 0)) {
                k.r(0x3F02, 0x3F12);
                const d5 = (st.rw(a3 + 0x0C) - st.rw(a0 + 2) + 0x0F) & 0xFFFF;
                R.setw(5, d5);
                if (!k.b(0x3F12, s16(d5) < -0x10)) {
                    k.i(0x3F14);
                    kill = !k.b(0x3F18, d5 < 0x130);
                }
            }
        }
        if (kill) return ptero_killed(st, k, R, a0, a3);
    }
    return player_eaten(st, k, R, a0);
}

fn ptero_killed(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.r(0x3F1A, 0x3F2A);
    const d3 = R.d[3] | 0x20;
    R.d[3] = d3;
    st.wb(a3 + 0x1E, 4);
    st.wb(a3 + 0x1F, 4);
    coll.sfx_at(st, k, 0x3F2A, 2);
    k.i(0x3F34);
    k.r(0x3F38, 0x3F50);
    st.ww(a3, d3);
    R.d[0] ^= 0x8000;
    st.ww(a0 + 0x0C, -st.rw(a0 + 0x0C));
    st.ww(a0 + 6, -st.rw(a0 + 6));
    st.wb(a0 + 0x41, st.rb(a0 + 0x41) + 1);
    st.ww(a0, R.d[0]);
    k.i(0x3F50);
    score.score_add(st, k, 0x4250, a0);
    k.i(0x3F56); // bra.w $3FDA
    return j3fda(k);
}

fn player_eaten(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x3F5A, 0x3F82);
    st.s(V.survival_lost, 1);
    R.d[0] |= 0x3000;
    st.wl(a0 + 0x2A, st.rl(a0 + 0x14) - 0x280);
    const sb = st.g(V.screen_base);
    R.d[5] = sb;
    if (!k.b(0x3F82, s32(sb) < s32(st.rl(a0 + 0x2A)))) {
        k.i(0x3F84);
        st.wl(a0 + 0x2A, st.rl(a0 + 0x14));
    }
    k.r(0x3F8A, 0x3F9C);
    st.wb(a0 + 0x33, st.rb(a0 + 0x1D));
    st.wb(a0 + 0x32, 9);
    if (!k.b(0x3F9C, a0 != P1)) {
        k.r(0x3F9E, 0x3FAE);
        st.wb(a0 + 0x1E, 0x19);
        st.wl(a0 + 0x2E, BASE + 0x958C);
    } else {
        k.r(0x3FAE, 0x3FBC);
        st.wb(a0 + 0x1E, 0x20);
        st.wl(a0 + 0x2E, BASE + 0x973C);
    }
    k.r(0x3FBC, 0x3FC4);
    st.wb(a0 + 0x43, st.rb(a0 + 0x43) + 5);
    st.ww(a0, R.d[0]);
    k.i(0x3FC4);
    score.score_add(st, k, 0x4250, a0);
    coll.sfx_at(st, k, 0x3FCA, 5);
    k.r(0x3FD4, 0x3FDA); // addq.w #2,a7; bra.w $393A
}

fn j3fda(k: *Clk) void {
    k.r(0x3FDA, 0x3FE2); // nop; jmp $393A
}
