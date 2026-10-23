// --------------------------------------------------------------------------
// The scrolltext: font.png (32x32 from ' ') through scrolltext_horizontal at
// speed 2 into a 640x32 canvas, blitted at (0,368) = ST rows 184..199.
//
// The glyph colour: after drawing, go() sets 'source-in' and draws bg2.png
// over the strip, so a glyph pixel keeps its shape and takes bg2's colour at
// that strip pixel: zg.blit's .pattern ink with bg2 at the strip's origin.
// font.png's own red never reaches the screen.
//
// The wave: fx.sinx copies the strip to a second canvas row by row, row i
// shifted by sin(value + 0.22 i) * 2.5, then value += 0.2. go() calls it EVERY
// frame, but shows the shifted copy only while its frame counter (incremented
// first, wrapped at 1000) is above 500: 501 frames straight, 499 waving.
//
// 2.5 640-pixels is 1.25 ST pixels. The browser draws the fractional shift
// smoothed; indexed pixels cannot, so ST row r takes source row 2r's shift
// rounded to the nearest pixel: -1, 0 or +1. That rounding is the port's.
//
// The 'destination-over' go() leaves set is inert: letters are 32 apart and
// 32 wide and the sinx rows are one high each, so nothing ever overlaps.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const fixtrig = zg.fixtrig;
const art = @import("art.zig");

pub const TOP: usize = 368 / 2; // mycanvasscr.draw(mycanvas, 0, 368)
pub const ROWS: usize = 16; // the 640x32 canvas
const GLYPH: usize = 16; // initTile(32,32,32)
const FONT_COLS: usize = 10;
const FONT_FIRST: u8 = 32;
const SPEED: i32 = 1; // scrolltext.init(..., 2)
// wide = ceil(640/32)+1 = 21; letters 0..wide, the first at wide*32
const LETTERS: usize = 22;
const START: i32 = 21 * GLYPH;

const CYCLE: u16 = 1000; // if (frame >= 1000) frame = 0
const STRAIGHT_UNTIL: u16 = 500; // if (frame <= 500) the straight strip
// fx.sinx {value 0, amp 2.5, inc 0.22, offset 0.2}; ST row r is source row 2r
const ROW_STEP: u32 = 2 *% fixtrig.angle(0.22);
const FRAME_STEP: u32 = fixtrig.angle(0.2);

pub const TEXT = " THE REPLICANTS PRESENT ARKANOID II (REVENGE OF DOH) . CRACKIND TIME : 40 SECONDS CHRONO, BY  < R.AL > FROM HOFA ON 19.07.88. MEMBERS OF THE REPLICANTS ARE : HOFA ( < R.AL >, DOM, SNAKE, COBRA, GO HAINE !, KNIGHT 2001), A-TEAM (RANK XEROX, HANNIBAL, EXCALIBUR, GOLDORAK), SHOGUN (NINJA). SPECIAL THANX TO MAD MAX AND ES OF TEX FOR THE FANTASTIC MUSIC. GREETINGS TO : THE UNION, B.O.S.S., WAS (NOT WAS), TSUNOO, THE BLADE RUNNERS, ELWOOD, THE LOCKBUSTER. THIS INTRO WAS CODED BY < R.AL >, MUSIC WRITTEN BY MAD MAX AND GRAPHIC BY HOFA. SEE YOU A NEXT TIME.....                        ";

comptime {
    @setEvalBranchQuota(10_000);
    for (TEXT) |c| if (c < FONT_FIRST or c - FONT_FIRST >= FONT_COLS * 6) @compileError("no glyph for a scrolltext character");
}

const ink = blit.Ink{ .pattern = .{ .img = art.bg2, .ox = 0, .oy = 0 } };

const Ring = zg.scrollring.Ring(i32, LETTERS);

pub const Scroller = struct {
    ring: Ring,
    frame: u16,
    phase: u32, // fx.sinx's value, as a fixtrig angle
    waving: bool,
    shift: [ROWS]i32, // per strip row, this frame (0 while straight)

    pub fn init(self: *Scroller) void {
        self.ring = Ring.init(TEXT, START, GLYPH);
        self.frame = 0;
        self.phase = 0;
        self.waving = false;
        self.shift = [_]i32{0} ** ROWS;
    }

    pub fn step(self: *Scroller) void {
        _ = self.ring.step(SPEED);
        for (&self.shift, 0..) |*s, r| {
            const sn = fixtrig.sin(self.phase +% @as(u32, @intCast(r)) *% ROW_STEP);
            s.* = (5 * sn + 2 * 65536) >> 18; // round(1.25 * sin)
        }
        self.phase +%= FRAME_STEP;
        self.frame += 1;
        if (self.frame >= CYCLE) self.frame = 0;
        self.waving = self.frame > STRAIGHT_UNTIL;
    }

    /// bg back under the strip, then every letter in it.
    pub fn draw(self: *const Scroller, plane: blit.Dst) void {
        art.restore(plane, 0, TOP, art.W, ROWS);
        const strip = plane.window(0, TOP, art.W, ROWS);
        for (self.ring.x, self.ring.c) |x, c| {
            if (x <= -@as(i32, GLYPH) - 1 or x >= art.W + 1) continue;
            const nb: usize = c - FONT_FIRST;
            const gx = (nb % FONT_COLS) * GLYPH;
            const gy = (nb / FONT_COLS) * GLYPH;
            if (!self.waving) {
                blit.blit(strip, art.font, .{ .x = gx, .y = gy, .w = GLYPH, .h = GLYPH }, x, 0, 0, ink);
                continue;
            }
            for (0..ROWS) |r| {
                const part = blit.Rect{ .x = gx, .y = gy + r, .w = GLYPH, .h = 1 };
                blit.blit(strip, art.font, part, x + self.shift[r], @intCast(r), 0, ink);
            }
        }
    }
};
