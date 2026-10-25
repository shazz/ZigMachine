// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/gnomes_headless.mjs): the
// frame state, so the harness can step its own model of the ORIGINAL alongside.
// Pulled in only when this scene IS the cart (gnomes.zig checks cart.Cart).
// --------------------------------------------------------------------------
const app = @import("app.zig");
const text = @import("text.zig");
const A = @import("assets.zig");

/// 0 frame, 1 tty ptr, 2 tty col, 3 tty row, 4 tty pause, 5 tty page,
/// 6 the scroller's first column, 7 the logo x of line 0.
export fn gnState(f: u32) i32 {
    return switch (f) {
        0 => @intCast(app.frame),
        1 => @intCast(app.tty.ptr),
        2 => app.tty.col,
        3 => app.tty.row,
        4 => app.tty.pause,
        5 => app.tty.page,
        6 => app.scroller.firstColumn(app.frame),
        7 => app.logo.x(app.frame, 0),
        else => 0,
    };
}

export fn gnBigTextLen() u32 {
    return text.BIG_TEXT.len;
}

export fn gnTtyLen() u32 {
    return A.TTY.len;
}
