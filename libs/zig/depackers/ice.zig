// --------------------------------------------------------------------------
// Pack-Ice depacker.
//
// Pack-Ice is the cruncher the ST scene used for everything — most SNDH tunes
// and a great many .PRGs in the wild are `ICE!` files. Depacking one is the ST
// machine's own job, the same way it loads its own samples, so this lives in
// ZigOS rather than in a build-time tool.
//
// The format runs BACKWARDS: the bit stream is read from the last byte of the
// packed data towards the first, and the output is written from the end of the
// destination towards the start. Bits arrive MSB-first out of an 8-bit shift
// register that reloads when it empties, with the bit shifted out at the moment
// of reload becoming the new register's bottom sentinel — which is what makes
// exactly eight bits come out of every byte.
//
// The stream is then a run of two moves: a LITERAL run (copy N fresh bytes) and
// a STRING match (copy N bytes from somewhere ahead of the write cursor, i.e.
// text already produced). Lengths and offsets use escalating bit widths, read
// from the small tables below.
//
// Ported from the canonical 68000 routine by Axe of Delight, optimised by Nyh
// (the version circulated with Pack-Ice 2.4 and preserved in Lonny Pursell's
// ice24.gfa), working from its structure rather than any C translation.
// --------------------------------------------------------------------------
const std = @import("std");

/// Escalating widths for a literal run's length: read n+1 bits, and while the
/// value read is the maximum for that width, read the next width too.
const LIT_BITS = [_]u16{ 1, 1, 2, 7, 0xE };
const LIT_MAX = [_]u16{ 3, 3, 7, 0xFF, 0x8000 };

// Match length: how many leading zero bits preceded the 1 picks the column.
const LEN_BITS = [_]u8{ 9, 1, 0, 0xFF, 0xFF }; // 0xFF: no extra bits at all
const LEN_BASE = [_]u16{ 8, 4, 2, 1, 0 }; // 0 sends us down the short-offset path

// Match offset, same idea with a second, two-bit prefix.
const OFF_BITS = [_]u16{ 0x0B, 0x04, 0x07 };
const OFF_BASE = [_]u16{ 0x0120, 0x0000, 0x0020 };

pub fn isPacked(src: []const u8) bool {
    return src.len >= 12 and (std.mem.eql(u8, src[0..4], "ICE!") or std.mem.eql(u8, src[0..4], "Ice!"));
}

/// The size the image will depack to, straight out of the header — so a caller
/// can size (or refuse) the destination before doing any work.
pub fn depackedLen(src: []const u8) ?u32 {
    if (!isPacked(src)) return null;
    return be32(src, 8);
}

/// Depack `src` into `dst`, returning how many bytes were written. Null means
/// the image is not Pack-Ice, does not fit, or is corrupt — never a partial
/// result presented as a whole one.
pub fn depack(src: []const u8, dst: []u8) ?u32 {
    if (!isPacked(src)) return null;
    const packed_len = be32(src, 4);
    const out_len = be32(src, 8);
    if (packed_len > src.len or packed_len < 12 or out_len > dst.len) return null;

    var s = Stream{ .src = src[0..packed_len] };
    var w: usize = out_len; // write cursor, walking down towards 0

    while (w > 0) {
        if (s.bit() == 1) {
            // A literal run: one byte, or a counted run plus one.
            var extra: u32 = 0;
            if (s.bit() == 1) extra = @as(u32, s.runLength()) + 1;
            var i: u32 = 0;
            while (i <= extra) : (i += 1) {
                if (w == 0 or s.bad) return null;
                w -= 1;
                dst[w] = s.byte();
            }
        }
        if (s.bad) return null;
        if (w == 0) break;
        if (!s.match(dst, &w)) return null;
    }
    return if (s.bad) null else out_len;
}

