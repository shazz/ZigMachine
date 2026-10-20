// --------------------------------------------------------------------------
// The headless harness's door into the circle screen (apps/mentalhangover_headless.mjs).
// Pulled in only when this scene IS the cart, so the exports never leak into
// another cart's build.
//
// The state accessors expose the exact words the clock draws (so the Go tree's
// original-circle-clock.csv can be pinned against the live cart), and the glyph
// accessors expose the comptime-parsed outline table (so the harness's own
// parse of glyphs.bin can be held against it).
// --------------------------------------------------------------------------
const app = @import("app.zig");
const A = @import("assets.zig");
const clockmod = @import("clock.zig");

export fn mhOk() u32 {
    return if (app.ok) 1 else 0;
}

export fn mhTick() u32 {
    return app.clock.tick;
}

export fn mhPhase() u32 {
    return app.clock.phase;
}

export fn mhLocal() i32 {
    return app.clock.local;
}

export fn mhAngle() u32 {
    return app.clock.angle;
}

export fn mhCursor() u32 {
    return app.clock.cursor;
}

export fn mhPause() i32 {
    return app.clock.pause;
}

export fn mhRadiusStep() u32 {
    return app.clock.radius_step;
}

export fn mhFactor() u32 {
    return app.clock.factor;
}

export fn mhProfileStep() u32 {
    return app.clock.profile_step;
}

export fn mhRadiusPhase() u32 {
    return app.clock.radius_phase;
}

export fn mhProfilePhase() u32 {
    return app.clock.profile_phase;
}

export fn mhBase() i32 {
    return app.clock.base;
}

export fn mhRow(i: u32) i32 {
    return app.clock.rows[@as(usize, i) % clockmod.ROWS];
}

export fn mhLetter(i: u32) u32 {
    return app.clock.letters[@as(usize, i) % clockmod.SLOTS];
}

export fn mhLevel() u32 {
    return app.clock.level;
}

export fn mhActive() u32 {
    return if (app.clock.active) 1 else 0;
}

export fn mhDone() u32 {
    return if (app.clock.done) 1 else 0;
}

// --- the compiled assets ---------------------------------------------------
export fn mhTextLen() u32 {
    return @intCast(A.TEXT.len);
}

export fn mhTextByte(i: u32) u32 {
    return A.TEXT[@as(usize, i) % A.TEXT.len];
}

export fn mhGlyphCount() u32 {
    return @intCast(A.GLYPH_COUNT);
}

/// 0 = contour count, 1 = contour 0 point count, 2 = contour 1 point count.
export fn mhGlyphInfo(ch: u32, field: u32) u32 {
    if (ch < 32 or ch > 90) return 0;
    const g: usize = ch - 32;
    const gs: usize = A.TABLE.glyph_start[g];
    const gc: u32 = A.TABLE.glyph_count[g];
    return switch (field) {
        0 => gc,
        1 => if (gc > 0) @as(u32, A.TABLE.contour_count[gs]) else 0,
        2 => if (gc > 1) @as(u32, A.TABLE.contour_count[gs + 1]) else 0,
        else => 0,
    };
}

/// angle<<8 | row, or -1 past the contour.
export fn mhGlyphPoint(ch: u32, contour: u32, i: u32) i32 {
    if (ch < 32 or ch > 90) return -1;
    const g: usize = ch - 32;
    if (contour >= @as(u32, A.TABLE.glyph_count[g])) return -1;
    const k: usize = @as(usize, A.TABLE.glyph_start[g]) + @as(usize, contour);
    if (i >= @as(u32, A.TABLE.contour_count[k])) return -1;
    const p = A.TABLE.points[@as(usize, A.TABLE.contour_start[k]) + @as(usize, i)];
    return @as(i32, p.angle) << 8 | @as(i32, p.row);
}
