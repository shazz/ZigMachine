// --------------------------------------------------------------------------
// Call 8, $4C6E: the pterodactyls (the model's c_ptero.py): the spawn timer,
// the platform bounce; flying off in hazards_ptero_fly.zig, hunting and the
// lance in the mouth in hazards_ptero_hunt.zig, the frame animation, the move
// and the erase/draw in hazards_ptero_draw.zig.
//
// 4 records at $1428 ($20 bytes): +0 w flags (b0 spawn request, b1 moving
// down, b2 facing right, b3 leaving, b5 dying, b6 alive), +2 l drawn screen
// offset, +6 l drawn sprite, +$A w drawn shift, +$C x, +$E y, +$10 x speed,
// +$12 y speed, +$16 drawn byte offset, +$18 drawn height, +$1A animation
// counter, +$1C/+$1D clip timers (right/left half hidden), +$1E dying/lance
// timer, +$1F flap/dying counter.
// --------------------------------------------------------------------------
const fly = @import("hazards_ptero_fly.zig");
const State = @import("state.zig");
const C = @import("hazards_common.zig");
const cyc = @import("cyc.zig");
const ov = @import("coll_overlap.zig");
const pd = @import("hazards_ptero_draw.zig");
const St = State.St;
const V = State.V;
const Clock = C.Clock;
const BASE = State.BASE;
const M32 = C.M32;
const seq = C.seq;
const cost = C.cost;
const bcc = C.bcc;
const setw = State.setw;
const divu = State.divu;
const sw = State.s16;

const P0: i64 = 0x1428;
const P_END: i64 = 0x14A8;

/// Package B's $3FE2 (body to its rts), counted on a Clk and added to k (no
/// sound inside it, so nothing needs flushing first).
fn overlap(st: *St, k: *Clock) void {
    var c = cyc.Clk.init(st);
    ov.overlap_3fe2(st, &c);
    k.n += c.total;
}

/// $4CB6: adda.w #$20; cmpa.l #$14a8; bne -> true if another record follows.
fn next(a0: i64, k: *Clock) bool {
    k.n += seq(0x4CB6, 0x4CC0);
    if (a0 + 0x20 == P_END) {
        k.n += bcc(0x4CC0, false);
        return false;
    }
    k.n += bcc(0x4CC0, true);
    return true;
}

/// Call 8.
pub fn call_4c6e_pterodactyl(st: *St) void {
    var r = st.regs;
    var k = Clock.init(st, cost(0x0048) + seq(0x4C6E, 0x4C7A));
    st.s(V.ptero_timer, st.g(V.ptero_timer) - 1);
    var a0 = P0;
    while (true) {
        r[8] = BASE + a0;
        const d0 = st.rw(a0);
        r[0] = setw(r[0], d0);
        k.n += cost(0x4C7A);
        if (d0 != 0) {
            k.n += bcc(0x4C7E, true);
            active(st, &r, a0, &k);
        } else {
            k.n += bcc(0x4C7E, false) + cost(0x4C80);
            idle(st, a0, &k);
        }
        if (!next(a0, &k)) break;
        a0 += 0x20;
    }
    r[8] = BASE + P_END;
    k.n += cost(0x4CC2);
    st.regs = r;
    k.done();
}

/// An empty record: when the timer runs out (and play is on), halve the
/// period and ask for a pterodactyl.
fn idle(st: *St, a0: i64, k: *Clock) void {
    if (st.g(V.phase) != 0) {
        k.n += bcc(0x4C86, true);
        return;
    }
    k.n += bcc(0x4C86, false) + cost(0x4C88);
    if (st.g(V.alive_mask) == 0) {
        k.n += bcc(0x4C8E, true);
        return;
    }
    k.n += bcc(0x4C8E, false) + cost(0x4C90);
    if (sw(st.g(V.ptero_timer)) > 0) {
        k.n += bcc(0x4C96, true);
        return;
    }
    st.s(V.ptero_period, st.g(V.ptero_period) >> 1);
    st.s(V.ptero_timer, st.g(V.ptero_period) + 0x20);
    st.ww(a0, 1);
    k.n += bcc(0x4C96, false) + seq(0x4C98, 0x4CB6);
}

