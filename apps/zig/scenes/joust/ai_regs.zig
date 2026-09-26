// --------------------------------------------------------------------------
// Package B's register file (the model's b_regs.py): d0-d7 / a0-a7 loaded from
// st.regs at the start of a call and stored back, masked, at its end.
// --------------------------------------------------------------------------
const State = @import("state.zig");
const St = State.St;

pub const Regs = struct {
    st: *St,
    d: [8]i64,
    a: [8]i64,

    pub fn init(st: *St) Regs {
        var r: Regs = .{ .st = st, .d = undefined, .a = undefined };
        @memcpy(&r.d, st.regs[0..8]);
        @memcpy(&r.a, st.regs[8..16]);
        return r;
    }
    pub fn setw(self: *Regs, i: usize, v: i64) void {
        self.d[i] = (self.d[i] & 0xFFFF0000) | (v & 0xFFFF);
    }
    pub fn setb(self: *Regs, i: usize, v: i64) void {
        self.d[i] = (self.d[i] & 0xFFFFFF00) | (v & 0xFF);
    }
    pub fn store(self: *Regs) void {
        for (0..8) |i| {
            self.st.regs[i] = self.d[i] & State.M32;
            self.st.regs[8 + i] = self.a[i] & State.M32;
        }
    }
};
