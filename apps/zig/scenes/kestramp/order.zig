// --------------------------------------------------------------------------
// KESTRAMP: the track order over C:\MUSIC (name order). Next / Prev step
// through it; repeat wraps; shuffle plays every track once per round in a
// random order (integer xorshift, a fixed seed, so a run is the same each
// time). Pure: order_test.zig.
// --------------------------------------------------------------------------

pub const Order = struct {
    shuffle: bool = false,
    repeat: bool = false,
    seen: u64 = 0, // shuffle: the tracks played this round, one bit each (MAX is 64)
    rng: u32 = 0x2545F491,

    /// The track after `cur` (null: nothing playing yet), or null when the list is over.
    pub fn next(self: *Order, n: usize, cur: ?usize) ?usize {
        if (n == 0) return null;
        if (self.shuffle) return self.pickRandom(n);
        const at = if (cur) |c| c + 1 else 0;
        if (at < n) return at;
        return if (self.repeat) 0 else null;
    }

    /// The track before `cur`. The first track's previous is the last with repeat, else the first again.
    pub fn prev(self: *Order, n: usize, cur: ?usize) ?usize {
        if (n == 0) return null;
        if (self.shuffle) return self.pickRandom(n);
        const c = cur orelse return 0;
        if (c > 0) return c - 1;
        return if (self.repeat) n - 1 else 0;
    }

    /// Mark a track as started (shuffle's round). Call it for every start.
    pub fn markStarted(self: *Order, i: usize) void {
        self.seen |= @as(u64, 1) << @intCast(i);
    }

    /// A track not yet played this round, drawn from the RNG; a new round with repeat, else null.
    fn pickRandom(self: *Order, n: usize) ?usize {
        const full: u64 = if (n >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(n)) - 1;
        var free = ~self.seen & full;
        if (free == 0) {
            if (!self.repeat) return null;
            self.seen = 0;
            free = full;
        }
        var pick = self.rand() % @as(u32, @popCount(free));
        var bit: usize = 0;
        while (true) : (bit += 1) {
            if (free & (@as(u64, 1) << @intCast(bit)) != 0) {
                if (pick == 0) return bit;
                pick -= 1;
            }
        }
    }

    fn rand(self: *Order) u32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 17;
        self.rng ^= self.rng << 5;
        return self.rng;
    }
};
