// --------------------------------------------------------------------------
// The RNG ($05EA, the model's core.py): a pointer ($0E6C) that walks the
// program's OWN bytes as random words. That is why the port keeps the
// original's load base: the code bytes it reads, relocated longs included,
// are the random numbers.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;
const V = State.V;

pub const RNG_END: i64 = State.BASE + 0x7B84;

/// $05EA: advance the code-walking pointer $0E6C by 2. Past TEXT $7B84 it
/// restarts at TEXT (d0 & $FE), where d0 is the CALLER's d0 register.
pub fn rng_step(st: *St, d0: i64) void {
    var p = (st.g(V.rng_ptr) + 2) & State.M32;
    if (p >= RNG_END) p = State.BASE + (d0 & 0xFE);
    st.s(V.rng_ptr, p);
}

/// Word k (0,1,..) at the RNG pointer: the program's own bytes.
pub fn rng_word(st: *St, k: i64) i64 {
    return st.rd(st.g(V.rng_ptr) + 2 * k, 2);
}
