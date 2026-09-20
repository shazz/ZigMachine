// --------------------------------------------------------------------------
// The scrolltext: CODEF scrolltext_horizontal (codef_scrolltext.js), set up as
//
//   myfont.initTile(64, 64, 32)
//   myscrolltext.init(mycanvas, myfont, 4)      screen.js:74-77
//   myscrolltext.draw(390)                      screen.js:102
//
// init() is called with NO sinparam, so the draw loop's `prov` stays 0 for
// every letter: THIS SCROLLER IS FLAT. The sort by posx only fixes draw order
// between non-overlapping tiles, so it changes nothing and is not kept.
//
// wide = ceil(640 / 64) + 1 = 11, and the ring loops `i <= wide`, so there are
// TWELVE letters. Letter i starts at canvas x 11*64 + i*64, moves 4 canvas
// pixels a frame, and on reaching -64 rejoins at 704 + (posx + 64) carrying the
// next character. Every x is even, so halving is exact.
//
// drawTile's y is the tile TOP (drawPart translates by -handle, and the font is
// not mid-handled), so canvas y 390 is ST row 195 and the band is rows 195..226.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

/// screen.js:76, exactly. Its authors' words, not ours.
pub const TEXT = "abcdefghij      THE FUCKING BEST REPLICANTS ST AMIGOS PRESENTS:- EMLYN HUGUES FOOTBALL - BROKEN BY THE REPLICANTS     ONLY A FEW FUCKINGS TO NOCKTANAL THE CANADIANS DICKHEAD, OVERWANKERS DAY AFTER DAY YEAR AFTER YEAR YOU ARE LAMEST AND LAMEST JUST SOME GREETINGS TO OUR BEST FRIENDS: MCA, AUTOMATION, HOTLINE, TCB, TEX, DEREK MD...  CREDITS FOR THIS SCREEN                    CODING -VICKERS-                    AMIGAFONT RIPPER -VANTAGE- FROM ST CONNEXION                    BIG REPLICANTS LOGO BY -PULSAR- FROM NEXT                    MUSIX -MAD MAX- FROM -T-          END OF SCROLL       ";

const FIRST_CHAR = 32; // initTile's tilestart
const TILE_C = 64; // initTile(64, 64): canvas pixels
const TILE = TILE_C / 2; // ST pixels
const COLS = A.FONT_W / TILE; // img.width / tilew = 10
const TILES = COLS * (A.FONT_H / TILE); // 80: characters 32..111
const SPEED = 4; // init(..., 4)
const WIDE = 11; // Math.ceil(640 / 64) + 1
pub const LETTERS = WIDE + 1; // the ring loops i = 0 to wide INCLUSIVE
const START_C = WIDE * TILE_C; // 704
pub const ROW = 390 / 2; // draw(390), the tile's top

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + TILES) @compileError("scrolltext character outside font.png");
}

pub const Scroller = struct {
    posx: [LETTERS]i32, // canvas pixels, always even
    ltr: [LETTERS]u8,
    offset: usize, // scroffset

    pub fn init(self: *Scroller) void {
        self.offset = 0;
        for (&self.posx, &self.ltr, 0..) |*x, *c, i| {
            x.* = @intCast(START_C + i * TILE_C);
            c.* = TEXT[self.offset];
            self.offset += 1;
        }
    }

    /// The first half of draw(): every letter moves, and one that has left the
    /// canvas rejoins the back of the ring with the next character.
    pub fn update(self: *Scroller) void {
        for (&self.posx, &self.ltr) |*x, *c| {
            x.* -= SPEED;
            if (x.* > -TILE_C) continue;
            x.* += START_C + TILE_C;
            c.* = TEXT[self.offset];
            self.offset += 1;
            if (self.offset > TEXT.len - 1) self.offset = 0;
        }
    }

    pub fn draw(self: *const Scroller, dst: blit.Dst, font: blit.Image) void {
        for (self.posx, self.ltr) |x, c| {
            const g: usize = c - FIRST_CHAR;
            const cell = blit.Rect{ .x = g % COLS * TILE, .y = g / COLS * TILE, .w = TILE, .h = TILE };
            blit.blit(dst, font, cell, @divExact(x, 2), ROW, A.TRANSPARENT, .copy);
        }
    }
};
