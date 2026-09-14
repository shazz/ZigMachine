// --------------------------------------------------------------------------
// REPS scrollers: two CODEF scrolltext_horizontal (codef_scrolltext.js:44-174)
// over the menu's own text, red at canvas row 14 and blue at 326
// (screen.js:98-110, 262-267). Both start at the same offset and always move
// by the same speed, so they are one letter ring drawn twice.
//
// Speed: the joystick nudges scrollspeed by 0.025 inside [0, 4], and
// Math.round(scrollspeed) picks 2, 4, 8, 16 or 32 canvas px a frame
// (screen.js:187-222). Positions start at 704 and move by even steps, so a
// letter's ST column is exactly posx / 2.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

/// jsApp.scrolltext (main.js:50). Byte for byte the hub's text (the tail of
/// union_demo/menu_assets.bin; union_reps_headless.mjs checks it), so the hub's
/// scroller offset names the same character here.
pub const TEXT = @embedFile("../../assets/screens/union_reps/scrolltext.txt");

const FIRST_CHAR = 32; // initTile(64,64,32)
const GLYPH_C: i32 = 64;
const GLYPH = 32; // halved
const SHEET_COLS = 16; // 1024 / 64
const LETTERS = 12; // wide = ceil(640/64)+1 = 11, letters 0..wide
const START_C: i32 = 11 * GLYPH_C;
const RED_Y = 7; // scrolltextRedcanvas.draw(maincanvas, 0, 14)
const BLUE_Y = 163; // scrolltextBluecanvas.draw(maincanvas, 0, 326)
const SPEEDS_C = [_]i32{ 2, 4, 8, 16, 32 };
const DEFAULT_SPEED_C: i32 = 4;
const NUDGE = 0.025;
const MAX_SPEED = 4.0;

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| if (c < FIRST_CHAR or c >= FIRST_CHAR + SHEET_COLS * 4) @compileError("scrolltext character outside the font");
}

pub const Scroller = struct {
    pub const TEXT_LEN = TEXT.len;

    ring: zg.scrollring.Ring(i32, LETTERS),
    scrollspeed: f64,

    /// init(canvas, font, 4, undefined, 0, jsApp.mainscrollerPos): the letters
    /// take the text from `offset`, the hub scroller's next character. The JS
    /// reads past the text's end there; like the hub, this wraps.
    pub fn init(self: *Scroller, start: usize) void {
        self.ring = zg.scrollring.Ring(i32, LETTERS).initAt(TEXT, START_C, GLYPH_C, start);
        self.scrollspeed = 1;
    }

    /// scrolltextBlue.scroffset: the next character to enter (jsApp.mainscrollerPos).
    pub fn offset(self: *const Scroller) usize {
        return self.ring.next;
    }

    pub fn faster(self: *Scroller) void {
        if (self.scrollspeed < MAX_SPEED) self.scrollspeed += NUDGE;
    }

    pub fn slower(self: *Scroller) void {
        if (self.scrollspeed > 0.0) self.scrollspeed -= NUDGE;
    }

    /// The letter walk scrolltext.draw() does before drawing.
    pub fn update(self: *Scroller) void {
        _ = self.ring.stepCount(self.speed());
    }

    fn speed(self: *const Scroller) i32 {
        const r = @floor(self.scrollspeed + 0.5); // Math.round
        if (r >= 0 and r < SPEEDS_C.len) return SPEEDS_C[@intFromFloat(r)];
        return DEFAULT_SPEED_C;
    }

    pub fn draw(self: *const Scroller, dst: blit.Dst, font: blit.Image) void {
        for (self.ring.x, self.ring.c) |x, ch| {
            const g: usize = ch - FIRST_CHAR;
            const part = blit.Rect{ .x = g % SHEET_COLS * GLYPH, .y = g / SHEET_COLS * GLYPH, .w = GLYPH, .h = GLYPH };
            const sx = @divFloor(x, 2);
            blit.blit(dst, font, part, sx, RED_Y, 0, .{ .flat = A.RED_INK });
            blit.blit(dst, font, part, sx, BLUE_Y, 0, .{ .flat = A.BLUE_INK });
        }
    }
};
