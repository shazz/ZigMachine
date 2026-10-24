// --------------------------------------------------------------------------
// ANIMA -- a new multipart demo written for the ZigMachine (2026-10-23), in
// the spirit of the Atari ST / Amiga scenes: no port, no original to follow.
//
// anima/app.zig carries the screen notes (timeline, budget, machine features,
// assets and music); each part lives in its own file beside it.
//
// One overscan plane, every border earned by the flicker trick; Escape leaves.
// --------------------------------------------------------------------------
const app = @import("anima/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("anima/testapi.zig");
    }
}
