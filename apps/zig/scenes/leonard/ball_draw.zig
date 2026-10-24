// --------------------------------------------------------------------------
// The 16x16 ball as GENERATED STORES (the way Leonard drew 312 sprites: code,
// not a mask loop). A CHISEL blit costs ~800 cycles of setup before its 256
// pixels; the ball's opaque pixels are 16 contiguous row spans, so a ball is
// ~60 aligned u32/u16/u8 stores of constants instead. The store list is built
// at COMPILE TIME from the remapped ball (one_plane.zig), one variant per
// x & 3, so every store is naturally aligned (a misaligned one traps on the
// board). The bytes written are exactly the keyed blit's: every non-key pixel.
// --------------------------------------------------------------------------
const art = @import("one_plane.zig");

pub const SIZE = 16;
pub const STRIDE = 320; // the plane's row stride, checked by the caller

const Store = struct { off: u16, size: u8, value: u32 };

/// Opaque span [start, end) of ball row `r`; a hole inside a row would need a
/// mask, which this generator refuses to emit silently.
fn span(comptime r: usize) [2]usize {
    const row = art.ball[r * SIZE ..][0..SIZE];
    var s: usize = 0;
    while (s < SIZE and row[s] == 0) s += 1;
    var e: usize = SIZE;
    while (e > s and row[e - 1] == 0) e -= 1;
    for (row[s..e]) |v| if (v == 0) @compileError("ball row has a transparent hole");
    return .{ s, e };
}

fn countStores(comptime a: usize) usize {
    var n: usize = 0;
    for (0..SIZE) |r| {
        const se = span(r);
        var q = a + se[0];
        while (q < a + se[1]) : (n += 1) q += pick(q, a + se[1]);
    }
    return n;
}

fn pick(q: usize, end: usize) usize {
    if (q % 4 == 0 and q + 4 <= end) return 4;
    if (q % 2 == 0 and q + 2 <= end) return 2;
    return 1;
}

/// Stores for a ball whose left column sits `a` bytes past a word boundary;
/// offsets are relative to that word-aligned origin.
fn plan(comptime a: usize) [countStores(a)]Store {
    @setEvalBranchQuota(20000);
    var out: [countStores(a)]Store = undefined;
    var n: usize = 0;
    for (0..SIZE) |r| {
        const se = span(r);
        var q = a + se[0];
        while (q < a + se[1]) : (n += 1) {
            const sz = pick(q, a + se[1]);
            var v: u32 = 0;
            for (0..sz) |k| v |= @as(u32, art.ball[r * SIZE + q - a + k]) << (8 * k); // little-endian
            out[n] = .{ .off = r * STRIDE + q, .size = sz, .value = v };
            q += sz;
        }
    }
    return out;
}

const plans = .{ plan(0), plan(1), plan(2), plan(3) };

/// Draws the ball with its top-left at `origin` (the plane's pixel address,
/// already offset to (x, y)). The caller guarantees the ball is fully on the
/// plane and the plane's stride is STRIDE.
pub fn draw(origin: usize) void {
    switch (origin & 3) {
        inline 0...3 => |a| {
            const base = origin - a; // word aligned
            inline for (plans[a]) |st| {
                const at = base + st.off;
                switch (st.size) {
                    4 => @as(*volatile u32, @ptrFromInt(at)).* = st.value,
                    2 => @as(*volatile u16, @ptrFromInt(at)).* = @intCast(st.value),
                    else => @as(*volatile u8, @ptrFromInt(at)).* = @intCast(st.value),
                }
            }
        },
        else => unreachable,
    }
}

// Proof at compile time (no harness needed): every variant's stores, replayed
// into a scratch window, write exactly the ball's non-key pixels, each store
// naturally aligned, and nothing else.
comptime {
    @setEvalBranchQuota(200000);
    for (0..4) |a| {
        var buf = [_]u8{0} ** (STRIDE * SIZE + 8);
        var expect = [_]u8{0} ** (STRIDE * SIZE + 8);
        for (0..SIZE) |r| for (0..SIZE) |c| {
            const v = art.ball[r * SIZE + c];
            if (v != 0) expect[r * STRIDE + a + c] = v;
        };
        for (plans[a]) |st| {
            if (st.off % st.size != 0) @compileError("misaligned store in the ball plan");
            for (0..st.size) |k| {
                if (buf[st.off + k] != 0) @compileError("ball plan writes a byte twice");
                buf[st.off + k] = @truncate(st.value >> (8 * k));
            }
        }
        for (buf, expect) |got, want| if (got != want) @compileError("ball plan differs from the keyed blit");
    }
}
