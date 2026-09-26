// --------------------------------------------------------------------------
// Call 7 continued (the model's b_ai.py): the Hunter $21DA -- rise above a
// victim, dive when close (A recruits one from wave 6) -- and the Shadow
// Lord $2406 with its 11-frame dive.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const Regs = @import("ai_regs.zig").Regs;
const mount = @import("ai_mount.zig");
const St = State.St;
const V = State.V;
const Clk = cyc.Clk;
const s8 = State.s8;
const s16 = State.s16;
const P1 = State.P1;
const P2 = State.P2;
const back = @import("ai.zig");
const SPEED_H: i64 = 0x0D9A;
const SPEED_S: i64 = 0x0D9C;
const HUNT1: i64 = 0x0D9E;
const HUNT2: i64 = 0x0D9F;

pub fn hunter(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x21DA);
    if (!k.b(0x21DE, R.d[0] & 0x80 == 0)) {
        k.r(0x21E0, 0x21F6);
        st.wb(a0 + 0x48, 0);
        st.wb(a0 + 0x4B, 0);
        st.ww(a0 + 0x46, st.rw(a0 + 4) - 0x0F);
        var d2 = st.rd(R.a[1], 2); // move.w (a1)+,d2: an RNG word
        R.a[1] += 2;
        k.r(0x21F6, 0x21FE);
        d2 &= 3;
        R.setw(2, d2);
        st.ww(a0 + 0x46, st.rw(a0 + 0x46) + d2);
        k.r(0x21FE, 0x220A);
        if (k.b(0x220A, R.d[0] & 0x8000 != 0)) {
            st.ww(a0 + 0x0C, st.rw(SPEED_H));
            return mount.j2636(st, k, R, a0);
        }
        k.r(0x220E, 0x2216);
        st.ww(a0 + 0x0C, -st.rw(SPEED_H));
        return mount.j2636(st, k, R, a0);
    }
    back.target_vx(st, k, R, a0, 0x2216, SPEED_H);
    k.i(0x2228);
    if (!k.b(0x222E, st.g(V.alive_mask) != 0)) {
        k.r(0x2230, 0x223E);
        st.wb(a0 + 0x48, 0);
        st.ww(HUNT1, 0); // clr.w $0D9E: both hunter counts
        return mount.j2626(st, k, R, a0);
    }
    k.i(0x223E);
    if (k.b(0x2242, st.rb(a0 + 0x48) == 0)) return recruit(st, k, R, a0);
    k.r(0x2246, 0x2250);
    st.ww(a0 + 0x46, st.rw(a0 + 4) - 4);
    k.i(0x2250);
    const h = st.rb(a0 + 0x48);
    if (k.b(0x2254, h & 0x80 != 0)) return hunting_low(st, k, R, a0, h);
    k.i(0x2258);
    if (!k.b(0x225E, h != 1)) return hunt_on(st, k, R, a0, 0x2260, 1, HUNT1, P1, 0xFF);
    return hunt_on(st, k, R, a0, 0x22C6, 2, HUNT2, P2, 0xFE);
}

/// $2260 (P1) / $22C6 (P2): the victim still alive? Rise above it, then turn towards it.
pub fn hunt_on(st: *St, k: *Clk, R: *Regs, a0: i64, at: i64, bitn: i64, cnt: i64, p: i64, mark: i64) void {
    k.i(at); // btst #b,$0D47
    if (!k.b(at + 8, st.g(V.alive_mask) & bitn != 0)) {
        k.r(at + 10, at + 0x18); // clr.b $48; subq.b; bra
        st.wb(a0 + 0x48, 0);
        st.wb(cnt, st.rb(cnt) - 1);
        return mount.j2626(st, k, R, a0);
    }
    const q = at + 0x18; // $2278 / $22DE
    k.r(q, q + 12);
    var d2 = (st.rw(p + 4) - 0x1E) & 0xFFFF;
    R.setw(2, d2);
    if (k.b(q + 12, s16(d2) <= s16(st.rw(a0 + 4)))) return mount.j25ee(st, k, R, a0);
    k.r(q + 16, q + 30);
    st.wb(a0 + 0x48, mark);
    d2 = (st.rw(p + 2) - st.rw(a0 + 2)) & 0xFFFF;
    if (!k.b(q + 30, d2 & 0x8000 == 0)) {
        k.i(q + 32);
        d2 = (d2 + 0x140) & 0xFFFF;
    }
    R.setw(2, d2);
    k.i(q + 36); // cmpi.w #$a0,d2
    var right: bool = undefined;
    if (bitn == 1) {
        right = k.b(0x22A0, d2 < 0xA0);
    } else {
        right = k.b(0x2306, d2 < 0xA0);
        if (!right) k.i(0x2308);
    }
    if (right) {
        k.r(0x22B6, 0x22C2);
        R.d[0] |= 0x8000;
        st.ww(a0 + 0x0C, st.rw(SPEED_H));
        k.i(0x22C2);
    } else {
        k.r(0x22A2, 0x22B2);
        R.d[0] &= ~@as(i64, 0x8000);
        st.ww(a0 + 0x0C, -st.rw(SPEED_H));
        k.i(0x22B2);
    }
    return mount.j264e(st, k, R, a0);
}

