// --------------------------------------------------------------------------
// Call 10, $3932: collisions (the model's b_coll.py). For every live rider a0
// (flags != 0, b7 clear):
//   1. platform-edge bumps: its previous image vs every platform piece that is
//      on ($1A42 list); a hit sets b14 (edge_bump) and, for a player, SFX 7;
//   2. if still ridden (b13 clear): the joust against every later ridden slot
//      a3: equal y bounces (SFX 11), otherwise the higher rider (smaller y)
//      wins -- only a player can unseat;
//   3. a player then collects eggs / hatched knights, and meets the
//      pterodactyls (coll_eggs.zig).
// The joust itself, the unseat and the bounce are coll_joust.zig.
// --------------------------------------------------------------------------
const joust = @import("coll_joust.zig");
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const sound = @import("sound.zig");
const Regs = @import("ai_regs.zig").Regs;
const ov = @import("coll_overlap.zig");
const eggs = @import("coll_eggs.zig");
const St = State.St;
const V = State.V;
const Clk = cyc.Clk;
const BASE = State.BASE;
const SLOTS = State.SLOTS;
const RA = ov.RA;
const RB = ov.RB;
const HIT = ov.HIT;

const END: i64 = 0x13E8;

/// move.w #n,-(a7) + jsr $0A94 + the stack fix-up are counted by the caller.
pub fn sfx_0a94(st: *St, k: *Clk, n: i64) void {
    k.r(0x0A94, 0x0AA4);
    if (!k.b(0x0AA4, n > st.g(V.sfx_prio))) {
        k.r(0x0AA6, 0x0ABC);
        k.flush();
        _ = sound.play_sfx(st, n);
        k.i(0x0ABC); // trap #14 (Dosound)
        k.i(0x0ABE);
    }
    k.r(0x0AC2, 0x0AC8);
}

/// move.w #n,-(a7) at `push`, jsr, then addq/adda on a7 (6 + 6 + 2..4 bytes).
pub fn sfx_at(st: *St, k: *Clk, push: i64, n: i64) void {
    k.r(push, push + 10);
    sfx_0a94(st, k, n);
}

/// A rider's previous image as a rect (+$14 screen, +$18 sprite, 2 groups,
/// +$1D, +$1C, y).
pub fn rect_obj(st: *St, r: i64, o: i64) void {
    st.wl(r, st.rl(o + 0x14));
    st.wl(r + 4, st.rl(o + 0x18));
    st.ww(r + 8, 2);
    st.wb(r + 0x0A, st.rb(o + 0x1D));
    st.wb(r + 0x0B, st.rb(o + 0x1C));
    st.ww(r + 0x0E, st.rw(o + 4));
}

/// Call 10.
pub fn call_3932_collisions(st: *St) void {
    var R = Regs.init(st);
    var k = Clk.init(st);
    k.add(20); // jsr $3932
    k.r(0x3932, 0x393A); // movea.l; bra.b $394A
    var a0 = SLOTS;
    while (true) {
        R.a[0] = BASE + a0;
        k.r(0x394A, 0x3950);
        const d0 = st.rw(a0);
        R.d[0] = d0;
        if (!k.b(0x3950, d0 == 0)) {
            k.i(0x3952);
            if (!k.b(0x3956, d0 & 0x80 != 0)) rider(st, &k, &R, a0);
        }
        // $393A: next slot
        k.r(0x393A, 0x3946);
        a0 += 0x4E;
        R.a[0] = BASE + a0;
        if (k.b(0x3946, a0 != END)) continue;
        k.i(0x3948); // rts
        break;
    }
    R.store();
    k.done();
}

/// $3958..: returns to $393A.
fn rider(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    platforms(st, k, R, a0);
    k.i(0x39FA);
    if (k.b(0x39FE, R.d[0] & 0x2000 != 0)) return;
    k.r(0x3A02, 0x3A10);
    R.a[1] = BASE + RA;
    R.a[2] = BASE + RB;
    var a3 = a0;
    while (true) {
        k.r(0x3A10, 0x3A1C);
        a3 += 0x4E;
        R.a[3] = BASE + a3;
        if (k.b(0x3A1C, a3 == END)) break;
        k.r(0x3A20, 0x3A26);
        const d1 = st.rw(a3);
        R.d[1] = d1;
        if (k.b(0x3A26, d1 == 0)) continue;
        k.i(0x3A28);
        if (k.b(0x3A2C, d1 & 0x2000 != 0)) continue;
        k.i(0x3A2E);
        if (k.b(0x3A32, d1 & 0x80 != 0)) continue;
        k.r(0x3A34, 0x3A7C);
        rect_obj(st, RA, a0);
        rect_obj(st, RB, a3);
        k.i(0x3A7C); // bsr.w $3FE2
        ov.overlap_3fe2(st, k);
        k.i(0x3A80);
        if (k.b(0x3A86, st.rb(HIT) == 0)) continue;
        if (joust.joust(st, k, R, a0, a3)) break;
    }
    eggs.eggs_and_ptero(st, k, R, a0);
}

fn platforms(st: *St, k: *Clk, R: *Regs, a0: i64) void {
    k.r(0x3958, 0x395E); // movea.l #$1a42,a3
    var a3: i64 = 0x1A42;
    while (true) {
        k.r(0x395E, 0x3990);
        R.a[1] = BASE + RA;
        R.a[2] = BASE + RB;
        rect_obj(st, RA, a0);
        const a4 = st.rl(a3);
        a3 += 4;
        R.a[4] = a4;
        k.i(0x3990); // tst.b (a4)
        if (!k.b(0x3992, st.rd(a4, 1) != 0)) {
            k.r(0x3994, 0x399C); // adda.l #$c,a3; bra.b $39F0
            a3 += 12;
        } else {
            k.r(0x399C, 0x39C6);
            a3 += 1;
            st.wb(RB + 0x0B, st.rb(a3));
            a3 += 1;
            st.ww(RB + 8, st.rw(a3));
            a3 += 2;
            st.wl(RB + 4, st.rl(a3));
            a3 += 4;
            const off = st.rl(a3);
            st.wl(RB, off);
            st.wb(RB + 0x0A, 0);
            R.d[1] = st.g(V.screen_base);
            st.wl(RB, st.rl(RB) + st.g(V.screen_base));
            a3 += 4;
            const q = @divFloor(off, 0xA0);
            const rem = @mod(off, 0xA0);
            const d1 = if (q > 0xFFFF) off else (rem << 16) | q;
            R.d[1] = d1;
            st.ww(RB + 0x0E, d1);
            k.i(0x39C6); // bsr.w $3FE2
            ov.overlap_3fe2(st, k);
            k.i(0x39CA);
            if (!k.b(0x39D0, st.rb(HIT) == 0)) {
                k.r(0x39D2, 0x39DA);
                R.d[0] |= 0x4000;
                st.ww(a0, R.d[0]);
                R.a[3] = BASE + a3;
                k.i(0x39DA);
                if (!k.b(0x39DE, R.d[0] & 4 == 0)) {
                    sfx_at(st, k, 0x39E0, 7);
                    k.r(0x39EA, 0x39F0); // adda.w #2,a7; bra.b $39FA
                }
                return;
            }
        }
        R.a[3] = BASE + a3;
        k.i(0x39F0);
        if (!k.b(0x39F6, a3 != 0x1AC2)) return;
    }
}
