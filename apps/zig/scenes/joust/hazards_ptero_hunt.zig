// --------------------------------------------------------------------------
// Call 8 continued (the model's c_ptero.py): the platform level probe $53BA,
// dying $4F4A, hunting $5004 with the lance test $540A, the stunned run $50D0.
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
const lsrl = State.lsrl;
const sw = State.s16;
const sb = State.s8;
const back = @import("hazards_ptero_draw.zig");

/// $53BA after the bsr: 4 when a platform's underside band is at the
/// pterodactyl's y (x within $3C..$FA), else 0; d1 left in r[1].
pub fn plat_level(st: *St, r: *[16]i64, a0: i64, k: *Clock) i64 {
    k.n += cost(0x53BA);
    const x = sw(st.rw(a0 + 0xC));
    if (x < 0x3C) {
        k.n += bcc(0x53C0, true);
    } else {
        k.n += bcc(0x53C0, false) + cost(0x53C2);
        if (x > 0xFA) {
            k.n += bcc(0x53C8, true);
        } else {
            k.n += bcc(0x53C8, false) + cost(0x53CA);
            var a1: i64 = 0x1A42;
            const y = sw(st.rw(a0 + 0xE));
            while (true) {
                const a2 = st.rl(a1);
                r[10] = a2;
                k.n += seq(0x53D0, 0x53D4);
                if (st.rd(a2, 1) != 0) {
                    var d1 = divu(st.rl(a1 + 0xC), 0xA0);
                    const d2 = (d1 + st.rw(a1 + 4)) & M16;
                    r[2] = setw(r[2], d2);
                    k.n += bcc(0x53D4, false) + seq(0x53D6, 0x53E8);
                    if (sw(d2) >= y) {
                        d1 = setw(d1, d1 - 0xD);
                        k.n += bcc(0x53E8, false) + seq(0x53EA, 0x53F2);
                        if (sw(d1) <= y) {
                            r[1] = setw(d1, 4);
                            r[9] = BASE + a1;
                            k.n += bcc(0x53F2, false) + seq(0x53F4, 0x53F8) + cost(0x53F8);
                            return 4;
                        }
                        k.n += bcc(0x53F2, true);
                    } else {
                        k.n += bcc(0x53E8, true);
                    }
                    r[1] = d1;
                } else {
                    k.n += bcc(0x53D4, true);
                }
                a1 += 0x10;
                k.n += seq(0x53FA, 0x5404);
                if (a1 < 0x1AC2) {
                    k.n += bcc(0x5404, true);
                    continue;
                }
                k.n += bcc(0x5404, false);
                r[9] = BASE + a1;
                break;
            }
        }
    }
    r[1] = r[1] & 0xFFFF0000;
    k.n += seq(0x5406, 0x5408) + cost(0x5408);
    return 0;
}

/// $4F4A: speared: flash (flip every 4 frames), after the last flip a '1000' popup.
pub fn dying(st: *St, r: *[16]i64, a0: i64, d0_in: i64, k: *Clock) void {
    var d0 = d0_in;
    st.wb(a0 + 0x1D, 0);
    st.wb(a0 + 0x1C, 0);
    st.ww(a0 + 0x10, 0);
    st.ww(a0 + 0x12, 0);
    var v = (st.rb(a0 + 0x1E) - 1) & 0xFF;
    st.wb(a0 + 0x1E, v);
    k.n += seq(0x4F4A, 0x4F5E);
    if (v != 0) {
        k.n += bcc(0x4F5E, true);
        return flap(st, r, a0, d0, k);
    }
    d0 ^= 4;
    st.wb(a0 + 0x1E, 4);
    v = (st.rb(a0 + 0x1F) - 1) & 0xFF;
    st.wb(a0 + 0x1F, v);
    k.n += bcc(0x4F5E, false) + seq(0x4F62, 0x4F70);
    if (v != 0) {
        k.n += bcc(0x4F70, true);
        return flap(st, r, a0, d0, k);
    }
    d0 = 0;
    st.wb(a0 + 0x1D, 4);
    st.wb(a0 + 0x1C, 4);
    k.n += bcc(0x4F70, false) + seq(0x4F72, 0x4F86);
    var a1: i64 = 0x0E84;
    while (true) {
        k.n += cost(0x4F86);
        if (st.rb(a1) == 0) {
            k.n += bcc(0x4F8A, true);
            break;
        }
        a1 += 0xC;
        k.n += bcc(0x4F8A, false) + seq(0x4F8C, 0x4F96);
        if (a1 == 0x0FA4) {
            k.n += bcc(0x4F96, false) + cost(0x4F98);
            r[9] = BASE + a1;
            return back.move(st, r, a0, d0, k);
        }
        k.n += bcc(0x4F96, true);
    }
    r[9] = BASE + a1;
    st.wl(a1 + 8, st.rl(0x4F9E));
    st.wb(a1 + 2, 8);
    st.wb(a1, 1);
    st.wb(a1 + 1, 0x3C);
    var d1 = ((st.rw(a0 + 0xE) + 2) & M16) * 0xA0;
    st.wl(a1 + 4, d1);
    d1 = swap(divu((st.rw(a0 + 0xC) + 8) & M16, 0x10));
    st.wb(a1 + 3, d1);
    d1 = (lsrl(lsrl(d1, 8), 5) + st.g(V.screen_base)) & M32;
    st.wl(a1 + 4, st.rl(a1 + 4) + d1);
    r[1] = d1;
    k.n += seq(0x4F9C, 0x4FE4) + cost(0x4FE4);
    return back.move(st, r, a0, d0, k);
}

