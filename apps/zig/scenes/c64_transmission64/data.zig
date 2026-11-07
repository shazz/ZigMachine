// --------------------------------------------------------------------------
// The original's data, as tools/c64_transmission64_rip.py lays it out in
// apps/zig/assets/screens/c64_transmission64/. No @embedFile here, so the native tools and
// tests can hand in the same files read from disk; assets.zig embeds them for the cart.
// --------------------------------------------------------------------------
const std = @import("std");

pub const PART1_FRAMES = 726;
pub const PART1_LEN = 1000 + 1000 + 2048 + 242 + 48 + 2000 + 2 * PART1_FRAMES + 0x30;
pub const WIPE_LEN = 384;

/// part1.bin (ripped at part 1's first IRQ, $2B7B).
pub const Part1 = struct {
    b: *const [PART1_LEN]u8,

    /// $7400: the boot screen as part 1 saved it (after swapping 8 codes, $2A24).
    pub fn screen(self: Part1) *const [1000]u8 {
        return self.b[0..1000];
    }

    /// $7800: its colours (nibbles).
    pub fn colour(self: Part1) *const [1000]u8 {
        return self.b[1000..2000];
    }

    /// $2000: the charset: the character ROM's upper case set with 8 characters redrawn ($29AE).
    pub fn charset(self: Part1) *const [2048]u8 {
        return self.b[2000..4048];
    }

    /// $7C00: the codes fed to the centre ring, one every third frame.
    pub fn feed(self: Part1) *const [242]u8 {
        return self.b[4048..4290];
    }

    /// Ring k of the routine's order ($27 first): its cells (u16 LE screen offsets).
    pub fn ring(self: Part1, k: usize) []const u8 {
        var off: usize = 4338;
        for (0..k) |i| off += 2 * @as(usize, count(self, i));
        return self.b[off..][0 .. 2 * @as(usize, count(self, k))];
    }

    fn count(self: Part1, k: usize) u16 {
        return std.mem.readInt(u16, self.b[4290 + 2 * k ..][0..2], .little);
    }

    /// Frame n (1-based): beam time where $2C80 starts, cycles after line 248 (the IRQ). It
    /// follows the SID player's call, whose CPU time varies with the tune: measured in VICE.
    pub fn start(self: Part1, n: usize) u16 {
        return std.mem.readInt(u16, self.b[6338 + 2 * (n - 1) ..][0..2], .little);
    }

    /// $D000-$D02E at frame 1, and $DD00.
    pub fn vicRegs(self: Part1) [0x2F]u8 {
        return self.b[PART1_LEN - 0x30 ..][0..0x2F].*;
    }

    pub fn dd00(self: Part1) u8 {
        return self.b[PART1_LEN - 1];
    }
};

/// wipe.bin: the transitions' tables.
pub const Wipe = struct {
    b: *const [WIPE_LEN]u8,

    /// $0B00: the bars' IRQ line (low 8 bits), frame by frame.
    pub fn line(self: Wipe, x: usize) u16 {
        return @as(u16, self.b[x]) | (if (self.b[128 + x] & 0x80 != 0) @as(u16, 256) else 0);
    }

    /// $0A0D: the delay routine's low byte between bars ($9D = 1 line ... $E6 = 8 lines).
    pub fn delay(self: Wipe, x: usize) u8 {
        return self.b[256 + x];
    }
};

/// Cells are u16 LE in a ring's byte slice.
pub fn cell(cells: []const u8, i: usize) u16 {
    return std.mem.readInt(u16, cells[2 * i ..][0..2], .little);
}

pub const Data = struct {
    part1: Part1,
    wipe: Wipe,
};
