// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/hmdfac_headless.mjs): the
// timeline and the 68k wheel state, so the harness can step its own model of
// the machine alongside. Pulled in only when this scene IS the cart.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const run = @import("cube_run.zig");

/// 0 frame, 1 ca, 2 cb, 3 cc, 4 camera, 5 queue x, 6 queue y, 7 qi,
/// 8 popped, 9 the opening's screen offset in lines.
export fn hmState(f: u32) i32 {
    return switch (f) {
        0 => @intCast(app.frame),
        1 => run.wheel.ca,
        2 => run.wheel.cb,
        3 => run.wheel.cc,
        4 => @intCast(run.wheel.camera),
        5 => run.wheel.qx,
        6 => run.wheel.qy,
        7 => run.qi,
        8 => @intFromBool(app.popped),
        9 => @intCast(app.bob_off),
        else => 0,
    };
}

/// The timeline's phase boundaries: 0 opening end, 1 flash end, 2 hold end,
/// 3 cube1 end, 4 cube2 end, 5 cube end, 6 scroller start.
export fn hmPhaseEnd(i: u32) u32 {
    return switch (i) {
        0 => app.OPEN_END,
        1 => app.FLASH_END,
        2 => app.HOLD_END,
        3 => app.CUBE1_END,
        4 => app.CUBE2_END,
        5 => app.CUBE_END,
        else => app.P4_START,
    };
}
