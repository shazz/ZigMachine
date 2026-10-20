// --------------------------------------------------------------------------
// The headless harness's door into PHENOMENA (apps/phenomena_headless.mjs):
// every state word the update touches, the DNA ring, and the constant tables.
// Pulled in only when this scene IS the cart (phenomena.zig checks cart.Cart),
// so these exports never leak into another cart's build.
//
// The harness reads the master framebuffer (hwPhysicalPtr) and the same .dat
// assets for pixels; these exports are for the independent state model.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const A = @import("assets.zig");
const P = @import("palette.zig");
const dna = @import("dna.zig");

export fn phOk() u32 {
    return if (app.ok) 1 else 0;
}

export fn phState() u32 {
    return @intFromEnum(app.state);
}

export fn phPercent() i32 {
    return app.percent;
}

export fn phDir() i32 {
    return app.direction;
}

/// The opening raster's top row, content 1x Q16.16.
export fn phRasterY() i32 {
    return app.rasterbar_y;
}

/// Photon position, gravity and impact speed, 2x Q16.16 (main.go's units).
export fn phPhotonY() i32 {
    return app.photon_y;
}

export fn phGravity() i32 {
    return app.photon_gravity;
}

export fn phBounce() i32 {
    return app.photon_bounce;
}

/// The scroller clock and hue counter, Q16.16.
export fn phT() i32 {
    return @intCast(app.t);
}

export fn phColor() i32 {
    return @intCast(app.color);
}

export fn phBlackW() i32 {
    return app.black_rect_w;
}

export fn phBlackShow() u32 {
    return if (app.black_rect_show) 1 else 0;
}

export fn phFinished() u32 {
    return if (app.finished) 1 else 0;
}

// --- the DNA ring ----------------------------------------------------------
export fn phHead() u32 {
    return @intCast(dna.head);
}

export fn phRotation() i32 {
    return dna.rotation;
}

export fn phMsgIndex() u32 {
    return @intCast(dna.msg_index);
}

export fn phSliceCount() u32 {
    return @intCast(dna.slice_count);
}

export fn phPause() u32 {
    return if (dna.pause) 1 else 0;
}

export fn phPauseTime() i32 {
    return dna.pause_time;
}

export fn phRotSpeed() i32 {
    return dna.rot_speed;
}

export fn phScrollSpeed() u32 {
    return @intCast(dna.scroll_speed);
}

/// One ring cell in ring order (the visible strip order): f 0 glyph, 1 frame,
/// 2 slice.  The harness walks the ring as cells[(head + i) % 240].
export fn phCell(i: u32, f: u32) u32 {
    const c = dna.cells[(dna.head + i) % dna.CELLS];
    return switch (f) {
        0 => c.glyph,
        1 => c.frame,
        2 => c.slice,
        else => 0,
    };
}

/// The wave's strip top row (content) for slice i at the current t.
export fn phStripTop(i: u32) i32 {
    return dna.stripTop(i % dna.VISIBLE, app.t);
}

// --- constant tables (the harness also reads the .dat files) ----------------
/// dna.zig's sineOffsets[i] = sin(i*0.05)*15, Q16.16.
export fn phSine(i: u32) i32 {
    return P.SINE[i % dna.CELLS];
}

/// The opening raster's row d, as RGBA (the ST 3-bit grey).
export fn phBarIntro(d: u32) u32 {
    return A.introGrey(d % A.BAR_INTRO_H);
}

/// The purple raster's 2x row r (0..11), as RGBA.
export fn phBarMain(r: u32) u32 {
    return A.rgb3(A.mainBarRGB(r % 12));
}

/// hslToRGB(i/360, 1, 0.5), already snapped to the ST (the photon).
export fn phHue(i: u32) u32 {
    return A.rgb3(P.HUE[i % 360]);
}

export fn phPalette(i: u32) u32 {
    return A.paletteRGB(i % 16);
}

// The DNA filmstrip's three per-source-row gradient indices.
export fn phSilver(f: u32) u32 {
    return P.SILVER[f % 33];
}

export fn phPurple(f: u32) u32 {
    return P.PURPLE[f % 33];
}

export fn phRed(f: u32) u32 {
    return P.RED[f % 9];
}
