// --------------------------------------------------------------------------
// Call 10 continued (the model's b_coll.py): two riders overlap -- the joust
// $3A88: equal heights bounce (SFX 11), else the higher one wins and only a
// player unseats; $4188 the loser falls off, $41EE they are pushed apart.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const Regs = @import("ai_regs.zig").Regs;
const score = @import("flow_score.zig");
const St = State.St;
const V = State.V;
const Clk = cyc.Clk;
const BASE = State.BASE;
const s16 = State.s16;
const s32 = State.s32;
const P1 = State.P1;
const P2 = State.P2;
const back = @import("coll.zig");

/// $3A88: the two riders overlap. True when a0 was unseated (-> $3C8A).
pub fn joust(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) bool {
    k.r(0x3A88, 0x3A92);
    const y3 = st.rw(a3 + 4);
    R.d[2] = y3;
    const y0 = st.rw(a0 + 4);
    if (k.b(0x3A92, s16(y3) < s16(y0))) return a3_higher(st, k, R, a0, a3);
    if (k.b(0x3A94, s16(y3) > s16(y0))) {
        a0_higher(st, k, R, a0, a3);
        return false;
    }
    back.sfx_at(st, k, 0x3A98, 11);
    k.i(0x3AA2); // addq.w #2,a7
    bounce_tail(st, k, R, a0, a3);
    return false;
}

/// $3AA4: bsr $41EE; bra.w $3A10.
pub fn bounce_tail(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.i(0x3AA4);
    bounce_41ee(st, k, R, a0, a3);
    k.i(0x3AA8);
}

pub fn a3_higher(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) bool {
    k.i(0x3AAC);
    if (k.b(0x3AB0, R.d[0] & 4 == 0)) {
        // $3B2A: a0 is an enemy: both bounce away vertically
        k.i(0x3B2A);
        if (!k.b(0x3B2E, st.rw(a0 + 8) & 0x8000 == 0)) {
            k.i(0x3B30);
            st.ww(a0 + 8, -st.rw(a0 + 8));
        }
        k.i(0x3B34);
        if (!k.b(0x3B38, s16(st.rw(a3 + 8)) <= 0)) {
            k.r(0x3B3C, 0x3B44);
            st.ww(a3 + 8, -st.rw(a3 + 8));
        }
        bounce_tail(st, k, R, a0, a3);
        return false;
    }
    k.i(0x3AB4);
    if (!k.b(0x3AB8, R.d[1] & 4 == 0)) {
        k.r(0x3ABA, 0x3ACC);
        st.s(V.survival_lost, 1);
        st.wb(a3 + 0x42, st.rb(a3 + 0x42) + 5);
        if (!k.b(0x3ACC, st.g(V.cd_gladiator) != 0)) {
            k.i(0x3ACE);
            if (!k.b(0x3AD4, st.g(V.team_flag) != 0)) {
                k.r(0x3AD6, 0x3AE6);
                st.s(V.team_flag, 2);
                st.wb(a3 + 0x41, st.rb(a3 + 0x41) + 2);
                st.wb(a3 + 0x42, st.rb(a3 + 0x42) + 5);
            }
        }
    }
    k.i(0x3AE6);
    if (!k.b(0x3AEE, st.g(V.players) != 1)) {
        k.i(0x3AF0);
        st.s(V.survival_lost, 1);
    }
    k.i(0x3AF8); // bsr.w $4188: a0 unseated
    unseat_4188(st, k, R, a0);
    k.i(0x3AFC);
    score.score_add(st, k, 0x4262, P1);
    k.i(0x3B02);
    score.score_add(st, k, 0x4256, P2);
    back.sfx_at(st, k, 0x3B08, 5);
    k.i(0x3B12);
    k.i(0x3B14);
    bounce_41ee(st, k, R, a0, a3);
    k.i(0x3B18);
    if (!k.b(0x3B1C, s16(st.rw(a3 + 8)) <= 0)) {
        k.i(0x3B1E);
        st.ww(a3 + 8, -st.rw(a3 + 8));
    }
    k.r(0x3B22, 0x3B2A);
    st.ww(a0, R.d[0]);
    return true;
}

