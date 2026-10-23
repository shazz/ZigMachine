// --------------------------------------------------------------------------
// The screen: contour-filled outline text over a mountain silhouette, with the
// 49-band copper raster as REAL per-scanline palette writes.
//
// The Go composites at 352x272:
//
//   palette.Draw(dst, raster, PaletteScaled32, level)   // rows 102..199
//   if active { layer.Clear(); text.Draw(layer view y=8..208);
//               dst.DrawImage(layer, -2, shadow); dst.DrawImage(layer, 0) }
//   dst.DrawImage(mountain, +8)
//
// The canvas sits 1:1 in the centre of the 400x280 overscan plane at (24,4);
// the visible 320x200 window is untouched.  Index 0 is the raster/background,
// 1 the text blue, 2 its shadow, 3 the mountain's black.  Because index 0 is
// the raster on rows 106..203, the plane's side margins carry the same colour
// as the content -- a real ST raster runs edge to edge -- and its background
// above and below the raster is black.  The canvas's own content may spill
// into the open border bands, which is what the 400x280 plane is for.
//
// The text fill is the production's Ebiten FillRuleEvenOdd over all eight
// glyphs in one pass (textrow.zig turns it into per-row toggle masks).  The
// Go's layer order -- shadow (source row y+2 drawn at y), then text, then the
// mountain on top -- makes every canvas pixel a pure function of three bits:
//
//   mountain ? 3 : text(y) ? 1 : text(y+2) ? 2 : 0
//
// so the frame is composed four pixels at a time and a word is STORED only
// when it differs from what the plane already holds (on the board every store
// is a blocking DDR write).  The first port cleared all 112 KB, re-tested
// 70,400 mountain pixels and ran a 64-bit inside() per glyph-box pixel every
// frame; the picture is byte for byte the same.  Rows outside 6..207 of the
// canvas are only ever black: init's clear leaves them so.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const clockmod = @import("clock.zig");
const textrow = @import("textrow.zig");

pub const PHYS_W: usize = zg.PHYSICAL_WIDTH; // 400
pub const PHYS_H: usize = zg.PHYSICAL_HEIGHT; // 280
pub const CANVAS_W: usize = textrow.CANVAS_W; // 352
pub const CANVAS_H: usize = 272;
pub const CANVAS_X: usize = 24;
pub const CANVAS_Y: usize = 4; // (280-272)/2

pub const IDX_BG: u8 = 0;
pub const IDX_TEXT: u8 = 1;
pub const IDX_SHADOW: u8 = 2;
pub const IDX_MOUNTAIN: u8 = 3;

/// Raster rows in the canvas: y=102..199, two lines a colour.
const RASTER_Y0: usize = 102;
const RASTER_Y1: usize = 200;

/// Text source rows (the Go's clipped view) and the canvas rows they reach.
const TEXT_Y0: i32 = 8;
const TEXT_Y1: i32 = 207;
const ROW0: i32 = TEXT_Y0 - 2; // the shadow of source row 8
const MOUNTAIN_Y0: i32 = 8;

pub var raster_level: u8 = 0;

/// 4 mask bits -> 4 bytes of 0xFF.  `lsb` puts bit 0 at pixel 0 (text masks);
/// otherwise bit 3 is pixel 0 (the mountain's MSB-first bytes).
fn byteMasks(comptime lsb: bool) [16]u32 {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*o, n| {
        var v: u32 = 0;
        for (0..4) |i| {
            const b = if (lsb) (n >> i) & 1 else (n >> (3 - i)) & 1;
            if (b != 0) v |= @as(u32, 0xFF) << @intCast(8 * i);
        }
        o.* = v;
    }
    return t;
}
const TEXT_MASK = byteMasks(true);
const MOUNT_MASK = byteMasks(false);

