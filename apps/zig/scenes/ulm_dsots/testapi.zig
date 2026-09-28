// --------------------------------------------------------------------------
// The headless harness's window into the menu (apps/ulm_dsots_headless.mjs):
// dsotsVal(i) reads the state the remake's trace records, so a run here is
// compared with the remake's own in Chrome step by step. Exported only when
// this scene is the cart being built.
// --------------------------------------------------------------------------
const Demo = @import("../ulm_dsots.zig").Demo;

var demo: ?*Demo = null;

pub fn bind(d: *Demo) void {
    demo = d;
}

/// 0 x, 1 y, 2 vx, 3 vy, 4 view x, 5 view y, 6 parallax offset, 7 sprite,
/// 8 facing left, 9 steps run, 10 ready (the zg.mem views were built).
pub fn val(i: u32) callconv(.c) f64 {
    const d = demo orelse return -1;
    const g = &d.griffin;
    return switch (i) {
        0 => g.x,
        1 => g.y,
        2 => g.vx,
        3 => g.vy,
        4 => d.view.x,
        5 => d.view.y,
        6 => @floatFromInt(d.parallax.offset),
        7 => @floatFromInt(g.sprite()),
        8 => @floatFromInt(@intFromBool(g.flip)),
        9 => @floatFromInt(d.steps),
        10 => @floatFromInt(@intFromBool(d.ready)),
        else => -1,
    };
}
