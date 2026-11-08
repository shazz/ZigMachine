// --------------------------------------------------------------------------
// A frame's sprite rows as RUNS: one sprite showing consecutive rows of one block, one row a
// line, at the same X, look and border state. The VIC model (vic.zig) still decides, line by
// line, which row each sprite shows; this only gathers the lines into rectangles, which are
// drawn at the end of the frame from the expanded blocks (vic_cache.zig): a CHISEL keyed blit
// from cart RAM for a big one (~1 clock a pixel after ~800 cycles of set-up), a keyed CPU copy
// for a small one. A logo sprite is one run of up to 21 rows, a cube one of 20: ~120
// rectangles a frame instead of ~1,400 decoded rows.
//
// Exact: the C64 draws sprite 0 in front of 1 ... in front of 7, and two rows of the SAME
// sprite never share a line (a sprite shows one row a line), so its runs never overlap.
// Drawing every run of sprite 7, then 6, ..., then 0 puts each pixel where the line-by-line
// order did. Runs never span a held row ($D017: the same row again), a pointer switch, a
// change of X, colours or border state: each of those starts a new run.
// --------------------------------------------------------------------------
const cache = @import("vic_cache.zig");
pub const Look = cache.Look;

pub const MAX = 640; // a frame of this intro makes at most 125 (show_test.zig asserts a ceiling)
const NONE: u16 = 0xFFFF;

/// Everything that must stay the same along a run, in one word (a row compares one u32):
///   bits 0-8 the first column (sprite X + 16, PAL-wrapped: 0..503), 9-12 $D025, 13-16 the
///   sprite's $D027+n, 17-20 $D026 (C64 colours), 21 multicolour, 22 X-expanded,
///   23 left border open, 24 right border open, 25 the row comes from VIC bank 3.
pub const Key = u32;

pub fn key(c: u32, mc1: u8, spr: u8, mc2: u8, mcol: bool, xe2: bool, left: bool, right: bool, bank3: bool) Key {
    return c | @as(u32, mc1 & 15) << 9 | @as(u32, spr & 15) << 13 | @as(u32, mc2 & 15) << 17 |
        @as(u32, @intFromBool(mcol)) << 21 | @as(u32, @intFromBool(xe2)) << 22 |
        @as(u32, @intFromBool(left)) << 23 | @as(u32, @intFromBool(right)) << 24 | @as(u32, @intFromBool(bank3)) << 25;
}

pub const Run = struct {
    key: Key,
    r0: u16, // first plane row
    n: u16, // rows
    addr: u16, // VIC address of the last row's 3 bytes (the next row is addr + 3)
    s: u8, // sprite number (its priority)

    pub fn col(self: Run) u16 {
        return @intCast(self.key & 0x1FF);
    }
    pub fn bit(self: Run, comptime b: u5) bool {
        return (self.key >> b) & 1 != 0;
    }
    /// The C64 colours of codes 1 ($D025), 2 (the sprite's) and 3 ($D026).
    pub fn colours(self: Run) [3]u8 {
        const k = self.key;
        return .{ @intCast((k >> 9) & 15), @intCast((k >> 13) & 15), @intCast((k >> 17) & 15) };
    }
    pub fn width(self: Run) u16 {
        return if (self.bit(22)) 48 else 24;
    }
    pub fn block(self: Run) u16 {
        return (self.addr - 3 * (self.n - 1)) / 64;
    }
    pub fn row0(self: Run) u16 {
        return ((self.addr - 3 * (self.n - 1)) % 64) / 3;
    }
};

pub const Runs = struct {
    buf: [MAX]Run = undefined,
    n: usize = 0,
    open: [8]u16 = .{NONE} ** 8, // each sprite's run still growing

    pub fn reset(self: *Runs) void {
        self.n = 0;
        self.open = .{NONE} ** 8;
    }

    /// Sprite `s` shows the row at `addr` on plane row `r`. An `empty` row (24 bits 0) may
    /// extend a run, never start one.
    pub inline fn add(self: *Runs, r: u16, s: u3, addr: u16, k: Key, empty: bool) void {
        const i = self.open[s];
        if (i != NONE) {
            const run = &self.buf[i];
            if (run.r0 + run.n == r and run.addr + 3 == addr and run.key == k) {
                run.n += 1;
                run.addr = addr;
                return;
            }
        }
        if (empty) {
            self.open[s] = NONE;
            return;
        }
        if (self.n == MAX) @panic("vic: too many sprite runs"); // the ceiling is a test's
        self.buf[self.n] = .{ .key = k, .r0 = r, .n = 1, .addr = addr, .s = s };
        self.open[s] = @intCast(self.n);
        self.n += 1;
    }
};