pub fn a0_higher(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.i(0x3B44);
    if (k.b(0x3B48, R.d[0] & 4 == 0)) {
        // $3C70: a0 is an enemy
        k.i(0x3C70);
        if (!k.b(0x3C74, st.rw(a3 + 8) & 0x8000 == 0)) {
            k.i(0x3C76);
            st.ww(a3 + 8, -st.rw(a3 + 8));
        }
        k.i(0x3C7A);
        if (!k.b(0x3C7E, s16(st.rw(a0 + 8)) <= 0)) {
            k.r(0x3C82, 0x3C8A);
            st.ww(a0 + 8, -st.rw(a0 + 8));
        }
        return bounce_tail(st, k, R, a0, a3);
    }
    k.i(0x3B4C);
    if (!k.b(0x3B50, R.d[1] & 4 == 0)) {
        // both players: a3 unseated
        k.r(0x3B52, 0x3B56); // exg d0,d1; exg a0,a3
        var t = R.d[0];
        R.d[0] = R.d[1];
        R.d[1] = t;
        k.i(0x3B56);
        unseat_4188(st, k, R, a3);
        k.r(0x3B5A, 0x3B70); // exg, exg, move.b #1,$d44, addq.b #5,$42(a0), tst.b $d43
        t = R.d[0];
        R.d[0] = R.d[1];
        R.d[1] = t;
        st.s(V.survival_lost, 1);
        st.wb(a0 + 0x42, st.rb(a0 + 0x42) + 5);
        if (!k.b(0x3B70, st.g(V.cd_gladiator) != 0)) {
            k.i(0x3B72);
            if (!k.b(0x3B78, st.g(V.team_flag) != 0)) {
                k.r(0x3B7A, 0x3B8A);
                st.s(V.team_flag, 1);
                st.wb(a0 + 0x41, st.rb(a0 + 0x41) + 2);
                st.wb(a0 + 0x42, st.rb(a0 + 0x42) + 5);
            }
        }
        return j3b8a(st, k, R, a0, a3);
    }
    kill_enemy(st, k, R, a0, a3);
    return j3b8a(st, k, R, a0, a3);
}

pub fn j3b8a(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.i(0x3B8A);
    score.score_add(st, k, 0x4262, P1);
    k.i(0x3B90);
    score.score_add(st, k, 0x4256, P2);
    back.sfx_at(st, k, 0x3B96, 5);
    k.i(0x3BA0);
    k.i(0x3BA2);
    bounce_41ee(st, k, R, a0, a3);
    k.i(0x3BA6);
    if (!k.b(0x3BAA, s16(st.rw(a0 + 8)) <= 0)) {
        k.i(0x3BAC);
        st.ww(a0 + 8, -st.rw(a0 + 8));
    }
    k.r(0x3BB0, 0x3BB8);
    st.ww(a3, R.d[1]);
}

/// $3BB8: player a0 unseats enemy a3: points, and the rider becomes an egg.
pub fn kill_enemy(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.r(0x3BB8, 0x3BC4);
    const d1 = R.d[1] | 0x3000;
    R.d[1] = d1;
    if (!k.b(0x3BC4, d1 & 1 == 0)) {
        k.i(0x3BC6);
        st.wb(a0 + 0x42, st.rb(a0 + 0x42) + 5);
        k.i(0x3BCA);
        if (!k.b(0x3BCE, d1 & 2 == 0)) {
            k.r(0x3BD0, 0x3BD6);
            st.wb(a0 + 0x41, st.rb(a0 + 0x41) + 1);
        }
    } else {
        k.r(0x3BD6, 0x3BDE);
        st.wb(a0 + 0x42, st.rb(a0 + 0x42) + 7);
        st.wb(a0 + 0x43, st.rb(a0 + 0x43) + 5);
    }
    k.i(0x3BDE);
    score.score_add(st, k, 0x4250, a0);
    back.sfx_at(st, k, 0x3BE4, 5);
    k.i(0x3BEE);
    k.r(0x3BF0, 0x3C60);
    st.ww(a3 + 0x20, st.rw(a3 + 2));
    st.ww(a3 + 0x22, st.rw(a3 + 4) + 5);
    st.ww(a3 + 0x24, st.rw(a3 + 6));
    st.ww(a3 + 0x26, st.rw(a3 + 8));
    st.wb(a3 + 0x29, 6);
    st.wb(a3 + 0x28, 4);
    st.wl(a3 + 0x2A, st.rl(a3 + 0x14) + 0x3C0);
    st.wb(a3 + 0x33, st.rb(a3 + 0x1D));
    st.wb(a3 + 0x1F, 0xA6);
    const w = st.g(V.wave);
    R.setb(6, w);
    st.wb(a3 + 0x1F, 0xA6 - w);
    st.wl(a3 + 0x2E, BASE + 0x8CFC);
    st.wb(a3 + 0x32, 7);
    st.wb(a3 + 0x1E, 0x23);
    var t = d1 & 3;
    st.wb(a3 + 0x34, t);
    if (!k.b(0x3C60, t == 3)) {
        k.i(0x3C62);
        t += 1;
    }
    k.r(0x3C66, 0x3C70); // bset #7,$34(a3); bra.w $3B8A
    st.wb(a3 + 0x34, t | 0x80);
}

