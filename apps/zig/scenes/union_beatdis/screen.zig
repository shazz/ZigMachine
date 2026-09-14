// --------------------------------------------------------------------------
// BEAT DIS, both versions: screen.js (1024 KB) and screen2.js (512 KB), which
// are the same screen plus, in 512 KB, "THE UNION" on a ripped curve.
//
// update() (screen.js:72-94, screen2.js:103-128, and the letter move of
// scrolltext.draw), then draw() in the JS's order (screen.js:101-128):
//   backStLow.png at (0,0), scroll.png at (0,302)
//   a 640x300 canvas at (0,0): beatdis.png at posVertScrollY1 and Y2, 400 apart
//   a 576x32 canvas at (32,334): scrollback.png at posScrollerX
//   a 576x150 canvas at (32,300): the scroller, fonts2.png 96x100 at y 0
//   512 KB only: the nine sprites, the last first (screen2.js:162-166)
//
// Canvas to ST: every draw lands on an even canvas row, so an ST row is exact.
// x is not always even (3 and 7 a frame): ST column X shows canvas column 2X,
// i.e. a picture at canvas x shows from ST column ceil(x/2) (`halveX`).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const pathchain = zg.pathchain;
const A = @import("assets.zig");
const curve = @import("curve.zig");

pub const Version = enum { k1024, k512 };

pub const TEXT = @embedFile("../../assets/screens/union_beatdis/scrolltext.txt"); // main.js:50-229, jsApp.scrolltext
const FIRST_CHAR = 32;
const GLYPH_C: i32 = 2 * A.GLYPH_W;
const LETTERS = 8; // wide = ceil(576/96)+1 = 7, letters 0..wide
const LETTERS_START_C: i32 = 7 * GLYPH_C;
const TEXT_SPEED_C: i32 = 7; // scrolltext.init(scrolltextcanvas, bitmapfont, 7, ...)

const BACK_SPEED_C: i32 = 3; // posScrollerX -= 3
const BACK_LIMIT_C: i32 = -446; // if (posScrollerX < -446) posScrollerX = 0
const VERT_SPEED_C: i32 = 4; // posVertScrollY -= 4
const VERT_WRAP_C: i32 = 400; // if (<= -400) = 400
const VERT_START_C = [2]i32{ 400, 800 };

// Canvases, halved: (x, y, w, h)
const FRAME_Y = 302 / 2;
const VERT_H = 300 / 2;
const CANVAS_X = 32 / 2;
const CANVAS_W = 576 / 2;
const BACK_Y = 334 / 2;
const TEXT_Y = 300 / 2;
const TEXT_H = 150 / 2;

/// sprites[0..8] (screen2.js:28-36): T H E (blank) U N I O N, as sheet cells.
const SPRITE_CELLS = [_]?u8{ 0, 1, 2, null, 3, 4, 5, 6, 4 };
const SPRITE_LAG = 5; // spritePos - (i*5)

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + A.FONT_COLS * (A.FONT_H / A.GLYPH_H)) @compileError("scrolltext character outside fonts2.png");
}

pub const Screen = struct {
    version: Version,
    letters: zg.scrollring.Ring(i32, LETTERS),
    back_x: i32, // posScrollerX, canvas px
    vert_y: [2]i32, // posVertScrollY1/Y2, canvas px
    sprite_step: u32, // spritePos

    /// onResetEvent; the scroller starts at the top of its text (see union_beatdis.zig).
    pub fn init(self: *Screen, version: Version) void {
        self.version = version;
        self.letters = zg.scrollring.Ring(i32, LETTERS).init(TEXT, LETTERS_START_C, GLYPH_C);
        self.back_x = 0;
        self.vert_y = VERT_START_C;
        self.sprite_step = 0;
    }

    pub fn update(self: *Screen) void {
        self.back_x -= BACK_SPEED_C;
        if (self.back_x < BACK_LIMIT_C) self.back_x = 0;
        for (&self.vert_y) |*y| {
            y.* -= VERT_SPEED_C;
            if (y.* <= -VERT_WRAP_C) y.* = VERT_WRAP_C;
        }
        _ = self.letters.stepCount(TEXT_SPEED_C);
        self.sprite_step +%= 1;
    }

    /// Every pixel is written: backStLow.png is opaque and covers the plane.
    pub fn draw(self: *const Screen, dst: blit.Dst, img: A.Images) void {
        blit.blit(dst, img.background, null, 0, 0, null, .copy);
        blit.blit(dst, img.frame, null, 0, FRAME_Y, null, .copy);
        const vert = dst.window(0, 0, A.SCREEN_W, VERT_H);
        for (self.vert_y) |y| blit.blit(vert, img.beatdis, null, 0, @divExact(y, 2), null, .copy);
        const back = dst.window(CANVAS_X, BACK_Y, CANVAS_W, A.BACK_H);
        blit.blit(back, img.scrollback, null, halveX(self.back_x), 0, null, .copy);
        self.drawLetters(dst.window(CANVAS_X, TEXT_Y, CANVAS_W, TEXT_H), img);
        if (self.version == .k512) self.drawSprites(dst, img.sprites);
    }

    /// The letters sit 96 apart and never overlap, so CODEF's sort by x changes nothing.
    fn drawLetters(self: *const Screen, win: blit.Dst, img: A.Images) void {
        for (self.letters.x, self.letters.c) |x, c| {
            const x_st = halveX(x);
            if (c == '!' and @mod(x, 2) == 1) {
                blit.blit(win, img.bang_odd, null, x_st, 0, 0, .copy);
                continue;
            }
            const g: usize = c - FIRST_CHAR;
            const part = blit.Rect{ .x = g % A.FONT_COLS * A.GLYPH_W, .y = g / A.FONT_COLS * A.GLYPH_H, .w = A.GLYPH_W, .h = A.GLYPH_H };
            blit.blit(win, img.font, part, x_st, 0, 0, .copy);
        }
    }

    /// for (i = sprites.length-1; i >= 0; i--): T lands on top.
    fn drawSprites(self: *const Screen, dst: blit.Dst, sheet: blit.Image) void {
        var i: u32 = SPRITE_CELLS.len;
        while (i > 0) {
            i -= 1;
            const cell = SPRITE_CELLS[i] orelse continue;
            const p = pathchain.at(u16, &curve.X, &curve.Y, self.sprite_step, i, SPRITE_LAG) orelse continue;
            const part = blit.Rect{ .x = @as(usize, cell) * A.SPRITE, .y = 0, .w = A.SPRITE, .h = A.SPRITE };
            blit.blit(dst, sheet, part, p.x, p.y, 0, .copy);
        }
    }
};

/// The first ST column of a picture drawn at canvas x.
/// Scrollback at -3 puts its canvas column 3 (halved column 1) at ST column 0.
fn halveX(x_canvas: i32) i32 {
    return @divFloor(x_canvas + 1, 2);
}
