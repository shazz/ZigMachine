// --------------------------------------------------------------------------
// Call 13, $488A: the lava troll's hand, from wave 4 (the model's c_troll.py).
//
//   $0E32 state: b0 hand up (drawn), b1 holding a victim, b2 facing right
//   $0E34/$0E38/$0E3C/$0E46  the drawn frame (screen offset, sprite, shift, height)
//   $0E3E x  $0E40 y  $0E42 victim slot  $0E48 frame index (0/8/$10/$18 into $4C4E)
//   $0E4B cadence counter (2,1,0; $FF right after the hand appears)
// The frame, its erase/draw and the commit are hazards_troll_draw.zig.
// --------------------------------------------------------------------------
const tdraw = @import("hazards_troll_draw.zig");
const State = @import("state.zig");
const C = @import("hazards_common.zig");
const cyc = @import("cyc.zig");
const score = @import("flow_score.zig");
const St = State.St;
const V = State.V;
const Clock = C.Clock;
const BASE = State.BASE;
const SLOTS = State.SLOTS;
const SLOT_SZ = State.SLOT_SZ;
const M16 = C.M16;
const seq = C.seq;
const cost = C.cost;
const bcc = C.bcc;
const setw = State.setw;
const sw = State.s16;
const sb = State.s8;

const SLOTS_END = SLOTS + 14 * SLOT_SZ;

/// $49D0: the hand sinks back; when the frame index goes negative it is gone.
fn lower(st: *St, r: *[16]i64, d0_in: i64, k: *Clock) void {
    var d0 = d0_in;
    st.ww(0x0E40, st.rw(0x0E40) + 1);
    st.ww(0x0E3E, st.rw(0x0E3E) - 1);
    k.n += seq(0x49D0, 0x49E2);
    if (st.g(V.troll_cnt) != 0) {
        k.n += bcc(0x49E2, true);
        return tdraw.frame(st, r, d0, k);
    }
    const old = st.rw(0x0E48);
    st.ww(0x0E48, old - 8);
    k.n += bcc(0x49E2, false) + cost(0x49E6);
    if (sw(old) >= 8) {
        k.n += bcc(0x49EC, true);
        return tdraw.frame(st, r, d0, k);
    }
    d0 &= ~@as(i64, 1);
    k.n += bcc(0x49EC, false) + seq(0x49F0, 0x49F4) + cost(0x49F4);
    tdraw.finish(st, r, d0, k);
}

/// $49F8: the victim is held (b4 of its flags cleared, re-set if still held).
fn holding(st: *St, r: *[16]i64, d0_in: i64, k: *Clock) void {
    var d0 = d0_in;
    const a0 = st.rl(0x0E42);
    r[8] = a0;
    var d1 = st.rd(a0, 2) & ~@as(i64, 0x10);
    st.wr(a0, 2, d1);
    d0 &= ~@as(i64, 2);
    r[1] = setw(r[1], d1);
    k.n += seq(0x49F8, 0x4A10);
    if (d1 == 0) {
        k.n += bcc(0x4A10, true);
        return lower(st, r, d0, k);
    }
    k.n += bcc(0x4A10, false) + cost(0x4A12);
    if (d1 & 0x2000 != 0) {
        k.n += bcc(0x4A16, true);
        return lower(st, r, d0, k);
    }
    k.n += bcc(0x4A16, false) + cost(0x4A18);
    if (sw(st.rd(a0 + 4, 2)) < 0x8C) {
        k.n += bcc(0x4A1E, false) + cost(0x4A20);
        if (d1 & 4 == 0) {
            k.n += bcc(0x4A24, true);
            return lower(st, r, d0, k);
        }
        // $4A26: a player dropped while still over the lava edge band: +50,
        // then package D's $4250 (carry + reprint the score)
        st.wr(a0 + 0x43, 1, st.rd(a0 + 0x43, 1) + 5);
        k.n += bcc(0x4A24, false) + cost(0x4A26) + cost(0x4A2A);
        st.clock(k.n);
        k.n = 0;
        st.regs = r.*;
        var cy = cyc.Cy.init(st);
        score.score_add(st, &cy, 0x4250, a0 - BASE);
        cy.flush();
        r.* = st.regs;
        k.n += cost(0x4A2E);
        return lower(st, r, d0, k);
    }
    k.n += bcc(0x4A1E, true) + cost(0x4A30);
    const tests = [_][4]i64{ .{ 0x80, 0x4A34, 0x4A36, 0x4A44 }, .{ 0x100, 0x4A4C, 0x4A4E, 0x4A5C } };
    for (tests) |t| {
        if (d1 & t[0] != 0) {
            st.ww(0x0E32, 0);
            d1 &= ~@as(i64, 0x10);
            st.wr(a0, 2, d1);
            k.n += bcc(t[1], false) + seq(t[2], t[3]) + cost(t[3]);
            return tdraw.finish(st, r, d0, k);
        }
        k.n += bcc(t[1], true) + cost(if (t[0] == 0x80) t[1] + 0x14 else 0x4A60);
    }
    d1 |= 0x10;
    st.wr(a0, 2, d1);
    r[1] = setw(r[1], d1);
    d0 |= 2;
    st.ww(0x0E40, (st.rd(a0 + 4, 2) + 0xC) & M16);
    st.ww(0x0E3E, (st.rd(a0 + 2, 2) - 2) & M16);
    st.ww(0x0E48, 0x18);
    k.n += seq(0x4A64, 0x4A92);
    tdraw.frame(st, r, d0, k);
}

