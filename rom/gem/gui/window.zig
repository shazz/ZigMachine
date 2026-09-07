// --------------------------------------------------------------------------
// Window manager — draggable windows with a title bar, close + full boxes and
// a size gadget, plus z-order. Drawing lives in chrome.zig; this file owns the
// retained state and pointer interaction. No behaviour change from the split.
// --------------------------------------------------------------------------
const glyphs = @import("../gem_glyphs.zig");
const types = @import("types.zig");
const chrome = @import("chrome.zig");
const Gui = @import("core.zig").Gui;
const Rect = types.Rect;
const Window = types.Window;
const inRect = types.inRect;
const MENU_H = types.MENU_H;
const TITLE_H = types.TITLE_H;
const MAX_WIN = types.MAX_WIN;
const MIN_W = types.MIN_W;
const MIN_H = types.MIN_H;

pub const Wm = struct {
    wins: [MAX_WIN]Window = undefined,
    order: [MAX_WIN]u8 = undefined, // back-to-front draw order (indices into wins)
    n: u8 = 0,
    drag: ?u8 = null,
    resize: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,

    pub fn add(self: *Wm, w: Window) u8 {
        const id = self.n;
        self.wins[id] = w;
        self.order[id] = id;
        self.n += 1;
        return id;
    }
    // Like add() but reuses a closed slot first and returns null when all
    // MAX_WIN windows are open (GEM: "The Desktop has no more windows").
    pub fn tryAdd(self: *Wm, w: Window) ?u8 {
        var i: u8 = 0;
        while (i < self.n) : (i += 1) {
            if (!self.wins[i].open) {
                self.wins[i] = w;
                self.toFront(i);
                return i;
            }
        }
        if (self.n >= MAX_WIN) return null;
        return self.add(w);
    }

    pub fn toFront(self: *Wm, id: u8) void {
        var i: usize = 0;
        while (i < self.n and self.order[i] != id) : (i += 1) {}
        while (i + 1 < self.n) : (i += 1) self.order[i] = self.order[i + 1];
        self.order[self.n - 1] = id;
    }

    // GEM window control boxes: close (title left), full (title right), size
    // (bottom-right corner, over the scrollbars).
    fn closeBox(w: *const Window) Rect {
        return .{ .x = w.r.x, .y = w.r.y, .w = glyphs.GW, .h = glyphs.GH };
    }
    fn fullBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - glyphs.GW, .y = w.r.y, .w = glyphs.GW, .h = glyphs.GH };
    }
    fn sizeBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - glyphs.GW, .y = w.r.y + w.r.h - glyphs.GH, .w = glyphs.GW, .h = glyphs.GH };
    }

    // Process pointer: dragging, resizing, and the close / full / size controls.
    // Returns true when this frame's press landed on a window (so the caller's
    // desktop must not treat it as a desktop click).
    pub fn handle(self: *Wm, g: *Gui) bool {
        if (self.drag != null) return self.handleDrag(g);
        if (self.resize != null) return self.handleResize(g);
        if (!g.edge) return false;
        return self.handlePress(g);
    }

    fn handleDrag(self: *Wm, g: *Gui) bool {
        const id = self.drag.?;
        if (!g.down) self.drag = null else {
            self.wins[id].r.x = @intCast(@as(i32, g.px) - self.grab_dx);
            // GEM never lets a title bar go up under the menu bar.
            self.wins[id].r.y = @max(MENU_H + 1, @as(i16, @intCast(@as(i32, g.py) - self.grab_dy)));
        }
        return true;
    }

    fn handleResize(self: *Wm, g: *Gui) bool {
        const id = self.resize.?;
        if (!g.down) self.resize = null else {
            const w = &self.wins[id];
            w.r.w = @max(MIN_W, @as(i16, @intCast(@as(i32, g.px) + self.grab_dx - w.r.x)));
            w.r.h = @max(MIN_H, @as(i16, @intCast(@as(i32, g.py) + self.grab_dy - w.r.y)));
        }
        return true;
    }

    fn handlePress(self: *Wm, g: *Gui) bool {
        var k: i32 = @as(i32, self.n) - 1;
        while (k >= 0) : (k -= 1) {
            const id = self.order[@intCast(k)];
            if (!self.wins[id].open) continue;
            if (self.pressWindow(id, g)) return true;
        }
        return false;
    }

    // A press fell somewhere on window `id`: dispatch to its controls or start a
    // drag/select. Returns true if the press was consumed by this window.
    fn pressWindow(self: *Wm, id: u8, g: *Gui) bool {
        const w = &self.wins[id];
        if (inRect(closeBox(w), g.px, g.py)) {
            w.open = false;
            return true;
        }
        if (inRect(fullBox(w), g.px, g.py)) {
            self.toFront(id);
            self.toggleFull(id, g);
            return true;
        }
        if (inRect(sizeBox(w), g.px, g.py)) {
            self.toFront(id);
            self.resize = id;
            self.grab_dx = (w.r.x + w.r.w) - @as(i16, @intCast(g.px));
            self.grab_dy = (w.r.y + w.r.h) - @as(i16, @intCast(g.py));
            return true;
        }
        if (inRect(.{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H }, g.px, g.py)) {
            self.toFront(id);
            self.drag = id;
            self.grab_dx = @intCast(@as(i32, g.px) - w.r.x);
            self.grab_dy = @intCast(@as(i32, g.py) - w.r.y);
            return true;
        }
        if (inRect(w.r, g.px, g.py)) {
            self.toFront(id);
            return true;
        }
        return false;
    }

    fn toggleFull(self: *Wm, id: u8, g: *Gui) void {
        const w = &self.wins[id];
        if (w.full) {
            w.r = w.saved;
            w.full = false;
        } else {
            w.saved = w.r;
            // GEM "full" = the desktop work area (everything below the menu bar).
            w.r = .{ .x = 0, .y = MENU_H + 1, .w = g.screen_w, .h = 200 - MENU_H - 1 };
            w.full = true;
        }
    }

    pub fn drawChrome(self: *Wm, g: *Gui, id: u8, active: bool) Rect {
        return chrome.draw(g, &self.wins[id], active);
    }

    // The interior content rect WITHOUT drawing (same math as drawChrome's return),
    // for laying out / hit-testing a window's contents.
    pub fn contentRect(self: *Wm, id: u8) Rect {
        const w = &self.wins[id];
        const top = types.topBarsH(w);
        return .{ .x = w.r.x + 1, .y = w.r.y + top, .w = w.r.w - 2 - types.SCROLL, .h = w.r.h - top - types.SCROLL };
    }

    pub fn topId(self: *Wm) u8 {
        return self.order[self.n - 1];
    }
};
