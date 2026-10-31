// One MPP TRUECOLOR picture in one mode, as tools/mpp_convert.py writes it and
// build.zig ZX0-packs it: map (4 planes x 200 lines of u32 RGBA offset, u16 first
// entry, u16 count), then the indices, then the palette as delta-coded RGB.
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

/// The depacked views the HBL handler and the plane split read.
/// Word views, so the HBL's loads are aligned u32 loads (a misaligned one traps on the board).
pub const View = struct {
    map: []const Rec, // [plane * H + line]
    idx: []const u8,
    pal: []const u32, // RGBA, the plane palette's byte order
};

/// Mode 1 and 2 carry a u8 index per pixel; mode 3 an index byte and a plane byte.
pub fn idxLen(planes: usize) usize {
    return if (planes == 1) W * H else 2 * W * H;
}

/// Bytes the working buffer needs for this blob: depacked, plus the alpha bytes.
pub fn need(image: []const u8, planes: usize) ?usize {
    const len: usize = zx0.depackedLen(image) orelse return null;
    const head = MAP_LEN + idxLen(planes);
    if (len < head or (len - head) % 3 != 0) return null;
    return len + (len - head) / 3;
}

/// Palette words this blob decodes to (the VRAM table copper lists name, cop.zig).
pub fn paletteWords(image: []const u8, planes: usize) ?usize {
    const len: usize = zx0.depackedLen(image) orelse return null;
    const head = MAP_LEN + idxLen(planes);
    if (len < head or (len - head) % 3 != 0) return null;
    return (len - head) / 3;
}

/// Depack into `work` and decode the palette, all at once. Null when the image is unreadable
/// or a map record points outside the palette (the HBL would copy out of bounds).
pub fn load(image: []const u8, planes: usize, work: []align(4) u8) ?View {
    var d = Decoder.init(image, planes, work) orelse return null;
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
    planes: usize,
    head: usize = 0,
    colours: usize = 0,
    pass: enum { depack, delta, widen, check, done, failed } = .depack,
    i: usize = 0, // the pass's progress (delta: the next byte; widen: entries left; check: bytes done)
    view: View = undefined,

    // Base slice sizes, each ~0.1-0.2 Mc on the board (frame_cost).
    const DEPACK_BYTES: u32 = 1536;
    const DELTA_BYTES: usize = 16 * 1024;
    const WIDEN_ENTRIES: usize = 4 * 1024;
    const CHECK_BYTES: usize = 32 * 1024;

    pub fn init(image: []const u8, planes: usize, work: []align(4) u8) ?Decoder {
        const size = need(image, planes) orelse return null;
        if (work.len < size) return null;
        const stream = zx0.Stream.init(image, work) orelse return null;
        return .{ .stream = stream, .work = work, .planes = planes };
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
            .check => self.check(CHECK_BYTES *| k),
            .done => return .done,
            .failed => return .failed,
        }
        return switch (self.pass) {
            .done => .done,
            .failed => .failed,
            else => .more,
        };
    }

    fn startDelta(self: *Decoder) void {
        const len: usize = self.stream.written();
        self.head = MAP_LEN + idxLen(self.planes);
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
        // head is a multiple of 4 (MAP_LEN and idxLen are), so both word views stay aligned.
        self.view = .{
            .map = std.mem.bytesAsSlice(Rec, self.work[0..MAP_LEN]),
            .idx = self.work[MAP_LEN..self.head],
            .pal = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(pal))),
        };
        self.pass = if (mapFits(self.view)) .check else .failed;
    }

    // Mode 3's plane bytes must all be < PLANES (the split indexes the planes with them).
    fn check(self: *Decoder, n: usize) void {
        if (self.planes == 1) {
            self.pass = .done;
            return;
        }
        const plane = self.view.idx[W * H ..][0 .. W * H];
        const end = @min(plane.len, self.i +| n);
        for (plane[self.i..end]) |p| if (p >= PLANES) {
            self.pass = .failed;
            return;
        };
        self.i = end;
        if (end == plane.len) self.pass = .done;
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