/// $4CCC: sfx 3, reset the record, enter from a random side.
fn spawn(st: *St, r: *[16]i64, a0: i64, k: *Clock) i64 {
    k.n += seq(0x4CCC, 0x4CD6);
    C.sfx(k, 3);
    k.n += cost(0x4CD6);
    var d0 = r[0] & 0xFFFF0000;
    st.s(V.ptero_count, st.g(V.ptero_count) + 1);
    d0 |= 0x40;
    for ([_]i64{ 0x14, 0x10, 0x12, 0x0A, 0x1A, 0x18, 0x16 }) |o| st.ww(a0 + o, 0);
    st.ww(a0 + 0x10, 2);
    for ([_]i64{ 0x1F, 0x1C, 0x1D, 0x1E }) |o| st.wb(a0 + o, 0);
    st.ww(a0 + 0xE, 0x96);
    k.n += seq(0x4CD8, 0x4D1E);
    k.n += C.rng(st, d0);
    const a1 = st.g(V.rng_ptr);
    const b = st.rd(a1, 1);
    r[9] = a1 + 1;
    k.n += seq(0x4D1E, 0x4D28);
    if (b & 1 != 0) {
        d0 |= 4;
        st.wl(a0 + 6, st.rl(0x4D30));
        st.wl(a0 + 2, st.rl(0x4D38));
        st.ww(a0 + 0xC, 0x120);
        st.wb(a0 + 0x1D, 0xB);
        k.n += bcc(0x4D28, false) + seq(0x4D2A, 0x4D4A) + cost(0x4D4A);
    } else {
        st.wl(a0 + 6, st.rl(0x4D4E));
        st.wl(a0 + 2, st.rl(0x4D56));
        st.ww(a0 + 0xC, 0);
        st.wb(a0 + 0x1C, 0xB);
        k.n += bcc(0x4D28, true) + seq(0x4D4C, 0x4D66);
    }
    r[0] = d0;
    return d0;
}

fn active(st: *St, r: *[16]i64, a0: i64, k: *Clock) void {
    var d0 = r[0];
    k.n += cost(0x4CC4);
    if (d0 & 1 != 0) {
        k.n += bcc(0x4CC8, false);
        d0 = spawn(st, r, a0, k);
    } else {
        k.n += bcc(0x4CC8, true);
    }
    k.n += seq(0x4D66, 0x4D74);
    platforms(st, r, a0, d0, k);
}

