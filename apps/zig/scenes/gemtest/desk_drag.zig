// --------------------------------------------------------------------------
// GEMTEST's desktop icon drag (Matt on the board, 10 Nov: "moving an icon on the
// desktop doesn't show the shadow icon"; "option to stick to the invisible grid or
// free move"). Two options in the Mode menu:
//   Drag ghost    while the button is held, a dotted box of the icon follows the
//                 pointer, as TOS's graf_dragbox does; off: the icon jumps on release
//   Snap to grid  the icon lands on the grid the desk was laid out on (80 px
//                 columns from x 8, 48 px rows up from the bottom row); off: where
//                 it was dropped
// The ghost is drawn on the desk only (clipped to its visible rectangles), and the
// desk strips under its outline are redrawn before it moves on.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const redraw = rom.aes.redraw;
const Rect = rom.Rect;
const desk = @import("desk.zig");
const App = @import("../gemtest.zig").App;

pub const COL: i32 = 80; // desk.init's layout: x = 8 + k * 80
pub const ROW: i32 = desk.H + 6;
const X0: i32 = 8;

/// Has the press moved far enough to be a drag (the G14 threshold)?
pub fn moved(app: *const App) bool {
    const d = &app.desk;
    return @abs(app.px - d.from[0]) + @abs(app.py - d.from[1]) > 3;
}

/// Icon `k` dropped here: its position in the desk tree, kept on the desk, on the grid if snapping.
pub fn target(app: *const App, k: u8) [2]i16 {
    const d = &app.desk;
    const o = d.objs[1 + k];
    const root = d.objs[0];
    var x: i32 = o.x + app.px - d.from[0];
    var y: i32 = o.y + app.py - d.from[1];
    if (d.snap) {
        const base: i32 = root.h - desk.H - 4; // the bottom row, where desk.init put the icons
        x = X0 + @divFloor(x - X0 + @divTrunc(COL, 2), COL) * COL;
        y = base - @divFloor(base - y + @divTrunc(ROW, 2), ROW) * ROW;
    }
    x = std.math.clamp(x, 0, root.w - o.w);
    y = std.math.clamp(y, 0, root.h - o.h);
    return .{ @intCast(x), @intCast(y) };
}

/// A frame of a held drag: the ghost where the icon would land, if the option is on.
pub fn follow(app: *App, k: u8) void {
    const d = &app.desk;
    if (!d.ghost or !moved(app)) return;
    const t = target(app, k);
    const r: Rect = .{ .x = d.objs[0].x + t[0], .y = d.objs[0].y + t[1], .w = desk.W, .h = desk.H };
    if (d.shown) |s| if (s.x == r.x and s.y == r.y) return;
    erase(app);
    draw(app, r);
    d.shown = r;
}

/// The ghost gone: the desk under its outline drawn again.
pub fn erase(app: *App) void {
    const d = &app.desk;
    const s = d.shown orelse return;
    d.shown = null;
    const edges = [4]Rect{
        .{ .x = s.x, .y = s.y, .w = s.w, .h = 1 },
        .{ .x = s.x, .y = s.y + s.h - 1, .w = s.w, .h = 1 },
        .{ .x = s.x, .y = s.y, .w = 1, .h = s.h },
        .{ .x = s.x + s.w - 1, .y = s.y, .w = 1, .h = s.h },
    };
    for (edges) |e| desk.repaint(app.g, app.mode, e);
}

// The dotted outline (every other pixel, GEM black = index 0), on the desk only.
fn draw(app: *App, r: Rect) void {
    var it = redraw.rects(app.g, 0, .visible);
    while (it.next()) |v| {
        redraw.clip(app.g, v);
        dotted(app.g, r);
    }
    redraw.clipOff(app.g);
}

fn dotted(g: rom.Gui, r: Rect) void {
    var x: i32 = r.x;
    while (x < r.x + r.w) : (x += 2) {
        g.plot(@intCast(x), @intCast(r.y), 0);
        g.plot(@intCast(x), @intCast(r.y + r.h - 1), 0);
    }
    var y: i32 = r.y;
    while (y < r.y + r.h) : (y += 2) {
        g.plot(@intCast(r.x), @intCast(y), 0);
        g.plot(@intCast(r.x + r.w - 1), @intCast(y), 0);
    }
}
