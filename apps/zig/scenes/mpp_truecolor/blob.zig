// One MPP TRUECOLOR picture in one mode, as tools/mpp_convert.py writes it and
// build.zig ZX0-packs it. Indexed (modes 1, 2): map (4 planes x 200 lines of u32 RGBA
// offset, u16 first entry, u16 count), then the indices, then the palette as
// delta-coded RGB. RGB565 (mode 3): 320x200 little-endian words, nothing else.
//
// The pictures stay packed in the cart; the scene depacks the one on screen into a
// single working buffer, once per switch. The palette is stored as RGB deltas
// because that is what ZX0 packs best (the converter's docstring has the numbers),
// so it is decoded and widened to RGBA here, in place, before the HBL sees it.
const std = @import("std");
const zx0 = @import("depackers").zx0;

pub const W: usize = 320;
pub const H: usize = 200;
pub const PLANES: usize = 4;
pub const MAP_REC: usize = 8; // u32 offset, u16 first, u16 count
pub const MAP_LEN: usize = PLANES * H * MAP_REC;

/// One map record as the converter writes it (little-endian, like wasm and rv32):
/// `off` a byte offset into the RGBA palette, `span` = first | count << 16.
pub const Rec = extern struct { off: u32, span: u32 };
comptime {
    std.debug.assert(@sizeOf(Rec) == MAP_REC);
}
const PAL_ENTRIES: usize = 256;

/// Palette indices for one 8-bit plane, or RGB565 words for one true-colour plane (HW 1.15.0).
pub const Kind = enum { indexed, rgb565 };
pub const TC_LEN: usize = 2 * W * H;

/// The depacked views the HBL handler and the pixel copy read (rgb565: `idx` is the words'
/// bytes, map and pal empty). Word views, so the HBL's loads are aligned u32 loads (a
/// misaligned one traps on the board).
pub const View = struct {
    map: []const Rec, // [plane * H + line]
    idx: []const u8,
    pal: []const u32, // RGBA, the plane palette's byte order
};

/// Bytes the working buffer needs for this blob: depacked, plus the alpha bytes.
pub fn need(image: []const u8, kind: Kind) ?usize {
    const len: usize = zx0.depackedLen(image) orelse return null;
    if (kind == .rgb565) return if (len == TC_LEN) len else null;
    const head = MAP_LEN + W * H;
    if (len < head or (len - head) % 3 != 0) return null;
    return len + (len - head) / 3;
}

/// Palette words this blob decodes to (the VRAM table copper lists name, cop.zig).
pub fn paletteWords(image: []const u8, kind: Kind) ?usize {
    const size = need(image, kind) orelse return null;
    return if (kind == .rgb565) 0 else (size - MAP_LEN - W * H) / 4;
}

/// Depack into `work` and decode the palette, all at once. Null when the image is unreadable
/// or a map record points outside the palette (the HBL would copy out of bounds).
pub fn load(image: []const u8, kind: Kind, work: []align(4) u8) ?View {
    var d = Decoder.init(image, kind, work) orelse return null;
    while (true) switch (d.step(std.math.maxInt(u32))) {
        .more => {},
        .done => return d.view,
        .failed => return null,
    };
}

pub const Progress = zx0.Progress;

/// The same decode in slices (mpp_truecolor/stage.zig): one `step` does one slice of one
/// pass, `units` times its base size, so a switch can be spread over frames.
pub const Decoder = struct {
    stream: zx0.Stream,
    work: []align(4) u8,
    kind: Kind,
    head: usize = 0,
    colours: usize = 0,
    pass: enum { depack, delta, widen, done, failed } = .depack,
    i: usize = 0, // the pass's progress (delta: the next byte; widen: entries left)
    view: View = undefined,

    // Base slice sizes, each ~0.1-0.2 Mc on the board (frame_cost).
    const DEPACK_BYTES: u32 = 1536;
    const DELTA_BYTES: usize = 16 * 1024;
    const WIDEN_ENTRIES: usize = 4 * 1024;

    pub fn init(image: []const u8, kind: Kind, work: []align(4) u8) ?Decoder {
        const size = need(image, kind) orelse return null;
        if (work.len < size) return null;
        const stream = zx0.Stream.init(image, work) orelse return null;
        return .{ .stream = stream, .work = work, .kind = kind };
    }

    pub fn step(self: *Decoder, units: u32) Progress {
        const k: usize = units;
        switch (self.pass) {
            .depack => switch (self.stream.step(DEPACK_BYTES *| units)) {
                .more => {},
                .failed => self.pass = .failed,
                .done => self.startDelta(),
            },
            .delta => {
                const pal = self.work[self.head..][0 .. self.colours * 3];
                const end = @max(self.i, @min(pal.len, self.i +| DELTA_BYTES *| k));
                for (self.i..end) |i| pal[i] +%= pal[i - 3];
                self.i = end;
                if (end >= pal.len) self.startWiden();
            },
            .widen => self.widen(WIDEN_ENTRIES *| k),
            .done => return .done,
            .failed => return .failed,
        }
        return switch (self.pass) {
            .done => .done,
            .failed => .failed,
            else => .more,
        };
    }

    // RGB565 has no palette: the depacked words are the view.
    fn startDelta(self: *Decoder) void {
        const len: usize = self.stream.written();
        if (self.kind == .rgb565) {
            self.view = .{ .map = &.{}, .idx = self.work[0..TC_LEN], .pal = &.{} };
            self.pass = if (len == TC_LEN) .done else .failed;
            return;
        }
        self.head = MAP_LEN + W * H;
        self.colours = (len - self.head) / 3;
        self.pass = .delta;
        self.i = 3;
    }

    fn startWiden(self: *Decoder) void {
        self.pass = .widen;
        self.i = self.colours;
    }

    // Widen back to front: entry j moves from 3j to 4j, so no entry is overwritten before
    // it has been read, also across slices (each slice continues downward).
    fn widen(self: *Decoder, n: usize) void {
        const pal = self.work[self.head..][0 .. self.colours * 4];
        const stop = self.i -| n;
        var j = self.i;
        while (j > stop) {
            j -= 1;
            pal[4 * j + 3] = 255;
            pal[4 * j + 2] = pal[3 * j + 2];
            pal[4 * j + 1] = pal[3 * j + 1];
            pal[4 * j] = pal[3 * j];
        }
        self.i = stop;
        if (stop > 0) return;
        // head is a multiple of 4 (MAP_LEN and W * H are), so both word views stay aligned.
        self.view = .{
            .map = std.mem.bytesAsSlice(Rec, self.work[0..MAP_LEN]),
            .idx = self.work[MAP_LEN..self.head],
            .pal = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(pal))),
        };
        self.pass = if (mapFits(self.view)) .done else .failed;
    }
};

fn mapFits(v: View) bool {
    for (v.map) |r| {
        const off: usize = r.off;
        const first: usize = r.span & 0xffff;
        const n: usize = r.span >> 16;
        if (n == 0) continue;
        if (off % 4 != 0 or first + n > PAL_ENTRIES or off / 4 > v.pal.len or n > v.pal.len - off / 4) return false;
    }
    return true;
}
