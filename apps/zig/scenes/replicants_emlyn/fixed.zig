// --------------------------------------------------------------------------
// The DEFAULT cart's numbers: integers only once the screen is running. The
// cart CPU on the board has no FPU, and the CODEF port's f64 cost it 9 Mc a
// frame in ORIGINAL mode alone; this is what an ST coder would have written
// instead — a sine table, Q16.16 and spans (fill_fixed.zig, balls_fixed.zig).
// Float only builds the lens once, at init. float.zig is the f32 twin.
// --------------------------------------------------------------------------
const trig = @import("zigos").fixtrig;
const balls = @import("balls_fixed.zig");
const fill = @import("fill_fixed.zig");
const rasters = @import("rasters.zig");
const POINTS = @import("balls_f32.zig").POINTS;

pub const Mode = @import("mode.zig").Mode;
pub const Bob = @import("logo.zig").BobFixed;
pub const Curve = @import("curve.zig").CurveFixed;

/// The vectorball group and the raster table it feeds.
pub const Bars = struct {
    rotation: trig.Angle, // group.rotation.x

    pub fn init(self: *Bars) void {
        self.rotation = 0;
        balls.init();
    }

    pub fn turn(self: *Bars) void {
        self.rotation +%= balls.ROT_STEP;
    }

    pub fn build(self: *const Bars, mode: *const Mode) void {
        var parts: [POINTS.len]balls.Part = undefined;
        fill.build(balls.project(self.rotation, &parts), mode.theta, rasters.rows(mode.bordersOpen()));
    }
};