const Stream = struct {
    src: []const u8,
    pos: usize = std.math.maxInt(usize), // set on first use; walks down
    buf: u8 = 0, // bit register; 0 means "empty, reload"
    bad: bool = false,

    fn start(self: *Stream) void {
        if (self.pos == std.math.maxInt(usize)) self.pos = self.src.len;
    }

    /// The next byte of packed data, taken from the end backwards. Literal
    /// bytes and the bit register draw from the same cursor.
    fn byte(self: *Stream) u8 {
        self.start();
        if (self.pos == 0) {
            self.bad = true;
            return 0;
        }
        self.pos -= 1;
        return self.src[self.pos];
    }

    /// One bit, MSB first. When the register empties, the bit that emptied it
    /// becomes the reloaded register's bottom sentinel and the bit reported is
    /// the new byte's top one.
    fn bit(self: *Stream) u1 {
        const out: u1 = @truncate(self.buf >> 7);
        self.buf = self.buf << 1;
        if (self.buf != 0) return out;
        const b = self.byte();
        self.buf = (b << 1) | out;
        return @truncate(b >> 7);
    }

    fn bits(self: *Stream, count: u16) u16 {
        var v: u16 = 0;
        var i: u16 = 0;
        while (i < count and !self.bad) : (i += 1) v = (v << 1) | self.bit();
        return v;
    }

    /// Count ONE bits until a zero, at most `width` of them, and return the
    /// column they select: `width - 1` when the very first bit was already 0,
    /// down to -1 when all `width` were ones. (The original spells this as a
    /// `dbcc` loop, which exits when the carry is CLEAR — so it is the ones
    /// that are counted, not the zeros.)
    fn prefix(self: *Stream, width: i16) i16 {
        var d = width - 1;
        while (!self.bad) {
            if (self.bit() == 0) return d;
            d -= 1;
            if (d < 0) return -1;
        }
        return -1;
    }

    /// A literal run's length, through the escalating widths.
    fn runLength(self: *Stream) u16 {
        var total: u16 = 0;
        for (LIT_BITS, LIT_MAX) |width, max| {
            const v = self.bits(width + 1);
            total +%= v;
            if (v != max) break;
        }
        return total;
    }

    /// One string match: copy length+2 bytes from `offset+1` ahead of the write
    /// cursor — text the depacker has already produced.
    fn match(self: *Stream, dst: []u8, w: *usize) bool {
        const p = self.prefix(4);
        const col: usize = @intCast(p + 1);

        var length: u16 = LEN_BASE[col];
        var offset: u16 = 0;
        if (length != 0) {
            const width = LEN_BITS[col];
            if (width != 0xFF) length +%= self.bits(@as(u16, width) + 1);
            offset = self.matchOffset(length);
        } else {
            // The short form: a 6-bit offset, or a 9-bit one biased by 0x40.
            const long = self.bit() == 1;
            offset = self.bits(if (long) 9 else 6) +% (if (long) @as(u16, 0x40) else 0);
        }
        if (self.bad) return false;

        // length+2 bytes, both cursors walking down.
        var read = w.* + offset + 1;
        if (read > dst.len) return false;
        var i: u32 = 0;
        while (i < @as(u32, length) + 2) : (i += 1) {
            if (w.* == 0 or read == 0) return false;
            read -= 1;
            w.* -= 1;
            dst[w.*] = dst[read];
        }
        return true;
    }

    fn matchOffset(self: *Stream, length: u16) u16 {
        const col: usize = @intCast(self.prefix(2) + 1);
        var offset = self.bits(OFF_BITS[col] + 1) +% OFF_BASE[col];
        // An offset of exactly zero means "right behind the cursor"; every other
        // one is measured from the far end of the run, so it carries the length.
        if (offset != 0) offset +%= length;
        return offset;
    }
};

fn be32(d: []const u8, at: usize) u32 {
    return (@as(u32, d[at]) << 24) | (@as(u32, d[at + 1]) << 16) |
        (@as(u32, d[at + 2]) << 8) | d[at + 3];
}
