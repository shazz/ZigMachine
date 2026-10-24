// --------------------------------------------------------------------------
// The parts, in timeline order (timeline.zig). Each has `enter` (it takes over
// the plane, the palette and the raster's slots) and `draw` (one frame at its
// local tick). fresh = just entered; advance = the tick moved since the last
// frame; jumped = entered by a timeline jump, not by playing into it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const T = @import("timeline.zig");
const old = @import("old.zig");
const gag = @import("gag.zig");
const tunnel = @import("tunnel.zig");
const roto = @import("roto.zig");
const knot = @import("knot.zig");
const end = @import("end.zig");

pub fn enter(p: T.Part, fb: *zg.LogicalFB, bl: *zg.Blitter, jumped: bool) void {
    switch (p) {
        .old => old.enter(fb, bl),
        .gag => gag.enter(fb, bl, jumped),
        .tunnel => tunnel.enter(fb, bl),
        .roto => roto.enter(fb, bl),
        .torus => knot.enter(fb, bl),
        .end => end.enter(fb, bl),
    }
}

pub fn draw(p: T.Part, fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32, fresh: bool, advance: bool) void {
    const lt = t - T.partStart(p);
    switch (p) {
        .old => old.draw(fb, bl, t, fresh, advance),
        .gag => gag.draw(fb, bl, lt, advance),
        .tunnel => tunnel.draw(fb, lt),
        .roto => roto.draw(fb, lt),
        .torus => knot.draw(fb, bl, lt),
        .end => end.draw(fb, bl, lt),
    }
}
