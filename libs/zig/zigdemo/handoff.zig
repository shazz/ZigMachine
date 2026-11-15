//! zigdemo handoff: the "next part" store. A light part (the PRODUCER) fills it with DATA the heavy
//! part after it (the CONSUMER) would otherwise compute in its dearest frames (never pictures: the
//! data that makes them, item after item, e.g. a picture's perspective divides). Its memory is the
//! part region's, a stack (`Mem`): the producer opens it as the FIRST thing in its init, below its
//! own allocations, and it stays through the consumer, whose allocations go on top. It is freed
//! when any other part starts: wire enter() to the Ctx's `enter(id)` (zigdemo.part calls it between
//! the old part's deinit and the new one's init, the only moment the store is on top of the stack),
//! so at the consumer's end, or at a seek out of the pair.
//! The consumer never relies on it: a picture not in the store (a seek into the part, the producer
//! cut short, the store full) is computed as before.
//!
//! `Mem` (the cart's part-region allocator): Mark, mark() Mark, release(Mark), free() usize,
//! alloc(comptime T, n) ?[]T, and log(comptime fmt, args) for the console.

pub const Pair = struct { from: u16, to: u16, bytes: u32, reserve: u32 }; // reserve: what the consumer allocates itself

pub fn Store(comptime T: type, comptime Mem: type, comptime max_pictures: u32) type {
    return struct {
        const Self = @This();
        pub const MAXP = max_pictures;
        mark: ?Mem.Mark = null,
        pair: Pair = .{ .from = 0, .to = 0, .bytes = 0, .reserve = 0 },
        items: []T = &.{}, // the data, picture after picture
        start: [MAXP]u32 = undefined,
        len: [MAXP]u32 = undefined,
        ready: u32 = 0, // pictures 0 .. ready - 1 are in
        fill: u32 = 0, // items used
        full: bool = false, // the next picture did not fit: the producer stops

        /// The producer's init: its store (kept if this pair holds it already: a restart of the producer).
        pub fn open(self: *Self, p: Pair) void {
            if (self.mark != null and self.pair.from == p.from and self.pair.to == p.to) return;
            self.close();
            // never let the store starve the consumer: no room = no precompute
            if (Mem.free() < @as(usize, p.bytes) + p.reserve) return Mem.log("no room for {} KB (free {} KB)", .{ p.bytes / 1024, Mem.free() / 1024 });
            const m = Mem.mark();
            const a = Mem.alloc(T, p.bytes / @sizeOf(T)) orelse return Mem.log("no room for {} KB", .{p.bytes / 1024});
            self.* = .{ .mark = m, .pair = p, .items = a };
            Mem.log("{} KB for part {} -> {}", .{ p.bytes / 1024, p.from, p.to });
        }

        /// A part starts (the one before has ended): a part outside the pair frees the store.
        pub fn enter(self: *Self, id: u16) void {
            if (self.mark == null or id == self.pair.from or id == self.pair.to) return;
            Mem.log("freed at part {} ({} pictures, {} KB used)", .{ id, self.ready, self.fill * @sizeOf(T) / 1024 });
            self.close();
        }

        pub fn close(self: *Self) void {
            if (self.mark) |m| Mem.release(m);
            self.* = .{};
        }

        /// Picture k's items, if the consumer `to` has them.
        pub fn picture(self: *const Self, to: u16, k: u32) ?[]const T {
            if (self.mark == null or self.pair.to != to or k >= self.ready) return null;
            return self.items[self.start[k]..][0..self.len[k]];
        }

        /// Room for the next picture (the producer records into it, then commit()s); null once full.
        pub fn next(self: *Self) ?[]T {
            if (self.mark == null or self.full or self.ready >= MAXP) return null;
            return self.items[self.fill..];
        }

        /// The picture just recorded took n items (more than the room: it did not fit, the store is full).
        pub fn commit(self: *Self, n: u32) void {
            if (self.fill + n > self.items.len) {
                self.full = true;
                return;
            }
            self.start[self.ready] = self.fill;
            self.len[self.ready] = n;
            self.fill += n;
            self.ready += 1;
        }
    };
}
