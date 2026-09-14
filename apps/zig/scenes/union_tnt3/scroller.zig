// --------------------------------------------------------------------------
// TNT3's scroller: CODEF scrolltext_upAndDown (codef_scrolltext_updown.js),
// initialised with speed 3 on the 640x400 canvas (screen.js:113) and drawn at
// posx 320, posy 0 over a black 640x18 quad (screen.js:835-836).
//
// The object keeps a 640x36 canvas in two halves. Every 60*speed frames the
// active half flips (and the scroll direction with it); on that frame the next
// '|'-separated line is written into the new half, whose old text is cleared,
// while the other half keeps its line. Each frame the 18 rows from scrollposY
// (0..18, one row a frame towards the active half) are drawn at the top. So
// lines alternately drop in from above and rise from below.
//
// Halved: ST row Y shows canvas row 2Y, i.e. half-canvas row 2Y + scrollposY.
// A line of n glyphs starts at canvas x 320 - n*8, which is always even.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const TEXT = "HEY GUYS !|THE TNT-CREW IS VERY PROUD|TO PRESENT YOU THEIR FAST|3D-ROUTINES !!|WE ARE NOT READY AS THERE|ARE SOME ERRORS IN THE|HIDDEN-FACE-ALGORITHM||TRY THE KEYS 1..5|FOR DIFFERENT OBJECTS||1:  UNION-LOGO|2:  TNT-LOGO|3:  BALL|4:  GLIDER|5:  CARRIER||PRESS SPACE TO EXIT|||PROGRAMED BY:|JOJO AND HEXOGEN||LOOK OUT FOR OUR|3D-GAME !|PERHAPS READY AT THE END OF 1989||GREETINGS TO ALL GUYS OUT THERE !||HAVE YOU ALREADY THE 7-TH|TNT-DEMO ??|AGAIN WITH NICE DIGI-SOUND.|IT IS NOT SO BIG LIKE \"FNIL\"|BUT VERY NICE !!||THE LOUSY MUSIC IS FROM|MAD MAX (TEX)|DO YOU LIKE IT ?|||THE GREAT UNION-DEMO !!!||"; // screen.js:112

const SEPARATOR = '|';
const FIRST_CHAR = 32;
const SHEET_COLS = 16; // 256 / 16
const GLYPH_W = 8; // 16x18, halved
const TILE_H_C = 18; // canvas rows of a tile, and of the band
pub const BAND_ROWS = TILE_H_C / 2;
const HOLD_FRAMES = 60 * 3; // delay > 60*speed

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c != SEPARATOR and (c < FIRST_CHAR or c >= FIRST_CHAR + SHEET_COLS * 4)) @compileError("scrolltext character outside fonts.png");
}

pub const Scroller = struct {
    delay: u32,
    dir: i32, // scrolldir
    pos: i32, // scrollposY, 0..18
    high: bool, // scrollhigh: the top half is the active one
    advance: bool, // timeToAdvance
    textpos: usize,
    half: [2][]const u8, // the line each half of the canvas holds

    pub fn init(self: *Scroller) void {
        self.delay = 0;
        self.dir = -1;
        self.pos = TILE_H_C;
        self.high = true;
        self.advance = true;
        self.textpos = 0;
        self.half = .{ "", "" };
    }

    /// update(), then draw()'s text bookkeeping.
    pub fn update(self: *Scroller) void {
        self.delay += 1;
        if (self.delay > HOLD_FRAMES) {
            self.delay = 0;
            self.advance = true;
            self.high = !self.high;
            self.dir = -self.dir;
        }
        self.pos = std.math.clamp(self.pos + self.dir, 0, TILE_H_C);
        if (!self.advance) return;
        const start = self.textpos;
        while (self.textpos < TEXT.len and TEXT[self.textpos] != SEPARATOR) self.textpos += 1;
        self.half[if (self.high) 0 else 1] = TEXT[start..self.textpos];
        self.textpos += 1;
        if (self.textpos >= TEXT.len) self.textpos = 0;
        self.advance = false;
    }

    /// The band (already black) gets the glyphs' ink; their black field
    /// changes nothing on it.
    pub fn draw(self: *const Scroller, dst: blit.Dst, font: blit.Image) void {
        for (0..BAND_ROWS) |y| {
            const row: usize = 2 * y + @as(usize, @intCast(self.pos)); // 0..35 on the 640x36 canvas
            const line = self.half[row / TILE_H_C];
            const glyph_row = row % TILE_H_C / 2;
            const left: i32 = 160 - @as(i32, @intCast(line.len * GLYPH_W / 2));
            for (line, 0..) |c, i| {
                const g: usize = c - FIRST_CHAR;
                const part = blit.Rect{ .x = g % SHEET_COLS * GLYPH_W, .y = g / SHEET_COLS * BAND_ROWS + glyph_row, .w = GLYPH_W, .h = 1 };
                blit.blit(dst, font, part, left + @as(i32, @intCast(i * GLYPH_W)), @intCast(y), 0, .{ .flat = A.RED });
            }
        }
    }
};
