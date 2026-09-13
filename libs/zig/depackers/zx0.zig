// --------------------------------------------------------------------------
// ZX0 depacker, one-shot and resumable.
//
// ZX0 is Einar Saukas's optimal LZ77/LZSS format (BSD-3-Clause,
// https://github.com/einar-saukas/ZX0). Written here from the format
// description, not from its C sources. This is the CURRENT format (v2), not the
// "classic" v1 one: in v2 the high part of a new offset is stored with its
// Elias-gamma data bits inverted.
//
// ZX0 was chosen for carts because the depacker is a few dozen lines with no
// tables and no allocation, and its ratio lands near gzip on the 8-bit
// palette-indexed images the scenes embed. The packer is zx0_pack.zig, driven
// by tools/zx0pack.
//
// ZX0 streams have no header, so ZigMachine wraps them in a container (v1):
//
//   offset  size  field
//   0       4     magic "ZX0!"
//   4       1     container version, 1
//   5       1     fx: the effect shown while depacking (see Fx; 0..7)
//   6       4     depacked length, u32 LITTLE-endian
//   10      1     text length n, 1..MAX_TEXT, ONLY when fx == text
//   11      n     the message, printable ASCII, ONLY when fx == text
//   10      1     bar height (AtariDecrunch's MaxBarHeight, 0..255), ONLY when fx == automation
//   10      1     panel columns c, 1..MAX_PANEL_COLS, ONLY when fx == tex_loader
//   11      1     panel rows r, 1..MAX_PANEL_ROWS, ONLY when fx == tex_loader
//   12      c*r   the panel, row by row, chars in the TEX loader font (isPanelChar),
//                 ONLY when fx == tex_loader
//   ...           the raw ZX0 v2 stream (absent when the length is 0)
//
// An unknown version or fx, or a malformed message, makes the image unreadable:
// null, never a silent fallback to "no effect". `depack` itself ignores the
// effect and just returns the data; depack_fx.zig is what shows it.
//
// The stream is a sequence of blocks. Each one except the first is preceded by
// a single indicator bit whose meaning depends on the block before it:
//
//   after LITERALS:          0 = match at the last offset, 1 = match at a new offset
//   after either MATCH kind: 0 = literals,                 1 = match at a new offset
//
//   literals        gamma(len), then len raw bytes
//   last-offset     gamma(len), copy from the last offset used
//   new-offset      gamma_inverted(msb); msb == 256 ends the stream. Next a
//                   byte b: offset = msb*128 - (b >> 1). The LOW bit of b is
//                   the first bit of gamma(len - 1), which follows.
//
// Bits are read MSB-first from bytes taken off the same stream as literal
// bytes. "Interlaced" Elias gamma: start at 1; while the next bit is 0, shift
// in one more data bit. The first block is always literals, and the last offset
// starts at 1.
//
// `Stream` depacks a budget of output bytes per `step`, so a caller can spread
// a depack across frames or scanlines. `depack` is one unbounded step.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAGIC = "ZX0!";
pub const VERSION = 1;
pub const HEADER_LEN = 10;
pub const MAX_TEXT = 40;
/// The TEX loader panel's limits: the widest and tallest panel that fits the
/// 320x200 window at its fixed left edge (x 80) and bottom row (y 184), 8x8 cells.
pub const MAX_PANEL_COLS = 30;
pub const MAX_PANEL_ROWS = 24;
/// The TEX loader font's range: the 60 glyphs of loader.png, ' ' to '['.
pub const PANEL_FIRST_CHAR = 0x20;
pub const PANEL_LAST_CHAR = 0x5B;

/// The largest offset the format can express: msb 255, low part 0.
pub const MAX_OFFSET = 255 * 128;

pub const Fx = enum(u8) { none = 0, rasters = 1, bar = 2, text = 3, fade = 4, noise = 5, automation = 6, tex_loader = 7 };

pub const Header = struct {
    fx: Fx,
    /// The message (fx == .text) or the panel's cols*rows chars, row by row
    /// (fx == .tex_loader); empty otherwise.
    text: []const u8,
    /// AtariDecrunch's MaxBarHeight; 0 unless fx == .automation.
    bars: u8 = 0,
    /// The TEX loader panel's columns; 0 unless fx == .tex_loader (rows = text.len / cols).
    cols: u8 = 0,
    len: u32,
    /// Offset of the ZX0 stream in the image.
    stream: usize,
};

