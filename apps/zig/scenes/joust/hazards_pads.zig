// --------------------------------------------------------------------------
// Call 14, $75E2: the spawn-pad materialise strips (the model's c_pads.py).
//
// 4 records at $13E8 ($10 bytes): +0 w lines left (set to $1A on start), +2 w
// pad number (0 = idle; copied from +0 each frame, so the record stops when +0
// reaches 0), +4 w lines per step, +6 w groups per line, +8 l sprite pointer,
// +$C l screen pointer. Each frame the strip moves one line down: random
// pixels (the RNG pointer walked directly, 10 bytes per group) sparkle below
// it and the rider's mask is cut out above it.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const C = @import("hazards_common.zig");
const St = State.St;
const V = State.V;
const Clock = C.Clock;
const BASE = State.BASE;
const M16 = C.M16;
const M32 = C.M32;
const seq = C.seq;
const cost = C.cost;
const bcc = C.bcc;
const setw = State.setw;
const sw = State.s16;

const PADS: i64 = 0x13E8;
const PADS_END: i64 = 0x1428;

fn dec8(v: i64) i64 {
    return (v & ~@as(i64, 0xFF)) | ((v - 1) & 0xFF);
}

/// $75F6: the first frame of a pad: clear the rider's shape (mask) from the screen once.
fn start(st: *St, r: *[16]i64, a0: i64, d0_in: i64, k: *Clock) i64 {
    st.ww(a0, 0x1A);
    var d0 = (d0_in & M16) * 0x10;
    const a4 = (st.rl(0x75FE) + sw(d0)) & M32;
    st.wl(a0 + 4, st.rd(a4 + 4, 4));
    var a1 = st.rd(a4 + 8, 4);
    var a3 = (st.rd(a4 + 0xC, 4) + st.g(V.screen_base)) & M32;
    d0 = setw(d0, st.rd(a4 + 4, 2));
    k.n += seq(0x75F6, 0x761E);
    var a2 = a3;
    var d1: i64 = r[1];
    var d2: i64 = 0;
    while (true) {
        a2 = a3;
        d1 = setw(r[1], st.rw(a0 + 6));
        k.n += seq(0x761E, 0x7624);
        while (true) {
            d2 = ((st.rd(a1 + 4, 2) ^ 0xFFFF) | st.rd(a1 + 6, 2)) & M16;
            st.wr(a2 + 4, 2, st.rd(a2 + 4, 2) & d2);
            a1 += 8;
            a2 += 8;
            d1 = dec8(d1);
            k.n += seq(0x7624, 0x763E);
            if (d1 & 0xFF != 0) {
                k.n += bcc(0x763E, true);
                continue;
            }
            k.n += bcc(0x763E, false);
            break;
        }
        r[2] = setw(r[2], d2);
        a3 += 0xA0;
        d0 = dec8(d0);
        k.n += seq(0x7640, 0x7646);
        if (d0 & 0xFF != 0) {
            k.n += bcc(0x7646, true);
            continue;
        }
        k.n += bcc(0x7646, false);
        break;
    }
    r[1] = d1;
    r[11] = a3;
    r[12] = a4;
    st.wl(a0 + 8, a1);
    st.wl(a0 + 0xC, a2);
    k.n += cost(0x7648);
    return d0;
}

