// --------------------------------------------------------------------------
// A program's windows, one frame of input (appwin.zig's process): the work-area press
// that is the program's, the Wm's own gestures, the arrows repeated while held, the
// outline drawn save-under, and what changed on each window turned into EV_* bits.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const window = @import("window.zig");
const Gui = @import("core.zig").Gui;
const saveunder = @import("saveunder.zig");
const appwin = @import("appwin.zig");
const AppWin = appwin.AppWin;
const MAX_WIN = types.MAX_WIN;
const EV_WORK = appwin.EV_WORK;
const EV_HIT = appwin.EV_HIT;
const EV_CLOSED = appwin.EV_CLOSED;
const EV_MOVED = appwin.EV_MOVED;
const EV_SIZED = appwin.EV_SIZED;
const EV_SCROLLED = appwin.EV_SCROLLED;
const EV_TOPPED = appwin.EV_TOPPED;

const REPEAT_DELAY = 18; // frames an arrow is held before it repeats
const REPEAT_EVERY = 3;

pub fn process(self: *AppWin, g: *Gui) u32 {
    self.events = [_]u32{0} ** MAX_WIN;
    if (workPress(self, g)) |id| {
        self.events[id] = EV_WORK;
        return EV_WORK;
    }
    const hit = self.wm.handle(g);
    repeat(self, g, hit);
    drawOutline(self, g);
    var all: u32 = if (hit) EV_HIT else 0;
    var i: u8 = 0;
    while (i < self.wm.n) : (i += 1) {
        self.events[i] |= diff(self, i);
        if (hit and self.wm.topOpen() == i) self.events[i] |= EV_HIT;
        all |= self.events[i];
    }
    return all;
}

// A press that starts inside the TOP window's work area is the program's: the Wm
// would take it as a click on the window (and swallow it).
fn workPress(self: *AppWin, g: *Gui) ?u8 {
    if (!g.edge or self.wm.drag != null or self.wm.resize != null or self.wm.slider != null) return null;
    const t = self.wm.topOpen() orelse return null;
    if (!types.inRect(self.wm.contentRect(t), g.px, g.py)) return null;
    return t;
}

// An arrow held down steps again after REPEAT_DELAY frames, every REPEAT_EVERY.
fn repeat(self: *AppWin, g: *Gui, hit: bool) void {
    if (!g.down) return stopRepeat(self);
    if (g.edge) {
        stopRepeat(self);
        const t = self.wm.topOpen() orelse return;
        if (hit and window.Wm.onArrow(&self.wm.wins[t], g.px, g.py)) self.held_win = t;
        return;
    }
    const id = self.held_win orelse return;
    self.held += 1;
    if (self.held >= REPEAT_DELAY and (self.held - REPEAT_DELAY) % REPEAT_EVERY == 0)
        _ = window.Wm.scrollPress(&self.wm.wins[id], g);
}
fn stopRepeat(self: *AppWin) void {
    self.held_win = null;
    self.held = 0;
}

// The Wm's pending outline, drawn over the screen with what it covers kept.
fn drawOutline(self: *AppWin, g: *Gui) void {
    const want = self.wm.ghost;
    const have = self.outline.at;
    if (want) |w| if (have) |h| if (w.x == h.x and w.y == h.y and w.w == h.w and w.h == h.h) return;
    const p = saveunder.Plane{ .pix = g.fb.fb, .stride = g.fb.stride, .w = g.screen.w, .h = g.screen.h };
    self.outline.restore(p);
    if (want) |w| _ = self.outline.draw(p, .{ .x = w.x, .y = w.y, .w = w.w, .h = w.h }, types.BLACK);
}

// What changed on window `i` since it was last reported. A closer click is turned back
// into a request: the window reopens until the program closes it.
fn diff(self: *AppWin, i: u8) u32 {
    var ev: u32 = 0;
    const w = &self.wm.wins[i];
    const was = self.shown[i];
    if (was.open and !w.open) {
        w.open = true;
        _ = self.wm.takeClosed();
        ev |= EV_CLOSED;
    }
    _ = self.wm.takeZoom();
    if (w.r.x != was.r.x or w.r.y != was.r.y) ev |= EV_MOVED;
    if (w.r.w != was.r.w or w.r.h != was.r.h) ev |= EV_SIZED;
    if (w.vscroll != was.v or w.hscroll != was.h) ev |= EV_SCROLLED;
    const top = self.wm.topOpen();
    if (top == i and self.top != top) {
        ev |= EV_TOPPED;
        self.top = top;
    }
    self.shown[i] = appwin.snap(w);
    return ev;
}
