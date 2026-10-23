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
const al = @import("st_align.zig");

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

    /// A long: one 32-bit load where the address allows. On KESTREL a misaligned
    /// word access TRAPS (~700 cycles, emulated), and the 68000 reads a long at
    /// any even address (SYNC's 230-byte overscan lines put half of them at 2 mod 4).
    pub inline fn l(self: *const Ram, a: u32) u32 {
        const p = self.m[self.at(a, 4)..][0..4];
        if (@intFromPtr(p) & 3 == 0) return std.mem.readInt(u32, @as(*align(4) const [4]u8, @alignCast(p)), .big);
        return @byteSwap(al.le32Split(p));
    }

    pub inline fn sb(self: *const Ram, a: u32, v: u8) void {
        self.m[self.at(a, 1)] = v;
    }

    pub inline fn sw(self: *const Ram, a: u32, v: u16) void {
        std.mem.writeInt(u16, self.m[self.at(a, 2)..][0..2], v, .big);
    }

    /// A long store, split like l() where a 32-bit store would trap.
    pub inline fn sl(self: *const Ram, a: u32, v: u32) void {
        const p = self.m[self.at(a, 4)..][0..4];
        if (@intFromPtr(p) & 3 == 0) return std.mem.writeInt(u32, @as(*align(4) [4]u8, @alignCast(p)), v, .big);
        al.setLe32Split(p, @byteSwap(v));
    }

    /// `n` bytes at `a`.
    pub inline fn bytes(self: *const Ram, a: u32, n: usize) []u8 {
        return self.m[self.at(a, n)..][0..n];
    }

    /// movem / move.l copies: never overlapping in these routines.
    /// Word-aligned ends copy as LLVM likes; others (TCB's 6-byte plane runs at 2 mod 4)
    /// by halves, where LLVM's 4-byte pieces would trap on KESTREL.
    pub inline fn cp(self: *const Ram, dst: u32, src: u32, n: usize) void {
        const d = self.bytes(dst, n);
        const s = self.bytes(src, n);
        if ((@intFromPtr(d.ptr) | @intFromPtr(s.ptr)) & 3 == 0) @memcpy(d, s) else al.copySplit(d, s);
    }

    pub inline fn zero(self: *const Ram, a: u32, n: usize) void {
        const d = self.bytes(a, n);
        if (@intFromPtr(d.ptr) & 3 == 0) @memset(d, 0) else al.zeroSplit(d);
    }
};

pub const le32 = al.le32;

/// A 68000 word as the signed displacement `(a0,d0.w)` / `lea d(a0)` make of it.
pub inline fn sx(v: u16) i32 {
    return @as(i16, @bitCast(v));
}

/// `a + d` with a sign-extended displacement, wrapping as a 32-bit address does.
pub inline fn add(a: u32, d: i32) u32 {
    return a +% @as(u32, @bitCast(d));
}

/// ST colour word -> RGBA (a = 255), channel c * 255 / 7 as the other ST ports do.
/// A 512-entry table (3 bits a channel; the STE bit is ignored): a raster's 4,480
/// colours a frame are loads, not 12 multiplies and divides each.
pub inline fn color(v: u16) u32 {
    return color_lut[((v >> 2) & 0x1C0) | ((v >> 1) & 0x38) | (v & 7)];
}

const color_lut: [512]u32 = blk: {
    var t: [512]u32 = undefined;
    for (0..512) |i| {
        const r: u32 = (i >> 6) & 7;
        const g: u32 = (i >> 3) & 7;
        const bl: u32 = i & 7;
        t[i] = 0xFF00_0000 | (bl * 255 / 7) << 16 | (g * 255 / 7) << 8 | (r * 255 / 7);
    }
    break :blk t;
};

/// The shifter, one line: 20 groups of four plane words -> 320 palette indices.
pub fn lineToChunky(line: []const u8, out: *[320]u8) void {
    for (0..20) |g| groupToChunky(line[g * 8 ..][0..8], out[g * 16 ..][0..16]);
}

/// Nibble -> four pixel bytes (bit 3 = leftmost), as a little-endian u32: groupToChunky
/// stays in 32-bit registers (a u64 shift/or is a libcall pair on ZIGGY).
const spread4: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |v| {
        var x: u32 = 0;
        for (0..4) |k| x |= @as(u32, (v >> (3 - k)) & 1) << @intCast(8 * k);
        t[v] = x;
    }
    break :blk t;
};

/// One 16-pixel group of four plane words -> 16 palette indices.
pub fn groupToChunky(q: *const [8]u8, out: *[16]u8) void {
    inline for (0..2) |half| {
        const p0 = q[half];
        const p1 = q[2 + half];
        const p2 = q[4 + half];
        const p3 = q[6 + half];
        const hi = spread4[p0 >> 4] | (spread4[p1 >> 4] << 1) | (spread4[p2 >> 4] << 2) | (spread4[p3 >> 4] << 3);
        const lo = spread4[p0 & 15] | (spread4[p1 & 15] << 1) | (spread4[p2 & 15] << 2) | (spread4[p3 & 15] << 3);
        std.mem.writeInt(u32, out[half * 8 ..][0..4], hi, .little);
        std.mem.writeInt(u32, out[half * 8 + 4 ..][0..4], lo, .little);
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