/// $230A: from wave 6, a Hunter with no victim may pick one (up to
/// speed_shadow's low byte hunters per player).
pub fn recruit(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x230A, 0x2318);
    var d2 = st.rw(SPEED_S);
    R.setw(2, d2);
    if (k.b(0x2318, s8(st.g(V.wave)) <= 5)) return mount.j2626(st, k, R, a0);
    k.i(0x231C);
    const m = st.g(V.alive_mask);
    var two: bool = undefined;
    if (!k.b(0x2324, m != 3)) {
        k.r(0x2326, 0x2332);
        const d3 = st.rb(HUNT1);
        R.setb(3, d3);
        if (k.b(0x2332, s8(d3) > s8(st.rb(HUNT2)))) {
            two = true;
        } else {
            k.i(0x2334);
            two = false;
        }
    } else {
        k.i(0x2336);
        two = k.b(0x233E, m & 2 != 0);
    }
    d2 &= 0xFF;
    if (!two) {
        k.i(0x2340);
        if (k.b(0x2346, d2 <= st.rb(HUNT1))) return mount.j2626(st, k, R, a0);
        k.r(0x234A, 0x235A);
        st.wb(a0 + 0x48, 1);
        st.wb(HUNT1, st.rb(HUNT1) + 1);
        return mount.j2626(st, k, R, a0);
    }
    k.i(0x235A);
    if (k.b(0x2360, d2 <= st.rb(HUNT2))) return mount.j2626(st, k, R, a0);
    k.r(0x2364, 0x2374);
    st.wb(a0 + 0x48, 2);
    st.wb(HUNT2, st.rb(HUNT2) + 1);
    return mount.j2626(st, k, R, a0);
}

/// $2374: $48 = $FF/$FE: the hunter is above its victim: dive when close.
pub fn hunting_low(st: *St, k: *Clk, R: *Regs, a0: i64, h: i64) void {
    k.i(0x2374);
    var at: i64 = undefined;
    var bitn: i64 = undefined;
    var cnt: i64 = undefined;
    var p: i64 = undefined;
    if (!k.b(0x237A, h != 0xFF)) {
        at = 0x237C;
        bitn = 1;
        cnt = HUNT1;
        p = P1;
    } else {
        at = 0x23AE;
        bitn = 2;
        cnt = HUNT2;
        p = P2;
    }
    k.i(at);
    const alive = st.g(V.alive_mask) & bitn != 0;
    const drop = at + 10; // $2386 / $23B8
    if (k.b(at + 8, alive)) {
        const q = at + 0x18; // $2394 / $23C6
        k.r(q, q + 10);
        var d2 = (st.rw(p + 4) - 4 - st.rw(a0 + 4)) & 0xFFFF;
        R.setw(2, d2);
        if (!k.b(q + 10, s16(d2) <= 0)) {
            k.i(q + 12);
            if (k.b(q + 16, s16(d2) >= 0x28)) return mount.j25da(st, k, R, a0);
            k.i(q + 20); // move.w x(victim),d2
            d2 = st.rw(p + 2);
            if (bitn == 1) k.i(0x23AC); // bra $23DE
            return chase(st, k, R, a0, d2);
        }
    }
    k.r(drop, at + 0x18);
    st.wb(a0 + 0x48, 0);
    st.wb(cnt, st.rb(cnt) - 1);
    return mount.j2626(st, k, R, a0);
}

