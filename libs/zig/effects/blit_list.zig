// --------------------------------------------------------------------------
// The descriptor lists of the blitter's QUEUE (memmap BLIT_CMD_QUEUE), as pure
// code over a ring and a view of the register block, so blit_list_test.zig
// runs it natively; libs/zig/blit_queue.zig binds it to the machine.
//
// A list's ops run on a working copy of the block taken at its kick. `shadow`
// is that copy as the list's descriptors leave it: a word goes in the ring
// only when it changes it. The words the queue's ops set (`owned`) are the
// cart's intent and outlive their list: the block never saw them, so every new
// list opens with a COMMAND 0 descriptor restating each owned word the block
// does not hold (a flush in the middle of drawing, an auto-kick when a half is
// full: stniccc's spans lost their destination at both before this). Every
// other word is the block's, as the list's kick will find it.
// --------------------------------------------------------------------------

pub const WORDS: usize = 24; // the block words a descriptor can set
pub const Word = struct { k: u5, v: u32 }; // block word k (offset / 4) and its value
pub const Range = struct { start: usize, count: usize }; // a closed list, in ring words

// The bits of each word a descriptor sets: word 0's MINTERM and CON, the
// strides' low halves, every other word whole.
pub fn keep(k: usize) u32 {
    return switch (k) {
        0 => 0x00FF_FF00,
        3, 5, 7, 9 => 0x0000_FFFF,
        else => 0xFFFF_FFFF,
    };
}

pub const List = struct {
    ring: [*]volatile u32, // the QUEUE ring (2 x half words)
    block: [*]const volatile u32, // the register block, word 0 = COMMAND..CON2
    half: usize, // ring words a list may hold
    side: usize = 0, // the half the open list goes into
    n: usize = 0, // its words so far
    owned: u32 = 0, // the words the ops have set: kept from list to list
    shadow: [WORDS]u32 = [_]u32{0} ** WORDS,

    fn put(self: *List, v: u32) void {
        self.ring[self.side * self.half + self.n] = v;
        self.n += 1;
    }

    /// Room for an op of `len` words, the opening restatement included.
    pub fn fits(self: *const List, len: usize) bool {
        const opening: usize = if (self.n == 0) 1 + WORDS else 0;
        return self.n + opening + 1 + len <= self.half;
    }

    // A list's first descriptor: nothing (from the block), or the carried words.
    fn open(self: *List) void {
        var mask: u32 = 0;
        const at = self.n;
        self.put(0);
        for (0..WORDS) |k| {
            const b = self.block[k] & keep(k);
            if (self.owned >> @intCast(k) & 1 == 0) self.shadow[k] = b;
            if (b == self.shadow[k]) continue;
            mask |= @as(u32, 1) << @intCast(k);
            self.put(self.shadow[k]);
        }
        if (mask == 0) self.n = at else self.ring[self.side * self.half + at] = mask;
    }

    /// One op: COMMAND `cmd` (0: only set the words) after `words` (rising k).
    /// The caller has made room (fits()).
    pub fn op(self: *List, cmd: u8, words: []const Word) void {
        if (self.n == 0) self.open();
        const at = self.n;
        self.put(0);
        var mask: u32 = 0;
        for (words) |w| {
            const v = w.v & keep(w.k);
            self.owned |= @as(u32, 1) << w.k; // the cart's word now, even when the copy holds it
            if (self.shadow[w.k] == v) continue;
            self.shadow[w.k] = v;
            mask |= @as(u32, 1) << w.k;
            self.put(w.v);
        }
        if (mask == 0 and cmd == 0) {
            self.n = at; // nothing to set: no descriptor
            return;
        }
        self.ring[self.side * self.half + at] = mask | @as(u32, cmd) << 24;
    }

    /// Close the open list for its kick (null: empty); the next goes in the
    /// other half.
    pub fn close(self: *List) ?Range {
        if (self.n == 0) return null;
        const r = Range{ .start = self.side * self.half, .count = self.n };
        self.side ^= 1;
        self.n = 0;
        return r;
    }
};
