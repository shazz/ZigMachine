// --------------------------------------------------------------------------
// TNT2's moving parts, kept in CANVAS pixels as screen.js keeps them and halved
// only when drawn:
//   Layer     one parallax band (screen.js:35-41, 76-86, 175-180)
//   Scroller  CODEF scrolltext_horizontal with no sinparam (screen.js:29-33, 183)
//
// Halving a canvas x: an ST pixel X covers canvas columns 2X and 2X+1, and the
// art is doubled on the (0,0) grid, so it shows the canvas column 2X. An image
// drawn at canvas x puts its halved column X - ceil(x/2) there: its ST x is
// ceil(x/2). Every x is even at the default speeds; the keys can make it odd.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const CANVAS_W: i32 = 640;

pub fn stX(canvas_x: i32) i32 {
    return @divFloor(canvas_x + 1, 2);
}

pub const Layer = struct {
    scroll: i32, // canvas x of the left copy
    speed: i32, // canvas px a frame (negative: leftwards)

    pub fn init(self: *Layer, speed: i32) void {
        self.scroll = -CANVAS_W; // screen.js:35-37
        self.speed = speed;
    }

    /// screen.js:76-78. Not a modulo: a step past either end restarts at the
    /// other, so at -6 px a frame the band jumps from -636 to 0.
    pub fn update(self: *Layer) void {
        self.scroll +|= self.speed;
        if (self.scroll > 0) self.scroll = -CANVAS_W;
        if (self.scroll < -CANVAS_W) self.scroll = 0;
    }

    /// Drawn at scroll and scroll + 640 (screen.js:175-180).
    pub fn draw(self: *const Layer, dst: blit.Dst, img: blit.Image, top: i32) void {
        const x = stX(self.scroll);
        blit.blit(dst, img, null, x, top, 0, .copy);
        blit.blit(dst, img, null, x + @divExact(CANVAS_W, 2), top, 0, .copy);
    }
};

pub const TEXT = @embedFile("../../assets/screens/union_demo/scrolltext.txt"); // jsApp.scrolltext (main.js:50)

const FIRST_CHAR = 32; // bitmapfont.initTile(64,40,32)
const GLYPH_W_C: i32 = 64;
const GLYPH_W = 32; // halved
const GLYPH_H = 20;
const SHEET_COLS = 10; // fonts.png 640 / 64
const SHEET_ROWS = 7; // 280 / 40
const LETTERS = 12; // wide = ceil(640/64)+1 = 11, letters 0..wide
const START_C: i32 = 11 * GLYPH_W_C;
const POSY = 90; // scrolltext.draw(180), halved

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + SHEET_COLS * SHEET_ROWS) @compileError("scrolltext character outside fonts.png");
}

pub const Scroller = struct {
    ring: zg.scrollring.Ring(i32, LETTERS),

    /// scrolltext.init(..., offset jsApp.mainscrollerPos): the text from its start.
    pub fn init(self: *Scroller) void {
        self.ring = zg.scrollring.Ring(i32, LETTERS).init(TEXT, START_C, GLYPH_W_C);
    }

    pub fn step(self: *Scroller, speed: i32) void {
        _ = self.ring.step(speed);
    }

    /// No sinparam, so no phase walks the sorted letters, and letters 64 px
    /// apart never overlap: drawing order does not matter.
    pub fn draw(self: *const Scroller, dst: blit.Dst, font: blit.Image) void {
        for (self.ring.x, self.ring.c) |x, c| {
            const g: usize = c - FIRST_CHAR;
            const part = blit.Rect{ .x = g % SHEET_COLS * GLYPH_W, .y = g / SHEET_COLS * GLYPH_H, .w = GLYPH_W, .h = GLYPH_H };
            blit.blit(dst, font, part, stX(x), POSY, 0, .copy);
        }
    }
};
