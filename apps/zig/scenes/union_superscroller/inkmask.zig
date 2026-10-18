// --------------------------------------------------------------------------
// Bit masks over one row's 320 pixels (the letters' ink), and the per-row
// colour-key cache: a pixel's sources (two back taps, four overlay taps, ink)
// pack into a 17-bit key, and one row sees far fewer distinct keys than pixels,
// so the colour maths and the palette hash run once per key, not per pixel.
// Loads are cheap on ZIGGY and every store is a blocking DDR write, so the row
// is also written four pixels to a u32.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const WORDS = A.W / 32;
pub const Mask = [WORDS]u32;

/// Set bits x0..x1 (exclusive) of `m`.
pub fn setRange(m: *Mask, x0: usize, x1: usize) void {
    var x = x0;
    while (x < x1) {
        const w = x >> 5;
        const lo: u5 = @intCast(x & 31);
        const n = @min(x1 - x, 32 - @as(usize, lo));
        const bits: u32 = if (n == 32) ~@as(u32, 0) else ((@as(u32, 1) << @intCast(n)) - 1);
        m[w] |= bits << lo;
        x += n;
    }
}

pub inline fn bit(m: *const Mask, x: usize) u32 {
    return (m[x >> 5] >> @intCast(x & 31)) & 1;
}

const SLOTS = 1024;

/// key -> palette entry for the row being drawn; valid where stamp == gen.
pub const KeyCache = struct {
    keys: [SLOTS]u32,
    vals: [SLOTS]u8,
    stamp: [SLOTS]u32,
    gen: u32,

    pub fn init(self: *KeyCache) void {
        @memset(&self.stamp, 0);
        self.gen = 0;
    }

    pub fn nextRow(self: *KeyCache) void {
        self.gen += 1;
    }

    pub inline fn slot(key: u32) usize {
        return (key *% 0x9E37_79B1) >> (32 - 10);
    }

    pub inline fn find(self: *const KeyCache, key: u32) ?u8 {
        const s = slot(key);
        return if (self.stamp[s] == self.gen and self.keys[s] == key) self.vals[s] else null;
    }

    pub fn put(self: *KeyCache, key: u32, v: u8) void {
        const s = slot(key);
        self.stamp[s] = self.gen;
        self.keys[s] = key;
        self.vals[s] = v;
    }
};