/// $4FE8: alternate the two dying frames.
pub fn flap(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    k.n += cost(0x4FE8);
    if (sw(st.rw(a0 + 0x1A)) < 0x18) {
        st.ww(a0 + 0x1A, 0x18);
        k.n += bcc(0x4FEE, false) + seq(0x4FF0, 0x4FF6) + cost(0x4FF6);
    } else {
        st.ww(a0 + 0x1A, 0x10);
        k.n += bcc(0x4FEE, true) + seq(0x4FFA, 0x5000) + cost(0x5000);
    }
    return back.move(st, r, a0, d0, k);
}

/// $5004: chase: the lance-in-mouth test against each live player, then
/// climb/dive toward the nearer player every 3rd frame (or follow platform
/// heights with no player).
pub fn hunt(st: *St, r: *[16]i64, a0: i64, d0_in: i64, k: *Clock) void {
    var d0 = d0_in;
    const a1: i64 = 0x0FA4;
    const a2: i64 = 0x0FF2;
    r[9] = BASE + a1;
    r[10] = BASE + a2;
    k.n += seq(0x5004, 0x5014);
    if (st.rb(a0 + 0x1D) != 0) {
        k.n += bcc(0x5014, true);
    } else {
        k.n += bcc(0x5014, false) + cost(0x5016);
        if (st.rb(a0 + 0x1C) != 0) {
            k.n += bcc(0x501A, true);
        } else {
            k.n += bcc(0x501A, false) + cost(0x501C);
            if (st.rb(a0 + 0x1E) != 0) {
                k.n += bcc(0x5020, true);
                return stunned(st, r, a0, d0, k);
            }
            k.n += bcc(0x5020, false) + cost(0x5024);
            if (st.g(V.alive_mask) & 1 != 0) {
                k.n += bcc(0x502C, false) + seq(0x502E, 0x5030) + cost(0x5030);
                r[11] = BASE + a1;
                lance(st, r, a0, a1, d0, k);
            } else {
                k.n += bcc(0x502C, true);
            }
            k.n += cost(0x5034);
            if (st.g(V.alive_mask) & 2 != 0) {
                k.n += bcc(0x503C, false) + seq(0x503E, 0x5040) + cost(0x5040);
                r[11] = BASE + a2;
                lance(st, r, a0, a2, d0, k);
            } else {
                k.n += bcc(0x503C, true);
            }
        }
    }
    st.ww(a0 + 0x10, 3);
    k.n += seq(0x5044, 0x5050);
    if (st.g(V.alive_mask) == 0) {
        d0 &= ~@as(i64, 2);
        k.n += bcc(0x5050, true) + seq(0x50AE, 0x50B2) + cost(0x50B2);
        const d1 = plat_level(st, r, a0, k);
        st.ww(a0 + 0x12, d1);
        k.n += cost(0x50B6);
        if (d1 == 0) {
            k.n += bcc(0x50BA, true);
        } else {
            st.ww(a0 + 0x12, 1);
            k.n += bcc(0x50BA, false) + seq(0x50BC, 0x50C2) + cost(0x50C2);
        }
        return back.move(st, r, a0, d0, k);
    }
    st.ww(a0 + 0x12, 0);
    const old = st.rb(a0 + 0x1F);
    st.wb(a0 + 0x1F, old - 1);
    k.n += bcc(0x5050, false) + seq(0x5052, 0x505A);
    if (sb(old) > 1) {
        k.n += bcc(0x505A, true);
        return back.move(st, r, a0, d0, k);
    }
    st.wb(a0 + 0x1F, 3);
    st.ww(a0 + 0x12, 1);
    k.n += bcc(0x505A, false) + seq(0x505E, 0x5072);
    const y = sw(st.rw(a0 + 0xE));
    var target = a2;
    if (st.g(V.alive_mask) & 1 != 0) {
        k.n += bcc(0x5072, false) + cost(0x5074);
        if (st.g(V.alive_mask) & 2 != 0) {
            var d1 = (st.rw(a1 + 4) - st.rw(a0 + 0xE)) & M16;
            d1 = (sw(d1) * sw(d1)) & M32;
            var d2 = (st.rw(a2 + 4) - st.rw(a0 + 0xE)) & M16;
            d2 = (sw(d2) * sw(d2)) & M32;
            r[1] = d1;
            r[2] = d2;
            k.n += bcc(0x507C, false) + seq(0x507E, 0x5094);
            if (sw(d2) < sw(d1)) {
                k.n += bcc(0x5094, true);
            } else {
                k.n += bcc(0x5094, false);
                target = a1;
            }
        } else {
            k.n += bcc(0x507C, true);
            target = a1;
        }
    } else {
        k.n += bcc(0x5072, true);
    }
    const at: i64 = if (target == a1) 0x5096 else 0x50A2;
    const d1 = st.rw(target + 4);
    r[1] = setw(r[1], d1);
    k.n += seq(at, at + 8);
    if (sw(d1) < y) {
        d0 &= ~@as(i64, 2);
        k.n += bcc(at + 8, true) + seq(0x50CA, 0x50CE) + cost(0x50CE);
    } else {
        d0 |= 2;
        k.n += bcc(at + 8, false) + cost(at + 0xA) + seq(0x50C4, 0x50C8) + cost(0x50C8);
    }
    return back.move(st, r, a0, d0, k);
}

