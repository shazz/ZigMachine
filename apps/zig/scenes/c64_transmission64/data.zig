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

/// part2.bin (ripped when part 2's init has drawn the logo, $4062): a header of u32 section
/// offsets, then the sections in this order.
pub const Part2 = struct {
    b: []const u8,

    const Sec = enum(u8) { bitmap, screen, colour, maps, cycle, arrays, prog, irq, cycles, regs, events };

    fn sec(self: Part2, s: Sec) []const u8 {
        const i = @intFromEnum(s);
        const at = std.mem.readInt(u32, self.b[4 * i ..][0..4], .little);
        const end = if (i + 1 < 11) std.mem.readInt(u32, self.b[4 * (i + 1) ..][0..4], .little) else self.b.len;
        return self.b[at..end];
    }

    /// $2000-$3F3F: the multicolour bitmap (its first 64 bytes are the antenna sprite, block $80).
    pub fn bitmap(self: Part2) []const u8 {
        return self.sec(.bitmap);
    }
    /// $0400 and the colour RAM: all purple ($44, 4) until the cycles colour the logo.
    pub fn screen(self: Part2) []const u8 {
        return self.sec(.screen);
    }
    pub fn colour(self: Part2) []const u8 {
        return self.sec(.colour);
    }
    /// $7000-$71FF and $7200-$73FF: per logo cell, an index into the cycle's 256 colours.
    pub fn maps(self: Part2) []const u8 {
        return self.sec(.maps);
    }
    /// $7900: the 16 colour bands, a 16-byte window of them per cycle step.
    pub fn cycleTable(self: Part2) []const u8 {
        return self.sec(.cycle);
    }
    /// $4500-$4518, $4600-$4618 (the radio rings' colours, low and high nibble), $43F2 (the flash).
    pub fn arrays(self: Part2) []const u8 {
        return self.sec(.arrays);
    }
    /// $4700's generated code as (opcode, lo, hi) triples, after a u16 count.
    pub fn program(self: Part2) []const u8 {
        return self.sec(.prog);
    }
    /// The IRQ of part-2 frame `n`: entry, $4700 start and RTI end (cycles from the frame's
    /// line 0, measured in VICE: the SID player's time varies) and the music flags (bit 0:
    /// $0C1E is $B2 or $A0, bit 1: $0C22 is $11). Null: no IRQ that frame.
    pub fn irq(self: Part2, n: u32) ?Irq {
        const s = self.sec(.irq);
        const first = std.mem.readInt(u16, s[0..2], .little);
        const count = std.mem.readInt(u16, s[2..4], .little);
        if (n < first or n >= first + count) return null;
        const r = s[4 + 7 * (n - first) ..][0..7];
        const entry = std.mem.readInt(u16, r[0..2], .little);
        if (entry == 0xFFFF) return null;
        return .{ .entry = entry, .prog = std.mem.readInt(u16, r[2..4], .little), .rti = std.mem.readInt(u16, r[4..6], .little), .flags = r[6] };
    }
    pub fn firstIrq(self: Part2) u16 {
        return std.mem.readInt(u16, self.sec(.irq)[0..2], .little);
    }
    /// Colour cycle k: the frame and time its copy loops start, and the variant ($421B / $42AD).
    pub fn cycle(self: Part2, k: usize) ?Cycle {
        const s = self.sec(.cycles);
        if (k >= std.mem.readInt(u16, s[0..2], .little)) return null;
        const r = s[2 + 5 * k ..][0..5];
        return .{ .frame = std.mem.readInt(u16, r[0..2], .little), .start = std.mem.readInt(u16, r[2..4], .little), .variant = r[4] };
    }
    pub fn vicRegs(self: Part2) [0x2F]u8 {
        return self.sec(.regs)[0..0x2F].*;
    }
    /// (frame, time) of the logo's overlay done ($4062) and of the return to the main loop.
    pub fn event(self: Part2, k: usize) [2]u16 {
        const s = self.sec(.events);
        return .{ std.mem.readInt(u16, s[4 * k ..][0..2], .little), std.mem.readInt(u16, s[4 * k + 2 ..][0..2], .little) };
    }
};

pub const Irq = struct { entry: u16, prog: u16, rti: u16, flags: u8 };
pub const Cycle = struct { frame: u16, start: u16, variant: u8 };

/// Cells are u16 LE in a ring's byte slice.
pub fn cell(cells: []const u8, i: usize) u16 {
    return std.mem.readInt(u16, cells[2 * i ..][0..2], .little);
}

pub const Data = struct {
    part1: Part1,
    wipe: Wipe,
    part2: Part2,
    part3: @import("data3.zig").Part3,
};