/// $23DE: close enough in x (either way round the wrap) -> $266E, else $25DA.
pub fn chase(st: *St, k: *Clk, R: *Regs, a0: i64, d2_0: i64) void {
    k.r(0x23DE, 0x23E6);
    const d2 = (d2_0 - st.rw(a0 + 2)) & 0xFFFF;
    R.setw(2, d2);
    if (k.b(0x23E6, d2 <= 0x0C)) return mount.j266e(st, k, R, a0);
    k.i(0x23EA);
    if (k.b(0x23EE, d2 >= 0xFFF4)) return mount.j266e(st, k, R, a0);
    k.i(0x23F2);
    if (k.b(0x23F6, s16(d2) >= 0x134)) return mount.j266e(st, k, R, a0);
    k.i(0x23FA);
    if (k.b(0x23FE, s16(d2) <= -0x134)) return mount.j266e(st, k, R, a0);
    k.i(0x2402);
    return mount.j25da(st, k, R, a0);
}

pub fn shadow(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x2406);
    if (!k.b(0x240A, R.d[0] & 0x80 == 0)) {
        k.r(0x240C, 0x2426);
        st.wb(a0 + 0x49, 0);
        st.wb(a0 + 0x4B, 0);
        st.ww(a0 + 0x46, st.rw(a0 + 4) - 8);
        k.i(0x2426);
        if (k.b(0x242A, R.d[0] & 0x8000 != 0)) {
            st.ww(a0 + 0x0C, st.rw(SPEED_S));
            return;
        }
        k.r(0x242E, 0x2436);
        st.ww(a0 + 0x0C, -st.rw(SPEED_S));
        return;
    }
    back.target_vx(st, k, R, a0, 0x2436, SPEED_S);
    k.i(0x2448);
    if (k.b(0x244E, st.g(V.alive_mask) == 0)) return mount.j2626(st, k, R, a0);
    k.r(0x2452, 0x245C);
    st.ww(a0 + 0x46, st.rw(a0 + 4));
    if (!k.b(0x245C, R.d[0] & 0x200 == 0)) {
        k.i(0x245E);
        st.wb(a0 + 0x49, 0);
    }
    k.i(0x2462);
    if (k.b(0x2466, st.rb(a0 + 0x49) != 0)) return mount.j265e(st, k, R, a0);
    k.i(0x246A);
    if (!k.b(0x2472, st.g(V.alive_mask) & 1 == 0)) {
        const at = [8]i64{ 0x2474, 0x2480, 0x2484, 0x2488, 0x248A, 0x2490, 0x2494, 0x249E };
        if (!shadow_dive(st, k, R, a0, at, P1)) return;
    }
    k.i(0x249E);
    if (k.b(0x24A6, st.g(V.alive_mask) & 2 == 0)) return mount.j25da(st, k, R, a0);
    const at = [8]i64{ 0x24AA, 0x24B6, 0x24BA, 0x24BE, 0x24C2, 0x24C8, 0x24CC, 0x24D6 };
    if (shadow_dive(st, k, R, a0, at, P2)) return mount.j25da(st, k, R, a0);
}

/// $2474 / $24AA: victim within 10 above .. 50 below: at the top of the
/// screen start an 11-frame dive ($49 = $0B). True = 'next' (not handled).
pub fn shadow_dive(st: *St, k: *Clk, R: *Regs, a0: i64, at: [8]i64, p: i64) bool {
    const a = at[0];
    const blt = at[1];
    const cmp1 = at[2];
    const bgt = at[3];
    const cmp2 = at[4];
    const bge = at[5];
    const mv = at[6];
    const end = at[7];
    k.r(a, blt);
    const d1 = (st.rw(p + 4) - st.rw(a0 + 4) + 0x0A) & 0xFFFF;
    R.setw(1, d1);
    if (k.b(blt, d1 & 0x8000 != 0)) {
        mount.j264e(st, k, R, a0);
        return false;
    }
    k.i(cmp1);
    if (k.b(bgt, s16(d1) > 0x32)) return true;
    k.i(cmp2);
    if (k.b(bge, s16(st.rw(a0 + 4)) >= 4)) {
        mount.j264e(st, k, R, a0);
        return false;
    }
    k.r(mv, end);
    st.wb(a0 + 0x49, 0x0B);
    mount.j265e(st, k, R, a0);
    return false;
}
