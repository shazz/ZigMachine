// --------------------------------------------------------------------------
// The headless harness's door into the intro (apps/chonchon_headless.mjs): the
// native motion's every word (so the JS model and the Go tree's scroll-bank
// checkpoints can be pinned against the live cart), the two 3432-byte scroll
// banks, the three music-meter levels, and the cart's own YM register mirror
// plus its refused-write count. Pulled in only when this scene IS the cart
// (chonchon.zig checks cart.Cart), so the exports never leak into another
// cart's build.
// --------------------------------------------------------------------------
const scene = @import("../chonchon.zig");
const ymod = @import("ym.zig");

export fn chTick() u32 {
    return scene.clock.tick;
}

/// 0 tick, 1 logo_phase, 2 logo_y_phase, 3 logo_y, 4 scroll_phase,
/// 5 message_cursor, 6 counter, 7 write0, 8 write1, 9 read0, 10 read1.
export fn chField(i: u32) i32 {
    return switch (i) {
        0 => @intCast(scene.clock.tick),
        1 => scene.clock.logo_phase,
        2 => scene.clock.logo_y_phase,
        3 => scene.clock.logo_y,
        4 => scene.clock.scroll_phase,
        5 => scene.clock.message_cursor,
        6 => scene.clock.counter,
        7 => scene.clock.write[0],
        8 => scene.clock.write[1],
        9 => scene.clock.read[0],
        10 => scene.clock.read[1],
        else => 0,
    };
}

/// One byte of one of the two 3432-byte scroll banks (the Go tree's native
/// scroll-bank checkpoints live byte for byte here).
export fn chRing(bank: u32, i: u32) u32 {
    return scene.clock.ring[bank & 1][i % 3432];
}

export fn chMeters(i: u32) u32 {
    return scene.meters[i % 3];
}

export fn chYmReg(i: u32) u32 {
    return scene.ym.regs[i % 14];
}

export fn chYmRefused() u32 {
    return ymod.refused;
}
