// --------------------------------------------------------------------------
// The headless harness's door into LOCKBUSTER 3 (apps/lockbuster3_headless.mjs):
// the tick, the FRONT 320x240 index buffer (the Go's g.buffers[g.front], before
// the text bitplane and palette), the panel/scroll clocks, the letter words and
// the meter volumes. Pulled in only when this scene IS the registered cart.
// --------------------------------------------------------------------------
const scene = @import("app.zig");

export fn lb3Tick() u32 {
    return scene.tick;
}

export fn lb3Ready() u32 {
    return @intFromBool(scene.ready);
}

export fn lb3Front() u32 {
    if (!scene.ready) return 0;
    return @intFromPtr(scene.buffers[scene.front].ptr);
}

export fn lb3FrontIndex() u32 {
    return scene.front;
}

/// 0 tick, 1 front, 2 panel step, 3 panel offset, 4 panel cursor,
/// 5 panel cycle, 6 panel direction, 7 panel mode, 8 panel base,
/// 9 panel draw, 10 panel commit, 11 pose cell, 12 pose bank, 13 pose frame,
/// 14 remaining, 15 glyph, 16 column, 17 font row, 18 changes,
/// 19..21 meter volumes A/B/C.
export fn lb3Field(i: u32) i32 {
    return switch (i) {
        0 => @intCast(scene.tick),
        1 => scene.front,
        2 => scene.panel.step_n,
        3 => scene.panel.offset,
        4 => scene.panel.cursor,
        5 => scene.panel.cycle,
        6 => scene.panel.direction,
        7 => scene.panel.mode,
        8 => scene.panel.base,
        9 => @intFromBool(scene.panel.draw),
        10 => @intFromBool(scene.panel.commit),
        11 => scene.panel.pose.cell,
        12 => scene.panel.pose.bank,
        13 => scene.panel.pose.frame,
        14 => @intCast(scene.scroll.remaining),
        15 => @intCast(scene.scroll.glyph),
        16 => @intCast(scene.scroll.column),
        17 => @intCast(scene.scroll.row),
        18 => @intCast(scene.scroll.changes),
        19 => scene.volumes[0],
        20 => scene.volumes[1],
        21 => scene.volumes[2],
        else => 0,
    };
}

/// One unsigned 16-bit word of the Go's source.Letter.Words[which][word].
export fn lb3Letter(which: u32, word: u32) u32 {
    return @as(u16, @bitCast(scene.letters[which % 3][word % 8]));
}

/// The restore rectangle the Go stored for history[target][which].
export fn lb3History(target: u32, which: u32) u32 {
    const r = scene.history[target & 1][which % 3];
    return (@as(u32, @bitCast(r.x)) << 16) | @as(u16, @truncate(@as(u32, @bitCast(r.y))));
}

export fn lb3PaletteWord(i: u32) u32 {
    return scene.palette_words[i % 16];
}

export fn lb3RasterWord(i: u32) u32 {
    return scene.raster_words[i % scene.RASTER_LINES];
}
