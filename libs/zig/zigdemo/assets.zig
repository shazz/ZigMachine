//! MOCK: asset streaming. The real one (prototypes/suicide_barbie_re/ANALYSIS.md
//! §7 (3), assets.zig) keeps two slots in hwRamAlloc (the current part's and the
//! next one's) and a prefetch queue that the load track feeds 5-20 s ahead. It
//! reads 64 KB a frame from the disk and depacks with zx0.Stream a step at a time.
//!
//! This mock keeps the same bookkeeping (the queue, the slots, ready) and loads
//! instantly from `known`, the ids its table has. It touches neither the disk
//! nor the depacker.

const std = @import("std");

pub const slot_count = 2;
pub const queue_max = 8;

pub const Error = error{ UnknownAsset, QueueFull };

pub const Assets = struct {
    known: []const u16,
    slots: [slot_count]?u16 = [_]?u16{null} ** slot_count,
    queue: [queue_max]u16 = undefined,
    queued: usize = 0,

    /// Asks for asset `id`. A request for an id already loaded or queued is a no-op.
    pub fn request(self: *Assets, id: u16) Error!void {
        if (std.mem.indexOfScalar(u16, self.known, id) == null) return error.UnknownAsset;
        if (self.ready(id) or self.isQueued(id)) return;
        if (self.queued == queue_max) return error.QueueFull;
        self.queue[self.queued] = id;
        self.queued += 1;
    }

    /// Moves queued assets into free slots. The mock loads them at once; the
    /// real one reads one 64 KB block a frame.
    pub fn update(self: *Assets) void {
        while (self.queued > 0) {
            const free = self.freeSlot() orelse return;
            self.slots[free] = self.queue[0];
            std.mem.copyForwards(u16, self.queue[0 .. self.queued - 1], self.queue[1..self.queued]);
            self.queued -= 1;
        }
    }

    /// Whether `id` is loaded in a slot now. A queued id is not ready yet.
    pub fn ready(self: *const Assets, id: u16) bool {
        for (self.slots) |s| {
            if (s == id) return true;
        }
        return false;
    }

    /// Frees the slot that holds `id`, so a waiting asset can load.
    pub fn release(self: *Assets, id: u16) void {
        for (&self.slots) |*s| {
            if (s.* == id) s.* = null;
        }
    }

    fn freeSlot(self: *const Assets) ?usize {
        for (self.slots, 0..) |s, i| {
            if (s == null) return i;
        }
        return null;
    }

    fn isQueued(self: *const Assets, id: u16) bool {
        return std.mem.indexOfScalar(u16, self.queue[0..self.queued], id) != null;
    }
};
