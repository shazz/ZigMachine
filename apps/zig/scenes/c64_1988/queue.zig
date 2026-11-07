// The register writes a part's IRQ chain makes in a frame, as the sprite unit (vic.zig) reads them.

pub const Write = struct { line: u16, cyc: u8, reg: u8, val: u8 };

/// A frame's writes in line/cycle order. Lines >= 312 belong to the next frame (a handler
/// that runs past the frame's last line: part 3's end-of-frame work does).
pub const Queue = struct {
    pub const MAX = 1400;
    buf: [MAX]Write = undefined,
    n: usize = 0,

    pub fn w(self: *Queue, line: u16, cyc: u8, reg: u8, val: u8) void {
        if (self.n == MAX) @panic("vic queue full"); // a part emitting more than the C64 can
        self.buf[self.n] = .{ .line = line, .cyc = cyc, .reg = reg, .val = val };
        self.n += 1;
    }

    /// A write at `cyc` cycles into `line`, carried over 63-cycle lines (the 6510 counts on).
    pub fn at(self: *Queue, line: u16, cyc: u16, reg: u8, val: u8) void {
        self.w(line + cyc / 63, @intCast(cyc % 63), reg, val);
    }

    pub fn items(self: *const Queue) []const Write {
        return self.buf[0..self.n];
    }
};

/// A handler's writes past line 311, renumbered for the next frame.
pub const Carry = struct {
    pub const MAX = 64;
    buf: [MAX]Write = undefined,
    n: usize = 0,

    pub fn w(self: *Carry, line: u16, cyc: u8, reg: u8, val: u8) void {
        if (self.n == MAX) @panic("vic carry full");
        self.buf[self.n] = .{ .line = line, .cyc = cyc, .reg = reg, .val = val };
        self.n += 1;
    }
};
