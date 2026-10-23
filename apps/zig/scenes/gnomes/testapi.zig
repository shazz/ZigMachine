// --------------------------------------------------------------------------
// The headless harness's door into the cart (apps/gnomes_headless.mjs): the
// frame state, so the harness can step its own model alongside. Pulled in only
// when this scene IS the cart (gnomes.zig checks cart.Cart).
// --------------------------------------------------------------------------
const app = @import("app.zig");
const text = @import("text.zig");

/// 0 frame, 1 rain_rot, 2 band_first, 3 band_pos, 4 strip_ptr, 5 strip_col,
/// 6 strip_row, 7 strip_pause.
export fn gnState(f: u32) i32 {
    return switch (f) {
        0 => @intCast(app.frame),
        1 => app.rain_rot,
        2 => @intCast(app.band_first),
        3 => app.band_pos,
        4 => @intCast(app.tty.ptr),
        5 => app.tty.col,
        6 => app.tty.row,
        7 => app.tty.pause,
        else => 0,
    };
}

export fn gnBigTextLen() u32 {
    return text.BIG_TEXT.len;
}

export fn gnCyanTextLen() u32 {
    return text.CYAN_TEXT.len;
}
