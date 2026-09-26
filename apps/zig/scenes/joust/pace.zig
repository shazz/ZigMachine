// --------------------------------------------------------------------------
// Call 3, $0344: the busy-wait pacer (the model's pkg_a.call_0344_pace and
// cycles_0344.py). It burns CPU in proportion to how few objects are active,
// which is what holds the frame rate steady-ish: its RAM effects are small,
// its CYCLES are most of a frame.
//   phase != 0: $0D4A = characters in the active popups (max $23)
//   phase == 0: $0D48 live objects, $0D49 objects with +$1E != 0, $0D4B = 0,
//               and $0D48 += 1 if slot 0's +$1E is 4..$12.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;
const V = State.V;
const BASE = State.BASE;
const SLOTS = State.SLOTS;
const SLOT_SZ = State.SLOT_SZ;

pub fn call_0344_pace(st: *St) void {
    st.cycles = cycles_0344(st);
    if (st.g(V.phase) != 0) {
        var n: i64 = 0;
        var a0: i64 = 0x0FA4;
        var a1 = st.regs[9];
        var a: i64 = 0x0E84;
        while (a < 0x0FA4) : (a += 12) {
            if (st.rb(a) == 0) continue;
            a1 = st.rl(a + 4);
            while (true) {
                const c = st.rd(a1, 1);
                a1 += 1;
                if (c == 0) break;
                n += 1;
                if (n == 0x23) break;
            }
            if (n == 0x23) {
                a0 = a;
                break;
            }
        }
        st.s(V.popup_chars, n);
        st.regs[0] = 0; // moveq #$23 - count, then counted down to 0
        if (n != 0x23) st.regs[1] = 0xFFFFFF00; // moveq #$c8,d1 counted down as a byte
        st.set_a(0, BASE + a0);
        st.set_a(1, a1);
        return;
    }
    var live: i64 = 0;
    var busy: i64 = 0;
    for (0..14) |i| {
        const a = SLOTS + @as(i64, @intCast(i)) * SLOT_SZ;
        const f = st.rw(a);
        if (f != 0 and (f & 0x80 == 0 or st.rl(a + 0x14) != 0)) live += 1;
        if (st.rb(a + 0x1E) != 0) busy += 1;
    }
    st.s(V.live_objects, live);
    st.s(V.busy_objects, busy);
    st.s(V.ptero_count, 0);
    const t = st.rb(SLOTS + 0x1E);
    if (4 <= t and t <= 0x12) st.s(V.live_objects, live + 1);
    st.regs[0] = t; // moveq #8,d0 ... move.b $1e(a0),d0
    if (live < 8 or busy < 14) st.regs[1] = 0; // a delay loop ran: subq.l down to 0
    st.set_a(0, BASE + SLOTS);
}

/// The exact pure-cycle count of call 3 from the pre-call state.
fn cycles_0344(st: *St) i64 {
    if (st.g(V.phase) != 0) return banner(st);
    var c: i64 = 20 + 16 + 12; // jsr; tst.b $0D46; beq taken
    c += 20 + 20 + 12; // clr.b $0D48; clr.b $0D49; movea.l #$fa4,a0
    var live: i64 = 0;
    var busy: i64 = 0;
    for (0..14) |i| {
        const a = SLOTS + @as(i64, @intCast(i)) * SLOT_SZ;
        const f = st.rw(a);
        c += 12; // tst.w (a0)
        if (f == 0) {
            c += 12; // beq taken
        } else {
            c += 8 + 12 + 12; // beq not taken, move.w, btst #7
            if (f & 0x80 != 0) {
                c += 8 + 16; // beq not taken, tst.l $14(a0)
                if (st.rl(a + 0x14) != 0) {
                    c += 8 + 20; // beq not taken, addq.b
                    live += 1;
                } else c += 12; // beq taken
            } else {
                c += 12 + 20; // beq taken to $3C2, addq.b
                live += 1;
            }
        }
        c += 12; // tst.b $1e(a0)
        if (st.rb(a + 0x1E) != 0) {
            c += 8 + 20;
            busy += 1;
        } else c += 12;
        c += 12 + 16 + @as(i64, if (i < 13) 12 else 8); // adda.w, cmpa.l, bne
    }
    c += 20 + 4 + 16; // clr.b $0D4B, moveq #8, sub.b
    var n = 8 - live;
    if (n > 0) c += 8 + n * (12 + 900 * 20 - 4 + 4 + 12) - 4 else c += 12;
    c += 4 + 16; // moveq #$e, sub.b
    n = 14 - busy;
    if (n > 0) c += 8 + n * (4 + 100 * 20 - 4 + 4 + 12) - 4 else c += 12;
    const t = st.rb(SLOTS + 0x1E);
    c += 12 + 12 + 8; // movea.l, move.b $1e(a0), cmp.b #4
    if (t < 4) c += 12 else {
        c += 8 + 8;
        c += if (t > 0x12) 12 else 8 + 20;
    }
    return c + 16; // rts
}

fn banner(st: *St) i64 {
    var c: i64 = 20 + 16 + 8 + 20 + 12; // jsr; tst.b; beq not taken; clr.b $0D4A; movea.l
    var n: i64 = 0;
    var a: i64 = 0x0E84;
    while (true) {
        c += 12; // tst.b (a0)
        if (st.rb(a) == 0) {
            c += 12;
        } else {
            c += 8 + 16; // beq not taken; movea.l 4(a0),a1
            var p = st.rl(a + 4);
            var full = false;
            while (true) {
                const ch = st.rd(p, 1);
                p += 1;
                c += 8; // tst.b (a1)+
                if (ch == 0) {
                    c += 12;
                    break;
                }
                n += 1;
                c += 8 + 20 + 20; // beq not taken; addq.b; cmpi.b #$23
                if (n == 0x23) {
                    c += 12;
                    full = true;
                    break;
                }
                c += 8 + 12; // beq not taken; bra
            }
            if (full) break;
        }
        c += 12 + 16; // adda.w #12; cmpa.l
        a += 12;
        if (a == 0x0FA4) {
            c += 8;
            break;
        }
        c += 12;
    }
    c += 4 + 16; // moveq #$23; sub.b
    const k = 0x23 - n;
    if (k == 0) c += 12 else c += 8 + k * (4 + 200 * 16 - 4 + 4 + 12) - 4;
    return c + 16;
}
