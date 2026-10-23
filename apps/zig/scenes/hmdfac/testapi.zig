// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/hmdfac_headless.mjs): the
// timeline and the 68k wheel state, so the harness can step its own model of
// the machine alongside. Pulled in only when this scene IS the cart.
// --------------------------------------------------------------------------
const app = @import("app.zig");

/// 0 frame, 1 ca, 2 cb, 3 cc, 4 camera, 5 queue sy, 6 queue sx, 7 qi,
/// 8 popped.
export fn hmState(f: u32) i32 {
    return switch (f) {
        0 => @intCast(app.frame),
        1 => app.wheel.ca,
        2 => app.wheel.cb,
        3 => app.wheel.cc,
        4 => @intCast(app.wheel.camera),
        5 => app.wheel.sy,
        6 => app.wheel.sx,
        7 => app.qi,
        8 => @intFromBool(app.popped),
        else => 0,
    };
}

/// The timeline's phase boundaries: 0 boot end, 1 flash end, 2 cube1 end,
/// 3 cube2 end, 4 cube end.
export fn hmPhaseEnd(i: u32) u32 {
    return switch (i) {
        0 => app.BOOT_END,
        1 => app.FLASH_END,
        2 => app.CUBE1_END,
        3 => app.CUBE2_END,
        else => app.CUBE_END,
    };
}