/// $764E: one line of the strip.
fn step(st: *St, r: *[16]i64, a0: i64, d0_in: i64, k: *Clock) i64 {
    var d0 = setw(d0_in, st.rw(a0 + 4));
    var a1 = st.rl(a0 + 8);
    var a3 = st.rl(a0 + 0xC);
    var a4 = st.g(V.rng_ptr);
    k.n += seq(0x764E, 0x765E);
    var a2 = a3;
    var d1 = r[1];
    var d2 = r[2];
    var d4 = r[4];
    var d5 = r[5];
    while (true) {
        a2 = a3;
        d1 = setw(d1, st.rw(a0 + 6));
        k.n += seq(0x765E, 0x7664);
        while (true) {
            a1 = (a1 - 8) & M32;
            a2 = (a2 - 8) & M32;
            const w = st.rd(a1 + 6, 2);
            d5 = (w << 16) | w;
            const h = w & st.rd(a2 + 4, 2) & st.rd(a2 + 6, 2);
            d4 = (h << 16) | h;
            k.n += seq(0x7664, 0x768E);
            if (st.rw(a0) != 1) {
                d2 = st.rd(a4, 4);
                const lo = st.rd(a4 + 4, 2) | st.rd(a4 + 6, 2) | st.rd(a4 + 8, 2) | (d2 & M16);
                d2 = (d2 & 0xFFFF0000) | lo;
                a4 += 10;
                k.n += bcc(0x768E, false) + seq(0x7690, 0x7698);
                if (lo != 0) {
                    k.n += bcc(0x7698, true);
                } else {
                    d2 = (d2 & 0xFFFF0000) | 0xFFFF;
                    k.n += bcc(0x7698, false) + cost(0x769A);
                }
                const m = ((d2 & M16) << 16) | (d2 & M16);
                st.wl(0x0E5E, m);
                d4 &= m;
                st.wr(a2 + 0xA4, 4, st.rd(a2 + 0xA4, 4) | d4);
                d4 &= st.rd(a2, 4);
                st.wr(a2 + 0xA0, 4, st.rd(a2 + 0xA0, 4) | d4);
                k.n += seq(0x769C, 0x76B8);
            } else {
                k.n += bcc(0x768E, true);
            }
            d5 = ~d5 & M32;
            st.wr(a2, 4, st.rd(a2, 4) & d5);
            st.wr(a2 + 4, 4, st.rd(a2 + 4, 4) & d5);
            d1 = dec8(d1);
            k.n += seq(0x76B8, 0x76C2);
            if (d1 & 0xFF != 0) {
                k.n += bcc(0x76C2, true);
                continue;
            }
            k.n += bcc(0x76C2, false);
            break;
        }
        a3 = (a3 - 0xA0) & M32;
        d0 = dec8(d0);
        k.n += seq(0x76C4, 0x76CA);
        if (d0 & 0xFF != 0) {
            k.n += bcc(0x76CA, true);
            continue;
        }
        k.n += bcc(0x76CA, false);
        break;
    }
    d1 = setw(d1, st.rw(a0 + 6));
    k.n += cost(0x76CC);
    while (true) {
        const w = st.rd(a1 + 4, 2);
        d4 = ~((w << 16) | w) & M32;
        st.wr(a2, 4, st.rd(a2, 4) & d4);
        st.wr(a2 + 4, 4, st.rd(a2 + 4, 4) & d4);
        a1 += 8;
        a2 += 8;
        d1 = dec8(d1);
        k.n += seq(0x76D0, 0x76EA);
        if (d1 & 0xFF != 0) {
            k.n += bcc(0x76EA, true);
            continue;
        }
        k.n += bcc(0x76EA, false);
        break;
    }
    st.s(V.rng_ptr, a4);
    st.wl(a0 + 0xC, st.rl(a0 + 0xC) + 0xA0);
    st.ww(a0, st.rw(a0) - 1);
    st.ww(a0 + 2, st.rw(a0));
    st.s(V.rng_ptr, (st.g(V.rng_ptr) + 0x8E) & M32);
    k.n += seq(0x76EC, 0x7714);
    k.n += C.rng(st, d0);
    r[1] = d1;
    r[2] = d2;
    r[4] = d4;
    r[5] = d5;
    r[9] = a1;
    r[10] = a2;
    r[11] = a3;
    r[12] = a4;
    return d0;
}

/// Call 14.
pub fn call_75e2_spawn_pads(st: *St) void {
    var r = st.regs;
    var k = Clock.init(st, cost(0x006C) + cost(0x75E2));
    var a0 = PADS;
    var d0 = r[0];
    while (true) {
        d0 = setw(d0, st.rw(a0 + 2));
        k.n += cost(0x75E8);
        if (d0 & M16 != 0) {
            k.n += bcc(0x75EC, false) + cost(0x75F0);
            if (st.rw(a0) == 0) {
                k.n += bcc(0x75F4, false);
                d0 = start(st, &r, a0, d0, &k);
            } else {
                k.n += bcc(0x75F4, true);
            }
            d0 = step(st, &r, a0, d0, &k);
        } else {
            k.n += bcc(0x75EC, true);
        }
        a0 += 0x10;
        k.n += seq(0x7714, 0x771E);
        if (a0 < PADS_END) {
            k.n += bcc(0x771E, true);
            continue;
        }
        k.n += bcc(0x771E, false);
        break;
    }
    r[0] = d0;
    r[8] = BASE + a0;
    st.regs = r;
    k.n += cost(0x7722);
    k.done();
}
