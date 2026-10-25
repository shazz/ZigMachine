// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/leonard_spirit_headless.mjs):
// the record's count, the show's counters and where the plane is, so the
// harness can step its own model alongside. Pulled in only when this scene
// IS the cart.
// --------------------------------------------------------------------------
const scene = @import("../leonard_spirit.zig");

/// 0 sprites drawn a frame, 1 ball frame (0..359), 2 scroller tick,
/// 3 strip width, 4 scroller lap in ticks, 5 show frame t, 6 scroll phase
/// (Q16), 7 the borders the HBL opens (bit 0 sides, 1 bottom, 2 top).
export fn lsState(k: u32) u32 {
    return switch (k) {
        0 => scene.NB,
        1 => scene.frame,
        2 => scene.tick,
        3 => scene.Strip.W,
        4 => scene.Strip.TEXT_W / 2,
        5 => scene.t,
        6 => scene.phase,
        else => scene.open_mask,
    };
}

export fn lsPlane() u32 {
    return @intFromPtr(scene.plane);
}
