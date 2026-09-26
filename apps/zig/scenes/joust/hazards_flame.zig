// --------------------------------------------------------------------------
// Call 2, $7930: the lava flames / bridge ends (the model's c_flame.py).
//
// $0DAA is a 28-byte record, copied to $0DC6, advanced there, drawn (the old
// erased from $0DAA, the new drawn from $0DC6), then copied back:
//   +0 w line count (== +2 while shrinking)   +2 w height (lines drawn)
//   +4 l left sprite    +8 l left screen offset   +$C w left shift   +$E w left side
//   +$10 l right sprite +$14 l right offset       +$18 w right shift +$1A w right side
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
const sw = State.s16;
const sl = State.s32;
const rorl = State.rorl;
const lsrl = State.lsrl;

const OLD: i64 = 0x0DAA;
const NEW: i64 = 0x0DC6;

const Out = struct {
    d4: i64,
    d5: i64,
    d6: ?i64,
    d7: i64,
    a1: i64,
    a2: i64,
    a3: i64,
    d: ?[4]i64,
};

/// $7AA4: AND the mask ($90 into the sprite) over d7 lines; the side flag +$A
/// picks the groups (tst.b d5: blt skips the right group, bgt skips the left).
fn erase(st: *St, a5: i64, d7_0: i64, k: *Clock) Out {
    var d7 = d7_0;
    var a3 = st.rd(a5, 4) + 0x90;
    var a2 = (st.rd(a5 + 4, 4) + st.g(V.screen_base)) & M32;
    const d4 = st.rd(a5 + 8, 2);
    const d5 = st.rd(a5 + 0xA, 2);
    const b5 = d5 & 0xFF;
    k.n += seq(0x7AA4, 0x7ABC);
    var d6: ?i64 = null;
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x7ABC);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x7ABE, false) + cost(0x7AC0);
            return .{ .d4 = d4, .d5 = d5, .d6 = d6, .d7 = d7, .a1 = 0, .a2 = a2, .a3 = a3, .d = null };
        }
        var m = rorl(st.rd(a3, 4), d4);
        a3 += 4;
        k.n += bcc(0x7ABE, true) + cost(0x7AC2) + C.shift(d4, true) + cost(0x7AC6);
        if (b5 & 0x80 != 0) {
            k.n += bcc(0x7AC8, true);
        } else {
            k.n += bcc(0x7AC8, false) + seq(0x7ACA, 0x7ADA);
            for ([_]i64{ 8, 0xA, 0xC, 0xE }) |o| st.wr(a2 + o, 2, st.rd(a2 + o, 2) & m);
        }
        k.n += cost(0x7ADA);
        if (b5 != 0 and b5 & 0x80 == 0) {
            k.n += bcc(0x7ADC, true);
        } else {
            k.n += bcc(0x7ADC, false) + seq(0x7ADE, 0x7AEE);
            m = swap(m);
            for ([_]i64{ 0, 2, 4, 6 }) |o| st.wr(a2 + o, 2, st.rd(a2 + o, 2) & m);
        }
        d6 = m;
        a2 += 0xA0;
        k.n += seq(0x7AEE, 0x7AF4);
    }
}

