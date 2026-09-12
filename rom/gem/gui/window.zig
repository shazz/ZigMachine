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
    // GEM moves and resizes a window as a dotted OUTLINE and only commits the new
    // geometry on release (drawGhost paints it over the windows).
    ghost: ?Rect = null,
    // Has the pointer actually moved since the press? A plain CLICK on the mover
    // or the size gadget must leave the window exactly as it was — without this,
    // the pixel of jitter in a real click (doubled in low res) resizes it a step.
    moved: bool = false,
    press_x: i32 = 0,
    press_y: i32 = 0,
    // The window closed since the owner last looked (takeClosed). The owner uses
    // it to run the close animation; the Wm itself has no idea where a window
    // should shrink TO.
    closed: ?u8 = null,
    // A window that just grew to / shrank from full size, so the owner can run
    // the zoom-box animation between the two rects.
    zoomed: ?types.Zoom = null,
    // A scroll slider being dragged: which window, which axis, and how far into
    // the slider box the pointer grabbed it.
    slider: ?struct { id: u8, vertical: bool, grab: i16 } = null,

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
    // The four scroll arrow gadgets, in the same places chrome.scrollbars draws
    // them (up/down in the right gutter, left/right in the bottom one).
    fn upBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - glyphs.GW, .y = w.r.y + types.topBarsH(w) - 1, .w = glyphs.GW, .h = glyphs.GH };
    }
    fn downBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - glyphs.GW, .y = w.r.y + w.r.h - 2 * glyphs.GH + 1, .w = glyphs.GW, .h = glyphs.GH };
    }
    fn leftBox(w: *const Window) Rect {
        return .{ .x = w.r.x, .y = w.r.y + w.r.h - glyphs.GH, .w = glyphs.GW, .h = glyphs.GH };
    }
    fn rightBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - 2 * glyphs.GW + 1, .y = w.r.y + w.r.h - glyphs.GH, .w = glyphs.GW, .h = glyphs.GH };
    }

    // An arrow gadget steps the content by one unit (a row / a character cell),
    // clamped to the bounds the window's owner published in vmax / hmax.
    fn scrollPress(w: *Window, g: *Gui) bool {
        if (inRect(upBox(w), g.px, g.py)) {
            w.vscroll = @max(0, w.vscroll - 1);
        } else if (inRect(downBox(w), g.px, g.py)) {
            w.vscroll = @min(w.vmax, w.vscroll + 1);
        } else if (inRect(leftBox(w), g.px, g.py)) {
            w.hscroll = @max(0, w.hscroll - 1);
        } else if (inRect(rightBox(w), g.px, g.py)) {
            w.hscroll = @min(w.hmax, w.hscroll + 1);
        } else return false;
        return true;
    }

    // Process pointer: dragging, resizing, and the close / full / size controls.
    // Returns true when this frame's press landed on a window (so the caller's
    // desktop must not treat it as a desktop click).
    pub fn handle(self: *Wm, g: *Gui) bool {
        if (self.slider != null) return self.handleSlider(g);
        if (self.drag != null) return self.handleDrag(g);
        if (self.resize != null) return self.handleResize(g);
        if (!g.edge) return false;
        return self.handlePress(g);
    }

    fn handleDrag(self: *Wm, g: *Gui) bool {
        const w = &self.wins[self.drag.?];
        var r = w.r;
        r.x = @intCast(@as(i32, g.px) - self.grab_dx);
        // GEM never lets a title bar go up under the menu bar.
        r.y = @max(MENU_H + 1, @as(i16, @intCast(@as(i32, g.py) - self.grab_dy)));
        self.gesture(g, w, r, &self.drag);
        return true;
    }

    // Dragging a slider maps the pointer straight onto a scroll value; nothing is
    // deferred to release, so the content tracks the slider live.
    fn handleSlider(self: *Wm, g: *Gui) bool {
        const sl = self.slider.?;
        const w = &self.wins[sl.id];
        if (!g.down) {
            self.slider = null;
            return true;
        }
        if (sl.vertical) {
            w.vscroll = types.sliderScroll(types.vTrack(w), w.vslide, w.vmax, true, g.py, sl.grab);
        } else {
            w.hscroll = types.sliderScroll(types.hTrack(w), w.hslide, w.hmax, false, g.px, sl.grab);
        }
        return true;
    }

    // A press on a white slider box starts dragging it (the hatched part of the
    // track is not a target — GEM pages there, which nothing asks for yet).
    fn sliderPress(self: *Wm, id: u8, g: *Gui) bool {
        const w = &self.wins[id];
        if (w.vslide < 1000 and w.vmax > 0) {
            const b = types.sliderBox(types.vTrack(w), w.vslide, w.vscroll, w.vmax, true);
            if (inRect(b, g.px, g.py)) {
                self.slider = .{ .id = id, .vertical = true, .grab = @intCast(g.py - b.y) };
                return true;
            }
        }
        if (w.hslide < 1000 and w.hmax > 0) {
            const b = types.sliderBox(types.hTrack(w), w.hslide, w.hscroll, w.hmax, false);
            if (inRect(b, g.px, g.py)) {
                self.slider = .{ .id = id, .vertical = false, .grab = @intCast(g.px - b.x) };
                return true;
            }
        }
        return false;
    }

    fn handleResize(self: *Wm, g: *Gui) bool {
        const w = &self.wins[self.resize.?];
        var r = w.r;
        // GEM resizes in whole CHARACTER CELLS, so a window's contents stay on
        // the 8px grid they were laid out on instead of drifting a pixel at a time.
        r.w = cells(@max(w.min_w, @as(i16, @intCast(@as(i32, g.px) + self.grab_dx - w.r.x))));
        r.h = cells(@max(w.min_h, @as(i16, @intCast(@as(i32, g.py) + self.grab_dy - w.r.y))));
        self.gesture(g, w, r, &self.resize);
        return true;
    }

    // Round up to a whole 8px character cell.
    fn cells(v: i16) i16 {
        return @divTrunc(v + types.CELL - 1, types.CELL) * types.CELL;
    }

    // One frame of a move or a resize: show `r` as the dotted outline while the
    // button is held, and on release commit it — but only if this was a real
    // drag, so a click on the mover or the size gadget is a no-op.
    fn gesture(self: *Wm, g: *Gui, w: *Window, r: Rect, active: *?u8) void {
        if (g.px != self.press_x or g.py != self.press_y) self.moved = true;
        if (g.down) {
            if (self.moved) self.ghost = r;
            return;
        }
        if (self.moved) w.r = r;
        active.* = null;
        self.ghost = null;
    }

    // Arm a move/resize: remember where the press landed so `gesture` can tell a
    // click from a drag.
    fn armGesture(self: *Wm, g: *Gui) void {
        self.press_x = g.px;
        self.press_y = g.py;
        self.moved = false;
    }

    pub fn close(self: *Wm, id: u8) void {
        self.wins[id].open = false;
        self.closed = id;
    }
    // The window closed since the last call, if any (one-shot).
    pub fn takeClosed(self: *Wm) ?u8 {
        const c = self.closed;
        self.closed = null;
        return c;
    }

    // Paint the pending move/resize outline. Call it AFTER the windows are drawn.
    pub fn drawGhost(self: *Wm, g: *Gui) void {
        if (self.ghost) |r| g.dotted(r, types.BLACK);
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
            self.close(id);
            return true;
        }
        if (inRect(fullBox(w), g.px, g.py)) {
            self.toFront(id);
            self.toggleFull(id, g);
            return true;
        }
        if (self.sliderPress(id, g)) { // a white slider box: drag it
            self.toFront(id);
            return true;
        }
        if (scrollPress(w, g)) { // arrow gadgets sit over the window body
            self.toFront(id);
            return true;
        }
        if (inRect(sizeBox(w), g.px, g.py)) {
            self.toFront(id);
            self.resize = id;
            self.armGesture(g);
            self.grab_dx = (w.r.x + w.r.w) - @as(i16, @intCast(g.px));
            self.grab_dy = (w.r.y + w.r.h) - @as(i16, @intCast(g.py));
            return true;
        }
        if (inRect(.{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H }, g.px, g.py)) {
            self.toFront(id);
            self.drag = id;
            self.armGesture(g);
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
        const from = w.r;
        if (w.full) {
            w.r = w.saved;
            w.full = false;
        } else {
            w.saved = w.r;
            // GEM "full" = the desktop work area (everything below the menu bar).
            w.r = .{ .x = 0, .y = MENU_H + 1, .w = g.screen_w, .h = 200 - MENU_H - 1 };
            w.full = true;
        }
        self.zoomed = .{ .from = from, .to = w.r }; // owner animates the box
    }

    // The full-box zoom since the last call, if any (one-shot).
    pub fn takeZoom(self: *Wm) ?types.Zoom {
        const z = self.zoomed;
        self.zoomed = null;
        return z;
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

    // The frontmost OPEN window — GEM's active window. Closing a window leaves
    // its id in `order`, so scanning from the back and skipping closed slots is
    // what promotes the next window to active; without it the last window left on
    // screen would keep drawing with an inactive (unhatched) title bar.
    pub fn topOpen(self: *Wm) ?u8 {
        var i: usize = self.n;
        while (i > 0) {
            i -= 1;
            if (self.wins[self.order[i]].open) return self.order[i];
        }
        return null;
    }
};
