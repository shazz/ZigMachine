// --------------------------------------------------------------------------
// Window chrome — draw a window's shadow, frame, title bar, info line and
// scrollbars. Split out of Wm (window.zig) so neither file exceeds the size
// budget; these are pure drawing helpers over a Window. No behaviour change.
// --------------------------------------------------------------------------
const glyphs = @import("../gem_glyphs.zig");
const types = @import("types.zig");
const Gui = @import("core.zig").Gui;
const Rect = types.Rect;
const Window = types.Window;
const topBarsH = types.topBarsH;
const TITLE_H = types.TITLE_H;
const INFO_H = types.INFO_H;
const SCROLL = types.SCROLL;
const BLACK = types.BLACK;
const WHITE = types.WHITE;

// Draw a window's drop shadow + frame + title bar (close left, full right) +
// optional info line + scrollbars + size box; returns the interior content
// rect (inside the bars). The reference window carries a 2px black drop shadow
// (right + bottom), offset from the top-left corner.
pub fn draw(g: *Gui, w: *const Window, active: bool) Rect {
    g.rect(.{ .x = w.r.x + w.r.w, .y = w.r.y + 2, .w = 2, .h = w.r.h }, BLACK);
    g.rect(.{ .x = w.r.x + 2, .y = w.r.y + w.r.h, .w = w.r.w, .h = 2 }, BLACK);
    g.rect(w.r, WHITE);
    g.frame(w.r, BLACK);
    titleBar(g, w, active);
    if (w.info.len > 0) infoLine(g, w);
    scrollbars(g, w);
    const top = topBarsH(w);
    return .{ .x = w.r.x + 1, .y = w.r.y + top, .w = w.r.w - 2 - SCROLL, .h = w.r.h - top - SCROLL };
}

// Title bar, per the ST reference: gadget boxes at both ends, a 1px black line
// bounding the mover on each side, the grey mover pattern (active window only),
// and the title on a clear patch one char cell wider each side.
fn titleBar(g: *Gui, w: *const Window, active: bool) void {
    const bar = Rect{ .x = w.r.x + glyphs.GW, .y = w.r.y + 1, .w = w.r.w - 2 * glyphs.GW, .h = TITLE_H - 2 };
    if (active) g.hatch(bar, BLACK, WHITE) else g.rect(bar, WHITE);
    g.blit.fill(g.fb, bar.x, bar.y, 1, @intCast(bar.h), BLACK); // mover left bound
    g.blit.fill(g.fb, bar.x + bar.w - 1, bar.y, 1, @intCast(bar.h), BLACK); // mover right bound
    g.blit.fill(g.fb, w.r.x, w.r.y + TITLE_H - 1, @intCast(w.r.w), 1, BLACK); // underline
    const tw: i16 = @as(i16, @intCast(w.title.len)) * 8;
    const tx = w.r.x + @divTrunc(w.r.w - tw, 2);
    g.rect(.{ .x = tx - 8, .y = bar.y, .w = tw + 16, .h = bar.h }, WHITE); // clear patch
    g.text(w.title, tx, w.r.y + 2, BLACK, WHITE);
    g.gadget(w.r.x, w.r.y, glyphs.CLOSE, BLACK, WHITE);
    g.gadget(w.r.x + w.r.w - glyphs.GW, w.r.y, glyphs.FULL, BLACK, WHITE);
}

// GEM info line: plain text, one char row, closed by a 1px line. The text is
// clipped to the window width (8px cells) so it never spills past the right
// frame when the window is resized narrower than the string.
fn infoLine(g: *Gui, w: *const Window) void {
    const y = w.r.y + TITLE_H;
    const LEFT: i16 = 8; // one character cell in from the frame, like the drop-downs
    const max_chars: usize = @intCast(@max(0, @divTrunc(w.r.w - LEFT - 2, 8)));
    const info = w.info[0..@min(w.info.len, max_chars)];
    g.text(info, w.r.x + LEFT, y + 1, BLACK, WHITE); // 1px lower, like the title
    g.blit.fill(g.fb, w.r.x, y + INFO_H - 1, @intCast(w.r.w), 1, BLACK);
}

// Right + bottom scrollbars: real ST arrow gadgets sharing frame lines with
// their neighbours (as in the reference), grey tracks, and white sliders that
// fill the track (nothing scrolls yet), plus the size gadget.
fn scrollbars(g: *Gui, w: *const Window) void {
    const rx = w.r.x + w.r.w - glyphs.GW;
    const by = w.r.y + w.r.h - glyphs.GH;
    // right gutter: up gadget shares the bar's bottom line, down gadget the size box's top line
    slider(g, types.vTrack(w), w.vslide, w.vscroll, w.vmax, true);
    g.gadget(rx, w.r.y + topBarsH(w) - 1, glyphs.UP, BLACK, WHITE);
    g.gadget(rx, by - glyphs.GH + 1, glyphs.DOWN, BLACK, WHITE);
    // bottom gutter: left gadget shares the frame, right gadget the size box's left line
    slider(g, types.hTrack(w), w.hslide, w.hscroll, w.hmax, false);
    g.gadget(w.r.x, by, glyphs.LEFT, BLACK, WHITE);
    g.gadget(rx - glyphs.GW + 1, by, glyphs.RIGHT, BLACK, WHITE);
    g.gadget(rx, by, glyphs.SIZE, BLACK, WHITE);
}

// A GEM scroll track. `permille` of the content is visible, so the white slider
// box fills that fraction of the track and the rest shows the grey hatch; where
// it sits along the track is scroll/max of the remaining travel. At 1000 the
// slider fills the whole track (GEM's "everything fits" look) and the track
// draws as plain white with no inner lines, as in the reference. The rect
// INCLUDES the shared frame lines of the gadget boxes at both ends.
fn slider(g: *Gui, track: Rect, permille: i16, scroll: i16, max: i16, vertical: bool) void {
    if (permille >= 1000) {
        g.rect(track, WHITE);
        g.frame(track, BLACK);
        return;
    }
    g.hatch(track, BLACK, WHITE);
    g.frame(track, BLACK); // the gutter's own border — hatch() only fills
    const r = types.sliderBox(track, permille, scroll, max, vertical);
    g.rect(r, WHITE);
    g.frame(r, BLACK);
}
