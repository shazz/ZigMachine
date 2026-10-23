// --------------------------------------------------------------------------
// The headless harness's door into the cracktro (apps/ikplus_headless.mjs): the
// scrolltext as the cart compiled it (so the harness's own parse of game.go can
// be held against it), the scroll state, and the eight stars. Pulled in only
// when this scene IS the cart (ikplus.zig checks cart.Cart).
// --------------------------------------------------------------------------
const app = @import("app.zig");
const text = @import("text.zig");

export fn ikOk() u32 {
    return if (app.ok) 1 else 0;
}

/// scrollText1.offset, 1x, Q16.16 (fits i32: about -640..320 pixels).
export fn ikOff() i32 {
    return @intCast(app.off1);
}

/// game.go's actSize.
export fn ikSize() u32 {
    return app.act_size;
}

/// Index into the spinc list {0.25, 0.5, 1, 2, 3, 4}.
export fn ikSpinc() u32 {
    return app.spinc;
}

/// The Eliminator subtune F1..F5 last picked (1-based).
export fn ikTune() u32 {
    return app.tune;
}

export fn ikPosY() u32 {
    return app.pos_y;
}

export fn ikPosY2() u32 {
    return app.pos_y2;
}

export fn ikSeed() u32 {
    return app.STAR_SEED;
}

/// One star's field: 0 x, 1 y, 2 div, 3 phase (Q16.16 frames).
export fn ikStar(i: u32, f: u32) i32 {
    const st = app.field.s[i % app.field.s.len];
    return switch (f) {
        0 => st.x,
        1 => st.y,
        2 => st.div,
        3 => @intCast(st.phase),
        else => 0,
    };
}

// --- the compiled scrolltext -------------------------------------------------
export fn ikGlyphCount() u32 {
    return @intCast(text.GLYPH_COUNT);
}

export fn ikChangeCount() u32 {
    return @intCast(text.CHANGE_COUNT);
}

/// One font-change entry: f 0 = position (non-control chars), 1 = new size.
export fn ikChange(i: u32, f: u32) i32 {
    const c = text.CHANGES[i % text.CHANGE_COUNT];
    return switch (f) {
        0 => c.pos,
        1 => c.size,
        else => 0,
    };
}

/// One tile of one size: the glyph index, or -1 for a space / inactive slot.
export fn ikTile(size: u32, i: u32) i32 {
    return text.TILES[size % 4][i % text.GLYPH_COUNT];
}
