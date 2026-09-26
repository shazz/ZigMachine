// --------------------------------------------------------------------------
// Call 8 continued (the model's c_ptero.py): no platform hit $4E5E -- keep
// apart from the others $4E68, fly off $4EE0 or hunt.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const C = @import("hazards_common.zig");
const pd = @import("hazards_ptero_draw.zig");
const hunt = @import("hazards_ptero_hunt.zig");
const St = State.St;
const V = State.V;
const Clock = C.Clock;
const BASE = State.BASE;
const M16 = C.M16;
const seq = C.seq;
const cost = C.cost;
const bcc = C.bcc;
const setw = State.setw;
const divu = State.divu;
const sw = State.s16;
const P_END: i64 = 0x14A8;

/// $4E5E: no platform hit.
pub fn free(st: *St, r: *[16]i64, a0: i64, d0: i64, k: *Clock) void {
    k.n += cost(0x4E5E);
    if (d0 & 0x20 != 0) {
        k.n += bcc(0x4E62, true);
        return hunt.dying(st, r, a0, d0, k);
    }
    k.n += bcc(0x4E62, false) + cost(0x4E66);
    separate(st, r, a0, k);
    k.n += cost(0x4EBE);
    var leave = true;
    if (st.g(V.phase) != 0) {
        k.n += bcc(0x4EC4, true);
    } else {
        k.n += bcc(0x4EC4, false) + cost(0x4EC6);
        if (d0 & 8 != 0) {
            k.n += bcc(0x4ECA, true);
        } else {
            k.n += bcc(0x4ECA, false) + cost(0x4ECC);
            if (st.g(V.cd_ptero) == 0) {
                k.n += bcc(0x4ED2, true);
                leave = false;
            } else {
                k.n += bcc(0x4ED2, false) + cost(0x4ED6);
                if (st.g(V.alive_mask) != 0) {
                    k.n += bcc(0x4EDC, true);
                    leave = false;
                } else {
                    k.n += bcc(0x4EDC, false);
                }
            }
        }
    }
    if (leave) return leaveScreen(st, r, a0, d0, k);
    return hunt.hunt(st, r, a0, d0, k);
}

/// $4E68: push apart vertically from every later live pterodactyl closer than 30 px.
pub fn separate(st: *St, r: *[16]i64, a0: i64, k: *Clock) void {
    var a1 = a0;
    while (true) {
        a1 += 0x20;
        k.n += seq(0x4E68, 0x4E72);
        if (a1 >= P_END) {
            k.n += bcc(0x4E72, true);
            r[9] = BASE + a1;
            return;
        }
        k.n += bcc(0x4E72, false) + cost(0x4E74);
        var d1 = st.rw(a1);
        r[1] = setw(r[1], d1);
        if (d1 == 0) {
            k.n += bcc(0x4E78, true);
            continue;
        }
        k.n += bcc(0x4E78, false) + cost(0x4E7A);
        if (d1 & 0x20 != 0) {
            k.n += bcc(0x4E7E, true);
            continue;
        }
        d1 = (st.rw(a0 + 0xC) - st.rw(a1 + 0xC)) & M16;
        r[1] = setw(r[1], d1);
        k.n += bcc(0x4E7E, false) + seq(0x4E80, 0x4E8C);
        if (sw(d1) > 0x1E) {
            k.n += bcc(0x4E8C, true);
            continue;
        }
        k.n += bcc(0x4E8C, false) + cost(0x4E8E);
        if (sw(d1) < -0x1E) {
            k.n += bcc(0x4E92, true);
            continue;
        }
        const d2 = (st.rw(a0 + 0xE) - st.rw(a1 + 0xE)) & M16;
        r[2] = setw(r[2], d2);
        k.n += bcc(0x4E92, false) + seq(0x4E94, 0x4E9C);
        if (!(sw(st.rw(a0 + 0xE)) < sw(st.rw(a1 + 0xE)))) {
            k.n += bcc(0x4E9C, false) + cost(0x4E9E);
            if (sw(d2) > 0xC) {
                k.n += bcc(0x4EA2, true);
                continue;
            }
            st.ww(a0 + 0xE, st.rw(a0 + 0xE) + 2);
            st.ww(a1 + 0xE, st.rw(a1 + 0xE) - 2);
            k.n += bcc(0x4EA2, false) + seq(0x4EA4, 0x4EAC) + cost(0x4EAC);
        } else {
            k.n += bcc(0x4E9C, true) + cost(0x4EAE);
            if (sw(d2) < -0xC) {
                k.n += bcc(0x4EB2, true);
                continue;
            }
            st.ww(a0 + 0xE, st.rw(a0 + 0xE) - 2);
            st.ww(a1 + 0xE, st.rw(a1 + 0xE) + 2);
            k.n += bcc(0x4EB2, false) + seq(0x4EB4, 0x4EBC) + cost(0x4EBC);
        }
    }
}

/// $4EE0: fly off level (fast), at a platform's height or not.
pub fn leaveScreen(st: *St, r: *[16]i64, a0: i64, d0_in: i64, k: *Clock) void {
    var d0 = (d0_in | 8) & ~@as(i64, 2);
    st.ww(a0 + 0x10, 6);
    k.n += seq(0x4EE0, 0x4EEE) + cost(0x4EEE);
    var d1 = hunt.plat_level(st, r, a0, k);
    st.ww(a0 + 0x12, d1);
    d1 = divu(st.rw(a0 + 0xC), 6);
    r[1] = d1;
    k.n += seq(0x4EF2, 0x4F04);
    if (d0 & 4 != 0) {
        st.wb(a0 + 0x1D, 0);
        k.n += bcc(0x4F04, false) + seq(0x4F06, 0x4F10);
        if (st.rb(a0 + 0x1C) == 2) {
            d0 = 0;
            st.wb(a0 + 0x1D, 3);
            k.n += bcc(0x4F10, false) + seq(0x4F12, 0x4F1A);
        } else {
            k.n += bcc(0x4F10, true);
        }
        k.n += cost(0x4F1A);
        if (d1 & M16 != 0x2F) {
            k.n += bcc(0x4F1E, true);
        } else {
            st.wb(a0 + 0x1C, 7);
            k.n += bcc(0x4F1E, false) + cost(0x4F22) + cost(0x4F28);
        }
    } else {
        st.wb(a0 + 0x1C, 0);
        k.n += bcc(0x4F04, true) + seq(0x4F2C, 0x4F36);
        if (st.rb(a0 + 0x1D) == 2) {
            d0 = 0;
            k.n += bcc(0x4F36, false) + cost(0x4F38);
        } else {
            k.n += bcc(0x4F36, true);
        }
        k.n += cost(0x4F3A);
        if (d1 & M16 != 0) {
            k.n += bcc(0x4F3C, true);
        } else {
            st.wb(a0 + 0x1D, 7);
            k.n += bcc(0x4F3C, false) + cost(0x4F40) + cost(0x4F46);
        }
    }
    return pd.move(st, r, a0, d0, k);
}
