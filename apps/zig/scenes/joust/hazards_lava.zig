// --------------------------------------------------------------------------
// Package C: the lava. Call 0 ($7724) raises it; call 1 ($778E, the model's
// c_lava.py) runs the three lava bubbles. Program addresses used as
// immediates are read from the relocated image itself (st.rl(operand)), as
// the 68000 sees them.
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
const swap = State.swap;
const divu = State.divu;
const rorl = State.rorl;
const lsrl = State.lsrl;

/// Call 0. Waves 1-3: every 7th frame the lava top moves up one line; on the
/// new line the two 80-pixel side stretches ($776A: 5 groups each, x 0-79 and
/// x 240-319) get plane 3 set wherever all four planes were 0 (black becomes
/// lava colour 8).
pub fn call_7724_lava_rise(st: *St) void {
    if (st.g(V.lava_lines) == 0) {
        st.cycles = 60;
        return;
    }
    st.s(V.lava_delay, st.g(V.lava_delay) - 1);
    if (st.g(V.lava_delay) != 0) {
        st.cycles = 92;
        return;
    }
    st.cycles = 1276; // the rise path (fixed: no data-dependent loop)
    st.s(V.lava_risen, st.g(V.lava_risen) + 1);
    st.s(V.lava_lines, st.g(V.lava_lines) - 1);
    st.s(V.lava_delay, 7);
    const a1 = st.g(V.lava_top) - 0xA0;
    st.s(V.lava_top, a1);
    var a = a1;
    var d2: i64 = 0;
    for (0..2) |stretch| { // the 2nd bsr starts where the 1st left a1, plus $50
        for (0..5) |_| {
            d2 = st.rd(a, 2) | st.rd(a + 2, 2) | st.rd(a + 4, 2) | st.rd(a + 6, 2);
            d2 = ~d2 & 0xFFFF;
            st.wr(a + 6, 2, st.rd(a + 6, 2) | d2);
            a += 8;
        }
        if (stretch == 0) a += 0x50;
    }
    st.set_a(1, a);
    st.set_d(1, 0, 1);
    st.regs[2] = d2;
}

const BUB0: i64 = 0x0DE2;
const BUB_SZ: i64 = 0x0E;

/// top: addi.l #$c4,$e6c; jsr $5ea; movea.l $e6c,a3; clr.l dn; move.w (a3)+,dn;
/// add.w (a3)+,dn; beq top. Returns the non-zero word sum.
fn rng_sum(st: *St, r: *[16]i64, k: *Clock, top: i64, jsr: i64, beq: i64) i64 {
    const after = jsr + 6;
    while (true) {
        st.s(V.rng_ptr, (st.g(V.rng_ptr) + 0xC4) & M32);
        k.n += seq(top, after);
        k.n += C.rng(st, r[0]);
        const p = st.g(V.rng_ptr);
        const v = (st.rd(p, 2) + st.rd(p + 2, 2)) & M16;
        r[11] = (p + 4) & M32;
        k.n += seq(after, beq) + bcc(beq, v == 0);
        if (v != 0) return v;
    }
}

/// $78AA: 3 lines of the bubble mask into plane 3 (words +6 and +$E); below
/// the lava top the masked bits are set, above it cleared.
fn draw(st: *St, r: *[16]i64, a0: i64, k: *Clock) void {
    var a2 = st.rd(a0 + 2, 4);
    var a3 = st.rl(0x78B0);
    const d4 = st.rd(a0 + 6, 2);
    r[4] = setw(r[4], d4);
    k.n += seq(0x78AA, 0x78BC);
    const top = st.g(V.lava_top);
    var d0: i64 = 0;
    var d6: i64 = 0;
    for (0..3) |i| {
        d6 = rorl(st.rd(a3, 4), d4);
        a3 += 4;
        k.n += cost(0x78BC) + C.shift(d4, true) + seq(0x78C0, 0x78C8);
        if (a2 < top) {
            d0 = 0;
            k.n += bcc(0x78C8, true);
        } else {
            d0 = ~d6 & M32;
            k.n += bcc(0x78C8, false) + seq(0x78CA, 0x78CE);
        }
        st.wr(a2 + 0xE, 2, (st.rd(a2 + 0xE, 2) & d6) | d0);
        d6 = swap(d6);
        d0 = swap(d0);
        st.wr(a2 + 6, 2, (st.rd(a2 + 6, 2) & d6) | d0);
        a2 += 0xA0;
        k.n += seq(0x78CE, 0x78E8) + bcc(0x78E8, i < 2);
    }
    r[0] = d0;
    r[6] = d6;
    r[7] = setw(r[7], 0);
    r[10] = a2;
    r[11] = a3;
    k.n += cost(0x78EA);
}

/// $78EC: the current frame's 3 lines back over plane 3.
fn erase(st: *St, r: *[16]i64, a0: i64, k: *Clock) void {
    var a2 = st.rd(a0 + 2, 4);
    var a1 = st.rd(a0 + 0xA, 4);
    var a3 = a1 + 0x18;
    const d4 = st.rd(a0 + 6, 2);
    r[4] = setw(r[4], d4);
    k.n += seq(0x78EC, 0x7902);
    var d2: i64 = 0;
    var d6: i64 = 0;
    for (0..3) |i| {
        d6 = rorl(st.rd(a3, 4), d4);
        a3 += 4;
        d2 = lsrl(st.rd(a1 + 4, 4) & 0xFFFF0000, d4);
        k.n += seq(0x7902, 0x790A) + 2 * C.shift(d4, true);
        st.wr(a2 + 0xE, 2, (st.rd(a2 + 0xE, 2) & d6) | (d2 & M16));
        d6 = swap(d6);
        d2 = swap(d2);
        st.wr(a2 + 6, 2, (st.rd(a2 + 6, 2) & d6) | (d2 & M16));
        a2 += 0xA0;
        a1 += 8;
        k.n += seq(0x790E, 0x792C) + bcc(0x792C, i < 2);
    }
    r[2] = d2;
    r[6] = d6;
    r[7] = setw(r[7], 0);
    r[9] = a1;
    r[10] = a2;
    r[11] = a3;
    k.n += cost(0x792E);
}

