// The B.I.G. Demo, KEY B — the B.I.G. scroller.
//
// Giant letters filled with a vertical rainbow, sliding across a cave of
// stalactites and spiderwebs. The main picture advertises it ("Hit B for the
// B.I.G.-Scroller") and the CODEF remake binds no such key.
//
// TWO LAYERS, and the split is the demo's own. Planes 0..2 are the cave; PLANE
// 3 is the glyph. Because the base palette at $D39A makes pens 12..15 identical
// to pens 4..7, the glyph plane is INVISIBLE over the lit parts of the cave and
// only tints the dark parts — the letters do not overwrite the stalactites,
// they colour them, and the rock reads through. That duplication is the trick,
// and it is why the layers separate cleanly out of one bitmap.
//
// THE RAINBOW is static and exact. Timer B = $41 = 65, so the HBL's first write
// lands on display line 66; it then sets Timer B = 2 and writes ONE word every
// TWO scanlines, from a 32-word table at $C038, into palette entries 8, 9, 10
// and 11 at once (`move.w d3,(a5)+` four times). 32 x 2 = 64 lines, display
// 66..129, and the VBL resets the cursor every frame — so the gradient does not
// crawl. The letters move THROUGH a fixed rainbow.
//
// Verified against the real screen's capture to the scanline: every colour
// spans exactly two display lines with no exceptions, the sequence is $C038's
// in order, and the $0607 still on screen at lines 130..131 is the pens HOLDING
// the last word past the $FFFF terminator, not a 33rd entry. The glyph band is
// at 68..131, two lines below where the ramp starts, which is why the first two
// ramp lines have nothing to colour.
//
// THE TEXT IS THE DEMO'S OWN — 4,938 characters from $53000, opening "THE
// EXCEPTIONS PROUDLY PRESENT THE B.I.G.-SCROLL IN THEIR B.I.G.-DEMO" and
// crediting -ME- for code and rasters, Mad Max for music and ES for graphics.
// It is not ASCII: each character is TWO bytes, a $5F terminates, and the
// screen rewinds to the start rather than stopping.
//
// THE FONT is 90 half-glyphs of 32x64 in 30,720 bytes, and its layout is the
// nicest trick on this screen. Byte b picks PLANE b div 30 and CELL b mod 30 of
// a three-bank image, and a 64-pixel character is the pair (b, b+1) in the SAME
// plane. Plane 3 has no ink at all — which is exactly why SPACE is $5A (90 div
// 30 = 3, the empty plane) and why space is the only character written as the
// same byte twice instead of (n, n+1): with a blank plane it does not matter
// which cell you pick.
//
// That empty plane read as a contradiction at first — the screen blit touches
// plane 3 and the font's plane 3 is zero — and the resolution is that the two
// are different steps. Font ink lives in planes 0..2 as a glyph-set SELECTOR;
// screen ink lives in plane 3 as the tint layer; a renderer in between moves
// one to the other.
//
// THE SCROLL RATE, 2 px a frame, is DERIVED and not measured: eight phases
// consuming one 16-pixel coarse shift. The eight are not all distinct (1-3
// share handlers with 5-7), so they may not each advance equally, and the
// competing reading — phase 0 fetching one character per 8-phase cycle — gives
// 8 px a frame instead. One number, two readings, neither measured; it is a
// constant here so a measurement is a one-line change.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const D = @import("keyb_data.zig");

const W: usize = 320;
const H: usize = 200;
const X0: usize = (zg.PHYSICAL_WIDTH - W) / 2;
const Y0: usize = (zg.PHYSICAL_HEIGHT - H) / 2;
const GLYPH: u8 = 8; // plane 3, ORed onto the cave's pen
const STEP: usize = 2; // px per frame — derived, see the header
const ROW_BYTES: usize = D.CELL_W / 8;

const cave = @embedFile("../../assets/screens/big_demo/keyb_cave.raw");
/// 90 half-glyphs of 32x64, one bit per pixel, row-major within a half.
const font = @embedFile("../../assets/screens/big_demo/keyb_font.raw");
/// One byte per character: the LEFT half. The right is b+1, except space,
/// whose halves are both $5A.
const text = @embedFile("../../assets/screens/big_demo/keyb_text.raw");

/// Entries 8..11, one colour per physical row. Exactly four, which is exactly
/// what the copper drives — the demo writes the same word to all four pens and
/// this is the same operation.
var bars: [4]zg.copper.Table = undefined;

