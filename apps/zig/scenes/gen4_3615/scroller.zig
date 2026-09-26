// --------------------------------------------------------------------------
// The scroller and what shows through it (screen.js damier, 183-216, and
// scroller, 223-230).
//
// damier() paints a sky and a 3D chessboard floor, dancingFate() the logo over
// them, and then scroller() draws the 704x176 scroll canvas at (24, 268) with
// 'destination-in': everything on the main canvas survives ONLY where a glyph
// is opaque. So the big ULM font is a window: the letters are filled with sky,
// floor and logo, and everything else in the box is black.
//
// Here the box's contents are painted into a 352x88 buffer (sky and floor are
// raster INKS, the copper colours them per line), and each glyph is blitted
// with zg.blit's .pattern ink, which takes that buffer's pixel under it.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Fate = @import("fate.zig").Fate;

// the scroll canvas at (24, 268), 704x176, in ST pixels
pub const BOX_X = 12;
pub const BOX_Y = 134;
pub const BOX_W = 352;
pub const BOX_H = 88;

pub const SKY_TOP = 135; // fillRect(24, 270, 704, 90): the sky pattern's rows 0..44
pub const FLOOR_TOP = 180; // the floor's 90 canvas rows from 360
pub const FLOOR_ROWS = 90;
const FLOOR_W = 704; // drawPart's partw
const DAMIER_W = 16; // damierWidth: the pattern tile is 32x128, light at (0..15, 0..63) and (16..31, 64..127)
const DAMIER_AMPL: f64 = 400;
const PI: f64 = std.math.pi; // Math.PI: typed, so PI / 250 rounds in f64 as the JS does
const DAMIER_SPEED: f64 = PI / 250;
/// floor row y comes from source row y*corr, corr walking down from 10
const CORR_START: f64 = 10;
const CORR_STEP: f64 = 0.051;
const ZOOM_STEP: f64 = 0.04;
pub const SHADOW_ROWS = 70; // damierShadow's heights: 4+4+6+6+8+8+10+12+12

// scrolltext_horizontal.init(scrollCan, font, 12), in canvas pixels
const GLYPH = 192;
const SPEED = 12;
const WIDE = (FLOOR_W + GLYPH - 1) / GLYPH + 1; // ceil(704/192)+1 = 5
const LETTERS = WIDE + 1;
const Ring = zg.scrollring.Ring(i32, LETTERS);

/// What the box holds before the glyphs cut it out (module scope: too big for the Demo).
var box: [BOX_W * BOX_H]u8 = undefined;
/// Each letter's glyph unpacked to 0/1, re-unpacked only when its character changes.
var glyph_px: [LETTERS][A.FONT_W * A.FONT_H]u8 = undefined;

