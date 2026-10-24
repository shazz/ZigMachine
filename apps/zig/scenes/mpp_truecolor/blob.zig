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

/// Depack into `work` and decode the palette. Null when the image is unreadable or
/// a map record points outside the palette (the HBL would copy out of bounds).
pub fn load(image: []const u8, planes: usize, work: []align(4) u8) ?View {
    const size = need(image, planes) orelse return null;
    if (work.len < size) return null;
    const len: usize = zx0.depack(image, work) orelse return null;
    const head = MAP_LEN + idxLen(planes);
    const colours = (len - head) / 3;
    const pal = work[head..][0 .. colours * 4];
    // Undo the delta over the RGB bytes, then widen back to front: entry j moves
    // from 3j to 4j, so no entry is overwritten before it has been read.
    for (3..colours * 3) |i| pal[i] +%= pal[i - 3];
    var j = colours;
    while (j > 0) {
        j -= 1;
        pal[4 * j + 3] = 255;
        pal[4 * j + 2] = pal[3 * j + 2];
        pal[4 * j + 1] = pal[3 * j + 1];
        pal[4 * j] = pal[3 * j];
    }
    // head is a multiple of 4 (MAP_LEN and idxLen are), so both word views stay aligned.
    const view = View{
        .map = std.mem.bytesAsSlice(Rec, work[0..MAP_LEN]),
        .idx = work[MAP_LEN..head],
        .pal = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(pal))),
    };
    return if (mapFits(view) and (planes == 1 or planesFit(view.idx))) view else null;
}

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

fn planesFit(idx: []const u8) bool {
    for (idx[W * H ..]) |p| if (p >= PLANES) return false;
    return true;
}
