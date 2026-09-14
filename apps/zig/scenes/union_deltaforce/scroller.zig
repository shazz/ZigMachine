// --------------------------------------------------------------------------
// DELTA FORCE's scroller: CODEF scrolltext_horizontal at 10 canvas pixels a
// frame, no sinparam (codef_scrolltext.js:44-174), steered by effect letters
// hidden in its own text (screen.js:224-271, 355-404):
//
//   'c' INVERSE   twist += 0.1 until pi: turns the band upside down
//   'd' REVERSE   twist += 0.1 until 2 pi: turns it (back) upright
//   'e' GLOBAL    twist = 0, the whole band bobs 30 px on sin(sine += 0.1)
//   'f' NONE      twist = 0
//   'g' RESET     back to the credits band; the scroller starts over (see Demo:
//                 the full restart is a deliberate deviation)
//
// The band is drawn with a vertical scale of cos(twist). 'a' (per-letter sine)
// and 'b' (twist) exist in screen.js but no letter of the text selects them,
// and 'b's case compares against an undefined constant, so neither is ported.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Band = @import("band.zig").Band;

pub const TEXT = @embedFile("../../assets/screens/union_deltaforce/scrolltext.txt"); // screen.js:112, verbatim

const LETTERS = 12; // wide = ceil(640/64)+1 = 11, letters 0..wide
const GLYPH_C: i32 = 64;
const START_C: i32 = 11 * GLYPH_C;
const SPEED_C: i32 = 10; // scrolltextSpeed
const TWIST_STEP: f64 = 0.1;
const SINE_STEP: f64 = 0.1;
const TEXT_Y: f64 = 110 / 2 - 16; // scrollfx_noFX.siny(0, (110/2) - 16)
const SINE_Y: f64 = 110 / 2 - 24; // siny(0, (110/2) - 24 + (30*Math.sin(this.sine)))
const SINE_AMP: f64 = 30;
const CENTRE_Y: f64 = (300.0 + 110.0 / 2.0) / 2.0; // drawPart(main, 320, 300+(110/2), ...)

comptime {
    @setEvalBranchQuota(4 * TEXT.len + 1000);
    for (TEXT) |c| switch (c) {
        'c'...'g' => {},
        else => if (A.glyph(c, 0) == null) @compileError("scrolltext character outside questfont.png"),
    };
}

const Ring = zg.scrollring.Ring(i32, LETTERS);
const Fx = enum { inverse, reverse, global_sine, no_effect, reset };

pub const Scroller = struct {
    ring: Ring,
    fx: Fx,
    twist: f64,
    sine: f64,
    text_y: f64, // this frame's siny y
    visible: bool, // drawn this frame

    pub fn init(self: *Scroller) void {
        self.ring = Ring.init(TEXT, START_C, GLYPH_C);
        self.fx = .reverse; // this.fx = this.C_FX.FX_REVERSE
        self.twist = 0;
        self.sine = 0;
        self.text_y = TEXT_Y;
        self.visible = false;
    }

    /// update(): an effect letter about to enter is consumed and selects its effect.
    pub fn takeMarker(self: *Scroller) void {
        self.fx = switch (self.ring.upcoming()) {
            'c' => .inverse,
            'd' => .reverse,
            'e' => .global_sine,
            'f' => .no_effect,
            'g' => .reset,
            else => return,
        };
        self.ring.skip();
    }

    /// draw()'s own state changes: the letters move, the effect runs. Returns
    /// true on RESET, which leaves the merge canvas empty this frame.
    pub fn advance(self: *Scroller) bool {
        _ = self.ring.stepCount(SPEED_C);
        self.visible = true;
        self.text_y = TEXT_Y;
        switch (self.fx) {
            .reverse => {
                self.twist += TWIST_STEP;
                if (self.twist >= 2 * std.math.pi) self.twist = 2 * std.math.pi;
            },
            .inverse => {
                self.twist += TWIST_STEP;
                if (self.twist >= std.math.pi) self.twist = std.math.pi;
            },
            .no_effect => self.twist = 0,
            .global_sine => {
                self.twist = 0;
                self.sine += SINE_STEP;
                self.text_y = SINE_Y + SINE_AMP * @sin(self.sine);
            },
            .reset => {
                self.twist = 0;
                self.sine = 0;
                // DEVIATION (Matt, 2026-09-14): screen.js only sets scroffset = 0
                // and leaves fx on RESET, so the scroller never runs again. The
                // port restores the constructor's ring and effect: it loops.
                self.ring = Ring.init(TEXT, START_C, GLYPH_C);
                self.fx = .reverse;
                self.visible = false;
                return true;
            },
        }
        return false;
    }

    pub fn draw(self: *const Scroller, dst: blit.Dst, band: *Band, img: *const A.Images, gold_y: u32) void {
        if (!self.visible) return;
        band.clear();
        for (self.ring.x, self.ring.c) |x, c| band.letter(&img.font, c, x);
        const flat = zg.wave.SineSum(f64, 1){ .base = self.text_y, .amp = .{0}, .phase = .{0}, .inc = .{0}, .rounding = .round };
        var sweep = flat.sweep(0);
        band.compose(&sweep, img.gold, gold_y);
        band.draw(dst, 0, CENTRE_Y, @cos(self.twist));
    }
};