/// $7AF4: mask + 4 planes (the sprite's 4 words, shifted) over d7 lines.
fn draw(st: *St, a5: i64, d7_0: i64, k: *Clock) Out {
    var d7 = d7_0;
    var a1 = st.rd(a5, 4);
    var a3 = a1 + 0x90;
    var a2 = (st.rd(a5 + 4, 4) + st.g(V.screen_base)) & M32;
    const d4 = st.rd(a5 + 8, 2);
    const d5 = st.rd(a5 + 0xA, 2);
    const b5 = d5 & 0xFF;
    k.n += seq(0x7AF4, 0x7B0E);
    var d: ?[4]i64 = null;
    var d6: ?i64 = null;
    while (true) {
        d7 = (d7 - 1) & M16;
        k.n += cost(0x7B0E);
        if (d7 & 0x8000 != 0) {
            k.n += bcc(0x7B10, false) + cost(0x7B12);
            return .{ .d4 = d4, .d5 = d5, .d6 = d6, .d7 = d7, .a1 = a1, .a2 = a2, .a3 = a3, .d = d };
        }
        var m = rorl(st.rd(a3, 4), d4);
        a3 += 4;
        var dd: [4]i64 = undefined;
        for (0..4) |j| dd[j] = lsrl(st.rd(a1 + 2 * @as(i64, @intCast(j)), 4) & 0xFFFF0000, d4);
        k.n += bcc(0x7B10, true) + seq(0x7B14, 0x7B2C) + 5 * C.shift(d4, true) + cost(0x7B36);
        if (b5 & 0x80 != 0) {
            k.n += bcc(0x7B38, true);
        } else {
            k.n += bcc(0x7B38, false) + seq(0x7B3A, 0x7B5A);
            const offs = [_]i64{ 8, 0xA, 0xC, 0xE };
            for (offs) |o| st.wr(a2 + o, 2, st.rd(a2 + o, 2) & m);
            for (offs, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (dd[j] & M16));
        }
        k.n += cost(0x7B5A);
        if (b5 != 0 and b5 & 0x80 == 0) {
            k.n += bcc(0x7B5C, true);
        } else {
            k.n += bcc(0x7B5C, false) + seq(0x7B5E, 0x7B84);
            m = swap(m);
            for (&dd) |*x| x.* = swap(x.*);
            const offs = [_]i64{ 0, 2, 4, 6 };
            for (offs) |o| st.wr(a2 + o, 2, st.rd(a2 + o, 2) & m);
            for (offs, 0..) |o, j| st.wr(a2 + o, 2, st.rd(a2 + o, 2) | (dd[j] & M16));
        }
        d6 = m;
        d = dd;
        a2 += 0xA0;
        a1 += 8;
        k.n += seq(0x7B84, 0x7B8E);
    }
}

/// $7966..$7A44 on the copy at $0DC6.
fn advance(st: *St, k: *Clock) void {
    const a4 = NEW;
    for ([_][2]i64{ .{ 4, 0x7966 }, .{ 0x10, 0x7980 } }) |oa| {
        const o = oa[0];
        const at = oa[1];
        st.wl(a4 + o, st.rl(a4 + o) + 0xD8);
        k.n += seq(at, at + 0x10);
        if (sl(st.rl(a4 + o)) < sl(st.rl(at + 0xA))) {
            k.n += bcc(at + 0x10, true);
        } else {
            st.wl(a4 + o, st.rl(at + 0x14));
            k.n += bcc(at + 0x10, false) + cost(at + 0x12);
        }
    }
    k.n += cost(0x799A);
    if (st.rw(a4 + 0x18) == 0xC) {
        const d0 = (st.rl(a4 + 0x14) - st.rl(a4 + 8)) & M32;
        k.n += bcc(0x79A0, false) + seq(0x79A2, 0x79AE);
        if (!(sw(d0) > 0x60)) {
            k.n += bcc(0x79AE, false) + seq(0x79B0, 0x79CA) + cost(0x79CA);
            st.wl(a4 + 8, st.rl(a4 + 8) + 0xA0);
            st.wl(a4 + 0x14, st.rl(a4 + 0x14) + 0xA0);
            st.ww(a4 + 2, st.rw(a4 + 2) - 1);
            st.ww(a4, st.rw(a4 + 2));
            return;
        }
        k.n += bcc(0x79AE, true);
    } else {
        k.n += bcc(0x79A0, true);
    }
    k.n += cost(0x79CE);
    if (sw(st.rw(a4 + 2)) < 0x11) {
        k.n += bcc(0x79D4, false) + seq(0x79D6, 0x79EA) + cost(0x79EA);
        st.wl(a4 + 8, st.rl(a4 + 8) - 0xA0);
        st.wl(a4 + 0x14, st.rl(a4 + 0x14) - 0xA0);
        st.ww(a4 + 2, st.rw(a4 + 2) + 1);
        return;
    }
    k.n += bcc(0x79D4, true) + cost(0x79EC);
    if (st.g(V.wave) != 3) {
        k.n += bcc(0x79F4, true);
        return;
    }
    k.n += bcc(0x79F4, false) + cost(0x79F6);
    if (sw(st.rw(0x1828)) >= 0x13E) {
        k.n += bcc(0x79FE, false) + seq(0x7A00, 0x7A10);
        st.ww(0x1828, 0x134);
        st.ww(0x1826, 0xFFF5);
    } else {
        k.n += bcc(0x79FE, true);
    }
    st.ww(0x1826, st.rw(0x1826) + 1);
    st.ww(0x1828, st.rw(0x1828) - 1);
    st.ww(a4 + 0xC, st.rw(a4 + 0xC) + 1);
    k.n += seq(0x7A10, 0x7A26);
    if (sw(st.rw(a4 + 0xC)) >= 0x10) {
        k.n += bcc(0x7A26, false) + seq(0x7A28, 0x7A34);
        st.wl(a4 + 8, st.rl(a4 + 8) + 8);
        st.ww(a4 + 0xC, 0);
        st.ww(a4 + 0xE, 0);
    } else {
        k.n += bcc(0x7A26, true);
    }
    const old = st.rw(a4 + 0x18);
    st.ww(a4 + 0x18, old - 1);
    k.n += cost(0x7A34);
    if (sw(old) >= 1) {
        k.n += bcc(0x7A38, true);
    } else {
        k.n += bcc(0x7A38, false) + seq(0x7A3A, 0x7A48);
        st.wl(a4 + 0x14, st.rl(a4 + 0x14) - 8);
        st.ww(a4 + 0x18, 0xF);
        st.ww(a4 + 0x1A, 0);
    }
}

