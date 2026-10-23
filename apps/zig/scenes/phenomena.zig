// --------------------------------------------------------------------------
// PHENOMENA intro (Amiga): "THIS IS IMPOSSIBLE!" -- code Photon, rasta music
// Firefox, graphics Terminator. Ported from the CODEF remake at
// wab.com/?screen=560 (prototypes/codef/560/screen.js); phenomena/app.zig
// carries the port notes, geom.zig the 640x480 -> 640x240 mapping.
//
// One 800x280 medium overscan plane. Escape/Back leaves.
// --------------------------------------------------------------------------
const app = @import("phenomena/app.zig");

pub const Demo = app.Demo;

// The headless harness's exports exist only when this scene IS the registered
// cart, so they never leak into another cart's build.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("phenomena/testapi.zig");
    }
}
