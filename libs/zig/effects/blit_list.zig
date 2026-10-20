// --------------------------------------------------------------------------
// The descriptor lists of the blitter's QUEUE (memmap BLIT_CMD_QUEUE), as pure
// code over a ring and a view of the register block, so blit_list_test.zig
// runs it natively; libs/zig/blit_queue.zig binds it to the machine.
//
// A list's ops run on a working copy of the block taken at its kick. Words are
// stored as given, never compared first: on KESTREL a posted store is ~2 cycles
// and a compare against a shadow costs more than it saves (board, 19 Oct: the
// first version's ~450 cycles of CPU a queued op). The words op() and set()
// give are the queue's own (`owned`, their values in `shadow`): the block never
// sees them, so every new list (an auto-kick when a half is full, a flush in
// the middle of drawing) opens with a COMMAND 0 descriptor restating the owned
// words the block does not hold. An op that states all its words itself
// (whole3: a fill's colour, size and place) gives up those words' ownership.
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
    first: usize = 0, // the open list's first ring word (0 or half)
    n: usize = 0, // its words so far
    owned: u32 = 0, // the words op()/set() gave: kept from list to list
    shadow: [WORDS]u32 = [_]u32{0} ** WORDS,

    inline fn put(self: *List, v: u32) void {
        self.ring[self.first + self.n] = v;
        self.n += 1;
    }

    /// Room for an op of `len` words, the opening restatement included.
    pub inline fn fits(self: *const List, len: usize) bool {
        const opening: usize = if (self.n == 0) 1 + WORDS else 0;
        return self.n + opening + 1 + len <= self.half;
    }

    // A list's first descriptor: the owned words the block does not hold, if any.
    fn open(self: *List) void {
        const at = self.n;
        self.put(0);
        var mask: u32 = 0;
        var m = self.owned;
        while (m != 0) : (m &= m - 1) {
            const k: u5 = @intCast(@ctz(m));
            if (self.block[k] & keep(k) == self.shadow[k]) continue;
            mask |= @as(u32, 1) << k;
            self.put(self.shadow[k]);
        }
        if (mask == 0) self.n = at else self.ring[self.first + at] = mask;
    }

    /// One op: COMMAND `cmd` (0: only set the words) after `words` (rising k),
    /// which become the queue's own. The caller has made room (fits()).
    pub fn op(self: *List, cmd: u8, words: []const Word) void {
        if (self.n == 0) self.open();
        const at = self.n;
        self.put(0);
        var mask: u32 = 0;
        for (words) |w| {
            self.shadow[w.k] = w.v & keep(w.k);
            mask |= @as(u32, 1) << w.k;
            self.put(w.v);
        }
        self.owned |= mask;
        self.ring[self.first + at] = mask | @as(u32, cmd) << 24;
    }

    /// An op that states its three words itself: header `hdr` (mask of 3 words,
    /// COMMAND), then a, b, c in rising word order. The caller has made room (fits(3)).
    pub inline fn whole3(self: *List, hdr: u32, a: u32, b: u32, c: u32) void {
        if (self.n == 0) self.open();
        const p = self.ring + self.first + self.n;
        p[0] = hdr;
        p[1] = a;
        p[2] = b;
        p[3] = c;
        self.n += 4;
        self.owned &= ~hdr;
    }

    /// Close the open list for its kick (null: empty); the next goes in the other half.
    pub fn close(self: *List) ?Range {
        if (self.n == 0) return null;
        const r = Range{ .start = self.first, .count = self.n };
        self.first = self.half - self.first;
        self.n = 0;
        return r;
    }
};
