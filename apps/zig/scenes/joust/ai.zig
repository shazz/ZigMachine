// --------------------------------------------------------------------------
// Call 7, $20A6: enemy steering (the model's b_ai.py).
//
// For slots 2..13 (a0 = $1040..$13E8): one RNG step ($05EA, with the d0 of the
// previous slot), then per enemy type (flags & 3: 1 Bounder, 2 Hunter,
// 3 Shadow Lord) or for a riderless mount (b13) pick the target vx (+$0C),
// the target height (+$46) and the flap bits (b11 fire/flap held, b6 flap
// pose), then write the flags word back. The Hunter and the Shadow Lord are in
// ai_hunter.zig, the riderless mount and the shared tails in ai_mount.zig.
// --------------------------------------------------------------------------
const hunter = @import("ai_hunter.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const core = @import("core.zig");
const Regs = @import("ai_regs.zig").Regs;
const mount = @import("ai_mount.zig");
const St = State.St;
const V = State.V;
const Clk = cyc.Clk;
const BASE = State.BASE;
const s16 = State.s16;

pub const SPEED_B: i64 = 0x0D98;
pub const SPEED_H: i64 = 0x0D9A;
pub const SPEED_S: i64 = 0x0D9C;
const P1 = State.P1;
const P2 = State.P2;

/// jsr $05EA: advance the RNG pointer (the wrap uses the caller's d0).
fn rng_05ea(st: *St, k: *Clk, d0: i64) void {
    k.r(0x210A, 0x2110); // jsr
    k.r(0x05EA, 0x05FA); // addq.l, cmpi.l
    const wrap = ((st.g(V.rng_ptr) + 2) & State.M32) >= BASE + 0x7B84;
    if (!k.b(0x05FA, !wrap)) k.r(0x05FC, 0x0616);
    k.i(0x0616); // rts
    core.rng_step(st, d0);
}

/// Call 7.
pub fn call_20a6_enemy_ai(st: *St) void {
    var R = Regs.init(st);
    var k = Clk.init(st);
    k.add(20); // jsr $20A6 from the main loop
    k.r(0x20A6, 0x20BE);
    st.s(V.alive_mask, 0);
    const d5 = st.rw(P1);
    R.setw(5, d5);
    if (!k.b(0x20BE, d5 == 0)) {
        k.i(0x20C0);
        if (!k.b(0x20C4, d5 & 0x2000 != 0)) {
            k.i(0x20C6);
            if (!k.b(0x20CA, d5 & 0x80 != 0)) {
                k.i(0x20CC);
                st.s(V.alive_mask, 1);
            }
        }
    }
    k.r(0x20D4, 0x20DE);
    const d6 = st.rw(P2);
    R.setw(6, d6);
    if (!k.b(0x20DE, d6 == 0)) {
        k.i(0x20E0);
        if (!k.b(0x20E4, d6 & 0x2000 != 0)) {
            k.i(0x20E6);
            if (!k.b(0x20EA, d6 & 0x80 != 0)) {
                k.r(0x20EC, 0x20F6); // bset, bra
                st.s(V.alive_mask, st.g(V.alive_mask) | 2);
            }
        }
    }
    var a0: i64 = 0x1040;
    R.a[3] = BASE + P1;
    R.a[4] = BASE + P2;
    while (true) {
        rng_05ea(st, &k, R.d[0]);
        k.r(0x2110, 0x211A);
        R.a[1] = st.g(V.rng_ptr);
        const d0 = (R.d[0] & 0xFFFF0000) | st.rw(a0);
        R.d[0] = d0;
        R.a[0] = BASE + a0;
        if (!k.b(0x211A, d0 & 0xFFFF == 0)) slot(st, &k, &R, a0);
        // $20F6: move.w d0,(a0); adda.l; cmpa.l; bne
        k.r(0x20F6, 0x2106);
        st.ww(a0, R.d[0]);
        a0 += 0x4E;
        R.a[0] = BASE + a0;
        if (k.b(0x2106, a0 != 0x13E8)) continue;
        k.i(0x2108); // rts
        break;
    }
    R.store();
    k.done();
}

/// $211C..: one non-empty slot; returns to $20F6 (the caller writes d0 back).
fn slot(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    const d0 = R.d[0];
    k.i(0x211C);
    if (k.b(0x2120, d0 & 0x2000 != 0)) return mount.riderless(st, k, R, a0);
    k.r(0x2124, 0x212A);
    var d1 = d0 & 3;
    R.setb(1, d1);
    if (k.b(0x212A, d1 == 0)) return;
    k.i(0x212C);
    if (!k.b(0x2132, st.rb(a0 + 0x4B) < 3)) {
        k.r(0x2134, 0x213C);
        R.d[0] ^= 0x8000;
        st.wb(a0 + 0x4B, 0);
    }
    k.i(0x213C);
    d1 = (d1 - 1) & 0xFF;
    R.setb(1, d1);
    if (!k.b(0x213E, d1 != 0)) return bounder(st, k, R, a0);
    k.i(0x21D4);
    d1 = (d1 - 1) & 0xFF;
    R.setb(1, d1);
    if (!k.b(0x21D6, d1 != 0)) return hunter.hunter(st, k, R, a0);
    return hunter.shadow(st, k, R, a0);
}

/// move.w speed,$C(a0); btst #15,d0; bne +4; neg.w $C(a0) (the 4-instruction idiom).
pub fn target_vx(st: *St, k: *Clk, R: *Regs, a0: i64, at: i64, speed_var: i64) void {
    k.r(at, at + 12); // move.w abs,d16 (8 bytes) + btst (4 bytes)
    var v = st.rw(speed_var);
    if (!k.b(at + 12, R.d[0] & 0x8000 != 0)) {
        k.i(at + 14);
        v = -v;
    }
    st.ww(a0 + 0x0C, v);
}

// ---------------------------------------------------------------- Bounder
fn bounder(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x2142);
    if (!k.b(0x2146, R.d[0] & 0x80 == 0)) {
        k.r(0x2148, 0x215E);
        st.wb(a0 + 0x4B, 0);
        st.ww(a0 + 0x46, st.rw(a0 + 4) - 6);
        st.ww(a0 + 0x0C, st.rw(SPEED_B));
        k.i(0x215E);
        if (k.b(0x2162, R.d[0] & 0x8000 != 0)) return mount.j2636(st, k, R, a0);
        k.r(0x2166, 0x216E);
        st.ww(a0 + 0x0C, -st.rw(SPEED_B));
        return mount.j2636(st, k, R, a0);
    }
    target_vx(st, k, R, a0, 0x216E, SPEED_B);
    k.i(0x2180);
    if (k.b(0x2186, st.g(V.alive_mask) == 0)) return mount.j2626(st, k, R, a0);
    k.r(0x218A, 0x219C);
    st.ww(a0 + 0x46, st.rw(a0 + 4) - 4);
    const y = s16(st.rw(a0 + 4));
    if (!k.b(0x219C, st.g(V.alive_mask) & 1 == 0)) {
        k.r(0x219E, 0x21B2);
        const d2 = ((st.rw(SPEED_H) << 2) - 6) & 0xFFFF;
        R.setw(2, d2);
        const d1 = (st.rw(P1 + 4) - d2) & 0xFFFF;
        R.setw(1, d1);
        if (k.b(0x21B2, s16(d1) <= y)) return mount.j25ee(st, k, R, a0);
    }
    k.i(0x21B6);
    if (k.b(0x21BE, st.g(V.alive_mask) & 2 == 0)) return mount.j25da(st, k, R, a0);
    k.r(0x21C2, 0x21CC);
    const d1 = (st.rw(P2 + 4) - R.d[2]) & 0xFFFF;
    R.setw(1, d1);
    if (k.b(0x21CC, s16(d1) <= y)) return mount.j25ee(st, k, R, a0);
    k.i(0x21D0);
    return mount.j25da(st, k, R, a0);
}

// ---------------------------------------------------------------- Hunter
// ---------------------------------------------------------------- Shadow Lord
