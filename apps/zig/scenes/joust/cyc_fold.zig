// --------------------------------------------------------------------------
// The cycle counts the compiler can do: span() and cost() of LITERAL
// addresses (`cy.run(0x2D94, 0x2DA0)`, nearly every call in the
// transcriptions) are summed from the embedded cost table at compile time, so
// at run time they are a constant added to a counter. An ST coder would have
// written the number in the source; this keeps the source naming the code
// and lets the compiler write the number.
//
// A span the walk would reject (not on instruction boundaries, crossing a
// VAR-cost instruction) is not folded: it goes to the run-time walk, which
// counts it as a transcription error exactly as before.
// --------------------------------------------------------------------------
const std = @import("std");

const VAR: u16 = 0xFFFF;

/// True when x is known at compile time at this (inline) call site.
pub inline fn known(x: anytype) bool {
    return @typeInfo(@TypeOf(.{x})).@"struct".fields[0].is_comptime;
}

fn ln(comptime t: []const u8, comptime a: i64) i64 {
    if (a < 0 or (a + 1) * 4 > t.len) return 0;
    return t[@intCast(a * 4 + 2)];
}

/// The instruction at a's fixed cost, or null where the run-time cost() would fail.
pub fn cost(comptime t: []const u8, comptime a: i64) ?i64 {
    if (ln(t, a) == 0) return null;
    const i: usize = @intCast(a * 4);
    const c = std.mem.readInt(u16, t[i..][0..2], .little);
    return if (c == VAR) null else c;
}

/// The walk's sum over [lo, hi), or null where the walk would count an error.
pub fn span(comptime t: []const u8, comptime lo: i64, comptime hi: i64) ?i64 {
    @setEvalBranchQuota(100_000);
    var s: i64 = 0;
    var a = lo;
    while (a < hi) {
        const n = ln(t, a);
        if (n == 0) return null;
        s += cost(t, a) orelse return null;
        a += n;
    }
    return if (a == hi) s else null;
}
