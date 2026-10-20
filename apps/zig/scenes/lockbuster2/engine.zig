// --------------------------------------------------------------------------
// The six native scroll engines of Lockbuster 2, on the ST's screen bytes.
//
// The Go production (github.com/olivierh59500/go-lockbuster2,
// internal/source/clock.go, NewClock / Step / Screen) rebuilt the demo's
// byte-copy machinery as data: the 68000 code is gone, and what is left is the
// screen-memory arithmetic its unrolled MOVE.B chains actually performed --
// which seven gzipped RAM snapshots of the REAL machine pin byte for byte
// (its TestNativeDisplayCheckpoints: header + all six engines). This file is
// that Go clock, transcribed: every constant, every feedback copy and every
// relative stride is the source's, in the source's order.
//
// THE LAYOUT. Screen memory is the demo's own 32000 bytes inside a 131072-byte
// ring that keeps feeding itself (copies read the PREVIOUS front buffer and
// can land off-screen; the reflection passes read back what earlier rows
// wrote). A row is 160 bytes = 320 pixels x 4 PLANES INTERLEAVED per word:
// [p0w0 p1w0 p2w0 p3w0][p0w1 ...]; each plane word is 16 pixels, 20 word
// triplets a row. That interleaved shape is why a one-byte copy-map offset can
// shift one plane of a band by 8 pixels: the demo's "metallic" shear.
//
// GO SEMANTICS THAT MATTER. Go's copy() is memmove, and the checkpoints
// verified memmove against the 68000 -- so overridesic here uses an explicit
// memmove (dst < src forward, dst > src backward), never @memcpy, which is
// undefined on overlapping slices. Go's `copy` into a slice past its header
// length clamps: the header copies take min(length, 17000). Positions are
// i32 math only when a Go int could go negative, and every cast back to usize
// is one that the checkpoints prove is a non-negative, in-bounds index.
//
// NO FLOAT: the engine is pure integer, like the 68000 original.
// --------------------------------------------------------------------------
const std = @import("std");

pub const SCREEN_BYTES: usize = 32000;
pub const ORIGIN: usize = 32768; // where the demo's screen sits in its 128 KB buffer
pub const HEADER_BYTES: usize = 17000; // per title bank
pub const GLYPH_COUNT: usize = 59;
pub const GLYPH_BYTES: usize = 400; // one glyph: 25 rows x 16 bytes (2 chunks of 16 px)

pub const MAX_PHASES = 8; // phase wraps 0..7; 6 and 7 replay engine 5
pub const TITLE_TICKS: usize = 610; // two title banks of 305 VBLs each
/// The compiled text buffer: sized for the longest message once, reused.
pub const COMPILED_BYTES: usize = blk: {
    var n: usize = 0;
    for (messages) |t| n = @max(n, t.len * GLYPH_BYTES + 416);
    break :blk n;
};
pub const BUFFER_BYTES: usize = 131072; // x2: the two feeding buffers

// The copied-in artwork. tools/private_tools/lockbuster2_assets.py re-derives
// these from the PRG (the Go extractor's decode, re-expressed); each file is
// byte-identical to the Go tree's assets/original/ release of them.
pub const font_bin = @embedFile("../../assets/screens/lockbuster2/font.bin");
pub const raster_banks = [2][]const u8{
    @embedFile("../../assets/screens/lockbuster2/raster-old.bin"), // 139 HBL words
    @embedFile("../../assets/screens/lockbuster2/raster-new.bin"), // 118, an alternate bar set
};
pub const RASTER_BANK_LEN: usize = 2;
pub const messages = [10][]const u8{
    @embedFile("../../assets/screens/lockbuster2/message-0.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-1.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-2.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-3.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-4.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-5.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-6.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-7.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-8.bin"),
    @embedFile("../../assets/screens/lockbuster2/message-9.bin"),
};

comptime {
    if (font_bin.len != GLYPH_COUNT * GLYPH_BYTES)
        @compileError("lockbuster2: incomplete planar font");
    for (raster_banks) |b| if (b.len % 2 != 0) @compileError("lockbuster2: raster banks hold whole words");
}

pub const Copy = struct { src: i16, dst: i16 };

