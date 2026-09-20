// The B.I.G. Demo jukebox's three painted layers, split out of big/screen.zig
// so that file can stay under the project's 200-line ceiling. They are pure
// drawing: each takes the state it reads and the plane it writes, and holds
// none of its own. big/screen.zig owns the state and the order they run in,
// which is go()'s order (screen.js:390-492).
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");
const list = @import("list.zig");

/// The 320-byte slice of the plane that holds content row `y`. Every draw here
/// and in big/screen.zig goes through it, so the 40-px side margins — which
/// carry the real screen's borders (big/border.zig) — are never touched by
/// content code.
pub inline fn row(fb: *LogicalFB, y: usize) []u8 {
    return fb.fb[(A.TOP + y) * A.STRIDE + A.LEFT ..][0..A.W];
}

/// The transparent scroller: the IN font is a MASK filled with the scrolling
/// fontbg diagonal (canvas 'source-in'), the OUT font's outline over it.
/// `y0` is the band's top row in content coordinates: A.SCROLL_Y for the
/// jukebox, 35 lower for the Digital Solution. The fontbg diagonal is
/// anchored to the GLYPH's row (what the jukebox's 0-px replay confirms)
/// and repeats every 8 px, so drawing a band at another y is only a phase
/// shift of it.
pub fn scroller(fb: *LogicalFB, y0: usize, bgscrposx: i32, posx: []const i32, ltr: []const u8) void {
    const phase = @divFloor(-bgscrposx, 2); // fontbg's offset, halved
    for (posx, ltr) |px, lt| {
        // -ME-'s text is not pure uppercase: it carries 2 TABs and 38
        // lowercase 'r's, which land on tile -23 and tile 82 of a 70-tile
        // font. drawTile feeds both to drawPart, which clips the source
        // rectangle to nothing outside the font image and paints NOTHING —
        // so skipping them is the original's behaviour, not a shortcut.
        if (lt < A.FIRST_CHAR) continue;
        const g: usize = lt - A.FIRST_CHAR;
        if (g >= A.GLYPHS) continue;
        var sx: usize = 0;
        var x = @divFloor(px, 2);
        var n: usize = A.GW;
        if (x < 0) {
            sx = @intCast(-x);
            if (sx >= A.GW) continue;
            n -= sx;
            x = 0;
        }
        const dx: usize = @intCast(x);
        if (dx >= A.W) continue;
        if (n > A.W - dx) n = A.W - dx;
        for (0..A.GH) |y| {
            const off = (g * A.GH + y) * A.GW + sx;
            const mask = A.fontin[off..][0..n];
            const line = A.fontout[off..][0..n];
            const dst = row(fb, y0 + y)[dx..][0..n];
            for (mask, line, dst, 0..) |m, o, *d, k| {
                if (m != 0) {
                    const t = @as(i32, @intCast(dx + k)) + phase - @as(i32, @intCast(y));
                    d.* = A.FONTBG[@intCast(@mod(t, 8))];
                }
                if (o != A.TRANSPARENT) d.* = o;
            }
        }
    }
}

/// shadow.draw(mycanvas,0,447,0.5) / (...,500,0.5): an opaque grey at half
/// alpha is exactly a palette lookup once the palette is fixed.
pub fn shadows(fb: *LogicalFB) void {
    for (A.SHADOW_Y) |sy| {
        for (A.SHADOW_TONE, 0..) |tone, r| {
            const lut = A.shadow_lut[@as(usize, tone) * 256 ..][0..256];
            for (row(fb, sy + r)) |*d| d.* = lut[d.*];
        }
    }
}

/// Five entries around the cursor. The selected one is a filled bar with the
/// font's own ink ('source-over'); the others are the bar colour showing
/// through the glyphs only ('destination-in'). go() brackets these five
/// draws with globalCompositeOperation='darker', which no longer exists in
/// Canvas2D — an unknown op is ignored, so the rows land plain source-over.
pub fn listRows(fb: *LogicalFB, curent: usize, playing_idx: usize) void {
    for (A.LIST_INK, 0..) |ink, k| {
        const idx = curent - 2 + k;
        const playing = idx == playing_idx;
        const y0 = A.LIST_Y + k * A.LIST_STEP;
        if (playing) {
            for (0..A.PH) |y| @memset(row(fb, y0 + y)[A.LIST_X..][0 .. A.LIST_COLS * A.PW], ink);
        }
        const glyph = if (playing) A.FONTP_INK else ink;
        for (list.ENTRIES[idx].label, 0..) |ch, i| {
            if (i >= A.LIST_COLS or ch < 32) continue;
            const g: usize = ch - 32;
            if (g >= A.P_GLYPHS) continue;
            const x0 = A.LIST_X + i * A.PW;
            for (0..A.PH) |y| {
                const mask = A.fontp[(g * A.PH + y) * A.PW ..][0..A.PW];
                const dst = row(fb, y0 + y)[x0..][0..A.PW];
                for (mask, dst) |m, *d| {
                    if (m != 0) d.* = glyph;
                }
            }
        }
    }
}
