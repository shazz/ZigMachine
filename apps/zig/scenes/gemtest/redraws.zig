// --------------------------------------------------------------------------
// GEMTEST's window redraws on the ROM's WM_REDRAW rectangle lists (aes.redraw, G17;
// Matt on the board, 9 Nov: a move or a top flashed the screen, every window was
// repainted back to front unclipped). Split out of wins.zig.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const redraw = rom.aes.redraw;
const screen = @import("../notepad/screen.zig");
const wins = @import("wins.zig");
const App = @import("../gemtest.zig").App;
const paintContent = wins.paintContent;

/// This frame's damage only (WM_REDRAW, G17): the desk's rectangles, then each window's back
/// to front, each drawn clipped to its rectangle. Nothing else on the screen is written, so a
/// move or a top no longer repaints (and flashes) every window.
pub fn paintDamage(app: *App) void {
    const g = app.g;
    var it = redraw.rects(g, 0, .redraw);
    while (it.next()) |r| {
        redraw.clip(g, r);
        screen.desk(g, app.mode);
    }
    var k: u32 = 0;
    while (redraw.stackAt(g, k)) |id| : (k += 1) {
        const i = slotOf(app, id) orelse continue;
        var rs = redraw.rects(g, id, .redraw);
        while (rs.next()) |r| {
            redraw.clip(g, r);
            app.wins.slots[i].win.draw();
            app.wins.slots[i].shown = .{ -1, -1, -1, -1 };
            paintContent(app, i);
        }
    }
    redraw.clipOff(g);
}

/// A window's work area where it is visible (WF_FIRSTXYWH ..): a lower window's scroll too.
pub fn paintVisible(app: *App, i: u8) void {
    const g = app.g;
    var rs = redraw.rects(g, app.wins.slots[i].win.id, .visible);
    while (rs.next()) |r| {
        redraw.clip(g, r);
        paintContent(app, i);
    }
    redraw.clipOff(g);
}

/// The windows whose CONTENT changed this frame without being in the damage: a topped one (its
/// counter), a scrolled one, any whose stack position moved (each shows it): their work areas
/// where visible. A moved or sized one was redrawn whole by paintDamage.
pub fn paintShown(app: *App) void {
    const s = &app.wins;
    for (0..s.n) |k| {
        const i: u8 = @intCast(k);
        if (!s.slots[i].open) continue;
        const e = s.slots[i].win.events();
        if (e & (rom.aes.EV_MOVED | rom.aes.EV_SIZED) != 0) continue;
        const shows = e & (rom.aes.EV_TOPPED | rom.aes.EV_SCROLLED) != 0 or s.depth(i) != s.slots[i].depth_shown;
        if (shows) paintVisible(app, i);
    }
}

fn slotOf(app: *const App, id: u32) ?u8 {
    for (0..app.wins.n) |k| if (app.wins.slots[k].open and app.wins.slots[k].win.id == id) return @intCast(k);
    return null;
}
