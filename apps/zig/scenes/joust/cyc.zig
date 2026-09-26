// --------------------------------------------------------------------------
// Cycle counting: the em68 cost of every instruction the transcribed code
// executes, by TEXT address (costs.bin, from the reference model's own cost
// helpers), and the counters the model's four packages count with.
//
// Conditional branches, DBcc and shifts by a register are data dependent and
// the transcribed code costs them itself: Bcc taken 12, not taken 8 (.b) /
// 12 (.w); a shift r4(8 or 6 + 2n).
//
//   Cy     packages A and D: run/one/br/add, flush() feeds the pacer (before
//          anything that touches the sound chip), done() = flush + st.cycles
//   Clk    package B: total/pending; done() sets st.cycles WITHOUT flushing
//          (the driver runs the rest)
//   Clock  package C: one running count, flushed at an SFX trap and at done()
// --------------------------------------------------------------------------
const std = @import("std");
const State = @import("state.zig");
const St = State.St;

const TABLE = @embedFile("../../assets/screens/joust/costs.bin");
const VAR: u16 = 0xFFFF;
pub const F_BCC: u8 = 1;
pub const F_DBCC: u8 = 2;
pub const F_SHIFT: u8 = 4;
pub const F_LONG: u8 = 8;

/// Spans that did not land on instruction boundaries or crossed a
/// variable-cost instruction: a transcription error. The harness checks 0.
pub var errors: u32 = 0;
/// The first failing address (dev builds read it).
pub var err_at: i64 = 0;

fn fail(a: i64) void {
    if (errors == 0) err_at = a;
    errors += 1;
}

fn entry(a: i64) ?*const [4]u8 {
    if (a < 0 or (a + 1) * 4 > TABLE.len) return null;
    const i: usize = @intCast(a * 4);
    return TABLE[i..][0..4];
}

pub fn len(a: i64) i64 {
    const e = entry(a) orelse return 0;
    return e[2];
}

pub fn flags(a: i64) u8 {
    const e = entry(a) orelse return 0;
    return e[3];
}

/// The fixed cost of the instruction at TEXT a.
pub fn cost(a: i64) i64 {
    const e = entry(a) orelse {
        fail(a);
        return 0;
    };
    const c = std.mem.readInt(u16, e[0..2], .little);
    if (c == VAR or e[2] == 0) {
        fail(a);
        return 0;
    }
    return c;
}

/// The sum of the fixed costs of every instruction in [lo, hi).
pub fn span(lo: i64, hi: i64) i64 {
    var s: i64 = 0;
    var a = lo;
    while (a < hi) {
        const n = len(a);
        if (n == 0) {
            fail(a);
            return s;
        }
        s += cost(a);
        a += n;
    }
    if (a != hi) fail(hi);
    return s;
}

/// A Bcc at a: taken 12, not taken 8 (.b) / 12 (.w).
pub fn brc(a: i64, taken: bool) i64 {
    if (taken) return 12;
    return if (len(a) == 4) 12 else 8;
}

/// Package A's shift by a register (no count masking, as a_cyc.sh).
pub fn sh(n: i64, long: bool) i64 {
    return ((if (long) @as(i64, 8) else 6) + 2 * n + 3) & ~@as(i64, 3);
}

/// Packages C and D: r4((8 if long else 6) + 2 * (n & 63)).
pub fn shm(n: i64, long: bool) i64 {
    return ((if (long) @as(i64, 8) else 6) + 2 * (n & 63) + 3) & ~@as(i64, 3);
}

pub fn r4(n: i64) i64 {
    return (n + 3) & ~@as(i64, 3);
}

/// Packages A and D.
pub const Cy = struct {
    st: *St,
    pend: i64,
    total: i64,

    pub fn init(st: *St) Cy {
        return .{ .st = st, .pend = 0, .total = 0 };
    }
    pub fn run(self: *Cy, lo: i64, hi: i64) void {
        self.pend += span(lo, hi);
    }
    pub fn one(self: *Cy, a: i64) void {
        self.pend += cost(a);
    }
    pub fn br(self: *Cy, a: i64, taken: bool) bool {
        self.pend += brc(a, taken);
        return taken;
    }
    pub fn add(self: *Cy, n: i64) void {
        self.pend += n;
    }
    pub fn flush(self: *Cy) void {
        if (self.pend != 0) {
            self.total += self.pend;
            self.st.clock(self.pend);
            self.pend = 0;
        }
    }
    pub fn done(self: *Cy) void {
        self.flush();
        self.st.cycles = self.total;
    }
};

/// Package B.
pub const Clk = struct {
    st: *St,
    total: i64,
    pending: i64,

    pub fn init(st: *St) Clk {
        return .{ .st = st, .total = 0, .pending = 0 };
    }
    pub fn add(self: *Clk, n: i64) void {
        self.total += n;
        self.pending += n;
    }
    pub fn r(self: *Clk, a: i64, hi: i64) void {
        self.add(span(a, hi));
    }
    pub fn i(self: *Clk, a: i64) void {
        self.add(cost(a));
    }
    pub fn b(self: *Clk, a: i64, cond: bool) bool {
        self.add(brc(a, cond));
        return cond;
    }
    pub fn db(self: *Clk, expired: bool) void {
        self.add(if (expired) 16 else 12);
    }
    pub fn sh(self: *Clk, a: i64, cnt: i64) void {
        const base: i64 = if (flags(a) & F_LONG != 0) 8 else 6;
        self.add((base + 2 * (cnt & 63) + 3) & ~@as(i64, 3));
    }
    // package D's routines count into a Clk through Cy's names
    pub fn run(self: *Clk, a: i64, b2: i64) void {
        self.r(a, b2);
    }
    pub fn one(self: *Clk, a: i64) void {
        self.i(a);
    }
    pub fn br(self: *Clk, a: i64, cond: bool) bool {
        return self.b(a, cond);
    }
    pub fn flush(self: *Clk) void {
        if (self.pending != 0) {
            self.st.clock(self.pending);
            self.pending = 0;
        }
    }
    pub fn done(self: *Clk) void {
        self.st.cycles = self.total;
    }
};

/// Package C.
pub const Clock = struct {
    st: *St,
    n: i64,

    pub fn init(st: *St, n: i64) Clock {
        return .{ .st = st, .n = n };
    }
    pub fn add(self: *Clock, k: i64) void {
        self.n += k;
    }
    pub fn done(self: *Clock) void {
        self.st.clock(self.n);
        self.n = 0;
        self.st.cycles = self.st.clocked;
    }
};