pub const Scroller = struct {
    ring: Ring,
    cached: [LETTERS]u8, // the character glyph_px[i] holds, 0 = none
    damier_ctr: f64,
    tx: i32, // the chessboard pattern's translation this frame
    ty: i32,
    corr: [FLOOR_ROWS]f64, // damier()'s float walk, kept as the JS computes it

    pub fn init(self: *Scroller) void {
        self.ring = Ring.init(A.text, WIDE * GLYPH, GLYPH);
        self.cached = @splat(0);
        self.damier_ctr = 0;
        self.tx = 0;
        self.ty = 0;
        var c = CORR_START;
        for (&self.corr) |*v| {
            v.* = c;
            c -= CORR_STEP;
        }
    }

    /// damier()'s part of go(): the pattern offset it draws with, then the step.
    pub fn stepFloor(self: *Scroller) void {
        self.tx = trunc(-DAMIER_AMPL - DAMIER_AMPL * @cos(self.damier_ctr));
        self.ty = trunc(-DAMIER_AMPL - DAMIER_AMPL * @sin(2 * self.damier_ctr));
        self.damier_ctr += DAMIER_SPEED;
    }

    /// scrolltext.draw(0)'s move. A letter reaching -192 over a ^C command runs
    /// it (codef_scrolltext.js:119-125) and takes the character after it: the
    /// JS takes that character one frame later, from x -204 instead of -192,
    /// which lands it at the same x (948) the frame after, both off screen.
    pub fn step(self: *Scroller, fate: *Fate) void {
        for (self.ring.x) |x| {
            if (x - SPEED > -GLYPH) continue;
            while (true) {
                switch (self.ring.upcoming()) {
                    A.LOGO_FATE => fate.logoFate(),
                    A.LOGO_WAVEFORM => fate.logoWaveform(),
                    else => break,
                }
                self.ring.skip();
            }
            break; // letters are 192 apart: one wraps per frame at most
        }
        _ = self.ring.step(SPEED);
    }

    /// Paint the box: sky, floor, logo, then keep only the glyphs.
    pub fn render(self: *Scroller, canvas: blit.Dst, fate: *const Fate) void {
        @memset(box[0..BOX_W], 0); // canvas rows 268-269: nothing drawn yet
        @memset(box[BOX_W .. (FLOOR_TOP - BOX_Y) * BOX_W], A.SKY_INK);
        for (FLOOR_TOP..BOX_Y + BOX_H) |Y| self.floorRow(Y, box[(Y - BOX_Y) * BOX_W ..][0..BOX_W]);
        fate.draw(&box, BOX_W, BOX_X, BOX_Y);

        const hole = canvas.window(BOX_X, BOX_Y, BOX_W, BOX_H);
        const ink = blit.Ink{ .pattern = .{ .img = blit.Image.init(&box, BOX_W), .ox = 0, .oy = 0 } };
        for (self.ring.x, self.ring.c, 0..) |x, c, i| {
            const gx = @divExact(x, 2);
            if (gx >= BOX_W or gx + A.FONT_W <= 0) continue;
            if (self.cached[i] != c) unpack(&glyph_px[i], c);
            self.cached[i] = c;
            blit.blit(hole, blit.Image.init(&glyph_px[i], A.FONT_W), null, gx, 0, 0, ink);
        }
    }

    /// Floor row y = 2Y - 360 of damierCan drawn with drawPart(main, -16y,
    /// 360+y, 0, y*corr, 704, 1, 1, 0, 1+0.04y, 1): source x at canvas x cx is
    /// floor((cx + 0.5 + 16y) / zoom), the source row floor(y*corr + 0.5).
    fn floorRow(self: *const Scroller, Y: usize, out: []u8) void {
        const y = 2 * (Y - FLOOR_TOP);
        const fy: f64 = @floatFromInt(y);
        const x0: f64 = 0 - fy * 16;
        const zoom: f64 = 1 + fy * ZOOM_STEP;
        const v: i32 = @intFromFloat(@floor(fy * self.corr[y] + 0.5));
        const top_half = @mod(v - self.ty, 8 * DAMIER_W) < 4 * DAMIER_W;
        for (out, 0..) |*p, bx| {
            const cx: f64 = @floatFromInt(2 * (bx + BOX_X));
            const u = @floor((cx + 0.5 - x0) / zoom);
            if (u >= FLOOR_W) {
                // only floor row 0 stops short (at x 704): the shadow alone is there
                p.* = if (y < SHADOW_ROWS) A.SHADOW_BARE else 0;
                continue;
            }
            const left_half = @mod(@as(i32, @intFromFloat(u)) - self.tx, 2 * DAMIER_W) < DAMIER_W;
            p.* = if (left_half == top_half) A.CHECK_LIGHT else A.CHECK_DARK;
        }
    }
};

fn unpack(out: *[A.FONT_W * A.FONT_H]u8, c: u8) void {
    const bits = A.font[@as(usize, c - A.FONT_FIRST) * A.FONT_H * A.FONT_ROW_BYTES ..][0 .. A.FONT_H * A.FONT_ROW_BYTES];
    for (out, 0..) |*p, i| p.* = (bits[i >> 3] >> @intCast(7 - (i & 7))) & 1;
}

fn trunc(v: f64) i32 {
    return @intFromFloat(@trunc(v));
}