/// $4D68..$4E5A: the pterodactyl's mask vs each visible platform ($3FE2); a
/// hit bounces it (and marks the platform for redraw).
fn platforms(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    var a5 = st.rl(0x4D6A);
    var a3 = st.rl(0x4D70);
    const a1: i64 = 0x0E0E;
    const a2: i64 = 0x0E1E;
    var a4: i64 = 0;
    var d1: i64 = 0;
    while (true) {
        a4 = (st.rl(a0 + 2) + st.g(V.screen_base) + sw(st.rw(a0 + 0x16))) & M32;
        st.wl(a1, a4);
        st.wl(a1 + 4, st.rl(a0 + 6));
        st.ww(a1 + 8, 3);
        st.wb(a1 + 0xA, st.rb(a0 + 0xB));
        st.wb(a1 + 0xB, st.rb(a0 + 0x19));
        st.ww(a1 + 0xE, st.rw(a0 + 0xE));
        d1 = divu(st.rw(a0 + 0x16), 0xA0);
        st.ww(a1 + 0xE, st.rw(a1 + 0xE) + d1);
        a4 = st.rd(a3, 4);
        a3 += 4;
        k.n += seq(0x4D74, 0x4DC2);
        if (st.rd(a4, 1) == 0) {
            a3 += 0xC;
            k.n += bcc(0x4DC2, false) + seq(0x4DC4, 0x4DCA) + cost(0x4DCA);
        } else {
            a3 += 1;
            st.wb(a2 + 0xB, st.rd(a3, 1));
            a3 += 1;
            st.ww(a2 + 8, st.rd(a3, 2));
            a3 += 2;
            st.wl(a2 + 4, st.rd(a3, 4));
            a3 += 4;
            st.wl(a2, st.rd(a3, 4));
            st.wb(a2 + 0xA, 0);
            st.wl(a2, st.rl(a2) + st.g(V.screen_base));
            d1 = divu(st.rd(a3, 4), 0xA0);
            a3 += 4;
            st.ww(a2 + 0xE, d1);
            k.n += bcc(0x4DC2, true) + seq(0x4DCC, 0x4DFC);
            overlap(st, k);
            k.n += cost(0x4DFC);
            if (st.rb(0x0E2F) != 0) {
                k.n += bcc(0x4E02, true);
                r[9] = BASE + a1;
                r[10] = BASE + a2;
                r[11] = a3;
                r[12] = a4;
                r[13] = a5;
                return bounce(st, r, a0, d0, a4, a5, k);
            }
            k.n += bcc(0x4E02, false);
        }
        a5 += 6;
        k.n += seq(0x4E04, 0x4E0C);
        if (a3 == BASE + 0x1AC2) {
            k.n += bcc(0x4E0C, false) + cost(0x4E10);
            break;
        }
        k.n += bcc(0x4E0C, true);
    }
    r[9] = BASE + a1;
    r[10] = BASE + a2;
    r[11] = a3;
    r[12] = a4;
    r[13] = a5;
    r[1] = d1;
    return fly.free(st, r, a0, d0, k);
}

fn bounce(st: *St, r: *[16]i64, a0: i64, d0_in: i64, a4: i64, a5_in: i64, k: *Clock) void {
    var d0 = d0_in;
    var a5 = a5_in;
    st.wr(a4, 1, 1);
    const x = sw(st.rw(a0 + 0xC));
    var d1 = st.rd(a5, 2);
    a5 += 2;
    k.n += seq(0x4E12, 0x4E1C);
    r[1] = setw(r[1], d1);
    if (sw(d1) >= x) {
        st.ww(a0 + 0x10, 4);
        d0 &= ~@as(i64, 4);
        k.n += bcc(0x4E1C, false) + seq(0x4E1E, 0x4E28) + cost(0x4E28);
        r[13] = a5;
        return pd.move(st, r, a0, d0, k);
    }
    d1 = st.rd(a5, 2);
    a5 += 2;
    r[1] = setw(r[1], d1);
    k.n += bcc(0x4E1C, true) + seq(0x4E2C, 0x4E32);
    if (sw(d1) <= x) {
        st.ww(a0 + 0x10, 4);
        d0 |= 4;
        k.n += bcc(0x4E32, false) + seq(0x4E34, 0x4E3E) + cost(0x4E3E);
        r[13] = a5;
        return pd.move(st, r, a0, d0, k);
    }
    st.ww(a0 + 0x12, 4);
    d1 = st.rd(a5, 2);
    a5 += 2;
    r[1] = setw(r[1], d1);
    r[13] = a5;
    d0 &= ~@as(i64, 2);
    k.n += bcc(0x4E32, true) + seq(0x4E42, 0x4E52);
    if (sw(d1) > sw(st.rw(a0 + 0xE))) {
        k.n += bcc(0x4E52, true);
    } else {
        d0 |= 2;
        k.n += bcc(0x4E52, false) + seq(0x4E56, 0x4E5A) + cost(0x4E5A);
    }
    return pd.move(st, r, a0, d0, k);
}
