// --------------------------------------------------------------------------
// RACER: the stuck-car rescue (R82 32X look, LOOK.md item 4). ARCADE only: an AI car is put back on the racing
// line one segment on, stopped (the hard crash's placement, wall.putBack), as the 32X puts a car back on its path,
// when it has had three or four wheels off the asphalt for STUCK_TICKS in a row, or has not gained a segment of
// track in STILL_TICKS (pinned on a wall, lost under the crossing's deck). Since the bug pass' pushes (pushes.zig)
// a car can be shoved off the 32X courses' narrow roads, and the AI's PID never finds the way back from there.
// CLASSIC is freds72's and never rescues (its Lua CRCs stay). Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const arcade = @import("arcade.zig");
const car = @import("car.zig");
const fix = @import("fix.zig");
const wall = @import("wall.zig");

pub const STUCK_TICKS: u16 = 90; // 3 s of the 30 Hz tick off the asphalt
pub const STILL_TICKS: u16 = 180; // 6 s without a segment of progress
pub var break_rescue = false; // --break rescue: never rescued (rescue_test.zig; key % in the cart, the A/B)

/// A car's watch: ticks off the asphalt, ticks since it last gained a segment, and the track position it gained it at.
pub const Watch = struct { off: u16 = 0, still: u16 = 0, mark: i32 = 0 };

/// One tick of car `c`'s watch (the race keeps one a car). True when the car was put back.
pub fn tick(c: *car.Car, w: *Watch) bool {
    if (c.model != .arcade) return false;
    w.off = if (c.eng.off == arcade.OFF_FULL) w.off +| 1 else 0;
    if (c.track.u -% w.mark >= fix.ONE) {
        w.mark = c.track.u;
        w.still = 0;
    } else w.still +|= 1;
    if ((w.off < STUCK_TICKS and w.still < STILL_TICKS) or break_rescue) return false;
    wall.putBack(c, c.track.segment + 1); // its engine reset too: off the asphalt no more
    w.* = .{ .mark = c.track.u };
    return true;
}