/// Call 13.
pub fn call_488a_troll(st: *St) void {
    var r = st.regs;
    var k = Clock.init(st, cost(0x0066) + cost(0x488A));
    troll(st, &r, &k);
    st.regs = r;
    k.done();
}

fn troll(st: *St, r: *[16]i64, k: *Clock) void {
    if (sb(st.g(V.wave)) < 4) {
        k.n += bcc(0x4892, true) + cost(0x4918);
        return;
    }
    k.n += bcc(0x4892, false) + cost(0x4896);
    const old = st.g(V.troll_cnt);
    st.s(V.troll_cnt, old - 1);
    if (sb(old) >= 1) {
        k.n += bcc(0x489C, true);
    } else {
        st.s(V.troll_cnt, 2);
        k.n += bcc(0x489C, false) + cost(0x489E);
    }
    const d0 = st.rw(0x0E32);
    r[0] = setw(r[0], d0);
    k.n += seq(0x48A6, 0x48B0);
    if (d0 & 2 != 0) {
        k.n += bcc(0x48B0, true);
        return holding(st, r, d0, k);
    }
    k.n += bcc(0x48B0, false) + cost(0x48B4);
    var a0 = SLOTS;
    while (true) {
        const d1 = st.rw(a0);
        r[1] = setw(r[1], d1);
        r[8] = BASE + a0;
        k.n += cost(0x48BA);
        var ok = false;
        if (d1 == 0) {
            k.n += bcc(0x48BE, true);
        } else {
            k.n += bcc(0x48BE, false);
            var broke = false;
            for ([_][2]i64{ .{ 0x80, 0x48C0 }, .{ 0x2000, 0x48C6 }, .{ 0x100, 0x48CC } }) |ba| {
                k.n += cost(ba[1]);
                if (d1 & ba[0] != 0) {
                    k.n += bcc(ba[1] + 4, true);
                    broke = true;
                    break;
                }
                k.n += bcc(ba[1] + 4, false);
            }
            if (!broke) {
                k.n += cost(0x48D2);
                if (sw(st.rw(a0 + 4)) < 0x8F) {
                    k.n += bcc(0x48D8, true);
                } else {
                    const d2 = (st.rw(a0 + 2) - 0x32) & M16;
                    r[2] = setw(r[2], d2);
                    k.n += bcc(0x48D8, false) + seq(0x48DA, 0x48E6);
                    if (d2 <= 0xDC) {
                        k.n += bcc(0x48E6, true);
                    } else {
                        k.n += bcc(0x48E6, false) + cost(0x48E8);
                        ok = true;
                    }
                }
            }
        }
        if (ok) {
            if (d0 & 1 == 0) {
                k.n += bcc(0x48EC, true);
                return appear(st, r, a0, d1, k);
            }
            const d2 = (st.rw(a0 + 2) - st.rw(0x0E3E)) & M16;
            r[2] = setw(r[2], d2);
            k.n += bcc(0x48EC, false) + seq(0x48EE, 0x48FC);
            if (d2 <= 0xC) {
                k.n += bcc(0x48FC, true);
                return reach(st, r, a0, d0, k);
            }
            k.n += bcc(0x48FC, false) + cost(0x48FE);
            if (sw(d2) <= -0x134) {
                k.n += bcc(0x4902, true);
                return reach(st, r, a0, d0, k);
            }
            k.n += bcc(0x4902, false);
        }
        a0 += SLOT_SZ;
        r[8] = BASE + a0;
        k.n += seq(0x4904, 0x490E);
        if (a0 == SLOTS_END) {
            k.n += bcc(0x490E, false);
            break;
        }
        k.n += bcc(0x490E, true);
    }
    k.n += cost(0x4910);
    if (d0 & 1 != 0) {
        k.n += bcc(0x4914, false);
        return lower(st, r, d0, k);
    }
    k.n += bcc(0x4914, true) + cost(0x4918);
}

