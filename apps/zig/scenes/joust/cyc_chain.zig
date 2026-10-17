// --------------------------------------------------------------------------
// span() in two loads: the cost table's straight-line runs as prefix sums.
//
// cyc.span(lo, hi) sums the fixed cost of every instruction from lo to hi by
// walking the table one instruction at a time, and the transcribed routines
// call it for nearly every instruction they run -- a quarter of a game frame
// was that walk (and on the board's rv32 every step is i64 maths). A 68000
// coder would have counted once: here every RUN of instructions that the walk
// passes straight through (each one fixed-cost, ending where the next starts,
// none overlapping another's start) gets an id, and each of its instruction
// boundaries the running sum from the run's first instruction. A span inside
// one run is then P[hi] - P[lo], exactly the walk's sum.
//
// Anything else -- an odd address, a VAR-cost instruction, lo > hi, a gap, an
// instruction another one jumps into the middle of, two different runs --
// returns null and cyc.span() walks as before, so its result AND its error
// count stay the walk's.
//
// One u32 per even address (68000 code is word-aligned): id << 16 | P.
// JOUST's table has 1,034 runs, the longest summing 13,568 cycles: both fit 16
// bits; build() keeps the walk for good if a table ever didn't.
// --------------------------------------------------------------------------
const zg = @import("zigos");

const VAR: u16 = 0xFFFF;

var tab: ?[]u32 = null;

fn ln(t: []const u8, a: usize) usize {
    return if ((a + 1) * 4 > t.len) 0 else t[a * 4 + 2];
}

fn cost(t: []const u8, a: usize) u16 {
    return @as(u16, t[a * 4]) | @as(u16, t[a * 4 + 1]) << 8;
}

/// Fixed cost, and no other instruction starts inside it.
fn regular(t: []const u8, s: usize) bool {
    const n = ln(t, s);
    if (n == 0 or cost(t, s) == VAR) return false;
    for (1..n) |k| if (ln(t, s + k) != 0) return false;
    return true;
}

/// Once per cart load (the scene's init), from the cart RAM arena.
pub fn build(t: []const u8) void {
    if (tab != null) return;
    const n = t.len / 4;
    const out = zg.mem.mustAlloc(u32, n / 2 + 2);
    @memset(out, 0);
    var id: u32 = 0;
    var s: usize = 0;
    while (s < n) : (s += 2) {
        if (!regular(t, s)) continue;
        if (out[s / 2] >> 16 == 0) id += 1; // not reached from a previous run: a new one
        const here = if (out[s / 2] >> 16 == 0) id << 16 else out[s / 2];
        const e = s + ln(t, s);
        const p = (here & 0xFFFF) + cost(t, s);
        if (id > 0xFFFF or p > 0xFFFF or e & 1 != 0 or e / 2 >= out.len) return; // keep walking
        out[s / 2] = here;
        out[e / 2] = (here & 0xFFFF_0000) | p;
    }
    tab = out;
}

/// The walk's sum from lo to hi, when one run holds both; null otherwise.
pub inline fn lookup(lo: i64, hi: i64) ?i64 {
    const t = tab orelse return null;
    if (lo < 0 or lo > hi or (lo | hi) & 1 != 0 or hi >> 1 >= t.len) return null;
    const il: usize = @intCast(lo >> 1);
    const ih: usize = @intCast(hi >> 1);
    const el = t[il];
    const eh = t[ih];
    if (el >> 16 == 0 or el >> 16 != eh >> 16) return null;
    return @as(i64, eh & 0xFFFF) - @as(i64, el & 0xFFFF);
}