/// Call 2.
pub fn call_7930_lava_flames(st: *St) void {
    var r = st.regs;
    var k = Clock.init(st, cost(0x0024) + seq(0x7930, 0x793A));
    r[8] = BASE + OLD;
    if (sw(st.rw(OLD)) <= 0) {
        k.n += bcc(0x793A, true) + cost(0x7AA2);
        st.regs = r;
        k.done();
        return;
    }
    st.s(V.flame_timer, st.g(V.flame_timer) - 1);
    k.n += bcc(0x793A, false) + cost(0x793E);
    if (st.g(V.flame_timer) != 0) {
        k.n += bcc(0x7944, true) + cost(0x7AA2);
        st.regs = r;
        k.done();
        return;
    }
    k.n += bcc(0x7944, false) + seq(0x7948, 0x7950);
    st.s(V.flame_timer, 3);
    k.n += seq(0x7950, 0x795C);
    var d0: i64 = 0x18;
    while (d0 >= 0) : (d0 -= 4) {
        st.wl(NEW + d0, st.rl(OLD + d0));
        k.n += seq(0x795C, 0x7964) + bcc(0x7964, d0 > 0);
    }
    advance(st, &k);
    k.n += seq(0x7A48, 0x7A58) + cost(0x7A58);
    _ = erase(st, BASE + OLD + 4, st.rw(OLD + 2), &k);
    k.n += seq(0x7A5A, 0x7A6A) + cost(0x7A6A);
    const f = draw(st, BASE + NEW + 4, st.rw(NEW + 2), &k);
    k.n += seq(0x7A6E, 0x7A7E) + cost(0x7A7E);
    const e = erase(st, BASE + OLD + 0x10, st.rw(OLD + 2), &k);
    k.n += seq(0x7A80, 0x7A90) + cost(0x7A90);
    const last = draw(st, BASE + NEW + 0x10, st.rw(NEW + 2), &k);
    k.n += seq(0x7A92, 0x7A98);
    d0 = 0x18;
    while (d0 >= 0) : (d0 -= 4) {
        st.wl(OLD + d0, st.rl(NEW + d0));
        k.n += seq(0x7A98, 0x7AA0) + bcc(0x7AA0, d0 > 0);
    }
    k.n += cost(0x7AA2);
    r[0] = 0xFFFC;
    var d6 = last.d6;
    var d = last.d;
    if (d == null) { // the last draw drew nothing: registers of the one before
        d6 = if (e.d6 != null) e.d6 else f.d6;
        d = f.d;
    }
    if (d) |dv| {
        r[1] = dv[1];
        r[2] = dv[2];
        r[3] = dv[3];
    }
    r[4] = setw(r[4], last.d4);
    r[5] = setw(r[5], last.d5);
    if (d6) |v| r[6] = v;
    r[7] = last.d7;
    r[9] = last.a1;
    r[10] = last.a2;
    r[11] = last.a3;
    r[12] = BASE + NEW;
    r[13] = BASE + NEW + 0x10;
    st.regs = r;
    k.done();
}
