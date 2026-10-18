// --------------------------------------------------------------------------
// The ST screen as NATRIUM wrote it: 32000 bytes of low-res interleaved
// bitplanes (20 groups of four big-endian plane words per line). Every effect
// in this port writes the exact bytes the 68000 wrote, into these buffers, so
// "which planes an effect touches" is kept, and a buffer can be compared byte
// for byte with a Hatari RAM snapshot. ZigMachine has no planar mode, so the
// shown buffer is expanded to palette indices once a frame (`toChunky`) --
// which is what the ST's shifter did every scanline.
// --------------------------------------------------------------------------
const std = @import("std");

pub const BYTES = 32000;
pub const LINE = 160;
pub const Screen = [BYTES]u8;

pub inline fn getW(s: *const Screen, off: usize) u16 {
    return (@as(u16, s[off]) << 8) | s[off + 1];
}

pub inline fn setW(s: *Screen, off: usize, v: u16) void {
    s[off] = @truncate(v >> 8);
    s[off + 1] = @truncate(v);
}

pub inline fn orW(s: *Screen, off: usize, v: u16) void {
    setW(s, off, getW(s, off) | v);
}

/// $BF1A: clear all 200 lines.
pub fn clear(s: *Screen) void {
    @memset(s, 0);
}

/// $BED8: copy a whole screen (a1 -> a0).
pub fn copy(dst: *Screen, src: *const Screen) void {
    @memcpy(dst, src);
}

/// $E7C2's fill: every plane set, colour 15 everywhere.
pub fn fillWhite(s: *Screen) void {
    @memset(s, 0xFF);
}

/// $BFB4: longs 00000000 FFFFFFFF -> planes 0,1 clear, planes 2,3 set = colour 12.
pub fn fillColour12(s: *Screen) void {
    var off: usize = 0;
    while (off < BYTES) : (off += 8) {
        @memset(s[off..][0..4], 0x00);
        @memset(s[off + 4 ..][0..4], 0xFF);
    }
}

/// $C47E: an uncompressed ILBM BODY (row = plane0[40] plane1[40] plane2[40]
/// plane3[40]) into ST interleave, rows `row0..row0+rows`. No transform.
pub fn fromIlbm(dst: *Screen, body: []const u8, row0: usize, rows: usize) void {
    for (0..rows) |r| {
        const src = body[r * LINE ..][0..LINE];
        const out = dst[(row0 + r) * LINE ..][0..LINE];
        for (0..20) |x| {
            for (0..4) |p| {
                out[x * 8 + 2 * p] = src[p * 40 + 2 * x];
                out[x * 8 + 2 * p + 1] = src[p * 40 + 2 * x + 1];
            }
        }
    }
}

/// Byte -> eight pixel bytes (bit 7 = leftmost), as two little-endian u32
/// halves: spread_lo is pixels 0..3, spread_hi pixels 4..7. (One u64 table was
/// two-word maths on rv32, and its `writeInt` into a byte slice compiled to
/// eight byte stores: 64,000 bus writes a frame.)
const spread_lo: [256]u32 = spreadTable(0);
const spread_hi: [256]u32 = spreadTable(4);

fn spreadTable(comptime first: usize) [256]u32 {
    @setEvalBranchQuota(10000);
    var t: [256]u32 = undefined;
    for (0..256) |b| {
        var v: u32 = 0;
        for (0..4) |k| v |= @as(u32, (b >> @intCast(7 - first - k)) & 1) << @intCast(8 * k);
        t[b] = v;
    }
    return t;
}

/// The shifter: planes -> palette index p0 + 2p1 + 4p2 + 8p3, 320 x 200.
/// Eight pixels are two aligned u32 stores when the plane allows it.
pub fn toChunky(s: *const Screen, out: []u8, stride: usize) void {
    const aligned = @intFromPtr(out.ptr) & 3 == 0 and stride & 3 == 0;
    for (0..200) |y| {
        const line = s[y * LINE ..][0..LINE];
        const row = out[y * stride ..][0..320];
        for (0..20) |g| {
            const w = line[g * 8 ..][0..8];
            inline for (0..2) |half| {
                const lo = spread_lo[w[half]] | (spread_lo[w[2 + half]] << 1) |
                    (spread_lo[w[4 + half]] << 2) | (spread_lo[w[6 + half]] << 3);
                const hi = spread_hi[w[half]] | (spread_hi[w[2 + half]] << 1) |
                    (spread_hi[w[4 + half]] << 2) | (spread_hi[w[6 + half]] << 3);
                const at = g * 16 + half * 8;
                if (aligned) {
                    const wp: [*]u32 = @ptrCast(@alignCast(row.ptr));
                    wp[at / 4] = lo;
                    wp[at / 4 + 1] = hi;
                } else {
                    std.mem.writeInt(u32, row[at..][0..4], lo, .little);
                    std.mem.writeInt(u32, row[at + 4 ..][0..4], hi, .little);
                }
            }
        }
    }
}

/// $144B8, the field-parity long every interlaced effect shares. The routines
/// disagree on how they read it, and the disagreement is part of the sequence.
pub const Flag = struct {
    v: u32,

    /// $D670, $D472/$D570, $EB42: word = (word + 1) & 1, and that is the parity.
    pub fn toggleWord(self: *Flag) u1 {
        const hi: u32 = ((self.v >> 16) + 1) & 1;
        self.v = (hi << 16) | (self.v & 0xFFFF);
        return @intCast(hi);
    }

    /// $DDEC: parity = word & 1, then `addq.w #1` with no mask.
    pub fn postIncWord(self: *Flag) u1 {
        const hi = self.v >> 16;
        self.v = (((hi + 1) & 0xFFFF) << 16) | (self.v & 0xFFFF);
        return @intCast(hi & 1);
    }

    /// $D7F6, $DB14: the LONG = (long + 1) & 1 -- which zeroes the word the
    /// others read, and toggles $144BA instead.
    pub fn toggleLong(self: *Flag) u1 {
        self.v = (self.v +% 1) & 1;
        return @intCast(self.v);
    }
};

/// ST colour word -> RGBA (a = 255), channel c * 255 / 7 as the other ST ports do.
pub fn stColor(v: u16) u32 {
    const ch = struct {
        fn f(x: u16) u32 {
            return @as(u32, x & 7) * 255 / 7;
        }
    };
    return (0xFF << 24) | (ch.f(v) << 16) | (ch.f(v >> 4) << 8) | ch.f(v >> 8);
}