/// A copy path of one engine: 40 (source offset, destination offset) pairs of
/// signed screen-byte offsets relative to the row's first plane word (or
/// src == 0x7fff: read the compiled scroll text instead). Parsed at comptime
/// from the extractor's 160-byte IMAGE data per mode -- 40 big-endian i16
/// pairs, as the 68000's own unrolled dl-lists were cut.
fn copyMap(comptime mode: usize) [40]Copy {
    const path = std.fmt.comptimePrint("../../assets/screens/lockbuster2/copy-map-{d}.bin", .{mode});
    const raw = @embedFile(path);
    if (raw.len != 40 * 4) @compileError("lockbuster2: incomplete copy map");
    var out: [40]Copy = undefined;
    inline for (0..40) |j| {
        out[j].src = @bitCast(std.mem.readInt(u16, raw[j * 4 ..][0..2], .big));
        out[j].dst = @bitCast(std.mem.readInt(u16, raw[j * 4 + 2 ..][0..2], .big));
    }
    return out;
}

pub const maps: [6][40]Copy = blk: {
    var m: [6][40]Copy = undefined;
    for (0..6) |i| m[i] = copyMap(i);
    break :blk m;
};

/// Go:
///   mode := [8]int{0, 1, 2, 3, 4, 5, 5, 5}[phase]
pub const mode_of_phase = [MAX_PHASES]u3{ 0, 1, 2, 3, 4, 5, 5, 5 };

/// The longest scroll text: message-8, 519 chars -> len*400 + 416 bytes, is
/// the COMPILED_BYTES constant above.
/// Go copy()/clear(), and their bounds:
fn memmove(buf: []u8, dst: usize, src: usize, n: usize) void {
    if (n == 0) return;
    if (dst <= src) {
        std.mem.copyForwards(u8, buf[dst .. dst + n], buf[src .. src + n]);
    } else {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            buf[dst + i] = buf[src + i];
        }
    }
}

fn clear(buf: []u8, pos: usize, n: usize) void {
    @memset(buf[pos .. pos + n], 0);
}

