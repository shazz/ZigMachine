// --------------------------------------------------------------------------
// Package C's shared pieces (the model's c_common.py): the RNG and SFX
// subroutines with their cycles, counted on C's Clock.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const cyc = @import("cyc.zig");
const core = @import("core.zig");
const sound = @import("sound.zig");
const St = State.St;
const V = State.V;
pub const Clock = cyc.Clock;
pub const seq = cyc.span;
pub const cost = cyc.cost;
pub const bcc = cyc.brc;
pub const M16 = State.M16;
pub const M32 = State.M32;

/// shift(n, long): r4((8 if long else 6) + 2 * (n & 63)).
pub fn shift(n: i64, long: bool) i64 {
    return cyc.shm(n, long);
}

/// The body of $05EA (after the caller's jsr): step the pointer, return its cycles.
pub fn rng(st: *St, d0: i64) i64 {
    const p = (st.g(V.rng_ptr) + 2) & M32;
    core.rng_step(st, d0);
    if (p >= core.RNG_END)
        return seq(0x05EA, 0x05FA) + bcc(0x05FA, false) + seq(0x05FC, 0x0616) + cost(0x0616);
    return seq(0x05EA, 0x05FA) + bcc(0x05FA, true) + cost(0x0616);
}

/// $0A94(n) after the caller's jsr: the priority test, and the Dosound trap if
/// it passes (the clock is run up to the trap first).
pub fn sfx(k: *Clock, n: i64) void {
    const st = k.st;
    const exit = cost(0x0AC2) + cost(0x0AC6);
    k.n += seq(0x0A94, 0x0AA4);
    if (n > st.g(V.sfx_prio)) {
        k.n += bcc(0x0AA4, true) + exit;
        return;
    }
    k.n += bcc(0x0AA4, false) + seq(0x0AA6, 0x0ABC);
    st.clock(k.n);
    k.n = 0;
    _ = sound.play_sfx(st, n);
    k.n += seq(0x0ABC, 0x0AC2) + exit;
}
