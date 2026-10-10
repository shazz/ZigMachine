// --------------------------------------------------------------------------
// The f32 cart's numbers (replicants_emlyn_f32): the CODEF port's algorithm
// as it was — three.js's projection, a per-bucket search with a divide and a
// floor per bar tried, libm sines — on f32 instead of JavaScript's doubles,
// because the FPU planned for the board is single precision only. It exists
// to measure that FPU; fixed.zig is what the default cart runs.
// --------------------------------------------------------------------------
const balls = @import("balls_f32.zig");
const fill = @import("fill_f32.zig");

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
        fill.build(balls.project(self.rotation, &parts), mode.theta);
    }
};