/// True when the image carries the ZX0 magic. Whether it is READABLE is
/// parseHeader's call.
pub fn isPacked(src: []const u8) bool {
    return src.len >= HEADER_LEN and std.mem.eql(u8, src[0..4], MAGIC);
}

pub fn parseHeader(src: []const u8) ?Header {
    if (!isPacked(src) or src[4] != VERSION) return null;
    const fx: Fx = switch (src[5]) {
        0 => .none,
        1 => .rasters,
        2 => .bar,
        3 => .text,
        4 => .fade,
        5 => .noise,
        6 => .automation,
        7 => .tex_loader,
        else => return null,
    };
    var h = Header{ .fx = fx, .text = "", .len = std.mem.readInt(u32, src[6..10], .little), .stream = HEADER_LEN };
    if (fx == .text) {
        if (src.len <= HEADER_LEN) return null;
        const n = src[HEADER_LEN];
        if (n == 0 or n > MAX_TEXT or src.len - HEADER_LEN - 1 < n) return null;
        h.text = src[HEADER_LEN + 1 ..][0..n];
        if (!isPrintable(h.text)) return null;
        h.stream += 1 + n;
    }
    if (fx == .automation) {
        if (src.len <= HEADER_LEN) return null;
        h.bars = src[HEADER_LEN];
        h.stream += 1;
    }
    if (fx == .tex_loader) {
        if (src.len < HEADER_LEN + 2) return null;
        const cols = src[HEADER_LEN];
        const rows = src[HEADER_LEN + 1];
        if (cols == 0 or cols > MAX_PANEL_COLS or rows == 0 or rows > MAX_PANEL_ROWS) return null;
        const n = @as(usize, cols) * rows;
        if (src.len - HEADER_LEN - 2 < n) return null;
        h.cols = cols;
        h.text = src[HEADER_LEN + 2 ..][0..n];
        if (!isPanelText(h.text)) return null;
        h.stream += 2 + n;
    }
    return h;
}

/// True when every char has a glyph in the TEX loader font (no lowercase).
pub fn isPanelText(text: []const u8) bool {
    for (text) |c| if (c < PANEL_FIRST_CHAR or c > PANEL_LAST_CHAR) return false;
    return true;
}

pub fn isPrintable(text: []const u8) bool {
    for (text) |c| if (c < 0x20 or c > 0x7E) return false;
    return true;
}

/// The size the image depacks to, read from the header without depacking.
pub fn depackedLen(src: []const u8) ?u32 {
    return (parseHeader(src) orelse return null).len;
}

/// Depack `src` into `dst` and return the number of bytes written. Null means
/// the image is not readable ZX0, `dst` is too small, or the stream is corrupt:
/// it overruns its input or the stated length, or references data before the
/// start. Never a partial result.
pub fn depack(src: []const u8, dst: []u8) ?u32 {
    var s = Stream.init(src, dst) orelse return null;
    return switch (s.step(std.math.maxInt(u32))) {
        .done => s.written(),
        .more, .failed => null,
    };
}

pub const Progress = enum { more, done, failed };

