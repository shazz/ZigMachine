// --------------------------------------------------------------------------
// PHENOMENA — "ENIGMA" (1991) intro.
//
// Ported from the Go/Ebitengine remake github.com/olivierh59500/phenomena-dna-scroll-intro
// (vendored at prototypes/go-phenomena/).  phenomena/app.zig carries the port
// notes, the 640x480 -> 320x240 halving and the music evidence; dna.zig has the
// filmstrip maths; rasters.zig has the two real per-scanline registers.
//
// One 400x280 overscan plane, sixteen colours, twelve states. Space/Enter
// starts the outro, Escape/Back leaves.
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
