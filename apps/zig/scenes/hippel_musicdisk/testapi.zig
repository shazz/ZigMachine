// --------------------------------------------------------------------------
// The headless harness's door (apps/hippel_musicdisk_headless.mjs). Pulled in
// only when this scene IS the cart, so the exports never leak elsewhere.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const C = @import("amiga_copper.zig");
const tunes = @import("tunes.zig");

export fn hipOk() u32 {
    return @intFromBool(app.ok);
}

/// The original's frame count (50 Hz): the copper scroll and the bar rotation.
export fn hipPhase() u32 {
    return app.phase;
}

/// The key ('a' = 0) whose tune was last requested.
export fn hipTune() u32 {
    return tunes.current;
}

/// Words in the rebuilt Amiga copper list, and word i of it.
export fn hipCopperLen() u32 {
    return C.LEN;
}
export fn hipCopperWord(i: u32) u32 {
    return if (i < C.LEN) C.AMIGA_LIST[i] else 0;
}

/// Plane 0's COLOR00 for physical row r (the copper table).
export fn hipBarAt(r: u32) u32 {
    return if (r < app.bars[0].len) app.bars[0][r] else 0;
}

/// Plane 1's line palette: colour of column c on visible line n, and how many
/// entries the line writes (0 on a line with no text pixel).
export fn hipTextAt(n: u32, c: u32) u32 {
    return if (n < 200 and c < C.COLUMNS) app.text_pal.colours[n][c] else 0;
}
export fn hipTextUsed(n: u32) u32 {
    return if (n < 200) app.text_pal.used[n] else 0;
}
