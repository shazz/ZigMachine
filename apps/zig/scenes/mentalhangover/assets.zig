// --------------------------------------------------------------------------
// MENTAL HANGOVER -- the circular-outline / mountain screen.
//
// Every byte here comes from tools/private_tools/mentalhangover_assets.py,
// which rips it out of github.com/olivierh59500/go-mentalhangover's decoded
// assets/raw/greetings.bin (the production's own Amiga bank at $9000).  The
// script asserts the bank's layout, the 59-glyph outline font, the two byte
// waves, the 49 copper words, the text's 2 `|` / 3 `>` control codes and the
// mountain's 1527 non-zero bytes before writing these files.
//
//   wave.bin      256 signed bytes   source.CircleData.Wave      ($9d12)
//   profile.bin   256 signed bytes   source.CircleData.Profile   ($9e12)
//   colors.bin     49 big-endian RGB12 words                     ($9868)
//   mountain.bin   44 * 200 bytes    1bpp silhouette              ($9fe8)
//   text.bin       raw control text, ending at the $ff terminator ($9f12)
//   glyphs.bin     MHGF v1: 59 glyphs of (angle,row) contours
//
// The glyph table is flat, not nested: GLYPH_START/GLYPH_COUNT index CONTOURS,
// and CONTOUR_START/COUNT index POINTS.  The renderer only needs that, and a
// comptime parse keeps the strings out of RAM.
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/mentalhangover/";

pub const WAVE: []const u8 = @embedFile(DIR ++ "wave.bin");
pub const PROFILE: []const u8 = @embedFile(DIR ++ "profile.bin");
pub const COLOR_BYTES: []const u8 = @embedFile(DIR ++ "colors.bin");
pub const MOUNTAIN: []const u8 = @embedFile(DIR ++ "mountain.bin");
pub const TEXT: []const u8 = @embedFile(DIR ++ "text.bin");
pub const GLYPH_BYTES: []const u8 = @embedFile(DIR ++ "glyphs.bin");

pub const GLYPH_COUNT: usize = 59;
pub const MAX_CONTOURS: usize = 2; // measured: no glyph has more
pub const MAX_POINTS: usize = 13; // measured: 'S' is the longest contour
pub const MAX_TOTAL_CONTOURS: usize = 118;
pub const MAX_TOTAL_POINTS: usize = 512;

pub const Point = struct { angle: u8, row: u8 };

const Table = struct {
    glyph_start: [GLYPH_COUNT]u8,
    glyph_count: [GLYPH_COUNT]u8,
    contour_start: [MAX_TOTAL_CONTOURS]u16,
    contour_count: [MAX_TOTAL_CONTOURS]u8,
    points: [MAX_TOTAL_POINTS]Point,
    ncontours: u16,
    npoints: u16,
};

pub const TABLE: Table = blk: {
    @setEvalBranchQuota(500_000);
    if (GLYPH_BYTES.len < 6 or !std.mem.eql(u8, GLYPH_BYTES[0..5], "MHGF\x01"))
        @compileError("mentalhangover: bad glyphs.bin magic");
    var t: Table = .{
        .glyph_start = @splat(0),
        .glyph_count = @splat(0),
        .contour_start = @splat(0),
        .contour_count = @splat(0),
        .points = @splat(Point{ .angle = 0, .row = 0 }),
        .ncontours = 0,
        .npoints = 0,
    };
    var at: usize = 6; // magic (5) + glyph count (1)
    var g: usize = 0;
    while (g < GLYPH_COUNT) : (g += 1) {
        t.glyph_start[g] = @intCast(t.ncontours);
        const nc: usize = GLYPH_BYTES[at];
        at += 1;
        t.glyph_count[g] = @intCast(nc);
        var c: usize = 0;
        while (c < nc) : (c += 1) {
            const np: usize = GLYPH_BYTES[at];
            at += 1;
            t.contour_start[@as(usize, t.ncontours)] = t.npoints;
            t.contour_count[@as(usize, t.ncontours)] = @intCast(np);
            t.ncontours += 1;
            var p: usize = 0;
            while (p < np) : (p += 1) {
                t.points[@as(usize, t.npoints)] = .{ .angle = GLYPH_BYTES[at], .row = GLYPH_BYTES[at + 1] };
                at += 2;
                t.npoints += 1;
            }
        }
    }
    if (at != GLYPH_BYTES.len) @compileError("mentalhangover: trailing glyph bytes");
    break :blk t;
};

