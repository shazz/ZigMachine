// --------------------------------------------------------------------------
// Keyframes for seeking back. A frame of the stream that does not clear the
// screen paints over the one before, so drawing frame n out of order replays
// from the last clear frame: up to ~100 frames, which is 100x a frame's work.
// The rewind asks for such a frame every VBL, and on the board (a 100 MHz cart
// CPU, a frame costing a few M cycles) that froze the rewind for seconds.
//
// A Snaps keeps the drawn window of every EVERY-th frame of a delta chain,
// run-length coded per row (flat polygons: ~3.5 KB a frame instead of 51 KB),
// so a seek restores the nearest kept frame and draws at most EVERY - 1 more.
// A kept frame is the window exactly as drawing it left it, so restoring it is
// pixel-exact. Kept only for the view they were drawn at: a new view empties
// the cache. A full pool keeps nothing more; seeks just replay as before.
// Pure (no ZigOS); tested at the bottom and in player_test.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const polyfill = @import("polyfill.zig");

pub const EVERY: u32 = 2; // keep frames 2, 4, 6... into a chain: a seek draws at most 1 frame
pub const MAX: usize = 512; // frames kept at most (the small window's rewind needs ~120)
pub const POOL_BYTES: usize = 640 * 1024; // the scene's: frames 0..760 take 506 KB (rewind_test.zig)

/// The view a frame was drawn at: where, and the size its vertices were scaled to.
pub const Key = struct { px: usize, stride: usize, w: usize, h: usize, ox: usize, sw: u32, sh: u32 };

pub fn keyOf(t: polyfill.Target, sw: u32, sh: u32) Key {
    return .{ .px = @intFromPtr(t.px.ptr), .stride = t.stride, .w = t.w, .h = t.h, .ox = t.ox, .sw = sw, .sh = sh };
}

pub const Snaps = struct {
    pool: []u8, // runs of (length - 1, value), row after row
    used: usize,
    n: usize,
    full: bool, // a frame did not fit: nothing more is kept
    key: ?Key,
    frames: [MAX]u32,
    starts: [MAX]u32, // where frame i's runs begin in the pool

    /// Field by field, not `self.* = .{...}`: a struct literal this size is
    /// emitted as a data segment of its own (the 517 KB lesson).
    pub fn init(self: *Snaps, pool: []u8) void {
        self.pool = pool;
        self.key = null;
        self.used = 0;
        self.n = 0;
        self.full = false;
    }

    /// Forget every kept frame unless they were drawn at `key`.
    pub fn bind(self: *Snaps, key: Key) void {
        if (self.key) |k| if (std.meta.eql(k, key)) return;
        self.key = key;
        self.n = 0;
        self.used = 0;
        self.full = false;
    }

    /// The latest kept frame in lo..hi, if any.
    pub fn find(self: *const Snaps, lo: u32, hi: u32) ?usize {
        var best: ?usize = null;
        for (self.frames[0..self.n], 0..) |f, i| {
            if (f < lo or f > hi) continue;
            if (best == null or f > self.frames[best.?]) best = i;
        }
        return best;
    }

    pub fn frame(self: *const Snaps, i: usize) u32 {
        return self.frames[i];
    }

    /// Keep frame f, which the window `t` shows right now.
    pub fn save(self: *Snaps, f: u32, t: polyfill.Target) void {
        if (self.full or self.find(f, f) != null) return;
        if (self.n == MAX) return self.markFull();
        var at = self.used;
        for (0..t.h) |y| {
            const row = t.px[y * t.stride + t.ox ..][0..t.w];
            var x: usize = 0;
            while (x < row.len) {
                const v = row[x];
                const e = runEnd(row, x);
                if (at + 2 > self.pool.len) return self.markFull();
                self.pool[at] = @intCast(e - x - 1);
                self.pool[at + 1] = v;
                at += 2;
                x = e;
            }
        }
        self.frames[self.n] = f;
        self.starts[self.n] = @intCast(self.used);
        self.n += 1;
        self.used = at;
    }

    // One past the run of row[x]'s value from x, at most 256 long. Compared a
    // word at a time where it can be: a byte compare per pixel was 0.9 Mc of a
    // keyframe (51,200 pixels, every 2nd frame of the small act), the runs are
    // long (flat polygons), and the end found is the byte loop's own.
    fn runEnd(row: []const u8, x: usize) usize {
        const v = row[x];
        const lim = @min(row.len, x + 256);
        const base = @intFromPtr(row.ptr);
        var e = x + 1;
        while (e < lim and (base + e) & 3 != 0 and row[e] == v) e += 1;
        if ((base + e) & 3 == 0) {
            const rep = @as(u32, v) * 0x0101_0101;
            while (e + 4 <= lim and @as(*const u32, @ptrFromInt(base + e)).* == rep) e += 4;
        }
        while (e < lim and row[e] == v) e += 1;
        return e;
    }

    fn markFull(self: *Snaps) void {
        self.full = true;
    }

    /// Paint kept frame i back into the window it was drawn in.
    pub fn restore(self: *const Snaps, i: usize, t: polyfill.Target) void {
        var at: usize = self.starts[i];
        for (0..t.h) |y| {
            const row = t.px[y * t.stride + t.ox ..][0..t.w];
            var x: usize = 0;
            while (x < row.len) : (at += 2) {
                const len = @as(usize, self.pool[at]) + 1;
                @memset(row[x..][0..len], self.pool[at + 1]);
                x += len;
            }
        }
    }
};