/// $491A: a rider low over the lava -> the hand appears under it.
fn appear(st: *St, r: *[16]i64, a0: i64, d1: i64, k: *Clock) void {
    var d0: i64 = 1;
    k.n += seq(0x491A, 0x4924);
    if (d1 & 0x8000 != 0) {
        d0 |= 4;
        k.n += bcc(0x4924, false) + cost(0x4926);
    } else k.n += bcc(0x4924, true);
    r[0] = setw(r[0], d0);
    st.ww(0x0E3C, 0);
    st.ww(0x0E48, 0);
    st.s(V.troll_cnt, 0xFF);
    st.ww(0x0E46, 9);
    st.ww(0x0E3E, st.rw(a0 + 2));
    st.ww(0x0E40, 0xAF);
    st.ww(0x0E3E, st.rw(0x0E3E) - 0xC);
    st.wl(0x0E38, st.rl(0x4960));
    st.wl(0x0E34, st.rl(0x496A));
    k.n += seq(0x492A, 0x4972);
    reach(st, r, a0, d0, k);
}

/// $4972: grab when within 11 lines, else rise one line and follow the rider's x.
fn reach(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    var d2 = (st.rw(0x0E40) - st.rw(a0 + 4)) & M16;
    r[2] = setw(r[2], d2);
    k.n += seq(0x4972, 0x4980);
    if (d2 <= 0xB) {
        st.wl(0x0E42, BASE + a0);
        k.n += bcc(0x4980, false) + seq(0x4982, 0x4992);
        C.sfx(k, 6);
        k.n += seq(0x4992, 0x4994) + cost(0x4994);
        r[0] = setw(r[0], d0);
        return holding(st, r, d0, k);
    }
    st.ww(0x0E40, st.rw(0x0E40) - 1);
    k.n += bcc(0x4980, true) + seq(0x4996, 0x49A2);
    if (st.g(V.troll_cnt) != 0) {
        k.n += bcc(0x49A2, true);
    } else {
        st.ww(0x0E48, st.rw(0x0E48) + 8);
        k.n += bcc(0x49A2, false) + seq(0x49A4, 0x49B2);
        if (st.rw(0x0E48) <= 0x10) {
            k.n += bcc(0x49B2, true);
        } else {
            st.ww(0x0E48, 0x10);
            k.n += bcc(0x49B2, false) + cost(0x49B4);
        }
    }
    d2 = st.rw(a0 + 6);
    r[2] = setw(r[2], d2);
    st.ww(0x0E3E, st.rw(0x0E3E) + d2);
    st.ww(0x0E3E, st.rw(0x0E3E) + 1);
    k.n += seq(0x49BC, 0x49CC) + cost(0x49CC);
    r[0] = setw(r[0], d0);
    tdraw.frame(st, r, d0, k);
}
