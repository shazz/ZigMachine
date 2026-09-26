// --------------------------------------------------------------------------
// Call 7 continued (the model's b_ai.py): the riderless mount $24D6, the
// wandering enemy mount $2550, and the shared tails that set the flap bits.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const Regs = @import("ai_regs.zig").Regs;
const borrowed = @import("ai_borrowed.zig");
const St = State.St;
const Clk = cyc.Clk;
const s16 = State.s16;

const SPEED_B: i64 = 0x0D98;
const SPEED_H: i64 = 0x0D9A;

// ---------------------------------------------------------------- riderless mount
pub fn riderless(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    while (true) {
        k.i(0x24D6);
        if (k.b(0x24DA, R.d[0] & 0x1000 == 0)) {
            k.i(0x2544);
            if (k.b(0x2548, st.rb(a0 + 0x1E) != 0)) return wander(st, k, R, a0);
            k.r(0x254A, 0x2550);
            R.d[0] |= 0x1000;
            continue;
        }
        break;
    }
    k.r(0x24DC, 0x24E4);
    R.d[0] &= ~@as(i64, 0x20);
    const x = s16(st.rw(a0 + 2));
    var gone: bool = undefined;
    if (!k.b(0x24E4, R.d[0] & 0x8000 == 0)) {
        k.i(0x24E6);
        gone = !k.b(0x24EC, x < 0x13C);
    } else {
        k.i(0x24FA);
        if (k.b(0x2500, x < 0x130)) {
            gone = false;
        } else {
            k.i(0x2502);
            gone = k.b(0x2508, x <= 0x133);
        }
    }
    if (gone) {
        k.i(0x24EE); // jsr $38AC
        borrowed.erase_rider_38ac(st, k, R, a0);
        k.r(0x24F4, 0x24FA); // clr.l d0; bra $20F6
        R.d[0] = 0;
        return;
    }
    k.r(0x250A, 0x2514);
    const vx = st.rw(a0 + 6);
    st.ww(a0 + 0x0C, 4);
    if (!k.b(0x2514, vx & 0x8000 == 0)) {
        k.i(0x2516);
        st.ww(a0 + 0x0C, -4);
    }
    k.r(0x251A, 0x2526);
    st.ww(a0 + 0x46, 0x8C);
    const y = s16(st.rw(a0 + 4));
    if (k.b(0x2526, y > 0x64)) return j2626(st, k, R, a0);
    k.r(0x252A, 0x2536);
    st.ww(a0 + 0x46, 0x42);
    if (k.b(0x2536, y > 0x28)) return j2626(st, k, R, a0);
    k.r(0x253A, 0x2544);
    st.ww(a0 + 0x46, 0x0A);
    return j2626(st, k, R, a0);
}

/// $2550: a riderless enemy mount (+$1E busy): fly back over its pad and
/// pick the rider up.
fn wander(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x2550);
    const x = st.rw(a0 + 2);
    if (!k.b(0x2556, x >= 0x12C)) {
        k.i(0x2558);
        if (!k.b(0x255E, x <= 2)) {
            k.i(0x2560);
            R.d[0] |= 0x20;
        }
    }
    k.i(0x2564);
    if (k.b(0x2568, R.d[0] & 0x20 == 0)) return j2626(st, k, R, a0);
    k.r(0x256C, 0x2586);
    st.wb(a0 + 0x49, 0);
    st.wb(a0 + 0x4B, 0);
    st.wb(a0 + 0x48, 0);
    const d1 = (x + 2 - st.rw(a0 + 0x20)) & 0xFFFF;
    R.setw(1, d1);
    var near = true;
    if (!k.b(0x2586, d1 <= 2)) {
        k.i(0x2588);
        if (!k.b(0x258C, s16(d1) <= -0x13E)) {
            k.i(0x258E);
            if (!k.b(0x2592, d1 >= 0xFFFE)) {
                k.i(0x2594);
                if (!k.b(0x2598, s16(d1) >= 0x13E)) near = false;
            }
        }
    }
    if (!near) {
        k.i(0x259A);
        if (k.b(0x259E, st.rb(a0 + 0x4A) != 0)) return j2626(st, k, R, a0);
        k.r(0x25A2, 0x25B0);
        st.ww(a0 + 0x0C, -st.rw(a0 + 0x0C));
        st.wb(a0 + 0x4A, 1);
        return j2626(st, k, R, a0);
    }
    k.i(0x25B0);
    if (!k.b(0x25B6, st.rb(a0 + 0x4A) == 1)) {
        k.r(0x25B8, 0x25C8);
        st.wb(a0 + 0x4A, 0);
        st.ww(a0 + 0x46, st.rw(a0 + 0x22) - 2);
        return j2626(st, k, R, a0);
    }
    k.i(0x25C8);
    R.d[0] &= ~@as(i64, 0x2000);
    k.i(0x25CC); // jsr $2A96
    borrowed.erase_aux_2a96(st, k, R, a0);
    k.r(0x25D2, 0x25DA); // clr.b $1e; bra $20F6
    st.wb(a0 + 0x1E, 0);
}

