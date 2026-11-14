// --------------------------------------------------------------------------
// GEM 5's program API, the windows (rom_app.zig has the rest): wind_create .. wind_get for the
// program context that owns rom_app's state, the Wm's results as event bits (appwin.zig).
// --------------------------------------------------------------------------
const main = @import("rom_main.zig");
const app = @import("rom_app.zig");
const appwin = @import("rom").gui.appwin;
const slot = app.slot;

// --- windows -------------------------------------------------------------------

fn winOf(h: u32, id: u32) ?struct { w: *appwin.AppWin, i: u32 } {
    _ = slot(h) orelse return null;
    if (id == 0) return null;
    return .{ .w = &app.app_win, .i = id - 1 };
}

/// wind_create + wind_open with every gadget: a window id (1-based), 0 when none is free.
export fn winOpen(h: u32, x: i32, y: i32, w: i32, hh: i32, ptr: u32, len: u32) u32 {
    _ = slot(h) orelse return 0;
    const id = app.app_win.open(main.rectOf(x, y, w, hh), main.slice(ptr, len)) orelse return 0;
    return @as(u32, id) + 1;
}
export fn winClose(h: u32, id: u32) void {
    const o = winOf(h, id) orelse return;
    o.w.close(o.i);
}
export fn winTitle(h: u32, id: u32, ptr: u32, len: u32) void {
    const o = winOf(h, id) orelse return;
    o.w.setTitle(o.i, main.slice(ptr, len));
}
export fn winInfo(h: u32, id: u32, ptr: u32, len: u32) void {
    const o = winOf(h, id) orelse return;
    o.w.setInfo(o.i, main.slice(ptr, len));
}
/// wind_set's sliders: `vertical` 1 / 0, the slider's size in per mille, the position and its
/// maximum in the program's units (rows, columns), and what a track click pages.
export fn winScroll(h: u32, id: u32, vertical: u32, size: i32, pos: i32, max: i32, page: i32) void {
    const o = winOf(h, id) orelse return;
    o.w.setScroll(o.i, vertical != 0, size, pos, max, page);
}
/// wind_set WF_CURRXYWH: the window's outer box.
export fn winSet(h: u32, id: u32, x: i32, y: i32, w: i32, hh: i32) void {
    const o = winOf(h, id) orelse return;
    const s = main.guiAt(h).?.screen;
    o.w.setRect(o.i, main.rectOf(x, y, w, hh), s.w, s.h); // sized as a drag would be (G22, G23)
}
/// A frame of input for every window: the OR of their event bits (appwin.zig EV_*).
export fn winProcess(h: u32) u32 {
    _ = slot(h) orelse return 0;
    return app.app_win.process(main.guiAt(h).?);
}
export fn winEvents(h: u32, id: u32) u32 {
    const o = winOf(h, id) orelse return 0;
    return o.w.eventsOf(o.i);
}
/// The window's chrome; its work area is the program's to draw after.
export fn winDraw(h: u32, id: u32) void {
    const o = winOf(h, id) orelse return;
    o.w.draw(main.guiAt(h).?, o.i);
}
/// The scrollbars alone, after winScroll moved a slider (the chrome's other parts stay).
export fn winDrawBars(h: u32, id: u32) void {
    const o = winOf(h, id) orelse return;
    o.w.drawBars(main.guiAt(h).?, o.i);
}
/// wind_get: 0..3 the work area x, y, w, h; 4..7 the outer box; 8 vscroll; 9 hscroll;
/// 10 the top window's id (0: none).
export fn winGet(h: u32, id: u32, what: u32) i32 {
    const o = winOf(h, id) orelse return 0;
    const win = o.w.window_(o.i) orelse return 0;
    const wk = o.w.work(o.i);
    return switch (what) {
        0 => wk.x,
        1 => wk.y,
        2 => wk.w,
        3 => wk.h,
        4 => win.r.x,
        5 => win.r.y,
        6 => win.r.w,
        7 => win.r.h,
        8 => win.vscroll,
        9 => win.hscroll,
        10 => if (o.w.wm.topOpen()) |t| @as(i32, t) + 1 else 0,
        else => 0,
    };
}