pub const COLOR_WORDS: [49]u16 = blk: {
    var out: [49]u16 = undefined;
    for (&out, 0..) |*w, i| w.* = std.mem.readInt(u16, COLOR_BYTES[i * 2 ..][0..2], .big);
    break :blk out;
};

pub fn waveAt(i: u32) i8 {
    return @bitCast(WAVE[@as(usize, i & 255)]);
}

pub fn profileAt(i: u32) i8 {
    return @bitCast(PROFILE[@as(usize, i & 255)]);
}

/// The text terminator is the first byte >= 128 that is not a command payload.
/// The raw bank has payload bytes $c0 and a final $ff, so a plain scan would
/// stop eight bytes too early.
pub const TERMINAL: usize = blk: {
    var i: usize = 0;
    while (i < TEXT.len) {
        const v = TEXT[i];
        if (v >= 128) break;
        i += 1 + (if (v == '|') @as(usize, 1) else if (v == '>') @as(usize, 5) else 0);
    }
    break :blk i;
};

/// Mountain bit (x, y); one plane, rows of 44 bytes, MSB first.
pub fn mountainPixel(x: usize, y: usize) bool {
    return (MOUNTAIN[y * 44 + (x >> 3)] >> @as(u3, @intCast(7 - (x & 7)))) & 1 != 0;
}

// --- colours ---------------------------------------------------------------
/// The ST's 3-bit channel level n displays at n*255/7.  The Go's copper words
/// are RGB12 (four bits a gun), so a channel snaps to the nearest 3-bit level.
pub fn st3(v4: u16) u8 {
    const n: u16 = (v4 * 7 + 7) / 15;
    return @intCast(n * 255 / 7);
}

pub const BLACK: u32 = 0xFF00_0000;
/// source.RGB12(0x3ad) = (51,170,221) = RGB12 (3,10,13).
pub const TEXT_RGBA: u32 = rgba3(st3(3), st3(10), st3(13));
/// op.ColorScale.Scale(0, 0.6, 11/13) on that colour = (0,102,187) = (0,6,11).
pub const SHADOW_RGBA: u32 = rgba3(st3(0), st3(6), st3(11));
pub const MOUNTAIN_RGBA: u32 = BLACK;

fn rgba3(r: u8, g: u8, b: u8) u32 {
    return (@as(u32, 255) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
}

/// The copper pass is QuantizedScale/32: floor(channel * level / 32) on the
/// 4-bit grid, then the same ST snap.  level is 0..32.
pub fn rasterColor(index: usize, level: u8) u32 {
    const w = COLOR_WORDS[index % 49];
    const r4: u32 = (w >> 8) & 15;
    const g4: u32 = (w >> 4) & 15;
    const b4: u32 = w & 15;
    return rgba3(
        st3(@intCast(r4 * @as(u32, level) / 32)),
        st3(@intCast(g4 * @as(u32, level) / 32)),
        st3(@intCast(b4 * @as(u32, level) / 32)),
    );
}

comptime {
    std.debug.assert(WAVE.len == 256);
    std.debug.assert(PROFILE.len == 256);
    std.debug.assert(COLOR_BYTES.len == 49 * 2);
    std.debug.assert(MOUNTAIN.len == 44 * 200);
    std.debug.assert(TEXT.len == 213);
    std.debug.assert(TERMINAL == TEXT.len - 1);
    std.debug.assert(@as(usize, TABLE.ncontours) <= MAX_TOTAL_CONTOURS);
    std.debug.assert(@as(usize, TABLE.npoints) <= MAX_TOTAL_POINTS);
}
