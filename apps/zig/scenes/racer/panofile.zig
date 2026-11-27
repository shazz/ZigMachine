// --------------------------------------------------------------------------
// RACER: a track's panorama file, `<TRACK>.PAN` (R82 32X look, LOOK.md item 1), checked and viewed in place.
// A palette-indexed strip that wraps a full turn, drawn behind the 3D instead of the mood's backdrop shape
// (backdrop.zig): it scrolls with the camera's yaw and sits on the horizon. Written by tools/racer/panc.py;
// the layout (little-endian, 4-aligned):
//   0 magic "KPAN", 4 version 1, 8 total bytes (= the file), 12 CRC-32 of bytes 32..total
//   16 width u16 (texels a full turn: a power of two, 256..1024), 18 rows u16 (1..MAX_ROWS)
//   20 horizon u16 (the strip row on the horizon line: rows above it are above, the rest below), 22 u0 u16 (the
//      texel straight ahead at yaw 0, < width)
//   24 colours u8 (1..MAX_COLOURS), 25 first u8 (the palette entry of colour 1), 26 flags u8 (bit 0 OPAQUE: no
//      texel is 0, the sky fill under it can be skipped), 27 0
//   28 lower width u16, 30 lower rows u16: the strip's LOWER part (the sea or the plain below the skyline), rows that
//      repeat every `lower width` texels (a power of two, MIN_LOWER..width), stored once: 0, 0 = none
//   32 the colours, RGB0 x colours; then the texels, rows x width bytes, then the lower part's, lower rows x lower
//      width: 0 = clear (the sky shows), else an entry in [first, first + colours)
// The file is untrusted input (a disk's, a user's): every field and every texel is bounded here, a bad file is refused
// by name (the track keeps its mood's backdrop shape), never followed blindly. The entries must lie on the track's own
// ramps, off the car ramps, and no face or decal of the track may use them (trackset checks that with `clash`).
// No ZigOS import: panofile_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const trk = @import("trk.zig");

pub const MAGIC: u32 = 0x4E41504B; // "KPAN"
pub const VERSION: u32 = 1;
pub const HEADER = 32;
pub const MAX_W = 1024;
pub const MIN_W = 256;
pub const MAX_ROWS = 128;
pub const MAX_LOWER = 160; // the lower part's rows
pub const MIN_LOWER = 8; // ... and its narrowest period
pub const MAX_COLOURS = 64;
pub const OPAQUE: u8 = 1;
pub const CAR_LO = 16 + 12 * 8; // the car ramps 12..18 (carmodel: liveries and car files)
pub const CAR_HI = 16 + 19 * 8;
pub var break_crc = false; // racer_look.mjs --break crc (key ^): the CRC not checked, a corrupted file accepted
pub const Error = error{ Truncated, BadMagic, BadVersion, BadCrc, BadSize, BadColours, BadTexel, Clash };

pub const Pan = struct {
    width: u32,
    rows: u32, // the upper part's (rows x width texels)
    horizon: u32,
    u0: u32,
    first: u8,
    colours: []const [4]u8,
    opaque_: bool,
    texels: []const u8, // rows x width
    lower_w: u32 = 0, // the lower part (0 = none): lower_rows x lower_w texels, below the upper part, repeating across
    lower_rows: u32 = 0,
    lower: []const u8 = &.{},

    /// The palette entries the panorama owns.
    pub fn owns(self: *const Pan, c: u8) bool {
        return c >= self.first and c < @as(u32, self.first) + self.colours.len;
    }
};

fn half(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u16, b[at..][0..2], .little);
}

fn word(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, b[at..][0..4], .little);
}

pub fn parse(b: []const u8) Error!Pan {
    if (b.len < HEADER) return error.Truncated;
    if (word(b, 0) != MAGIC) return error.BadMagic;
    if (word(b, 4) != VERSION) return error.BadVersion;
    if (word(b, 8) != b.len) return error.Truncated;
    if (!break_crc and std.hash.crc.Crc32IsoHdlc.hash(b[HEADER..]) != word(b, 12)) return error.BadCrc;
    const w = half(b, 16);
    const rows = half(b, 18);
    const n: u32 = b[24];
    const first: u32 = b[25];
    if (w < MIN_W or w > MAX_W or !std.math.isPowerOfTwo(w) or rows < 1 or rows > MAX_ROWS) return error.BadSize;
    const lw = half(b, 28);
    const lr = half(b, 30);
    if (half(b, 20) > rows + lr or half(b, 22) >= w or b[26] & ~OPAQUE != 0 or b[27] != 0) return error.BadSize;
    if ((lw == 0) != (lr == 0) or lr > MAX_LOWER) return error.BadSize;
    if (lw != 0 and (lw < MIN_LOWER or lw > w or !std.math.isPowerOfTwo(lw))) return error.BadSize;
    if (n < 1 or n > MAX_COLOURS or first < 16 or first + n > 256) return error.BadColours;
    if (first < CAR_HI and first + n > CAR_LO) return error.BadColours; // never over the cars' ramps
    if (b.len != HEADER + 4 * n + w * rows + lw * lr) return error.BadSize;
    const p = Pan{
        .width = w,
        .rows = rows,
        .horizon = half(b, 20),
        .u0 = half(b, 22),
        .first = @intCast(first),
        .colours = @as([*]const [4]u8, @ptrCast(b[HEADER..].ptr))[0..n],
        .opaque_ = b[26] & OPAQUE != 0,
        .texels = b[HEADER + 4 * n ..][0 .. w * rows],
        .lower_w = lw,
        .lower_rows = lr,
        .lower = b[HEADER + 4 * n + w * rows ..],
    };
    for (b[HEADER + 4 * n ..]) |t| {
        if (t == 0 and p.opaque_) return error.BadTexel;
        if (t != 0 and !p.owns(t)) return error.BadTexel;
    }
    return p;
}

/// The panorama's entries must lie on the track's ramps and be used by none of its faces or decals.
pub fn clash(p: *const Pan, t: *const trk.Track) Error!void {
    if (@as(u32, p.first) + p.colours.len > 16 + 8 * t.palette.len) return error.Clash;
    for (t.faces) |f| if (p.owns(f.colour)) return error.Clash;
    for (t.inner) |f| if (p.owns(f.colour)) return error.Clash;
}
