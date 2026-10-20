// --------------------------------------------------------------------------
// The headless harness's door into CHONCHON 2 (apps/chonchon2_headless.mjs).
// Pulled in only when this scene IS the registered cart (chonchon2.zig checks
// cart.Cart), so the exports never leak into another cart's build.
//
// The harness compares these live words against an independent JS model every
// frame: the clock counters, both poses, the entire 32000-byte screen, the
// glyph and ribbon, the two 200-line rasters, and the cart's own YM mirror.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const rastermod = @import("raster.zig");

fn fnv(bytes: []const u8) u32 {
    var h: u32 = 0x811c9dc5;
    for (bytes) |b| h = (h ^ b) *% 0x01000193;
    return h;
}

export fn c2Tick() u32 {
    return app.clock.tick;
}

/// 0 tick, 1 profile_cursor, 2 message_cursor, 3 glyph_column, 4 glyph_counter,
/// 5 scroll_y, 6 old_y, 7 sprite_cursor 0, 8 sprite_cursor 1,
/// 9 caption_cursor, 10 caption_hold, 11 caption_wait, 12 caption_shift.
export fn c2Field(i: u32) i32 {
    return switch (i) {
        0 => @intCast(app.clock.tick),
        1 => @intCast(app.clock.profile_cursor),
        2 => @intCast(app.clock.message_cursor),
        3 => @intCast(app.clock.glyph_column),
        4 => app.clock.glyph_counter,
        5 => app.clock.scroll_y,
        6 => app.clock.old_y,
        7 => @intCast(app.clock.sprite_cursor[0]),
        8 => @intCast(app.clock.sprite_cursor[1]),
        9 => @intCast(app.clock.caption_cursor),
        10 => app.clock.caption_hold,
        11 => app.clock.caption_wait,
        12 => @intCast(app.clock.caption_shift),
        else => 0,
    };
}

/// 0 x, 1 y, 2 half.
export fn c2Pose(i: u32, field: u32) i32 {
    const p = app.clock.poses[i % 2];
    return switch (field) {
        0 => p.x,
        1 => p.y,
        else => @intFromBool(p.half),
    };
}

export fn c2ScreenByte(i: u32) u32 {
    return app.clock.screen[i % app.clock.screen.len];
}

export fn c2ScreenHash() u32 {
    return fnv(app.clock.screen[0..]);
}

export fn c2GlyphByte(i: u32) u32 {
    return app.clock.glyph[i % app.clock.glyph.len];
}

export fn c2GlyphHash() u32 {
    return fnv(app.clock.glyph[0..]);
}

export fn c2RibbonByte(row: u32, col: u32) u32 {
    return app.clock.ribbon[row % 23][col % 320];
}

export fn c2RibbonHash() u32 {
    var h: u32 = 0x811c9dc5;
    for (app.clock.ribbon) |line| {
        for (line) |b| h = (h ^ b) *% 0x01000193;
    }
    return h;
}

/// The two raster tables the HBL feeds entries 0 and 2, as packed RGBA.
export fn c2Bg(i: u32) u32 {
    return rastermod.bg[i % 200];
}

export fn c2Fg(i: u32) u32 {
    return rastermod.fg[i % 200];
}

export fn c2Pal(i: u32) u32 {
    return app.static_pal[i % 16];
}

export fn c2YmReg(i: u32) u32 {
    return app.ym.regs[i % 14];
}

export fn c2YmTrack() u32 {
    return @intCast(app.track);
}

export fn c2YmFrames() u32 {
    return app.ym.frames;
}

export fn c2YmApplied() u32 {
    return app.ym.applied;
}

export fn c2Meters(i: u32) u32 {
    return app.meters[i % 3];
}

/// Whether the first Update has drawn (false only at boot).
export fn c2Drawn() u32 {
    return @intFromBool(app.clock.tick != 0);
}