/// Compose the frame and store only the words that change.  Only the 32-pixel
/// chunks of a row that hold text now or held it last frame are visited: the
/// rest already hold exactly their mountain (or black) pixels.
/// `text`: the glyphs are shown; `mountain`: the silhouette is (false once done).
pub fn drawFrame(fb: *zg.LogicalFB, c: *const clockmod.Clock, text: bool, mountain: bool) void {
    if (text) textrow.prepare(c);
    var ring: [3]textrow.Row = undefined;
    var full: u32 = 0; // bit i: ring[i] holds a built row (a register, not a stack array)
    const words: [*]u32 = @ptrCast(@alignCast(fb.fb));
    const redo_all = mountain != last_mountain;
    // Canvas rows 6 and 7 carry no text of their own (sources start at 8), so
    // the ring starts empty; T(r+2) is built at row r and read again at r+2.
    var r: i32 = ROW0;
    while (r <= TEXT_Y1) : (r += 1) {
        const ahead = r + 2;
        const ai: usize = @intCast(@mod(ahead, 3));
        const built = text and ahead >= TEXT_Y0 and ahead <= TEXT_Y1 and textrow.build(ahead, &ring[ai]);
        full = (full & ~(@as(u32, 1) << @intCast(ai))) | (@as(u32, @intFromBool(built)) << @intCast(ai));
        const ri: usize = @intCast(@mod(r, 3));
        const tr: *const textrow.Row = if (full >> @intCast(ri) & 1 != 0) &ring[ri] else &EMPTY_ROW;
        const sr: *const textrow.Row = if (full >> @intCast(ai) & 1 != 0) &ring[ai] else &EMPTY_ROW;
        const ix: usize = @intCast(r - ROW0);
        const now = inkedChunks(tr) | inkedChunks(sr);
        const todo: u16 = if (redo_all) ALL_CHUNKS else now | last_chunks[ix];
        if (last_chunks[ix] != now) last_chunks[ix] = now;
        if (todo == 0) continue;
        const my = r - MOUNTAIN_Y0;
        const mrow: *const [44]u8 = if (mountain and my >= 0) A.MOUNTAIN[@as(usize, @intCast(my)) * 44 ..][0..44] else &EMPTY_MOUNTAIN;
        const base = ((CANVAS_Y + @as(usize, @intCast(r))) * PHYS_W + CANVAS_X) / 4;
        composeRow(words + base, tr, sr, mrow, todo);
    }
    last_mountain = mountain;
}

const EMPTY_ROW: textrow.Row = @splat(0);
const EMPTY_MOUNTAIN: [44]u8 = @splat(0);
const ALL_CHUNKS: u16 = (1 << textrow.WORDS) - 1;

/// Per canvas row ROW0..TEXT_Y1, the 32-pixel chunks that carried text (or
/// its shadow) last frame; and the mountain flag drawn last frame.  reset()
/// makes the next frame compose every chunk (init's clear has no mountain).
var last_chunks: [TEXT_Y1 - ROW0 + 1]u16 = @splat(ALL_CHUNKS);
var last_mountain: bool = false;

pub fn reset() void {
    last_chunks = @splat(ALL_CHUNKS);
    last_mountain = false;
}

fn inkedChunks(row: *const textrow.Row) u16 {
    var m: u16 = 0;
    for (row, 0..) |w, i| m |= @as(u16, @intFromBool(w != 0)) << @intCast(i);
    return m;
}

/// The chunks in `todo` of one canvas row: 8 words (32 pixels) each.
fn composeRow(dst: [*]u32, tr: *const textrow.Row, sr: *const textrow.Row, mrow: *const [44]u8, todo: u16) void {
    var c: usize = 0;
    while (c < textrow.WORDS) : (c += 1) {
        if ((todo >> @intCast(c)) & 1 == 0) continue;
        const t32 = tr[c];
        const s32 = sr[c];
        for (0..8) |j| {
            const sh: u5 = @intCast(j * 4);
            const t = TEXT_MASK[(t32 >> sh) & 15];
            const s = TEXT_MASK[(s32 >> sh) & 15];
            const msh: u3 = if (j & 1 == 0) 4 else 0;
            const m = MOUNT_MASK[(mrow[c * 4 + j / 2] >> msh) & 15];
            const v = (m & 0x0303_0303) | (~m & ((t & 0x0101_0101) | (~t & s & 0x0202_0202)));
            const w = c * 8 + j;
            if (dst[w] != v) dst[w] = v;
        }
    }
}

// --- the per-line copper ---------------------------------------------------
var last0: u32 = 0xFFFF_FFFF;

pub fn install(fb: *zg.LogicalFB) void {
    last0 = 0xFFFF_FFFF;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    // Every line, so the top, sides and bottom all reopen: this is the same
    // flickerAllHbl openBorders(.all) installs, with the copper added.
    fb.flickerBorder();
    const c = lineColor(line);
    if (c != last0) {
        fb.palette[@as(usize, IDX_BG)] = c;
        last0 = c;
    }
}

pub fn lineColor(phys: u16) u32 {
    const y: usize = phys;
    const top = CANVAS_Y + RASTER_Y0;
    const bottom = CANVAS_Y + RASTER_Y1;
    if (y < top or y >= bottom) return A.BLACK;
    return A.rasterColor((y - top) / 2, raster_level);
}
