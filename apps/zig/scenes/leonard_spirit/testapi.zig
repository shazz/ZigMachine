// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/leonard_spirit_headless.mjs):
// the record's count, the path phase, the scroller tick and where the plane
// is, so the harness can step its own model alongside. Pulled in only when
// this scene IS the cart.
// --------------------------------------------------------------------------
const scene = @import("../leonard_spirit.zig");

/// 0 sprites drawn a frame, 1 path frame (0..359), 2 scroller tick,
/// 3 strip width, 4 scroller lap in ticks.
export fn lsState(k: u32) u32 {
    return switch (k) {
        0 => scene.NB,
        1 => scene.frame,
        2 => scene.tick,
        3 => scene.Strip.W,
        else => scene.Strip.TEXT_W / 2,
    };
}

export fn lsPlane() u32 {
    return @intFromPtr(scene.plane);
}

export fn lsStrip() u32 {
    return @intFromPtr(&scene.Strip.pixels);
}