/// $779E..$786A: a new bubble: flip side, frame 0, random x, y from the lava,
/// delay. False when it gives up (no lava risen, or y off the lava).
fn spawn(st: *St, r: *[16]i64, a0: i64, k: *Clock) bool {
    st.wb(a0, st.rb(a0) ^ 4);
    st.wl(a0 + 0xA, st.rl(0x77A6));
    k.n += seq(0x779E, 0x77AC);
    var d2 = rng_sum(st, r, k, 0x77AC, 0x77B6, 0x77C8);
    d2 = swap(divu(d2, 0x41));
    k.n += seq(0x77CA, 0x77D6);
    if (st.rb(a0) & 4 != 0) {
        k.n += bcc(0x77D6, true);
    } else {
        d2 = setw(d2, d2 + 0xF5);
        k.n += bcc(0x77D6, false) + cost(0x77D8);
    }
    r[2] = d2;
    var d1 = rng_sum(st, r, k, 0x77DC, 0x77E6, 0x77F8);
    r[1] = d1;
    k.n += cost(0x77FA);
    const risen = st.g(V.lava_risen);
    if (risen == 0) {
        k.n += bcc(0x7800, true);
        return false;
    }
    d1 = swap(divu(d1, risen));
    d1 = setw(d1, -((d1 - 0xC6) & M16));
    r[1] = d1;
    k.n += bcc(0x7800, false) + seq(0x7804, 0x7816);
    if ((d1 & M16) > 0xC4) {
        k.n += bcc(0x7816, true);
        return false;
    }
    k.n += bcc(0x7816, false) + seq(0x781A, 0x783E);
    d1 = (d1 & M16) * 0xA0;
    st.wl(a0 + 2, d1);
    d1 = swap(divu(d2 & M16, 0x10));
    st.ww(a0 + 6, d1);
    d1 = lsrl(lsrl(d1, 8), 5);
    d1 = (d1 + st.g(V.screen_base)) & M32;
    st.wl(a0 + 2, st.rl(a0 + 2) + d1);
    while (true) {
        d1 = rng_sum(st, r, k, 0x783E, 0x7848, 0x785A);
        d1 = swap(divu(d1, 0x35));
        st.ww(a0 + 8, d1);
        r[1] = d1;
        k.n += seq(0x785C, 0x7866);
        if (d1 & M16 != 0) {
            k.n += bcc(0x7866, false);
            break;
        }
        k.n += bcc(0x7866, true);
    }
    st.wb(a0, st.rb(a0) | 2);
    k.n += cost(0x7868);
    return true;
}

/// Call 1. 3 bubble records at $0DE2 ($0E bytes): +0 flags (b1 alive, b2 side),
/// +2 screen address, +6 shift, +8 frame delay, +$A frame pointer (3 lines,
/// $24 apart, 3 frames).
pub fn call_778e_lava_bubbles(st: *St) void {
    var r = st.regs;
    var k = Clock.init(st, cost(0x001E) + seq(0x778E, 0x7794));
    var a0 = BUB0;
    const end = st.rl(0x78A0);
    while (true) {
        const A = BASE + a0;
        r[8] = A;
        k.n += cost(0x7794);
        var alive = true;
        if (st.rb(a0) & 2 == 0) {
            k.n += bcc(0x779A, false);
            alive = spawn(st, &r, a0, &k);
        } else {
            k.n += bcc(0x779A, true);
        }
        if (alive) {
            const w = (st.rw(a0 + 8) - 1) & M16;
            st.ww(a0 + 8, w);
            k.n += cost(0x786E);
            if (w != 0) {
                k.n += bcc(0x7872, true);
            } else {
                st.wl(a0 + 0xA, st.rl(a0 + 0xA) + 0x24);
                k.n += bcc(0x7872, false) + seq(0x7874, 0x7884);
                if (st.rl(a0 + 0xA) < st.rl(0x787E)) {
                    st.ww(a0 + 8, 6);
                    k.n += bcc(0x7884, true) + seq(0x7890, 0x7896);
                    k.n += cost(0x7896);
                    draw(st, &r, A, &k);
                    k.n += cost(0x7898);
                    erase(st, &r, A, &k);
                } else {
                    st.wb(a0, st.rb(a0) & ~@as(i64, 2));
                    k.n += bcc(0x7884, false) + seq(0x7886, 0x788C);
                    k.n += cost(0x788C);
                    draw(st, &r, A, &k);
                    k.n += cost(0x788E);
                }
            }
        }
        a0 += BUB_SZ;
        k.n += seq(0x789A, 0x78A4);
        if (BASE + a0 == end) {
            k.n += bcc(0x78A4, false);
            break;
        }
        k.n += bcc(0x78A4, true);
    }
    r[8] = BASE + a0;
    st.regs = r;
    k.n += cost(0x78A8);
    k.done();
}
