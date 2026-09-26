// --------------------------------------------------------------------------
// Call 8 continued (the model's c_ptero.py): the flap animation $50F0, the
// move with its wrap and clip timers $50FA, and the erase $522C / draw $52A0.
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
const sb = State.s8;

/// $50F0: advance the flap animation (not while dying).
pub fn move(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    k.n += cost(0x50F0);
    if (d0 & 0x20 != 0) {
        k.n += bcc(0x50F4, true);
    } else {
        st.ww(a0 + 0x1A, st.rw(a0 + 0x1A) + 3);
        k.n += bcc(0x50F4, false) + cost(0x50F6);
    }
    return draw_all(st, r, a0, d0, k);
}

/// $50FA: frame, move with wrap, clip timers, erase + draw, commit.
pub fn draw_all(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    const a1 = st.rl(0x50FC);
    var d1 = st.rw(a0 + 0x1A) & 0x18;
    st.wl(0x0E5E, st.rd(a1 + d1, 4));
    st.ww(0x0E66, st.rd(a1 + d1 + 4, 2));
    st.ww(0x0E64, st.rd(a1 + d1 + 6, 2));
    k.n += seq(0x50FA, 0x5124);
    if (d0 & 4 != 0) {
        st.wl(0x0E5E, st.rl(0x0E5E) + 0x180);
        k.n += bcc(0x5124, false) + cost(0x5126);
    } else {
        k.n += bcc(0x5124, true);
    }
    d1 = st.rw(a0 + 0x10);
    k.n += seq(0x5130, 0x5138);
    if (d0 & 4 == 0) {
        const x = st.rw(a0 + 0xC);
        st.ww(a0 + 0xC, x - d1);
        k.n += bcc(0x5138, false) + cost(0x513A);
        if (sw(x) < sw(d1)) {
            st.ww(a0 + 0xC, 0x13F);
            k.n += bcc(0x513E, false) + seq(0x5140, 0x5146) + cost(0x5146);
        } else {
            k.n += bcc(0x513E, true);
        }
    } else {
        const v = (st.rw(a0 + 0xC) + d1) & M16;
        st.ww(a0 + 0xC, v);
        k.n += bcc(0x5138, true) + seq(0x5148, 0x5152);
        if (sw(v) < 0x140) {
            k.n += bcc(0x5152, true);
        } else {
            st.ww(a0 + 0xC, 0);
            k.n += bcc(0x5152, false) + cost(0x5154);
        }
    }
    d1 = st.rw(a0 + 0x12);
    k.n += seq(0x5158, 0x5160);
    if (d0 & 2 == 0) {
        const y = st.rw(a0 + 0xE);
        st.ww(a0 + 0xE, y - d1);
        k.n += bcc(0x5160, false) + cost(0x5162);
        if (sw(y) < sw(d1)) {
            st.ww(a0 + 0xE, 0);
            k.n += bcc(0x5166, false) + seq(0x5168, 0x516C) + cost(0x516C);
        } else {
            k.n += bcc(0x5166, true);
        }
    } else {
        const v = (st.rw(a0 + 0xE) + d1) & M16;
        st.ww(a0 + 0xE, v);
        k.n += bcc(0x5160, true) + seq(0x516E, 0x5178);
        if (v < 0x96) {
            k.n += bcc(0x5178, true);
        } else {
            st.ww(a0 + 0xE, 0x96);
            k.n += bcc(0x5178, false) + cost(0x517A);
        }
    }
    st.wl(0x0E56, st.rw(a0 + 0xE) * 0xA0);
    d1 = swap(divu(st.rw(a0 + 0xC), 0x10));
    st.ww(0x0E62, d1);
    d1 = lsrl(lsrl(d1, 8), 5);
    st.wl(0x0E56, st.rl(0x0E56) + d1);
    r[1] = d1;
    k.n += seq(0x5180, 0x51AE);
    for ([_][3]i64{ .{ 0x1C, 0x51AE, 0x51B0 }, .{ 0x1D, 0x51B8, 0x51BA } }) |t| {
        const o = t[0];
        const old = st.rb(a0 + o);
        st.wb(a0 + o, old - 1);
        if (sb(old) < 1) {
            st.wb(a0 + o, 0);
            k.n += bcc(t[1], false) + cost(t[2]);
        } else {
            k.n += bcc(t[1], true);
        }
        if (o == 0x1C) k.n += cost(0x51B4);
    }
    const b = st.rb(a0 + 0x1D);
    st.s(V.ptero_var_d4c, b);
    st.s(V.ptero_var_d4d, b);
    st.s(V.ptero_var_d4e, b);
    k.n += seq(0x51BE, 0x51DC);
    const x = st.rw(a0 + 0xC);
    if (x >= 0x120) {
        st.s(V.ptero_var_d4e, st.rb(a0 + 0x1C));
        k.n += bcc(0x51DC, false) + seq(0x51DE, 0x51EC);
        if (x >= 0x130) {
            st.s(V.ptero_var_d4d, st.rb(a0 + 0x1C));
            k.n += bcc(0x51EC, false) + cost(0x51EE);
        } else {
            k.n += bcc(0x51EC, true);
        }
    } else {
        k.n += bcc(0x51DC, true);
    }
    k.n += cost(0x51F6);
    erase(st, r, a0, k);
    k.n += cost(0x51F8);
    draw(st, r, k);
    st.ww(a0, d0);
    st.ww(a0 + 0x18, st.rw(0x0E64));
    st.ww(a0 + 0xA, st.rw(0x0E62));
    st.ww(a0 + 0x16, st.rw(0x0E66));
    st.wl(a0 + 2, st.rl(0x0E56));
    st.wl(a0 + 6, st.rl(0x0E5E));
    k.n += seq(0x51FC, 0x5228) + cost(0x5228);
    r[0] = d0 & M32;
}

