// --------------------------------------------------------------------------
// THE REPLICANTS — "INTERNATIONAL KARATE PLUS" (IK+) cracktro.
//
// Ported from the Go/Ebitengine re-creation github.com/olivierh59500/go-dom-intro
// (vendored at prototypes/go-dom-intro/); ikplus/app.zig carries the port notes,
// the halving maths and the music match, and ikplus/rasters.zig explains why the
// two rast*.png are real per-scanline colour registers here and not sprites.
//
// One overscan plane, six palette entries, a scrolltext in four sizes, the logo
// outline and eight stars. F1/F2 step the scroll speed; Escape leaves.
// --------------------------------------------------------------------------
const app = @import("ikplus/app.zig");

pub const Demo = app.Demo;

// The headless harness's exports exist only when this scene IS the registered
// cart, so they never leak into another cart's build.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("ikplus/testapi.zig");
    }
}
