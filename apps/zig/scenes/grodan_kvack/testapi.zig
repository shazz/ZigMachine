// --------------------------------------------------------------------------
// The headless harness's door into the demo (apps/grodan_kvack_headless.mjs).
// It reads back the words compose() draws from -- the tick count, the four
// scroll positions and the Go's own animation counters -- so a pixel check that
// ever drifts can say WHERE (which layer) it drifted, not just that it did.
// Imported only when this scene IS the cart (grodan_kvack.zig checks cart.Cart),
// so the exports never leak into another cart's build (kickoff2's pattern).
// --------------------------------------------------------------------------
const scene = @import("../grodan_kvack.zig");

/// The 60 Hz tick count (one step of the Go's Update()).
export fn gkTick() u32 {
    return scene.tick;
}

/// Scroll position by layer: 0 = mainText, 1 = vertText, 2 = smallText1,
/// 3 = smallText2 (the Go's ScreenWidth font-px units).
export fn gkScroll(layer: u32) i32 {
    const s = &scene.state;
    return switch (layer) {
        0 => s.s1.scroll,
        1 => s.s2.scroll,
        2 => s.s3.scroll,
        else => s.s4.scroll,
    };
}

/// The state words by selector, for the harness's sanity assertions:
/// 0 moveY, 1 moveX, 2 X, 3 Y, 4 bgcount, 5 ychange (tenths), 6 swing, 7 swingy.
export fn gkState(sel: u32) i32 {
    const s = &scene.state;
    return switch (sel) {
        0 => s.moveY,
        1 => s.moveX,
        2 => s.X,
        3 => s.Y,
        4 => s.bgcount,
        5 => s.ychange10,
        6 => @bitCast(s.swing),
        else => @bitCast(s.swingy),
    };
}
