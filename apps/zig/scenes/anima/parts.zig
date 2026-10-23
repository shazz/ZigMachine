// --------------------------------------------------------------------------
// The parts, in timeline order (timeline.zig). Each has `enter` (it takes over
// the plane, the palette and the raster's slots) and `draw` (one frame at tick
// t, with fresh = just entered and advance = the tick moved since last frame).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const T = @import("timeline.zig");
const old = @import("old.zig");
const gag = @import("gag.zig");
const tunnel = @import("tunnel.zig");

pub fn enter(p: T.Part, fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32, jumped: bool) void {
    switch (p) {
        .old => old.enter(fb, bl),
        .gag => gag.enter(fb, bl, jumped),
        .tunnel => tunnel.enter(fb, bl),
        else => tunnel.enter(fb, bl),
    }
    _ = t;
}

pub fn draw(p: T.Part, fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32, fresh: bool, advance: bool) void {
    switch (p) {
        .old => old.draw(fb, bl, t, fresh, advance),
        .gag => gag.draw(fb, bl, t - T.GAG, advance),
        .tunnel => tunnel.draw(fb, t - T.TUNNEL),
        else => tunnel.draw(fb, t - T.TUNNEL),
    }
}