pub const Stream = struct {
    r: Reader,
    out: []u8,
    w: usize = 0,
    last_offset: u32 = 1,
    /// The block about to be decoded, or the run in progress.
    phase: Phase = .literal_block,
    /// Bytes still owed by the literal run or match in progress.
    pending: u32 = 0,
    /// Blocks decoded so far; the raster effect keys off it.
    tokens: u32 = 0,

    const Phase = enum { literal_block, rep_block, new_block, literals, copy, done, failed };

    /// Null when the image is not readable ZX0 or `dst` cannot hold it.
    pub fn init(src: []const u8, dst: []u8) ?Stream {
        const h = parseHeader(src) orelse return null;
        if (h.len > dst.len) return null;
        var s = Stream{ .r = .{ .src = src, .pos = h.stream }, .out = dst[0..h.len] };
        if (h.len == 0) s.phase = .done;
        return s;
    }

    pub fn written(self: *const Stream) u32 {
        return @intCast(self.w);
    }

    pub fn total(self: *const Stream) u32 {
        return @intCast(self.out.len);
    }

    /// The last byte the bit reader pulled off the packed stream.
    pub fn lastBitByte(self: *const Stream) u8 {
        return self.r.bits;
    }

    /// Write at most `max_bytes` more output bytes. Once it has answered .done
    /// or .failed it keeps answering the same.
    pub fn step(self: *Stream, max_bytes: u32) Progress {
        var budget = max_bytes;
        while (true) {
            switch (self.phase) {
                .done => return .done,
                .failed => return .failed,
                .literals, .copy => {
                    if (budget == 0) return .more;
                    budget -= self.run(budget);
                },
                .literal_block, .rep_block, .new_block => self.block(),
            }
        }
    }

    fn fail(self: *Stream) void {
        self.phase = .failed;
    }

    /// Decode one block header and validate the whole run before any of it is written.
    fn block(self: *Stream) void {
        self.tokens +%= 1;
        switch (self.phase) {
            .literal_block => {
                const len = self.r.gamma(false) orelse return self.fail();
                if (len > self.out.len - self.w or len > self.r.src.len - self.r.pos) return self.fail();
                self.pending = len;
                self.phase = .literals;
            },
            .rep_block => {
                const len = self.r.gamma(false) orelse return self.fail();
                self.startCopy(len);
            },
            .new_block => {
                const msb = self.r.gamma(true) orelse return self.fail();
                if (msb == 256) {
                    self.phase = if (self.w == self.out.len) .done else .failed;
                    return;
                }
                if (msb > 256) return self.fail();
                const low = self.r.byte() orelse return self.fail();
                self.last_offset = msb * 128 - (low >> 1);
                self.r.backtrack = true;
                const len = self.r.gamma(false) orelse return self.fail();
                self.startCopy(len + 1);
            },
            else => unreachable,
        }
    }

    fn startCopy(self: *Stream, len: u32) void {
        if (self.last_offset == 0 or self.last_offset > self.w or len > self.out.len - self.w) return self.fail();
        self.pending = len;
        self.phase = .copy;
    }

    /// Continue the run in progress by up to `budget` bytes; returns bytes written.
    fn run(self: *Stream, budget: u32) u32 {
        const n = @min(self.pending, budget);
        const dst = self.out[self.w..][0..n];
        if (self.phase == .literals) {
            @memcpy(dst, self.r.src[self.r.pos..][0..n]);
            self.r.pos += n;
        } else {
            // Byte by byte: overlapping matches (offset < len) are how runs are encoded.
            for (dst, self.w..) |*d, i| d.* = self.out[i - self.last_offset];
        }
        self.w += n;
        self.pending -= n;
        if (self.pending == 0) {
            const next_is_new = (self.r.bit() orelse {
                self.fail();
                return n;
            }) == 1;
            self.phase = if (next_is_new) .new_block else if (self.phase == .literals) .rep_block else .literal_block;
        }
        return n;
    }
};

const Reader = struct {
    src: []const u8,
    pos: usize,
    mask: u8 = 0,
    bits: u8 = 0,
    last: u8 = 0,
    backtrack: bool = false,

    fn byte(self: *Reader) ?u8 {
        if (self.pos >= self.src.len) return null;
        self.last = self.src[self.pos];
        self.pos += 1;
        return self.last;
    }

    fn bit(self: *Reader) ?u1 {
        if (self.backtrack) {
            self.backtrack = false;
            return @truncate(self.last);
        }
        self.mask >>= 1;
        if (self.mask == 0) {
            self.mask = 0x80;
            self.bits = self.byte() orelse return null;
        }
        return @intFromBool(self.bits & self.mask != 0);
    }

    /// Interlaced Elias gamma. Capped at 2^26 so a stream of zero bits cannot
    /// spin or overflow; no real length or offset part gets anywhere near that.
    fn gamma(self: *Reader, inverted: bool) ?u32 {
        var value: u32 = 1;
        while ((self.bit() orelse return null) == 0) {
            if (value >= 1 << 26) return null;
            const b: u32 = self.bit() orelse return null;
            value = (value << 1) | (b ^ @intFromBool(inverted));
        }
        return value;
    }
};