/// $522C: AND the old frame's mask (at sprite + $120: 2 longs a line) over 3 groups.
fn erase(st: *St, r: *[16]i64, a0: i64, k: *Clock) void {
    var a2 = (st.rl(a0 + 6) + 0x120) & M32;
    var a1 = (st.rl(a0 + 2) + st.g(V.screen_base) + sw(st.rw(a0 + 0x16))) & M32;
    const d4 = st.rw(a0 + 0xA);
    var d7 = st.rw(a0 + 0x18);
    r[4] = setw(r[4], d4);
    k.n += seq(0x522C, 0x524A);
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x524A);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x524C, false) + cost(0x524E);
            break;
        }
        var d1 = rorl(st.rd(a2, 4), d4);
        var d2 = rorl(st.rd(a2 + 4, 4), d4);
        a2 += 8;
        k.n += bcc(0x524C, true) + seq(0x5250, 0x5254) + 2 * C.shift(d4, true) + seq(0x5258, 0x52A0);
        for ([_]i64{ 8, 0xA, 0xC, 0xE }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d1);
        for ([_]i64{ 0x10, 0x12, 0x14, 0x16 }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d2);
        d1 = swap(d1);
        d2 = swap(d2);
        for ([_]i64{ 0, 2, 4, 6 }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d1);
        for ([_]i64{ 8, 0xA, 0xC, 0xE }) |o| st.wr(a1 + o, 2, st.rd(a1 + o, 2) & d2);
        r[1] = d1;
        r[2] = d2;
        a1 += 0xA0;
    }
    r[7] = setw(r[7], d7);
    r[9] = a1;
    r[10] = a2;
}

/// $52A0: OR the new frame (4 planes, 3 groups; each clip flag hides one part).
fn draw(st: *St, r: *[16]i64, k: *Clock) void {
    var a1 = st.rl(0x0E5E);
    var a2 = (st.rl(0x0E56) + st.g(V.screen_base) + sw(st.rw(0x0E66))) & M32;
    const d5 = st.rw(0x0E62);
    var d7 = st.rw(0x0E64);
    r[5] = setw(r[5], d5);
    k.n += seq(0x52A0, 0x52C4);
    const h_r = st.g(V.ptero_var_d4d);
    const h_l = st.g(V.ptero_var_d4c);
    const h_x = st.g(V.ptero_var_d4e);
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x52C4);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x52C6, false) + cost(0x52C8);
            break;
        }
        var d: [4]i64 = undefined;
        for (0..4) |j| {
            const o = 2 * @as(i64, @intCast(j));
            d[j] = lsrl((st.rd(a1 + o, 2) << 16) | st.rd(a1 + 8 + o, 2), d5);
        }
        k.n += bcc(0x52C6, true) + seq(0x52CA, 0x52E8) + 4 * C.shift(d5, true) + cost(0x52F0);
        if (h_r != 0) {
            k.n += bcc(0x52F6, true);
        } else {
            k.n += bcc(0x52F6, false) + seq(0x52F8, 0x5308);
            for ([_]i64{ 8, 0xA, 0xC, 0xE }, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (d[j] & M16));
        }
        k.n += cost(0x5308);
        if (h_l != 0) {
            k.n += bcc(0x530E, true);
        } else {
            k.n += bcc(0x530E, false) + seq(0x5310, 0x5326);
            for (&d) |*x| x.* = swap(x.*);
            for ([_]i64{ 0, 2, 4, 6 }, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (d[j] & M16));
        }
        k.n += cost(0x5326);
        if (h_x != 0) {
            k.n += bcc(0x532C, true);
        } else {
            for (0..4) |j| d[j] = lsrl(st.rd(a1 + 8 + 2 * @as(i64, @intCast(j)), 4) & 0xFFFF0000, d5);
            k.n += bcc(0x532C, false) + seq(0x532E, 0x5346) + 4 * C.shift(d5, true) + seq(0x534E, 0x535E);
            for ([_]i64{ 0x10, 0x12, 0x14, 0x16 }, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (d[j] & M16));
        }
        r[1] = d[0];
        r[2] = d[1];
        r[3] = d[2];
        r[4] = d[3];
        a1 += 0x18;
        a2 += 0xA0;
        k.n += seq(0x535E, 0x5366) + cost(0x5366);
    }
    r[7] = setw(r[7], d7);
    r[9] = a1;
    r[10] = a2;
}
