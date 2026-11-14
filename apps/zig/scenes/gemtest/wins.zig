// --------------------------------------------------------------------------
// GEMTEST's windows: the area on show (one at a time; the Windows area opens
// four), their stacking order and their scroll. A change of the stack (a top, a
// move, a size, a close) redraws only the ROM's WM_REDRAW rectangles (aes.redraw,
// G17): the desk's, then each window's back to front, clipped to each one. A
// scroll redraws the window's work area where it is visible (WF_FIRSTXYWH ..).
// The program still keeps its own order from EV_TOPPED for its counters.
// --------------------------------------------------------------------------
const std = @import("std");
const rom = @import("rom_sdk");
const aes = rom.aes;
const redraws = @import("redraws.zig");
const Rect = rom.Rect;
const Pen = @import("pen.zig").Pen;
const areas = @import("areas.zig");
const Area = areas.Area;
const screen = @import("../notepad/screen.zig");
const App = @import("../gemtest.zig").App;

pub const MAX = 4;

pub const Slot = struct {
    win: aes.Window,
    part: u8, // which of the area's windows
    top: i32 = 0, // the scroll, in rows and columns
    left: i32 = 0,
    shown: [4]i32 = .{ -1, -1, -1, -1 }, // the extent and the scroll the sliders were last told
    moved: u16 = 0, // the Windows area counts its events
    sized: u16 = 0,
    topped: u16 = 0,
    scrolled: u16 = 0,
    depth_shown: usize = 0, // the stack position its content last showed
    open: bool = true,
};

pub const Set = struct {
    area: ?Area = null,
    slots: [MAX]Slot = undefined,
    n: u8 = 0, // the area's windows, open or closed
    live: u8 = 0, // the open ones, in `order`
    order: [MAX]u8 = undefined, // back to front, indices into slots

    pub fn closeAll(self: *Set) void {
        for (self.order[0..self.live]) |i| self.slots[i].win.close();
        self.n = 0;
        self.live = 0;
        self.area = null;
    }

    /// The area's windows, the last one on top; the Windows area's larger-than-the-screen one first
    /// (at the back: the others stay visible over it).
    pub fn show(self: *Set, g: rom.Gui, area: Area, mode: aes.ScreenMode) void {
        self.closeAll();
        self.area = area;
        const n = areas.windows(area);
        const parts = [_]u8{ 3, 0, 1, 2 };
        for (0..n) |i| {
            const part: u8 = if (n == 1) 0 else parts[i];
            const r = rectOf(mode, area, part);
            const win = aes.Window.open(g, r, areas.title(area, part)) orelse break;
            win.info(areas.info(area, part));
            self.slots[self.n] = .{ .win = win, .part = part };
            self.order[self.n] = self.n;
            self.n += 1;
        }
        self.live = self.n;
    }

    pub fn topSlot(self: *const Set) ?u8 {
        return if (self.live == 0) null else self.order[self.live - 1];
    }

    /// The window `i` came to the front (EV_TOPPED): the program's copy of the stack follows.
    pub fn raise(self: *Set, i: u8) void {
        var k: usize = 0;
        while (k < self.live and self.order[k] != i) : (k += 1) {}
        if (k == self.live) return;
        while (k + 1 < self.live) : (k += 1) self.order[k] = self.order[k + 1];
        self.order[self.live - 1] = i;
        self.slots[i].topped += 1;
    }

    /// The window's stack position, 1 = the back.
    pub fn depth(self: *const Set, i: u8) usize {
        for (self.order[0..self.live], 0..) |o, k| if (o == i) return k + 1;
        return 0;
    }
};

/// Where each window opens: one window in notepad's box; the Windows area's four
/// overlapping, part 3 larger than the screen.
fn rectOf(mode: aes.ScreenMode, area: Area, part: u8) Rect {
    const base = screen.windowRect(mode);
    if (area != .windows) return base;
    const w = screen.width(mode);
    const h = screen.height(mode);
    const p: i16 = @intCast(part);
    return switch (part) {
        0 => .{ .x = 8, .y = 19, .w = @divTrunc(w * 3, 5), .h = @divTrunc(h * 3, 5) },
        1, 2 => .{ .x = @divTrunc(w, 4) + p * 24, .y = 19 + @divTrunc(h, 5) + p * 12, .w = @divTrunc(w, 2), .h = @divTrunc(h, 2) },
        else => .{ .x = 24, .y = 40, .w = w + 160, .h = h + 120 },
    };
}