// ---------------------------------------------------------------- shared tails
pub fn j25da(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x25DA);
    if (k.b(0x25E0, s16(st.rw(a0 + 8)) > 1)) return j2636(st, k, R, a0);
    k.i(0x25E2);
    return j2642(st, k, R, a0);
}

pub fn j25ee(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x25EE, 0x260A);
    const n = (st.rb(a0 + 0x49) - 1) & 0xFF;
    st.wb(a0 + 0x49, n);
    var d2 = (9 - st.rw(SPEED_H)) & 0xFFFF;
    const d1 = st.rw(SPEED_B) >> 1;
    R.setw(1, d1);
    d2 = (d2 - d1) & 0xFFFF;
    R.setw(2, d2);
    if (k.b(0x260A, (d2 & 0xFF) >= n)) return j2642(st, k, R, a0);
    k.r(0x260C, 0x2626);
    R.d[0] = (R.d[0] & ~@as(i64, 0x0600)) | 0x0840;
    d2 = (d2 + 1) & 0xFFFF;
    R.setw(2, d2);
    st.wb(a0 + 0x49, d2);
}

pub fn j2626(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x2626, 0x262E);
    const y = st.rw(a0 + 4);
    R.setw(1, y);
    if (k.b(0x262E, s16(y) <= s16(st.rw(a0 + 0x46)))) return j2642(st, k, R, a0);
    k.i(0x2630);
    if (k.b(0x2634, st.rw(a0 + 8) & 0x8000 != 0)) return j2642(st, k, R, a0);
    return j2636(st, k, R, a0);
}

pub fn j2636(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    _ = st;
    _ = a0;
    k.r(0x2636, 0x2642);
    R.d[0] ^= 0x0840;
}

pub fn j2642(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    _ = st;
    _ = a0;
    k.r(0x2642, 0x264E);
    R.d[0] &= ~@as(i64, 0x0840);
}

pub fn j264e(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    _ = st;
    _ = a0;
    k.r(0x264E, 0x265E);
    R.d[0] = ((R.d[0] | 0x0800) & ~@as(i64, 0x0400)) ^ 0x40;
}

pub fn j265e(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x265E, 0x266E);
    st.wb(a0 + 0x49, st.rb(a0 + 0x49) - 1);
    R.d[0] = (R.d[0] & ~@as(i64, 0x0800)) ^ 0x40;
}

pub fn j266e(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.i(0x266E);
    if (!k.b(0x2672, R.d[0] & 0x200 == 0)) {
        k.r(0x2674, 0x2680);
        var v = st.rw(SPEED_H);
        if (!k.b(0x2680, R.d[0] & 0x8000 != 0)) {
            k.r(0x2684, 0x268C);
            v = -v;
        }
        st.ww(a0 + 0x0C, v);
        return j25da(st, k, R, a0);
    }
    k.i(0x268C);
    const vx = st.rw(a0 + 6);
    st.ww(a0 + 0x0C, vx);
    if (k.b(0x2692, vx == 0)) return j2642(st, k, R, a0);
    k.r(0x2694, 0x269C);
    R.d[0] &= ~@as(i64, 0x8000);
    const nv = (-vx) & 0xFFFF;
    st.ww(a0 + 0x0C, nv);
    if (k.b(0x269C, nv & 0x8000 != 0)) return j264e(st, k, R, a0);
    k.r(0x269E, 0x26A4);
    R.d[0] |= 0x8000;
    return j264e(st, k, R, a0);
}
