// --------------------------------------------------------------------------
// Painting the desktop scene, back to front: the work area, the desktop icons,
// the windows with their directories, then GEM's dotted overlays — window
// move/resize outline, drag ghosts, the zoom-box and the rubber-band marquee.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const icons = @import("../gem_icons.zig");
const icon_mod = @import("icon.zig");
const dt = @import("desktop.zig");
const dirview = @import("dirview.zig");
const deskwin = @import("deskwin.zig");
const desksel = @import("desksel.zig");
const desk_icons = @import("desk_icons.zig");
const Desktop = dt.Desktop;
const Rect = gui.Rect;

pub fn drawScene(d: *Desktop, g: *gui.Gui) void {
    g.rect(.{ .x = 0, .y = 0, .w = g.screen_w, .h = 200 }, gui.DESK); // green work area
    for (&d.items, 0..) |*it, i| {
        // A dragged file over the TRASH highlights it as a valid drop target.
        const drop_hot = i == desk_icons.IC_TRASH and d.file_drag >= 0 and it.hitAt(@intCast(g.px), @intCast(g.py));
        it.draw(g, d.sel_icon == @as(i16, @intCast(i)) or drop_hot);
    }
    var i: usize = 0;
    while (i < d.wm.n) : (i += 1) {
        const id = d.wm.order[i];
        if (!d.wm.wins[id].open) continue;
        const is_dir = deskwin.isFloppyWin(d, id);
        if (is_dir) deskwin.updateChrome(d, id); // info line + scroll state
        const v = if (is_dir) deskwin.viewOf(d, id) else undefined;
        _ = d.wm.drawChrome(g, id, id == d.wm.topOpen());
        if (is_dir) dirview.drawDir(d, g, d.win_dir[id], v);
    }
    if (d.wm.takeZoom()) |z| startGrow(d, z.from, z.to); // full-box zoom
    deskwin.shrinkClosed(d); // a window just closed -> zoom-box back to its icon
    d.wm.drawGhost(g); // pending window move / resize outline
    drawDragGhosts(d, g);
    drawGrow(d, g); // window-open zoom-box
    if (d.band) g.dotted(desksel.bandRect(d), gui.BLACK); // rubber-band marquee
}

// A dragged item hangs off the pointer at the offset it was GRABBED at, so the
// outline sits over the icon instead of jumping left of the cursor. The item
// itself stays where it is until the drop.
fn drawDragGhosts(d: *Desktop, g: *gui.Gui) void {
    if (d.file_drag >= 0 and d.file_moved) { // a file dragged out of a window
        const bmp = dirview.fileBmp(d, @intCast(d.file_drag));
        dragGhost(g, @intCast(@as(i32, g.px) - d.file_gx), @intCast(@as(i32, g.py) - d.file_gy), bmp);
    }
    if (d.drag) |di| { // a desktop icon
        if (d.moved) {
            const p = desk_icons.ghostAt(d, g);
            dragGhost(g, p.x, p.y, d.items[di].bmp);
        }
    }
}

const GROW_STEPS: u8 = 6;
pub fn startGrow(d: *Desktop, from: Rect, to: Rect) void {
    d.grow_a = from;
    d.grow_b = to;
    d.grow_t = GROW_STEPS;
}

// GEM zoom-box: a dotted frame interpolated from grow_a to grow_b over a few frames.
fn drawGrow(d: *Desktop, g: *gui.Gui) void {
    if (d.grow_t == 0) return;
    const n: i16 = GROW_STEPS;
    const k: i16 = n - @as(i16, @intCast(d.grow_t)) + 1; // 1..n
    const a = d.grow_a;
    const b = d.grow_b;
    g.dotted(.{
        .x = a.x + @divTrunc((b.x - a.x) * k, n),
        .y = a.y + @divTrunc((b.y - a.y) * k, n),
        .w = a.w + @divTrunc((b.w - a.w) * k, n),
        .h = a.h + @divTrunc((b.h - a.h) * k, n),
    }, gui.BLACK);
    d.grow_t -= 1;
}

// A GEM drag ghost: ONE dotted contour around the whole icon+label unit — the
// narrow icon box sitting on the wider label field traces a single "hat"
// (inverse-T) outline, not two stacked rectangles. The label box is the full
// fixed-width label FIELD, so the ghost is the exact footprint the icon takes
// once dropped.
fn dragGhost(g: *gui.Gui, x: i16, y: i16, bmp: icons.Icon) void {
    const art = icon_mod.artBox(bmp);
    const ax = x + art.x;
    const iw = art.w;
    const lw = icon_mod.LABEL_W;
    const lh = icon_mod.LABEL_H;
    const lx = ax + @divTrunc(iw - lw, 2);
    const top = y + art.y;
    const shoulder = top + art.h; // the row where the icon box meets the label field
    const c = gui.BLACK;
    dotH(g, ax, ax + iw, top, c); // icon top
    dotV(g, top, shoulder, ax, c); // icon left
    dotV(g, top, shoulder, ax + iw - 1, c); // icon right
    dotH(g, lx, ax, shoulder, c); // left shoulder
    dotH(g, ax + iw, lx + lw, shoulder, c); // right shoulder
    dotV(g, shoulder, shoulder + lh, lx, c); // label left
    dotV(g, shoulder, shoulder + lh, lx + lw - 1, c); // label right
    dotH(g, lx, lx + lw, shoulder + lh - 1, c); // label bottom
}

// Dotted segments (every other pixel, clipped by Gui.plot), the pieces a GEM
// outline is built from.
fn dotH(g: *gui.Gui, x0: i16, x1: i16, y: i16, c: u8) void {
    var x: i16 = x0;
    while (x < x1) : (x += 2) g.plot(x, y, c);
}
fn dotV(g: *gui.Gui, y0: i16, y1: i16, x: i16, c: u8) void {
    var y: i16 = y0;
    while (y < y1) : (y += 2) g.plot(x, y, c);
}
