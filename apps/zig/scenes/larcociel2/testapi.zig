// --------------------------------------------------------------------------
// The headless harness's door into the intro (apps/larcociel2_headless.mjs):
// the trail clock's every word (so the Go tree's native-motion-49.json
// checkpoint and the JS model can both be pinned against the live cart), the
// six projected ball slots, the scrolling slice window and the two raster
// words. Pulled in only when this scene IS the cart (larcociel2.zig checks cart.Cart), so the
// exports never leak into another cart's build.
// --------------------------------------------------------------------------
const scene = @import("../larcociel2.zig");
const textmod = @import("text.zig");

export fn lcTick() u32 {
    return scene.clock.tick;
}

/// 0 counter, 1..3 velocity X/Y/Z, 4..6 acceleration, 7..9 position.
export fn lcField(i: u32) i32 {
    return switch (i) {
        0 => scene.clock.counter,
        1 => scene.clock.velocity[0],
        2 => scene.clock.velocity[1],
        3 => scene.clock.velocity[2],
        4 => scene.clock.acceleration[0],
        5 => scene.clock.acceleration[1],
        6 => scene.clock.acceleration[2],
        7 => scene.clock.position[0],
        8 => scene.clock.position[1],
        9 => scene.clock.position[2],
        else => 0,
    };
}

export fn lcHistory(i: u32, j: u32) i32 {
    return scene.clock.history[i % 66][j % 3];
}

/// The slice window: head, then each slot's atlas glyph (-1 = empty) and
/// column index 0..3.
export fn lcHead() u32 {
    return @intCast(scene.stream.head);
}

export fn lcSliceGlyph(i: u32) i32 {
    return scene.stream.slot(i % textmod.CAP).glyph;
}

export fn lcSliceIndex(i: u32) u32 {
    return scene.stream.slot(i % textmod.CAP).index;
}

/// The projected ball slot: 0 x, 1 y, 2 atlas image, 3 visible.
export fn lcSlot(i: u32, field: u32) i32 {
    const p = scene.slotInfo(i);
    return switch (field) {
        0 => p.x,
        1 => p.y,
        2 => @intCast(p.image),
        else => @intFromBool(p.visible),
    };
}

/// The palette word (entry 0..15) and the raster ramp (index 0..19).
export fn lcPal(i: u32) u32 {
    return scene.static_pal[i % 16];
}

export fn lcRast(i: u32) u32 {
    return scene.rast[i % 20];
}

/// Whether the balls and text are being composited yet (false only at boot).
export fn lcShownLive() u32 {
    return @intFromBool(scene.shown_live);
}
