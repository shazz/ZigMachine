// --------------------------------------------------------------------------
// The f32 numbers (F in the cart, and the side replicants_emlyn_f32 boots on):
// the CODEF port's algorithm as it was — three.js's projection, a per-bucket
// search with a divide and a floor per bar tried, libm sines — on f32 instead
// of JavaScript's doubles, because the board's FPU is single precision only.
// This is the one INTENTIONAL float-per-frame path in the screen: it exists to
// measure that FPU against fixed.zig, which is what the cart boots on.
// --------------------------------------------------------------------------
const balls = @import("balls_f32.zig");
const fill = @import("fill_f32.zig");
const rasters = @import("rasters.zig");

pub const Mode = @import("mode_f32.zig").Mode;
pub const Bob = @import("logo.zig").BobF32;
pub const Curve = @import("curve.zig").CurveF32;

/// The vectorball group and the raster table it feeds.
pub const Bars = struct {
    rotation: f32, // group.rotation.x, a float accumulator as the remake's

    pub fn init(self: *Bars) void {
        self.rotation = 0;
        balls.init();
    }

    pub fn turn(self: *Bars) void {
        self.rotation += balls.ROT_STEP;
    }

    pub fn build(self: *const Bars, mode: *const Mode) void {
        var parts: [balls.POINTS.len]balls.Particle = undefined;
        fill.build(balls.project(self.rotation, &parts), mode.theta, rasters.rows(mode.bordersOpen()));
    }
};
