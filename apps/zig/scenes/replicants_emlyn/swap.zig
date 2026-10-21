// --------------------------------------------------------------------------
// F: the screen's state carried from one number system to the other, so the
// switch is a change of maths, not a jump. Positions, letters and directions
// are integers in both and copy as they are; the angles go between a fixtrig
// Angle (a whole turn = 2^32) and f32 radians, and the bend between a frame
// count 0..20 and 0..1.
//
// Float here runs once per keypress, never per frame, so the fixed-point side
// stays integer-only between presses (the board's cart CPU may have no FPU).
// From the boot state every angle is 0, so a cart switched before its first
// frame is the f32 cart exactly (the headless harness proves it).
// --------------------------------------------------------------------------
const std = @import("std");
const trig = @import("zigos").fixtrig;
const Motion = @import("motion.zig").Motion;
const BEND_FRAMES = @import("mode.zig").BEND_FRAMES;

pub const Fixed = Motion(@import("fixed.zig"));
pub const Float = Motion(@import("float.zig"));

const radians = trig.toRadians;
const angle = trig.fromRadians;

pub fn toFloat(src: *const Fixed, dst: *Float) void {
    copyShared(src, dst);
    dst.bars.rotation = radians(src.bars.rotation);
    dst.logo.bob.posy = radians(src.logo.bob.posy);
    for (&dst.scroller.curve.phase, src.scroller.curve.phase) |*d, s| d.* = radians(s);
    dst.mode.theta = radians(src.mode.theta);
    dst.mode.bend = @as(f32, @floatFromInt(src.mode.bend)) / BEND_FRAMES;
    dst.mode.sw = src.mode.sw;
}

pub fn toFixed(src: *const Float, dst: *Fixed) void {
    copyShared(src, dst);
    dst.bars.rotation = angle(src.bars.rotation);
    dst.logo.bob.posy = angle(src.logo.bob.posy);
    for (&dst.scroller.curve.phase, src.scroller.curve.phase) |*d, s| d.* = angle(s);
    dst.mode.theta = angle(src.mode.theta);
    dst.mode.bend = @intFromFloat(std.math.clamp(@round(src.mode.bend * BEND_FRAMES), 0, BEND_FRAMES));
    dst.mode.sw = src.mode.sw;
}

/// The integer state, the same in both: the logo's sweep, the scroll ring.
fn copyShared(src: anytype, dst: anytype) void {
    dst.logo.posx = src.logo.posx;
    dst.logo.sweeping_left = src.logo.sweeping_left;
    dst.scroller.posx = src.scroller.posx;
    dst.scroller.ltr = src.scroller.ltr;
    dst.scroller.offset = src.scroller.offset;
}