/// $540A: a player's lance in the pterodactyl's open mouth -> SFX 3, 20 frames dying.
pub fn lance(st: *St, r: *[16]i64, a0: i64, a3: i64, d0: i64, k: *Clock) void {
    var d1 = (st.rw(a0 + 0xE) - st.rw(a3 + 4) + 4) & M16;
    r[1] = setw(r[1], d1);
    k.n += seq(0x540A, 0x5418);
    if (d1 > 0xA) {
        k.n += bcc(0x5418, true) + cost(0x5450);
        return;
    }
    d1 = (st.rw(a0 + 0xC) + 8 - st.rw(a3 + 2)) & M16;
    k.n += bcc(0x5418, false) + seq(0x541A, 0x5428);
    if (d0 & 4 != 0) {
        d1 = -d1 & M16;
        k.n += bcc(0x5428, false) + cost(0x542A);
    } else {
        k.n += bcc(0x5428, true);
    }
    r[1] = setw(r[1], d1);
    k.n += cost(0x542C);
    if (d1 >= 0xFF29) {
        k.n += bcc(0x5430, true) + cost(0x5450);
        return;
    }
    k.n += bcc(0x5430, false) + cost(0x5432);
    if (sw(d1) >= 0x69) {
        k.n += bcc(0x5436, true) + cost(0x5450);
        return;
    }
    k.n += bcc(0x5436, false) + cost(0x5438);
    if (sw(d1) <= 8) {
        k.n += bcc(0x543C, true) + cost(0x5450);
        return;
    }
    k.n += bcc(0x543C, false) + seq(0x543E, 0x5448);
    C.sfx(k, 3);
    st.wb(a0 + 0x1E, 0x14);
    k.n += seq(0x5448, 0x5450) + cost(0x5450);
}

/// $50D0: lance hit: fast, level, mouth-open frames while +$1E counts down.
pub fn stunned(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    st.ww(a0 + 0x10, 6);
    st.ww(a0 + 0x12, 0);
    st.wb(a0 + 0x1E, st.rb(a0 + 0x1E) - 1);
    const d1 = st.rw(a0 + 0x1A) & 0x18;
    r[1] = setw(r[1], d1);
    k.n += seq(0x50D0, 0x50EA);
    if (d1 == 0x10) {
        k.n += bcc(0x50EA, true);
        return back.draw_all(st, r, a0, d0, k);
    }
    st.ww(a0 + 0x1A, st.rw(a0 + 0x1A) + 1);
    k.n += bcc(0x50EA, false) + cost(0x50EC);
    return back.move(st, r, a0, d0, k);
}
