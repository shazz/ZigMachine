//! zigdemo assets: a part's data file loaded into the cart's memory a chunk a frame, with the
//! next part's file prefetched while the current part plays (TBL's two-slot streamer,
//! prototypes/suicide_barbie_re/ANALYSIS.md §7 (3)).
//!
//! zigdemo imports nothing, so the cart hands in `Files`, its file system (on KESTREL a few
//! lines over KOS GEMDOS: Fopen / Fseek / Fread / Fclose, C:\ = the card's /HD):
//!   open(self, path) i32     a handle >= 0, or a negative error (a missing file)
//!   size(self, h) i32        the file's length in bytes, or a negative error
//!   read(self, h, dst) i32   reads on from where the last read stopped: bytes read, < 0 an error
//!   close(self, h) void
//!
//! Memory: ONE arena the cart allocates (its RAM window minus code, statics and buffers). A
//! blob goes in a slot: at most `slot_count` blobs live at once, each wherever it fits beside the
//! other (the lowest 16-aligned offset clear of it). A blob too big to sit beside the current one
//! waits in the queue until the cart releases the current one (a part change behind a black or
//! a flash); a blob bigger than the whole arena fails (`error.TooBig`).
//!
//! Per update(): ONE read of at most `chunk` bytes (one C: round trip on the board, 32 KiB = 64
//! sectors, ~0.5 ms), so a load never blocks a frame for long. progress() reports it for a loader.

const std = @import("std");
const place = @import("assets_place.zig");

pub const slot_count = 2;
pub const queue_max = 8;
pub const ALIGN = place.ALIGN;

pub const Error = error{ UnknownAsset, QueueFull };
/// Why a load failed (status .failed): the file is missing, unreadable, or larger than the arena.
pub const LoadError = error{ NotFound, ReadFailed, TooBig, Empty };

pub const State = enum { idle, queued, loading, ready, failed };

/// One asset: the file the part declares (e.g. "C:\\RIFT\\STATUE.BIN").
pub const Entry = struct { path: []const u8 };

pub const Slot = struct {
    id: ?u16 = null,
    off: u32 = 0,
    len: u32 = 0,
    got: u32 = 0,
    handle: i32 = -1,
    loading: bool = false,
};

pub fn Assets(comptime Files: type) type {
    return struct {
        const Self = @This();

        files: *Files,
        table: []const Entry,
        arena: []align(ALIGN) u8,
        chunk: u32 = 32 * 1024,
        slots: [slot_count]Slot = [_]Slot{.{}} ** slot_count,
        queue: [queue_max]u16 = undefined,
        queued: usize = 0,
        failed: ?struct { id: u16, why: LoadError } = null, // the last failure
        waiting: ?struct { id: u16, len: u32 } = null, // the head, too big to sit beside a slot now

        /// Asks for asset `id`. A request for an id already loading, loaded or queued is a no-op.
        pub fn request(self: *Self, id: u16) Error!void {
            if (id >= self.table.len) return error.UnknownAsset;
            if (self.state(id) != .idle and self.state(id) != .failed) return;
            if (self.queued == queue_max) return error.QueueFull;
            if (self.failed) |f| {
                if (f.id == id) self.failed = null; // a retry
            }
            self.queue[self.queued] = id;
            self.queued += 1;
        }

        /// One step: a chunk of the loading blob, or the next queued blob opened and placed.
        pub fn update(self: *Self) void {
            for (&self.slots) |*s| {
                if (s.loading) return self.step(s);
            }
            if (self.queued > 0) self.begin();
        }

        pub fn state(self: *const Self, id: u16) State {
            for (self.slots) |s| {
                if (s.id == id) return if (s.loading) .loading else .ready;
            }
            if (std.mem.indexOfScalar(u16, self.queue[0..self.queued], id) != null) return .queued;
            if (self.failed) |f| {
                if (f.id == id) return .failed;
            }
            return .idle;
        }

        pub fn ready(self: *const Self, id: u16) bool {
            return self.state(id) == .ready;
        }

        /// The loaded blob, 16-aligned, or null while it is not ready.
        pub fn bytes(self: *const Self, id: u16) ?[]align(ALIGN) const u8 {
            for (self.slots) |s| {
                if (s.id == id and !s.loading) return @alignCast(self.arena[s.off..][0..s.len]);
            }
            return null;
        }

        /// How much of `id` is in, per mille: 0 queued or idle, 1000 ready.
        pub fn progress(self: *const Self, id: u16) u32 {
            for (self.slots) |s| {
                if (s.id == id) return if (s.loading) @intCast(@as(u64, s.got) * 1000 / s.len) else 1000;
            }
            return 0;
        }

        /// Frees `id`'s slot (closing its file if it was still loading) or drops it from the queue.
        pub fn release(self: *Self, id: u16) void {
            for (&self.slots) |*s| {
                if (s.id != id) continue;
                if (s.loading) self.files.close(s.handle);
                s.* = .{};
            }
            if (std.mem.indexOfScalar(u16, self.queue[0..self.queued], id)) |i| self.dequeue(i);
        }

        fn dequeue(self: *Self, i: usize) void {
            std.mem.copyForwards(u16, self.queue[i .. self.queued - 1], self.queue[i + 1 .. self.queued]);
            self.queued -= 1;
        }

        fn fail(self: *Self, id: u16, why: LoadError) void {
            self.failed = .{ .id = id, .why = why };
        }

        /// Opens the queue's head and places it, or leaves it queued until a slot frees.
        fn begin(self: *Self) void {
            const id = self.queue[0];
            const free = for (&self.slots) |*s| {
                if (s.id == null) break s;
            } else return;
            if (self.waiting) |w| { // no reopen a frame while it still cannot fit
                if (w.id == id and place.find(&self.slots, w.len, @intCast(self.arena.len)) == null) return;
            }
            const h = self.files.open(self.table[id].path);
            if (h < 0) return self.drop(id, error.NotFound);
            const size = self.files.size(h);
            if (size <= 0) {
                self.files.close(h);
                return self.drop(id, if (size == 0) error.Empty else error.ReadFailed);
            }
            const len: u32 = @intCast(size);
            if (len > self.arena.len) {
                self.files.close(h);
                return self.drop(id, error.TooBig);
            }
            const off = place.find(&self.slots, len, @intCast(self.arena.len)) orelse {
                self.files.close(h); // waits beside the current blob until a release
                self.waiting = .{ .id = id, .len = len };
                return;
            };
            self.waiting = null;
            self.dequeue(0);
            free.* = .{ .id = id, .off = off, .len = len, .handle = h, .loading = true };
        }

        fn drop(self: *Self, id: u16, why: LoadError) void {
            self.dequeue(0);
            self.fail(id, why);
        }

        fn step(self: *Self, s: *Slot) void {
            const n = @min(self.chunk, s.len - s.got);
            const r = self.files.read(s.handle, self.arena[s.off + s.got ..][0..n]);
            if (r <= 0 or r > n) {
                const id = s.id.?;
                self.files.close(s.handle);
                s.* = .{};
                return self.fail(id, error.ReadFailed);
            }
            s.got += @intCast(r);
            if (s.got < s.len) return;
            self.files.close(s.handle);
            s.handle = -1;
            s.loading = false;
        }
    };
}
