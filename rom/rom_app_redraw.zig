// --------------------------------------------------------------------------
// GEM 5's program API, window redraws (G17, system table 1.22): the AES's WM_REDRAW
// rectangle lists and wind_get WF_FIRSTXYWH / WF_NEXTXYWH, for the program context
// that owns rom_app's windows (gui/appwin_damage.zig computes them). After
// winProcess (and winOpen / winClose / winSet) a program asks, per window back to
// front (winStack), the rectangles to redraw, sets each as the clip (guiClip) and
// draws its chrome and work area there: nothing else on the screen is touched, so
// a move or a top no longer repaints every window (Matt's flash on the board).
// Window id 0 is the desk: what no window covers.
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");
const app = @import("rom_app.zig");
const gui = @import("rom").gui;
const dmg = gui.appwin.dmg;

var list: dmg.RectList = .{}; // the last list asked for (winRects), read by winRect
const BREAK_WHOLE: u32 = 1 << 26; // deskSetEngine's mutant: a redraw list is the whole window (the flash back)

/// The rectangles of window `id` (1-based; 0 the desk): `which` 0 its WM_REDRAW list (this
/// frame's damage it must redraw), 1 what of it is visible (WF_FIRSTXYWH .. WF_NEXTXYWH). Their
/// count; read each with winRect. 0 for a bad handle or a closed window.
export fn winRects(h: u32, id: u32, which: u32) u32 {
    list = .{};
    _ = app.slot(h) orelse return 0;
    const g = main.guiAt(h).?;
    const s = app.app_win.stack();
    const win: ?u8 = if (id == 0) null else @intCast(@min(id - 1, 255));
    if (win) |w| if (w >= dmg.MAX or s.cover[w] == null) return 0;
    const screen: dmg.Rect = .{ .x = 0, .y = g.screen.metrics().menu_h, .w = g.screen.w, .h = g.screen.h - g.screen.metrics().menu_h };
    const whole = gui.proglook.breaks & BREAK_WHOLE != 0; // the mutant: every visible rect, every time
    if (which == 0 and !whole) dmg.redraw(&s, win, screen, &app.app_win.dirty, &list) else dmg.visible(&s, win, screen, &list);
    return @intCast(list.n);
}

/// Rectangle `i` of the last winRects list: `part` 0..3 = x, y, w, h.
export fn winRect(h: u32, i: u32, part: u32) i32 {
    _ = app.slot(h) orelse return 0;
    if (i >= list.n) return 0;
    const r = list.r[i];
    return switch (part) {
        0 => r.x,
        1 => r.y,
        2 => r.w,
        3 => r.h,
        else => 0,
    };
}

/// The id (1-based) of the k-th open window from the BACK (k = 0 the bottom one), 0 past the
/// top: the order to redraw in, and wind_get's stack beyond WF_TOP.
export fn winStack(h: u32, k: u32) u32 {
    _ = app.slot(h) orelse return 0;
    const s = app.app_win.stack();
    return if (k < s.n) @as(u32, s.order[k]) + 1 else 0;
}

/// The context's clip (vs_clip): every drawing call (the program's and winDraw's) stays inside
/// (x, y, w, h); w or h <= 0 turns the clip off.
export fn guiClip(h: u32, x: i32, y: i32, w: i32, hh: i32) void {
    const g = main.guiAt(h) orelse return;
    g.clip = if (w <= 0 or hh <= 0) null else main.rectOf(x, y, w, hh);
}