pub const Engine = struct {
    buffers: [2][]u8,
    headers: [2][]u8,
    compiled: []u8,
    compiled_len: usize = 0,

    front: usize = 0,
    tick: usize = 0,
    phase: i32 = -1,
    frame: usize = 0,
    byte_phase: usize = 0,
    offset: usize = 0,
    remaining: usize = 0,
    header_tick: usize = 0,

    gold: bool = false, // gold (F1) or metallic (F2) screen palette
    color_text: bool = false, // per-line colour-1 raster (F3) or black text (F4)
    new_raster: bool = false, // raster-new.bin (F5) or raster-old.bin (F6)

    /// zg.mem in the cart, static arrays in the native test: the caller owns
    /// the ring (2 x 128 KB, zeroed as Go's make() would), the two 17 KB
    /// title banks and the per-phase compiled text buffer (~202 KB).
    pub fn init(self: *Engine, buffers: [2][]u8, headers: [2][]u8, compiled: []u8) void {
        for (0..2) |i| @memset(buffers[i], 0);
        self.buffers = buffers;
        self.headers = headers;
        self.compiled = compiled;
        self.compiled_len = 0;
        for (0..2) |i| self.buildHeader(i);
        self.front = 0;
        self.tick = 0;
        self.phase = -1;
        self.frame = 0;
        self.byte_phase = 0;
        self.offset = 0;
        self.remaining = 0;
        self.header_tick = 0;
        self.gold = false;
        self.color_text = false;
        self.new_raster = false;
    }

    /// Go NewClock's Header[2]: each MAIN header message renders into a tall
    /// 17000-byte bank, a SPACE meaning the next 25-row band down (4000 bytes
    /// = 25 rows), so each word gets a band of its own and the slide window
    /// walks the words in sequence.
    fn buildHeader(self: *Engine, bank: usize) void {
        renderHeader(bank, self.headers[bank]);
    }

    /// buildHeader's bank image on its own (no engine), so chunky_tables.zig
    /// expands the very same bytes at comptime.
    pub fn renderHeader(bank: usize, h: []u8) void {
        @memset(h, 0);
        var position: usize = 320;
        var line: usize = 0;
        for (messages[bank]) |r| {
            if (r == ' ') {
                line += 1;
                position = 320 + line * 4000;
                continue;
            }
            const c: i32 = @as(i32, r) - 32;
            const gidx: i32 = std.math.clamp(c, 0, 58);
            const glyph: usize = @as(usize, @intCast(gidx)) * GLYPH_BYTES;
            for (0..25) |y| {
                // Go clock.go lines 53-54, transcribed as written: the bounds
                // check reads position+y*160+16 while the COPY lands at
                // position+y*160. The two readings differ mid-slide by a
                // within-row shift (verified against the model: ticks 160/476
                // differ, the slide-end checkpoint ticks cannot tell them
                // apart), and the shipped Go model is the reference we port,
                // so the copy offset is the literal one.
                const at = position + y * 160;
                if (at + 16 <= HEADER_BYTES) {
                    const src = font_bin[glyph + y * 16 ..][0..16];
                    @memcpy(h[at .. at + 16], src);
                }
            }
            position += 16;
        }
    }

    /// Go Screen(): the 32000 bytes of the front ring that the display shows.
    pub fn screen(self: *const Engine) []const u8 {
        return self.buffers[self.front][ORIGIN .. ORIGIN + SCREEN_BYTES];
    }

    /// The raster colour words of an HBL row, i.e. 0 past the bank's end --
    /// Go's Pixels() feed: w = BE(word) where b[i*2] exists else 0.
    pub fn rasterWord(self: *const Engine, bank: usize, row: usize) u16 {
        _ = self;
        const b = raster_banks[bank];
        if (row * 2 + 1 < b.len) {
            return std.mem.readInt(u16, b[row * 2 ..][0..2], .big);
        }
        return 0;
    }

    /// Go Step(): one VBL per call, in Go's exact order. Anything the checkpoints
    /// pin (positions, lengths, the feedback copies' directions) is transcribed.
    pub fn step(self: *Engine) void {
        self.tick += 1;

        // --- the two title slides: msg band 0 slides DOWN over 305 VBLs
        // into the ring, then bank 1 (with gold on) slides UP through it.
        if (self.header_tick < TITLE_TICKS) {
            const bank = self.header_tick / 305;
            const frame = self.header_tick % 305 + 1;
            var start: i64 = -99 + @as(i64, @intCast(frame));
            var length: usize = 101 * 160;
            if (bank == 1) {
                self.gold = true;
                start = 202 - @as(i64, @intCast(frame));
                length = 106 * 160; // the header is 17000 bytes; Go's slice clamps it
            }
            const target = 1 - self.front;
            const at: i64 = @as(i64, ORIGIN) + start * 160;
            // The checkpoints pin these ranges inside the ring (bank 0:
            // 17088..81888; bank 1: 16288..81888), so the copy is in bounds.
            // Header -> ring: two different allocations, no overlap possible,
            // so this is the one copy here that is NOT the memmove helper.
            const dst = self.buffers[target];
            const src = self.headers[bank];
            const n = @min(length, src.len);
            if (at < 0) @panic("lockbuster2: title slide starts off-ring");
            const dst_at: usize = @intCast(at);
            if (dst_at + n > dst.len) @panic("lockbuster2: title slide exceeds the ring");
            std.mem.copyForwards(u8, dst[dst_at..][0..n], src[0..n]);
            self.front = target;
            self.header_tick += 1;
            return;
        }

        // --- a scroll phase: on its last VBL, compile the next text
        if (self.remaining == 0) {
            self.phase = @mod(self.phase + 1, MAX_PHASES);
            self.frame = 0;
            self.byte_phase = 0;
            self.offset = 0;
            const text = messages[2 + @as(usize, @intCast(self.phase))];
            self.remaining = text.len * 4;
            self.compiled_len = text.len * GLYPH_BYTES + 416;
            @memset(self.compiled, 0); // Go's make(): zeroed
            for (text, 0..) |r, i| {
                const c: i32 = @as(i32, r) - 32;
                const gidx: i32 = std.math.clamp(c, 0, 58);
                const glyph: usize = @as(usize, @intCast(gidx)) * GLYPH_BYTES;
                @memcpy(
                    self.compiled[i * GLYPH_BYTES ..][0..GLYPH_BYTES],
                    font_bin[glyph .. glyph + GLYPH_BYTES],
                );
            }
            switch (self.phase) {
                0 => self.color_text = false,
                1 => {
                    self.gold = true;
                    self.color_text = true;
                },
                2 => self.color_text = false,
                3 => self.gold = true,
                4 => {
                    self.color_text = false;
                    self.new_raster = false;
                },
                5 => {
                    self.gold = true;
                    self.color_text = true;
                },
                else => {}, // phases 6 and 7 replay phase 5's look, flags untouched
            }
        }
        const phase: usize = @intCast(self.phase);
        const mode = mode_of_phase[phase];
        if (self.frame == 4) {
            self.frame = 0;
            self.offset += 384;
        }
        var base: i64 = @as(i64, ORIGIN) + 87 * 160;
        if (mode == 3) base += 15 * 160;
        if (mode == 4) base -= 20 * 160;
        if (mode == 5) base -= 15 * 160;
        const from = self.buffers[self.front];
        const to = self.buffers[1 - self.front];
        const height: usize = if (mode == 5) 24 else 25;
        for (0..height) |y| {
            for (0..4) |plane| {
                const start: i64 = base + @as(i64, @intCast(y)) * 160 + @as(i64, @intCast(plane)) * 2;
                for (maps[mode]) |op| {
                    const dst: usize = @intCast(start + op.dst);
                    if (op.src == 0x7fff) {
                        const off = self.offset + y * 16 + plane * 2;
                        if (off < self.compiled_len) {
                            to[dst] = self.compiled[off];
                        }
                    } else {
                        const src: usize = @intCast(start + op.src);
                        to[dst] = from[src];
                    }
                }
            }
        }
        self.front = 1 - self.front;
        self.byte_phase ^= 1;
        if (self.byte_phase == 0) self.offset += 6;
        self.offset += 1;
        self.frame += 1;
        self.remaining -= 1;

        // --- the reflection / duplicate passes, AFTER the exchange, reading
        // and writing the ring's own pixels (the glyph trails).
        self.pass(mode, base);
    }

    /// Go Step()'s tail: the same mode the copy pass used.
    fn pass(self: *Engine, mode: u3, base: i64) void {
        const buf = self.buffers[self.front];
        switch (mode) {
            0 => self.copyRows(buf, @intCast(base), @intCast(base + 0x38e0), 24, -320, false),
            1 => self.copyRows(buf, @intCast(base + 160), @intCast(base + 0x3700), 23, -320, true),
            2 => self.copyRows(buf, @intCast(base), @intCast(base + 0x46a0), 35, -320, false),
            3 => {
                var src: i64 = base;
                var dst: i64 = base - 0x2a80;
                var stride: i64 = 160;
                var count: i64 = 22;
                while (count >= 0) : (count -= 1) {
                    memmove(buf, @intCast(dst), @intCast(src), 160);
                    memmove(buf, @as(usize, @intCast(dst)) + 160, @intCast(src), 160);
                    src += 160;
                    dst += 160;
                    if (count == 20) stride += 160;
                    dst += stride;
                }
            },
            4 => {
                self.copyRows(buf, @intCast(base), @intCast(base + 0x3e80), 29, -320, false);
                var pos: i64 = @as(i64, ORIGIN) + 0x50f0;
                var delta: i64 = 238;
                var count: i64 = 19;
                while (count >= 0) : (count -= 1) {
                    const n: usize = @intCast((count + 21) * 2);
                    clear(buf, @intCast(pos), n);
                    pos += @as(i64, @intCast(n)) - delta;
                    delta -= 2;
                }
            },
            5 => {
                for (0..24) |y| {
                    const s: usize = @intCast(base + @as(i64, @intCast(y)) * 160);
                    memmove(buf, s + 0x2bc0, s, 160);
                    memmove(buf, s + 0x2bc0 - 0x5140, s, 160);
                }
            },
            else => {},
        }
    }

    /// Go copyRows(): copy()s that OVERLAP their source ring freely (the trail
    /// and its mirror move in 320-byte opposite steps), hence the memmove.
    fn copyRows(self: *Engine, buf: []u8, src_in: usize, dst_in: usize, rows: usize, stride: i64, double: bool) void {
        _ = self;
        var src: i64 = @intCast(src_in);
        var dst: i64 = @intCast(dst_in);
        for (0..rows) |_| {
            memmove(buf, @intCast(dst), @intCast(src), 160);
            if (double) memmove(buf, @intCast(dst + 160), @intCast(src), 160);
            src += 160;
            dst += stride;
        }
    }
};