fn colour(w: u16) zg.Color {
    return .{
        .r = @intCast((w >> 8 & 7) * 255 / 7),
        .g = @intCast((w >> 4 & 7) * 255 / 7),
        .b = @intCast((w & 7) * 255 / 7),
        .a = 255,
    };
}

pub const KeyB = struct {
    /// Pixels of text scrolled past the left edge. The text rewinds rather than
    /// stopping, as the demo's own $5F handler does.
    scroll: usize,

    pub fn enter(self: *KeyB, zigos: *zg.ZigOS, fb: *LogicalFB) void {
        self.scroll = 0;
        for (D.BASE, 0..) |w, i| fb.setPaletteEntry(@intCast(i), colour(w));
        fb.clearFrameBuffer(0);
        // Borders shut and black on this screen: entry 0 is $0000 and stays
        // there, so the plane's flicker goes and the hardware border with it.
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zg.copper.install(fb, &.{ 8, 9, 10, 11 }, &bars, .{});
        // The gradient never moves, so it is written once. Each word covers two
        // scanlines; past the table the pens HOLD the last one, which is what
        // the real screen shows below line 129.
        var last = colour(D.RAMP[0]).toRGBA();
        for (0..zg.PHYSICAL_HEIGHT) |row| {
            const y = @as(i32, @intCast(row)) - @as(i32, Y0);
            const i = @divFloor(y - @as(i32, D.RAMP_Y), 2);
            if (i >= 0 and i < D.RAMP.len) last = colour(D.RAMP[@intCast(i)]).toRGBA();
            for (0..4) |s| zg.copper.table(fb, @intCast(s))[row] = if (y < D.RAMP_Y) colour(D.RAMP[0]).toRGBA() else last;
        }
        for (0..H) |y| {
            @memcpy(fb.fb[(Y0 + y) * zg.PHYSICAL_WIDTH + X0 ..][0..W], cave[y * W ..][0..W]);
        }
    }

    pub fn draw(self: *KeyB, fb: *LogicalFB) void {
        for (0..D.BAND_H) |r| {
            const base = cave[(D.BAND_Y + r) * W ..][0..W];
            const dst = fb.fb[(Y0 + D.BAND_Y + r) * zg.PHYSICAL_WIDTH + X0 ..][0..W];
            for (dst, base, 0..) |*d, c, x| {
                d.* = if (inkAt(self.scroll + x, r)) c | GLYPH else c;
            }
        }
        self.scroll += STEP;
        if (self.scroll >= text.len * D.CHAR_W) self.scroll = 0;
    }
};

/// Is the text inked at absolute pixel column `p`, band row `r`? The character
/// is p / 64; within it, the left half is the text byte and the right is that
/// byte + 1 — except SPACE, both of whose halves are the same byte and which
/// selects the font's blank plane anyway.
fn inkAt(p: usize, r: usize) bool {
    const ch = (p / D.CHAR_W) % text.len;
    const col = p % D.CHAR_W;
    const left = text[ch];
    const b: usize = if (col < D.CELL_W or left == D.SPACE) left else @as(usize, left) + 1;
    if (b >= D.HALVES) return false; // the blank plane: space
    const x = col % D.CELL_W;
    const byte = font[(b * D.GH + r) * ROW_BYTES + x / 8];
    return byte & (@as(u8, 0x80) >> @intCast(x % 8)) != 0;
}

comptime {
    if (cave.len != W * H) @compileError("keyb_cave.raw is not 320x200");
    if (font.len != D.HALVES * D.GH * ROW_BYTES) @compileError("keyb_font.raw is not 90 halves of 32x64 bits");
    if (D.GH != D.BAND_H) @compileError("a glyph is exactly the band's height");
    if (text.len == 0) @compileError("keyb_text.raw is empty");
    if (D.RAMP.len != 32) @compileError("the ramp is 32 words, not 33: $FFFF terminates it");
    if (D.BAND_Y + D.BAND_H > H) @compileError("the glyph band runs off the screen");
    for (D.BASE[8..12]) |w| if (w != D.BASE[8]) @compileError("pens 8..11 must share one colour");
    for (D.BASE[12..16], D.BASE[4..8]) |a, b| if (a != b) @compileError("pens 12..15 must repeat 4..7");
}
