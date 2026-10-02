// --------------------------------------------------------------------------
// A part of the real demo, in its OWN memory. SYNC and TCB are ported from the
// disk (prototypes/snyd_re/NOTES.md), not from the CODEF remake: the loader
// reads a part's tracks to a fixed address and jumps in, and every routine of
// it then addresses its tables, variables and screens absolutely. So a part
// here keeps that memory -- the tracks as loaded, then the part's own
// screens and precalculated buffers above them -- and its routines are ported
// against the SAME addresses, named once in each part's module. Two things
// follow: a ripped table is used where the 68000 used it (nothing re-derived,
// nothing retyped), and any byte of it can be compared with a Hatari RAM dump
// of the real demo, which is how every routine here was checked.
//
// The buffer lives in the cart's part buffer (assets.zig: only one part runs
// at a time); `base` is the 68000 address of its first byte.
// --------------------------------------------------------------------------
const std = @import("std");

pub const LINE = 160; // bytes a low-res line
pub const SCREEN = 32000; // bytes a low-res screen
/// A part runs at the original's 50 Hz: one VBL every 20 ms of host time.
pub const VBL_MS: f32 = 20;

pub const Ram = struct {
    base: u32,
    m: []u8,

    /// The offset of `n` bytes at `a`. The routines chase pointers they read
    /// from this memory, so an address is data: one outside the part traps
    /// where safety is on (the tests), and in ReleaseSmall -- no bounds checks
    /// -- is kept inside the part rather than written over the cart's RAM.
    inline fn at(self: *const Ram, a: u32, n: usize) usize {
        const off: usize = a -% self.base;
        if (off < self.m.len and n <= self.m.len - off) return off;
        if (std.debug.runtime_safety) std.debug.panic("st.Ram: ${X} + {d} is outside the part", .{ a, n });
        return self.m.len -| n;
    }

    /// Whether `a` is inside the part. A loop that walks memory until it
    /// reads an end marker stops here too: past the part every read is
    /// clamped to its last bytes, so a missing marker would never be met.
    pub inline fn holds(self: *const Ram, a: u32) bool {
        return a -% self.base < self.m.len;
    }

    pub inline fn b(self: *const Ram, a: u32) u8 {
        return self.m[self.at(a, 1)];
    }

    pub inline fn w(self: *const Ram, a: u32) u16 {
        return std.mem.readInt(u16, self.m[self.at(a, 2)..][0..2], .big);
    }

    pub inline fn l(self: *const Ram, a: u32) u32 {
        return std.mem.readInt(u32, self.m[self.at(a, 4)..][0..4], .big);
    }

    pub inline fn sb(self: *const Ram, a: u32, v: u8) void {
        self.m[self.at(a, 1)] = v;
    }

    pub inline fn sw(self: *const Ram, a: u32, v: u16) void {
        std.mem.writeInt(u16, self.m[self.at(a, 2)..][0..2], v, .big);
    }

    pub inline fn sl(self: *const Ram, a: u32, v: u32) void {
        std.mem.writeInt(u32, self.m[self.at(a, 4)..][0..4], v, .big);
    }

    /// `n` bytes at `a`.
    pub inline fn bytes(self: *const Ram, a: u32, n: usize) []u8 {
        return self.m[self.at(a, n)..][0..n];
    }

    /// movem / move.l copies: never overlapping in these routines.
    pub inline fn cp(self: *const Ram, dst: u32, src: u32, n: usize) void {
        @memcpy(self.bytes(dst, n), self.bytes(src, n));
    }

    pub inline fn zero(self: *const Ram, a: u32, n: usize) void {
        @memset(self.bytes(a, n), 0);
    }
};

/// A 68000 word as the signed displacement `(a0,d0.w)` / `lea d(a0)` make of it.
pub inline fn sx(v: u16) i32 {
    return @as(i16, @bitCast(v));
}

/// `a + d` with a sign-extended displacement, wrapping as a 32-bit address does.
pub inline fn add(a: u32, d: i32) u32 {
    return a +% @as(u32, @bitCast(d));
}

/// ST colour word -> RGBA (a = 255), channel c * 255 / 7 as the other ST ports do.
pub fn color(v: u16) u32 {
    const r: u32 = (v >> 8) & 7;
    const g: u32 = (v >> 4) & 7;
    const bl: u32 = v & 7;
    return 0xFF00_0000 | (bl * 255 / 7) << 16 | (g * 255 / 7) << 8 | (r * 255 / 7);
}

/// Byte -> eight pixel bytes (bit 7 = leftmost), as a little-endian u64.
const spread: [256]u64 = blk: {
    @setEvalBranchQuota(10000);
    var t: [256]u64 = undefined;
    for (0..256) |v| {
        var x: u64 = 0;
        for (0..8) |k| x |= @as(u64, (v >> (7 - k)) & 1) << @intCast(8 * k);
        t[v] = x;
    }
    break :blk t;
};

/// The shifter, one line: 20 groups of four plane words -> 320 palette indices.
pub fn lineToChunky(line: []const u8, out: *[320]u8) void {
    for (0..20) |g| groupToChunky(line[g * 8 ..][0..8], out[g * 16 ..][0..16]);
}

/// One 16-pixel group of four plane words -> 16 palette indices.
pub fn groupToChunky(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const v = spread[q[half]] | (spread[q[2 + half]] << 1) |
            (spread[q[4 + half]] << 2) | (spread[q[6 + half]] << 3);
        std.mem.writeInt(u64, out[half * 8 ..][0..8], v, .little);
    }
}

test "the shifter reads plane 0 as bit 0 of the index, leftmost pixel first" {
    var line = [_]u8{0} ** LINE;
    line[0] = 0x80; // plane 0, pixel 0
    line[6] = 0x01; // plane 3, pixel 7
    var out: [320]u8 = undefined;
    lineToChunky(&line, &out);
    try std.testing.expectEqual(@as(u8, 1), out[0]);
    try std.testing.expectEqual(@as(u8, 8), out[7]);
    try std.testing.expectEqual(@as(u8, 0), out[1]);
}

test "an ST colour word keeps its three bits a channel" {
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), color(0x777));
    try std.testing.expectEqual(@as(u32, 0xFF00_00FF), color(0x700));
    try std.testing.expectEqual(@as(u32, 0xFF00_0000), color(0x888)); // STE bit ignored
}
