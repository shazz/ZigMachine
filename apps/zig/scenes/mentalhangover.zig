// --------------------------------------------------------------------------
// MENTAL HANGOVER -- the circular outline-text-over-mountain greeting from
// Olivier Huet's Go/Ebitengine re-creation of the Amiga demo (Scoopex).
//
// mentalhangover/app.zig carries the screen notes, the scale, the ST colour
// snap, the 3341-step clock and the soundtrack; mentalhangover/clock.zig is
// the production's ByteWindow transport and TablePolar projection, checked
// against its own native CPU fixture; mentalhangover/render.zig is the
// even-odd contour fill and the REAL per-scanline copper.
//
// One overscan plane, four palette entries, Escape leaves.
// --------------------------------------------------------------------------
const app = @import("mentalhangover/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("mentalhangover/testapi.zig");
    }
}
