// --------------------------------------------------------------------------
// The CPU's stores to the memory the VIC reads, each at its beam time: cycles from line 0,
// cycle 0 of the frame (a PAL frame is 312 x 63 = 19656). A routine that runs on past the
// frame's end leaves stores timed >= 19656: the caller carries them into the next frame.
// A store made with the I/O visible (`io`) to $D800-$DBFF is the colour RAM (a nibble);
// every other store is to the 64 KB (the RAM under the I/O too: the VIC sees it in bank 3).
// --------------------------------------------------------------------------
const std = @import("std");
const Mem = @import("vic_line.zig").Mem;

pub const Store = struct { t: u32, addr: u16, val: u8, io: bool };

pub const Stores = struct {
    pub const MAX = 8192;
    buf: [MAX]Store = undefined,
    n: usize = 0,
    sorted: bool = true, // false once a store is put before the last one (reset() sets it)

    pub fn reset(self: *Stores) void {
        self.n = 0;
        self.sorted = true;
    }

    /// Append a store; stores come in time order, except a later routine's that overlap an
    /// earlier one's (an IRQ inside the main loop's work), which items() sorts in.
    pub fn put(self: *Stores, t: u32, addr: u16, val: u8, io: bool) void {
        if (self.n == MAX) @panic("vic store list full"); // more than a frame of the 6510's
        if (self.n > 0 and self.buf[self.n - 1].t > t) self.sorted = false;
        self.buf[self.n] = .{ .t = t, .addr = addr, .val = val, .io = io };
        self.n += 1;
    }

    /// The stores in time order, equal times in the order they were put (a stable sort, as
    /// the insertion it replaces was). Sorted once here rather than on each put: part 2's IRQ
    /// puts its 561 ring stores into the middle of the main loop's ~800, and inserting them
    /// one by one moved ~160,000 stores on each of those frames.
    pub fn items(self: *Stores) []const Store {
        if (!self.sorted) {
            std.sort.block(Store, self.buf[0..self.n], {}, earlier);
            self.sorted = true;
        }
        return self.buf[0..self.n];
    }

    fn earlier(_: void, a: Store, b: Store) bool {
        return a.t < b.t;
    }

    /// Drop the first `done` stores and retime the rest into the next frame (still sorted).
    pub fn carry(self: *Stores, done: usize, frame: u32) void {
        const rest = self.n - done;
        for (0..rest) |i| {
            self.buf[i] = self.buf[done + i];
            self.buf[i].t -= frame;
        }
        self.n = rest;
    }
};

/// Apply stores from index `from` while their time is before `t`; returns the next index.
/// A store that changes RAM outside the screen rows at `screen` (the VIC's charsets, bitmap,
/// sprites, or memory it may show later) bumps `epoch` (vic_dirty.zig).
pub fn applyUntil(st: []const Store, from: usize, t: u32, mem: Mem, screen: u32, epoch: *u32) usize {
    var i = from;
    while (i < st.len and st[i].t < t) : (i += 1) {
        const s = st[i];
        if (s.io and s.addr >= 0xD800 and s.addr < 0xDC00) {
            mem.col[s.addr - 0xD800] = s.val & 15;
        } else {
            if (mem.ram[s.addr] != s.val and (s.addr < screen or s.addr >= screen + 1000)) epoch.* +%= 1;
            mem.ram[s.addr] = s.val;
        }
    }
    return i;
}
