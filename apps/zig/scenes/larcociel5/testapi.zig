// --------------------------------------------------------------------------
// The headless harness's door into the intro (apps/larcociel5_headless.mjs):
// the ribbon clock's every word (so the Go tree's native-ribbon-149.json
// checkpoint and the JS model can both be pinned against the live cart), the
// three Batman meter levels, and the YM registers they read on the last tick.
// Pulled in only when this scene IS the cart (larcociel5.zig
// checks cart.Cart), so the exports never leak into another cart's build.
// --------------------------------------------------------------------------
const scene = @import("../larcociel5.zig");

export fn lcTick() u32 {
    return scene.clock.tick;
}

/// 0 tick, 1 counter, 2 hold, 3 x, 4 y, 5 vx, 6 vy, 7 ax, 8 ay.
export fn lcField(i: u32) i32 {
    return switch (i) {
        0 => @intCast(scene.clock.tick),
        1 => scene.clock.counter,
        2 => scene.clock.hold,
        3 => scene.clock.x,
        4 => scene.clock.y,
        5 => scene.clock.vx,
        6 => scene.clock.vy,
        7 => scene.clock.ax,
        8 => scene.clock.ay,
        else => 0,
    };
}

export fn lcHistory(i: u32) i32 {
    return scene.clock.history[i % 50];
}

export fn lcMeters(i: u32) u32 {
    return scene.meters[i % 3];
}

export fn lcYmReg(i: u32) u32 {
    return scene.ym_regs[i % 14];
}

/// The colour bank at (row, entry), for the harness's raster check.
export fn lcBank(row: u32, i: u32) u32 {
    return scene.bank.colors[(row % 100) * 16 + (i % 16)];
}

/// Whether the bats are being composited yet (false only for the boot frame).
export fn lcShownBats() u32 {
    return @intFromBool(scene.shown_bats);
}