/// $4188: rider a (flags in d0) falls off: b13 riderless + b12, the aux image
/// becomes the falling-rider sparks (+$2A/$2E/$32/$33, timer +$1E), 50 points
/// digit. Leaves d5 = screen_base.
pub fn unseat_4188(st: *St, k: *Clk, R: *Regs, a: i64) void {
    k.r(0x4188, 0x41AC);
    R.d[0] |= 0x3000;
    st.wb(a + 0x35, 0);
    st.wl(a + 0x2A, st.rl(a + 0x14) - 0x280);
    const sb = st.g(V.screen_base);
    R.d[5] = sb;
    if (!k.b(0x41AC, s32(sb) < s32(st.rl(a + 0x2A)))) {
        k.i(0x41AE);
        st.wl(a + 0x2A, st.rl(a + 0x14));
    }
    k.r(0x41B4, 0x41C6);
    st.wb(a + 0x33, st.rb(a + 0x1D));
    st.wb(a + 0x32, 9);
    if (!k.b(0x41C6, a != P1)) {
        k.r(0x41C8, 0x41D8);
        st.wb(a + 0x1E, 0x19);
        st.wl(a + 0x2E, BASE + 0x958C);
    } else {
        k.r(0x41D8, 0x41E6);
        st.wb(a + 0x1E, 0x20);
        st.wl(a + 0x2E, BASE + 0x973C);
    }
    k.r(0x41E6, 0x41EE); // nop, addq.b #5,$43(a0), rts
    st.wb(a + 0x43, st.rb(a + 0x43) + 5);
}

/// $41EE: push the two riders apart in x (facing b15 in d0/d1, vx signs),
/// write both flags.
pub fn bounce_41ee(st: *St, k: *Clk, R: *Regs, a0: i64, a3: i64) void {
    k.r(0x41EE, 0x41FA);
    const d3 = (st.rw(a0 + 2) - st.rw(a3 + 2)) & 0xFFFF;
    R.setw(3, d3);
    var left = k.b(0x41FA, d3 >= 0xFFEE);
    if (!left) {
        k.i(0x41FC);
        left = k.b(0x4200, s16(d3) >= 0x12E);
    }
    if (!left) {
        k.r(0x4202, 0x420E);
        R.d[0] |= 0x8000;
        R.d[1] &= ~@as(i64, 0x8000);
        if (!k.b(0x420E, st.rw(a0 + 6) & 0x8000 == 0)) {
            k.i(0x4210);
            st.ww(a0 + 6, -st.rw(a0 + 6));
        }
        k.i(0x4214);
        if (!k.b(0x4218, s16(st.rw(a3 + 6)) <= 0)) {
            k.i(0x421A);
            st.ww(a3 + 6, -st.rw(a3 + 6));
        }
        k.r(0x421E, 0x4228);
    } else {
        k.r(0x4228, 0x4234);
        R.d[0] &= ~@as(i64, 0x8000);
        R.d[1] |= 0x8000;
        if (!k.b(0x4234, s16(st.rw(a0 + 6)) <= 0)) {
            k.i(0x4236);
            st.ww(a0 + 6, -st.rw(a0 + 6));
        }
        k.i(0x423A);
        if (!k.b(0x423E, st.rw(a3 + 6) & 0x8000 == 0)) {
            k.i(0x4240);
            st.ww(a3 + 6, -st.rw(a3 + 6));
        }
        k.r(0x4244, 0x424E);
    }
    st.ww(a0, R.d[0]);
    st.ww(a3, R.d[1]);
}
