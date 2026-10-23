// --------------------------------------------------------------------------
// Tables built at COMPILE time from screen.js's own numbers, so nothing in the
// frame path touches a float. f64 here replays the remake's double arithmetic
// operation for operation (IEEE + and *, the same as JavaScript), which is why
// the photon's drop is a table rather than fixed point: it is then exact.
// --------------------------------------------------------------------------
const G = @import("geom.zig");

pub const FRAMES: usize = 30; // filmstrip frames per glyph (posY steps of 2.25)

/// The front side (cnvSilverChars): frame k draws the glyph at posY =
/// 33 - 2.25k. SROW[k][R] is the glyph row filmstrip row R shows, -1 if none.
/// The browser smooths a fractional posY; the port takes the row under the
/// pixel centre, floor(R + 0.5 - posY).
pub const SROW: [FRAMES][G.STRIP_ROWS]i8 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [FRAMES][G.STRIP_ROWS]i8 = undefined;
    for (0..FRAMES) |k| {
        const pos: f64 = 33.0 - 2.25 * @as(f64, @floatFromInt(k));
        for (0..G.STRIP_ROWS) |r| t[k][r] = glyphRow(@as(f64, @floatFromInt(r)) + 0.5 - pos, false);
    }
    break :blk t;
};

/// The back side (cnvPurpleChars): cnvFont2 is cnvFont turned upside down in
/// its 33-row cell (draw at y 33, rot 180, zoom -1,1), so cell row c holds
/// glyph row 32 - c. Frames 0..14 at posY 0, 2.25..31.5, frames 15..29 at
/// -33, -30.75..-2.25.
pub const PROW: [FRAMES][G.STRIP_ROWS]i8 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [FRAMES][G.STRIP_ROWS]i8 = undefined;
    for (0..FRAMES) |k| {
        const kf: f64 = @floatFromInt(k);
        const pos: f64 = if (k < 15) 2.25 * kf else -33.0 + 2.25 * (kf - 15.0);
        for (0..G.STRIP_ROWS) |r| t[k][r] = glyphRow(@as(f64, @floatFromInt(r)) + 0.5 - pos, true);
    }
    break :blk t;
};

fn glyphRow(cell: f64, flipped: bool) i8 {
    const c: i32 = @intFromFloat(@floor(cell));
    const g: i32 = if (flipped) 32 - c else c;
    if (c < 0 or c >= G.STRIP_ROWS or g < 0 or g >= 26) return -1;
    return @intCast(g);
}

/// dropPhoton: y from 184, gravity += 0.30, y += gravity, and at y > 445 the
/// gravity becomes the bounce, which shrinks by 0.70; it ends once the bounce
/// is >= -0.70. DROP[n] is the first canvas row frame n's photon covers.
/// Chrome's nearest sampling (smoothing off) takes source row
/// ceil(Y + 0.5 - y) - 1 for canvas row Y -- on an exact texel edge it keeps
/// the LOWER texel (measured against the remake, see NEAREST below) -- so the
/// photon starts at floor(y - 0.5) + 1.
pub const DROP: [139]i16 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [139]i16 = undefined;
    var y: f64 = 184.0;
    var g: f64 = 0.0;
    var b: f64 = -9.50;
    var n: usize = 0;
    while (true) {
        t[n] = @as(i16, @intFromFloat(@floor(y - 0.5))) + 1;
        g += 0.30;
        y += g;
        if (y > 445.0) {
            g = b;
            b *= 0.70;
        }
        n += 1;
        if (b >= -0.70) break;
    }
    if (n != t.len) @compileError("the drop is not 139 frames");
    break :blk t;
};

/// NEAREST: every smoothing-off draw here maps canvas row Y to source row
/// ceil(src) - 1 with src = (Y + 0.5 - y) / zoom, not floor(src): where src is
/// an exact integer Chrome keeps the texel above (page 1's bar at a .5
/// rasterbarY, the scroller's x1.5 rows, the photon at a .5 y all show it).
///
/// cnvScroller drawn at y 156 with zoom 1.5: content line r (Y = 2r + 1) shows
/// scroller row ceil((4r - 309) / 3) - 1 = floor((4r - 310) / 3).
pub const SCROLL_ROW: [G.SCROLL_END]i16 = blk: {
    var t: [G.SCROLL_END]i16 = [_]i16{0} ** G.SCROLL_END;
    for (G.SCROLL_TOP..G.SCROLL_END) |r| t[r] = @intCast(@divFloor(4 * @as(i32, @intCast(r)) - 310, 3));
    break :blk t;
};
