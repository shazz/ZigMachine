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
// THE SCROLL IS THE MECHANISM WITH PLACEHOLDER CONTENT, and that is the one
// thing in this screen that is not the demo's.
//
// The mechanism is read: eight pre-shifted buffers at $D326 onward (stride $80
// = 64 words = one word per band line), an 8-phase frame counter at $D322
// dispatching through a jump table at $D356, a coarse 16-pixel shift of the
// whole band ($D164, every word moving down 8 bytes = one 16-pixel group), and
// a fresh column copied in at $D1F0. That is the classic ST smooth scroll and
// it is what runs here.
//
// What is NOT read is where the glyphs come from: the routine that renders text
// into those eight buffers, and the string it renders. Without it there is no
// text to scroll. So the band scrolls the 320 pixels of glyph THE CAPTURE
// HOLDS, cyclically — the motion, the rate and the colouring are the demo's,
// the letters repeat after 320 px and the real scroller does not. Swapping in
// the real text is a change to this one buffer and nothing else.
//
// The rate, 2 px a frame, is DERIVED and not measured: eight phases consuming
// one 16-pixel coarse shift. The eight phases are not all distinct (1-3 share
// handlers with 5-7), so they may not each advance equally.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const D = @import("keyb_data.zig");

const W: usize = 320;
const H: usize = 200;
const X0: usize = (zg.PHYSICAL_WIDTH - W) / 2;
const Y0: usize = (zg.PHYSICAL_HEIGHT - H) / 2;
const GLYPH: u8 = 8; // plane 3, ORed onto the cave's pen
const STEP: usize = 2; // px per frame — derived, see the header

const cave = @embedFile("../../assets/screens/big_demo/keyb_cave.raw");
const glyph = @embedFile("../../assets/screens/big_demo/keyb_glyph.raw");

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
            const src = glyph[r * W ..][0..W];
            const base = cave[(D.BAND_Y + r) * W ..][0..W];
            const dst = fb.fb[(Y0 + D.BAND_Y + r) * zg.PHYSICAL_WIDTH + X0 ..][0..W];
            for (dst, base, 0..) |*d, c, x| {
                d.* = if (src[(x + self.scroll) % W] != 0) c | GLYPH else c;
            }
        }
        self.scroll = (self.scroll + STEP) % W;
    }
};

comptime {
    if (cave.len != W * H) @compileError("keyb_cave.raw is not 320x200");
    if (glyph.len != W * D.BAND_H) @compileError("keyb_glyph.raw is not 320 x the band");
    if (D.RAMP.len != 32) @compileError("the ramp is 32 words, not 33: $FFFF terminates it");
    if (D.BAND_Y + D.BAND_H > H) @compileError("the glyph band runs off the screen");
    for (D.BASE[8..12]) |w| if (w != D.BASE[8]) @compileError("pens 8..11 must share one colour");
    for (D.BASE[12..16], D.BASE[4..8]) |a, b| if (a != b) @compileError("pens 12..15 must repeat 4..7");
}