/// The desk, every window back to front, the menu bar.
pub fn paintAll(app: *App) void {
    const s = &app.wins;
    @import("desk.zig").paint(app.g, app.mode, .{ .x = 0, .y = 0, .w = screen.width(app.mode), .h = screen.height(app.mode) });
    for (s.order[0..s.live]) |i| {
        s.slots[i].win.draw();
        s.slots[i].shown = .{ -1, -1, -1, -1 };
        paintContent(app, i);
    }
    app.bar.redraw();
}

/// One window's work area: white, its content, then its sliders if they changed.
pub fn paintContent(app: *App, i: u8) void {
    const s = &app.wins.slots[i];
    const wk = s.win.work();
    app.g.rect(wk, rom.WHITE);
    s.depth_shown = app.wins.depth(i);
    var p = Pen.init(app.g, wk, s.top, s.left);
    areas.draw(&p, app, app.wins.area.?, i);
    sliders(app, s, p.extent(), wk);
}

fn sliders(app: *App, s: *Slot, ext: [2]i32, wk: Rect) void {
    const c = aes.cell(app.g);
    const rows: i32 = @max(1, @divTrunc(wk.h, c[1]));
    const cols: i32 = @max(1, @divTrunc(wk.w, c[0]));
    const want = [4]i32{ ext[0], ext[1], s.top, s.left };
    if (std.mem.eql(i32, &want, &s.shown)) return;
    s.shown = want;
    const vmax = @max(0, ext[0] - rows);
    const hmax = @max(0, ext[1] - cols);
    s.win.scroll(true, if (ext[0] <= rows) 1000 else @divTrunc(rows * 1000, ext[0]), @min(s.top, vmax), vmax, rows);
    s.win.scroll(false, if (ext[1] <= cols) 1000 else @divTrunc(cols * 1000, ext[1]), @min(s.left, hmax), hmax, cols);
    s.win.drawBars();
}

/// A frame of the windows' input: the stack, the moves and sizes, the scrolls. True when the
/// top window's work area was pressed (the program's: its controls).
pub fn frame(app: *App) bool {
    const s = &app.wins;
    const ev = aes.processWindows(app.g);
    if (ev == 0 or s.live == 0) return false;
    var all = false;
    for (0..s.n) |k| {
        const i: u8 = @intCast(k);
        if (!s.slots[i].open) continue;
        const e = s.slots[i].win.events();
        if (e & aes.EV_TOPPED != 0) s.raise(i);
        if (e & aes.EV_MOVED != 0) s.slots[i].moved += 1;
        if (e & aes.EV_SIZED != 0) s.slots[i].sized += 1;
        if (e & aes.EV_CLOSED != 0) return closed(app, i);
        if (e & (aes.EV_TOPPED | aes.EV_MOVED | aes.EV_SIZED) != 0) all = true;
        if (e & aes.EV_SCROLLED != 0) {
            s.slots[i].top = s.slots[i].win.vscroll();
            s.slots[i].left = s.slots[i].win.hscroll();
            s.slots[i].scrolled += 1;
        }
    }
    if (all) redraws.paintDamage(app);
    redraws.paintShown(app);
    return ev & aes.EV_WORK != 0;
}

// The closer (a request, WM_CLOSED): that window goes, the others stay.
fn closed(app: *App, i: u8) bool {
    const s = &app.wins;
    s.slots[i].win.close();
    s.slots[i].open = false;
    var out: usize = 0;
    for (s.order[0..s.live]) |o| if (o != i) {
        s.order[out] = o;
        out += 1;
    };
    s.live = @intCast(out);
    redraws.paintDamage(app); // what was under it (winClose's damage)
    redraws.paintShown(app); // the others' stack positions moved
    return false;
}