// --- tests ------------------------------------------------------------------
const expectEqual = std.testing.expectEqual;

fn target(px: []u8) polyfill.Target {
    return .{ .px = px, .stride = 300, .w = 280, .h = 3, .ox = 10 };
}

test "a kept frame comes back byte for byte, runs over 256 pixels and the margins included" {
    var px: [300 * 3]u8 = undefined;
    for (&px, 0..) |*p, i| p.* = @intCast((i / 7) % 5);
    @memset(px[300 + 10 ..][0..280], 9); // a whole row, longer than one run
    const before = px;
    var pool: [4096]u8 = undefined;
    var s: Snaps = undefined;
    s.init(&pool);
    s.bind(keyOf(target(&px), 256, 200));
    s.save(42, target(&px));
    @memset(&px, 0xEE);
    for (0..3) |y| @memcpy(px[y * 300 ..][0..10], before[y * 300 ..][0..10]); // the margins are not the window's
    for (0..3) |y| @memcpy(px[y * 300 + 290 ..][0..10], before[y * 300 + 290 ..][0..10]);
    s.restore(s.find(40, 50).?, target(&px));
    try std.testing.expectEqualSlices(u8, &before, &px);
}

test "find picks the latest kept frame in range; a new view or a full pool keeps nothing" {
    var px = [_]u8{3} ** (300 * 3);
    var pool: [64]u8 = undefined; // 3 rows of 2 runs: 12 bytes a frame
    var s: Snaps = undefined;
    s.init(&pool);
    s.bind(keyOf(target(&px), 256, 200));
    for ([_]u32{ 4, 8, 6 }) |f| s.save(f, target(&px));
    try expectEqual(@as(u32, 8), s.frame(s.find(0, 100).?));
    try expectEqual(@as(u32, 6), s.frame(s.find(5, 7).?));
    try expectEqual(@as(?usize, null), s.find(9, 100));
    for (10..20) |f| s.save(@intCast(f), target(&px));
    try std.testing.expect(s.full);
    try expectEqual(@as(?usize, null), s.find(15, 19)); // the frame that did not fit is not half kept
    s.bind(keyOf(target(&px), 400, 280));
    try expectEqual(@as(?usize, null), s.find(0, 100));
    try std.testing.expect(!s.full);
}

test "the word-at-a-time run end is the byte loop's, at every alignment" {
    var prng = std.Random.DefaultPrng.init(0x5a95);
    const rnd = prng.random();
    var buf: [700]u8 align(4) = undefined;
    for (0..3000) |_| {
        for (&buf) |*b| b.* = if (rnd.uintLessThan(u8, 40) == 0) rnd.uintLessThan(u8, 3) else buf[0];
        const row = buf[rnd.uintLessThan(usize, 8)..][0 .. 600 + rnd.uintLessThan(usize, 90)];
        const x = rnd.uintLessThan(usize, row.len);
        var e = x + 1;
        while (e < row.len and e - x < 256 and row[e] == row[x]) e += 1;
        try expectEqual(e, Snaps.runEnd(row, x));
    }
}
