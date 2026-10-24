// --------------------------------------------------------------------------
// COLORSHOCK 2 — the scroll strip (mycanvas_scroll, 600x500 = ST 300x250).
// Only its top 26 rows ever hold anything: the glyphs are drawn at y=0 and
// scroll_acc.png is drawn over them at (0,0). It is built here in cart RAM,
// in the ink's own indices (0 = transparent), exactly as the original's
// canvas; inkpal.zig renumbers it and the scene keys it onto the field.
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/tcb_colorshock/";
const font_b = @embedFile(DIR ++ "font.raw");
const acc_b = @embedFile(DIR ++ "acc.raw");

pub const STRIP_W: u16 = 300;
const STRIP_WI: i32 = STRIP_W;
pub const STRIP_WU: usize = STRIP_W;
pub const STRIP_H: u16 = 26;

// lib/codef_scrolltext.js: wide = ceil(dst_w/fontw)+1 and the loops run i<=wide.
// The destination is the strip, the original's own 600-wide canvas halved, so
// the arithmetic halves exactly: ceil(600/70)+1 = ceil(300/35)+1 = 10.
const GLYPH_W: i32 = 35;
const GLYPH_H: u16 = 26;
const FONT_SHEET_W: usize = 350;
const GLYPH_COLS: usize = 10;
const FIRST_CHAR: u8 = 32; // myfont.initTile(70,52,32)
const LAST_CHAR: u8 = 91;
const WIDE: i32 = 10;
pub const NB_SLOTS: usize = 11;
const SCROLL_START: i32 = WIDE * GLYPH_W; // 350
const SCROLL_SPEED: i32 = 3; // 6 in CODEF

pub const SCROLL_TEXT = "        HELLO!  THIS IS THE COLORSHOCK DEMO!  CODING BY THE CAREBEARS AND MUSAXX BY MAD MAX.  EVERY ONE OF THOSE SQUARES BOUNCING BEHIND THIS SCROLLER CONTAINS ALL 512 POSSIBLE COLOURS, IMPRESSIVE? NO?  NO, NOT EXTREMELY. THIS IS A )DISK-FILLER)-DEMO. AT THE TIME OF WRITING THIS SCROLLTEXT WE DON'T KNOW WHETER WE WILL HAVE ROOM FOR IT ON THE DISK OR NOT.  THIS DEMO WAS CODED IN A FEW HOURS, SO THERE'S NO BIG LOSS IF WE CANT SQUEEZE IT ONTO THE DISK.   WE DON'T GET ANY INSPIRATION WHAT TO WRITE, SO PERHAPS WE'LL TALK A BIT ABOUT TABLE TENNIS..  ON THE LAWN OUTSIDE NICK'S VILLA, THERE'S A PING-PONG-TABLE.  WHEN ALL THE MEMBERS OF TCB, TANIS AND A.D. ARE HERE, NICK'S COMPUTER-ROOM GETS VERY CROWDED, SO WE HAVE TOURNAMENTS IN TABLE TENNIS.   IF WE GIVE YOU SOME FACTS, YOU SHOULD BE ABLE TO FIGURE OUT WHO IS THE BEST AT TABLE TENNIS....       AN COOL THINKS HE IS BETTER THAN NICK.   TANIS THINKS HE IS BETTER THAN AN COOL.  EVERYBODY WIPES THE FLOOR WITH A.D.   NICK IS BETTER THAN JAS.   TANIS HAS NO CHANCE WHEN HE'S PLAYING NICK.  TANIS HAS NEVER PLAYED JAS.   AN COOL THINKS HE IS BETTER THAN TANIS.   NICK IS BETTER THAN AN COOL.  JAS IS NOT AS GOOD AS AN COOL NOR TANIS.   JAS THINKS HE IS THE BEST.          NOW YOU SHOULD HAVE BEEN ABLE TO FIGURE OUT WHO IS THE BEST AT TABLE TENNIS, OR AT LEAST WHO WAS ON THE KEYBOARD WHEN THIS SCROLLTEXT WAS WRITTEN......    ";

const Slot = struct { x: i32, glyph: u8 };

/// The strip's pixels, rebuilt every frame. Module scope: a buffer inside the
/// Demo struct would cost a duplicate data segment.
pub var pixels: [STRIP_WU * STRIP_H]u8 = undefined;

pub const Text = struct {
    slots: [NB_SLOTS]Slot,
    scroffset: usize,

    pub fn init(self: *Text) void {
        self.scroffset = 0;
        for (&self.slots, 0..) |*slot, i| {
            slot.x = SCROLL_START + @as(i32, @intCast(i)) * GLYPH_W;
            slot.glyph = self.nextChar();
        }
    }

    fn nextChar(self: *Text) u8 {
        const c = SCROLL_TEXT[self.scroffset];
        self.scroffset += 1;
        if (self.scroffset >= SCROLL_TEXT.len) self.scroffset = 0;
        return if (c >= FIRST_CHAR and c <= LAST_CHAR) c - FIRST_CHAR else 0;
    }

    pub fn step(self: *Text) void {
        for (&self.slots) |*slot| {
            slot.x -= SCROLL_SPEED;
            if (slot.x <= -GLYPH_W) {
                slot.x = SCROLL_START + (slot.x + GLYPH_W);
                slot.glyph = self.nextChar();
            }
        }
    }

    /// The glyphs into the strip. The strip clips at its own 300-wide edges,
    /// so a glyph leaving it is cut rather than drawn on the screen behind.
    /// scroll_acc goes over them next (accRow), as the original draws it.
    pub fn build(self: *const Text) void {
        @memset(&pixels, 0);
        for (self.slots) |slot| drawGlyph(slot.glyph, slot.x);
    }
};

/// Strip row gy and scroll_acc's row gy, which is laid over it.
pub fn row(gy: usize) []u8 {
    return pixels[gy * STRIP_WU ..][0..STRIP_WU];
}
pub fn accRow(gy: usize) []const u8 {
    return acc_b[gy * STRIP_WU ..][0..STRIP_WU];
}

// One glyph, clipped to the strip. The clip is the same on every row, so it is
// computed once; the glyph's 0 pixels are copied too (they are transparent).
fn drawGlyph(glyph: u8, x: i32) void {
    const tile_x: usize = (@as(usize, glyph) % GLYPH_COLS) * @as(usize, GLYPH_W);
    const tile_y: usize = (@as(usize, glyph) / GLYPH_COLS) * @as(usize, GLYPH_H);
    const from: i32 = @max(0, -x);
    const to: i32 = @min(GLYPH_W, STRIP_WI - x);
    if (from >= to) return;
    const n: usize = @intCast(to - from);
    const dx: usize = @intCast(x + from);
    var gy: usize = 0;
    while (gy < GLYPH_H) : (gy += 1) {
        const src = (tile_y + gy) * FONT_SHEET_W + tile_x + @as(usize, @intCast(from));
        @memcpy(pixels[gy * STRIP_WU + dx ..][0..n], font_b[src..][0..n]);
    }
}

comptime {
    if (acc_b.len != pixels.len) @compileError("scroll_acc is not the strip's 300x26");
}
