// --------------------------------------------------------------------------
// Call 13 continued (the model's c_troll.py): the hand's frame $4A92 and its
// erase $4B4C / draw $4BC6 / commit $4B16.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const C = @import("hazards_common.zig");
const St = State.St;
const V = State.V;
const Clock = C.Clock;
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
const sw = State.s16;

/// $4B4C: AND the old frame's mask back, unless the frame did not change.
pub fn erase(st: *St, r: *[16]i64, k: *Clock) void {
    var a2 = st.rl(0x0E38);
    var a1 = st.rl(0x0E34);
    const d4 = st.rw(0x0E3C);
    var d7 = st.rw(0x0E46);
    r[4] = setw(r[4], d4);
    k.n += seq(0x4B4C, 0x4B64) + cost(0x4B64);
    var same = false;
    if (a2 == st.rl(0x0E5E)) {
        k.n += bcc(0x4B6A, false) + cost(0x4B6C);
        if (a1 == st.rl(0x0E56)) {
            k.n += bcc(0x4B72, false) + cost(0x4B74);
            if (d4 == st.rw(0x0E62)) {
                k.n += bcc(0x4B7A, false) + cost(0x4B7C);
                same = true;
            } else k.n += bcc(0x4B7A, true);
        } else k.n += bcc(0x4B72, true);
    } else k.n += bcc(0x4B6A, true);
    if (same) {
        r[7] = setw(r[7], d7);
        r[9] = a1;
        r[10] = a2;
        return;
    }
    a1 = (a1 + st.g(V.screen_base)) & M32;
    a2 = (a2 + 0x90) & M32;
    k.n += seq(0x4B7E, 0x4B88);
    const lim = (st.g(V.lava_top) - 8) & M32;
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x4B88);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x4B8A, true) + cost(0x4918);
            break;
        }
        k.n += bcc(0x4B8A, false) + seq(0x4B8E, 0x4B98);
        r[11] = lim;
        if (a1 >= lim) {
            k.n += bcc(0x4B98, true) + cost(0x4918);
            break;
        }
        var d2 = rorl(st.rd(a2, 4), d4);
        a2 += 4;
        k.n += bcc(0x4B98, false) + cost(0x4B9C) + C.shift(d4, true) + seq(0x4BA0, 0x4BC6);
        for ([_]i64{ 8, 0xA, 0xC, 0xE }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d2);
        d2 = swap(d2);
        for ([_]i64{ 0, 2, 4, 6 }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d2);
        r[2] = d2;
        a1 += 0xA0;
    }
    r[7] = setw(r[7], d7);
    r[9] = a1;
    r[10] = a2;
}

/// $4BC6: OR the new frame's 4 planes (no mask), only while the hand is up (b0).
pub fn draw(st: *St, r: *[16]i64, d0: i64, k: *Clock) void {
    k.n += cost(0x4BC6);
    if (d0 & 1 == 0) {
        k.n += bcc(0x4BCA, true) + cost(0x4918);
        return;
    }
    var a1 = st.rl(0x0E5E);
    var a2 = (st.rl(0x0E56) + st.g(V.screen_base)) & M32;
    const d6 = st.rw(0x0E62);
    var d7 = st.rw(0x0E64);
    r[6] = setw(r[6], d6);
    k.n += bcc(0x4BCA, false) + seq(0x4BCE, 0x4BEC);
    const lim = (st.g(V.lava_top) - 8) & M32;
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x4BEC);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x4BEE, true) + cost(0x4918);
            break;
        }
        k.n += bcc(0x4BEE, false) + seq(0x4BF2, 0x4BFC);
        r[11] = lim;
        if (a2 >= lim) {
            k.n += bcc(0x4BFC, true) + cost(0x4918);
            break;
        }
        var d: [4]i64 = undefined;
        for (0..4) |j| d[j] = lsrl(st.rd(a1 + 2 * @as(i64, @intCast(j)), 4) & 0xFFFF0000, d6);
        k.n += bcc(0x4BFC, false) + seq(0x4C00, 0x4C16) + 4 * C.shift(d6, true) + seq(0x4C1E, 0x4C4E);
        for ([_]i64{ 8, 0xA, 0xC, 0xE }, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (d[j] & M16));
        for (&d) |*x| x.* = swap(x.*);
        for ([_]i64{ 0, 2, 4, 6 }, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (d[j] & M16));
        r[2] = d[0];
        r[3] = d[1];
        r[4] = d[2];
        r[5] = d[3];
        a1 += 8;
        a2 += 0xA0;
    }
    r[7] = setw(r[7], d7);
    r[9] = a1;
    r[10] = a2;
}

/// $4B16: erase, draw, commit the new frame.
pub fn finish(st: *St, r: *[16]i64, d0: i64, k: *Clock) void {
    r[0] = setw(r[0], d0);
    k.n += cost(0x4B16);
    erase(st, r, k);
    k.n += cost(0x4B18);
    draw(st, r, d0, k);
    st.ww(0x0E32, d0);
    st.ww(0x0E46, st.rw(0x0E64));
    st.ww(0x0E3C, st.rw(0x0E62));
    st.wl(0x0E34, st.rl(0x0E56));
    st.wl(0x0E38, st.rl(0x0E5E));
    k.n += seq(0x4B1C, 0x4B4A) + cost(0x4B4A);
}

/// $4A92: pick the frame, move y by the height change (not while holding),
/// wrap x, screen offset + shift.
pub fn frame(st: *St, r: *[16]i64, d0: i64, k: *Clock) void {
    const a1 = st.rl(0x4A94);
    var d2 = st.rw(0x0E48);
    const e = a1 + sw(d2);
    st.wl(0x0E5E, st.rd(e, 4));
    st.ww(0x0E64, st.rd(e + 4, 2));
    k.n += seq(0x4A92, 0x4AAE) + cost(0x4AAE);
    if (d0 & 2 != 0) {
        k.n += bcc(0x4AB2, true);
    } else {
        d2 = (st.rw(0x0E46) - st.rw(0x0E64)) & M16;
        st.ww(0x0E40, st.rw(0x0E40) + d2);
        k.n += bcc(0x4AB2, false) + seq(0x4AB4, 0x4AC6);
    }
    k.n += cost(0x4AC6);
    if (st.rw(0x0E3E) & 0x8000 != 0) {
        st.ww(0x0E3E, st.rw(0x0E3E) + 0x140);
        k.n += bcc(0x4ACC, false) + cost(0x4ACE);
    } else k.n += bcc(0x4ACC, true);
    k.n += cost(0x4AD6);
    if (sw(st.rw(0x0E3E)) >= 0x140) {
        st.ww(0x0E3E, st.rw(0x0E3E) - 0x140);
        k.n += bcc(0x4ADE, false) + cost(0x4AE0);
    } else k.n += bcc(0x4ADE, true);
    d2 = st.rw(0x0E40) * 0xA0;
    st.wl(0x0E56, d2);
    d2 = swap(divu(st.rw(0x0E3E), 0x10));
    st.ww(0x0E62, d2);
    d2 = lsrl(lsrl(d2, 8), 5);
    st.wl(0x0E56, st.rl(0x0E56) + d2);
    r[2] = d2;
    r[9] = a1;
    k.n += seq(0x4AE8, 0x4B16);
    finish(st, r, d0, k);
}
