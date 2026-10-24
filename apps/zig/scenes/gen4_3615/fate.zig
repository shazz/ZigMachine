// --------------------------------------------------------------------------
// The "THE FATE" logo (screen.js dancingFate, 242-338): 113 two-row slices of
// the_fate.png, each placed on a 3D curve (y, z) that one of six waveforms
// computes, sorted by z, and drawn with a perspective x, width and y. It lives
// under the scroller: only the glyphs show it (see scroller.zig).
//
// Every constant is screen.js's own and ~~ is truncation toward zero. The JS
// does its maths in doubles (fate_curve.zig keeps that as the reference); the
// cart does it in fixed point (fate_fix.zig, fate_place.zig): no float per
// frame on ZIGGY. A slice may land 1 px off the f64 placement where the f64
// value sits right on an integer (fate_test.zig bounds and counts it).
// --------------------------------------------------------------------------
const fate_draw = @import("fate_draw.zig");
const fix = @import("fate_place.zig");
const C = @import("fate_curve.zig");

pub const SLICES = C.SLICES;
pub const Slice = C.Slice;
const ff = @import("fate_fix.zig");

pub const Fate = struct {
    shown: bool,
    /// shown when step() last ran: ^CLogoFate; lands after it (in scroller()),
    /// so on that frame the JS has no slices to draw yet, and neither does this.
    placed: bool,
    wave: u8,
    half: u64, // angle ctr / 2, 2^64 = one turn
    third: u64, // angle ctr / 1.5
    slices: [SLICES]Slice, // in draw order: z ascending, stable

    pub fn init(self: *Fate) void {
        self.shown = false;
        self.placed = false;
        self.wave = 0;
        self.half = 0;
        self.third = 0;
        self.slices = undefined;
    }

    /// ^CLogoFate; — the logo appears on the first waveform.
    pub fn logoFate(self: *Fate) void {
        self.shown = true;
        self.wave = 0;
    }

    /// ^CLogoWaveform; — the next of the six curves.
    pub fn logoWaveform(self: *Fate) void {
        self.wave += 1;
        if (self.wave > 5) self.wave = 0;
    }

    /// dancingFate()'s maths for this frame; then fateCtr advances.
    pub fn step(self: *Fate) void {
        self.placed = self.shown;
        if (!self.shown) return;
        fix.place(self, &self.slices);
        self.half +%= ff.HALF_STEP;
        self.third +%= ff.THIRD_STEP;
    }

    pub const Rows = fate_draw.Rows;

    /// Draw the slices into `bg`, a `bg_w`-wide buffer whose (0, 0) is ST
    /// pixel (ox, oy), and say which rows were painted. ST pixel (X, Y) is
    /// canvas pixel (2X, 2Y), so a slice shows only on its even canvas rows
    /// and columns.
    pub fn draw(self: *const Fate, bg: []u8, bg_w: usize, ox: i32, oy: i32) Rows {
        if (!self.placed) return .{ .lo = 0, .hi = 0 };
        return fate_draw.draw(&self.slices, bg, bg_w, ox, oy);
    }
};
