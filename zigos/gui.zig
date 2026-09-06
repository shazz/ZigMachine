// --------------------------------------------------------------------------
// ZigOS GUI — a small GEM-style windowing toolkit (open library).
//
// Immediate-mode drawing over the blitter (fast fills) + ZigOS text, plus a
// tiny retained window manager (draggable title bars, close boxes, z-order).
// Pointer state comes from the host via demo.pointer() (see sealed-loader.js).
//
// Resolution-agnostic: everything is in the visible 320x200 space; a future
// medium-res HW mode would widen it without changing this code.
// --------------------------------------------------------------------------
const std = @import("std");
const zsrc = @import("zigos.zig");
const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Color = zsrc.Color;

// GEM-ish palette (installed on the plane by installPalette).
pub const BLACK: u8 = 0;
pub const WHITE: u8 = 1;
pub const LGRAY: u8 = 2;
pub const MGRAY: u8 = 3;
pub const DGRAY: u8 = 4;
pub const DESK: u8 = 5;
pub const ACCENT: u8 = 6;
pub const WAVE: u8 = 7;

pub fn installPalette(fb: *LogicalFB) void {
    fb.setPaletteEntry(BLACK, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.setPaletteEntry(WHITE, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    fb.setPaletteEntry(LGRAY, .{ .r = 200, .g = 200, .b = 200, .a = 255 });
    fb.setPaletteEntry(MGRAY, .{ .r = 140, .g = 140, .b = 140, .a = 255 });
    fb.setPaletteEntry(DGRAY, .{ .r = 80, .g = 80, .b = 80, .a = 255 });
    fb.setPaletteEntry(DESK, .{ .r = 0, .g = 150, .b = 90, .a = 255 });
    fb.setPaletteEntry(ACCENT, .{ .r = 40, .g = 90, .b = 220, .a = 255 });
    fb.setPaletteEntry(WAVE, .{ .r = 60, .g = 230, .b = 140, .a = 255 });
}

pub const Rect = struct { x: i16, y: i16, w: i16, h: i16 };

fn inRect(r: Rect, px: i32, py: i32) bool {
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h;
}

// --------------------------------------------------------------------------
// Gui — pointer state + drawing primitives, held for one frame.
// --------------------------------------------------------------------------
pub const Gui = struct {
    os: *ZigOS,
    fb: *LogicalFB,
    blit: *Blitter,
    screen_w: i16 = 320, // set to 640 for a medium-res app (centres dialogs etc.)
    screen_h: i16 = 200,
    px: i32 = -1,
    py: i32 = -1,
    down: bool = false,
    prev: bool = false,
    edge: bool = false, // press started this frame

    pub fn setPointer(self: *Gui, x: i32, y: i32, buttons: u32) void {
        self.px = x;
        self.py = y;
        self.down = buttons != 0;
    }
    pub fn beginFrame(self: *Gui) void {
        self.edge = self.down and !self.prev;
    }
    pub fn endFrame(self: *Gui) void {
        self.prev = self.down;
    }

    // --- primitives ---
    pub fn rect(self: *Gui, r: Rect, color: u8) void {
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), @intCast(r.h), color);
    }
    pub fn frame(self: *Gui, r: Rect, color: u8) void {
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), 1, color);
        self.blit.fill(self.fb, r.x, r.y + r.h - 1, @intCast(r.w), 1, color);
        self.blit.fill(self.fb, r.x, r.y, 1, @intCast(r.h), color);
        self.blit.fill(self.fb, r.x + r.w - 1, r.y, 1, @intCast(r.h), color);
    }
    // A raised (or sunken) 3D bevel box — the GEM button look.
    pub fn bevel(self: *Gui, r: Rect, face: u8, raised: bool) void {
        const hi: u8 = if (raised) WHITE else DGRAY;
        const lo: u8 = if (raised) DGRAY else WHITE;
        self.rect(r, face);
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), 1, hi);
        self.blit.fill(self.fb, r.x, r.y, 1, @intCast(r.h), hi);
        self.blit.fill(self.fb, r.x, r.y + r.h - 1, @intCast(r.w), 1, lo);
        self.blit.fill(self.fb, r.x + r.w - 1, r.y, 1, @intCast(r.h), lo);
    }
    pub fn text(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        self.os.printText(self.fb, s, @intCast(x), @intCast(y), ink, paper);
    }

    pub fn hit(self: *Gui, r: Rect) bool {
        return inRect(r, self.px, self.py);
    }
    // A clickable bevel button; returns true on the frame the press lands inside.
    pub fn button(self: *Gui, r: Rect, label: []const u8, active: bool) bool {
        const held = active or (self.down and self.hit(r));
        self.bevel(r, if (active) LGRAY else WHITE, !held);
        const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
        self.text(label, tx, r.y + @divTrunc(r.h - 8, 2) + 1, BLACK, if (active) LGRAY else WHITE);
        return self.edge and self.hit(r);
    }
};

// --------------------------------------------------------------------------
// Window manager — draggable windows with a title bar, close + full boxes.
// --------------------------------------------------------------------------
pub const TITLE_H: i16 = 12;
pub const MAX_WIN = 6;

pub const Window = struct {
    r: Rect,
    title: []const u8,
    open: bool = true,
    full: bool = false, // toggled by the full box
    saved: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // rect to restore from full
};

pub const SCROLL: i16 = 11; // scrollbar gutter / control size
const MIN_W: i16 = 64;
const MIN_H: i16 = 44;

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

    pub fn toFront(self: *Wm, id: u8) void {
        var i: usize = 0;
        while (i < self.n and self.order[i] != id) : (i += 1) {}
        while (i + 1 < self.n) : (i += 1) self.order[i] = self.order[i + 1];
        self.order[self.n - 1] = id;
    }

    // GEM window control boxes: close (title left), full (title right), size
    // (bottom-right corner, over the scrollbars).
    fn closeBox(w: *const Window) Rect {
        return .{ .x = w.r.x + 1, .y = w.r.y + 1, .w = SCROLL, .h = TITLE_H - 2 };
    }
    fn fullBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - SCROLL - 1, .y = w.r.y + 1, .w = SCROLL, .h = TITLE_H - 2 };
    }
    fn sizeBox(w: *const Window) Rect {
        return .{ .x = w.r.x + w.r.w - SCROLL, .y = w.r.y + w.r.h - SCROLL, .w = SCROLL, .h = SCROLL };
    }

    // Process pointer: dragging, resizing, and the close / full / size controls.
    pub fn handle(self: *Wm, g: *Gui) void {
        if (self.drag) |id| {
            if (!g.down) self.drag = null else {
                self.wins[id].r.x = @intCast(@as(i32, g.px) - self.grab_dx);
                self.wins[id].r.y = @intCast(@as(i32, g.py) - self.grab_dy);
            }
            return;
        }
        if (self.resize) |id| {
            if (!g.down) self.resize = null else {
                const w = &self.wins[id];
                w.r.w = @max(MIN_W, @as(i16, @intCast(@as(i32, g.px) + self.grab_dx - w.r.x)));
                w.r.h = @max(MIN_H, @as(i16, @intCast(@as(i32, g.py) + self.grab_dy - w.r.y)));
            }
            return;
        }
        if (!g.edge) return;
        var k: i32 = @as(i32, self.n) - 1;
        while (k >= 0) : (k -= 1) {
            const id = self.order[@intCast(k)];
            const w = &self.wins[id];
            if (!w.open) continue;
            if (inRect(closeBox(w), g.px, g.py)) {
                w.open = false;
                return;
            }
            if (inRect(fullBox(w), g.px, g.py)) {
                self.toFront(id);
                self.toggleFull(id, g);
                return;
            }
            if (inRect(sizeBox(w), g.px, g.py)) {
                self.toFront(id);
                self.resize = id;
                self.grab_dx = (w.r.x + w.r.w) - @as(i16, @intCast(g.px));
                self.grab_dy = (w.r.y + w.r.h) - @as(i16, @intCast(g.py));
                return;
            }
            if (inRect(.{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H }, g.px, g.py)) {
                self.toFront(id);
                self.drag = id;
                self.grab_dx = @intCast(@as(i32, g.px) - w.r.x);
                self.grab_dy = @intCast(@as(i32, g.py) - w.r.y);
                return;
            }
            if (inRect(w.r, g.px, g.py)) {
                self.toFront(id);
                return;
            }
        }
    }

    fn toggleFull(self: *Wm, id: u8, g: *Gui) void {
        const w = &self.wins[id];
        if (w.full) {
            w.r = w.saved;
            w.full = false;
        } else {
            w.saved = w.r;
            w.r = .{ .x = 1, .y = TITLE_H + 1, .w = g.screen_w - 2, .h = 200 - TITLE_H - 2 };
            w.full = true;
        }
    }

    // Draw a window's frame + title bar (close left, full right) + scrollbar
    // gutters + size box; returns the interior content rect (inside the bars).
    pub fn drawChrome(self: *Wm, g: *Gui, id: u8, active: bool) Rect {
        const w = self.wins[id];
        g.rect(w.r, WHITE);
        g.frame(w.r, BLACK);
        const bar = Rect{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H };
        g.rect(.{ .x = bar.x + 1, .y = bar.y + 1, .w = bar.w - 2, .h = bar.h - 1 }, if (active) LGRAY else WHITE);
        g.blit.fill(g.fb, bar.x, bar.y + bar.h - 1, @intCast(bar.w), 1, BLACK); // title underline
        // close box (left)
        const cb = closeBox(&w);
        g.bevel(cb, WHITE, true);
        g.blit.fill(g.fb, cb.x + 3, cb.y + 3, SCROLL - 6, 3, BLACK);
        // full box (right)
        const fbx = fullBox(&w);
        g.bevel(fbx, WHITE, true);
        g.frame(.{ .x = fbx.x + 2, .y = fbx.y + 2, .w = SCROLL - 4, .h = TITLE_H - 6 }, BLACK);
        g.text(w.title, bar.x + 16, bar.y + 3, BLACK, if (active) LGRAY else WHITE);
        // scrollbar gutters (right + bottom) + size box
        g.rect(.{ .x = w.r.x + w.r.w - SCROLL, .y = w.r.y + TITLE_H, .w = SCROLL, .h = w.r.h - TITLE_H - SCROLL }, LGRAY);
        g.rect(.{ .x = w.r.x + 1, .y = w.r.y + w.r.h - SCROLL, .w = w.r.w - 2 - SCROLL, .h = SCROLL }, LGRAY);
        const sb = sizeBox(&w);
        g.bevel(sb, WHITE, true);
        g.blit.fill(g.fb, sb.x + 3, sb.y + 3, SCROLL - 5, SCROLL - 5, BLACK);
        return .{ .x = w.r.x + 1, .y = w.r.y + TITLE_H, .w = w.r.w - 2 - SCROLL, .h = w.r.h - TITLE_H - SCROLL };
    }

    pub fn topId(self: *Wm) u8 {
        return self.order[self.n - 1];
    }
};

// --------------------------------------------------------------------------
// Modal dialog — a centred GEM box: an alert (message + OK) or a file selector
// (a list + Cancel). While active it owns all input; process() returns a result
// on the frame the user chooses. Draw it LAST, over everything.
// --------------------------------------------------------------------------
pub const DlgResult = union(enum) { none, ok: u8, cancel };

pub const Dialog = struct {
    active: bool = false,
    filesel: bool = false,
    title: []const u8 = "",
    msg: []const u8 = "",
    items: []const []const u8 = &.{},
    want_w: i16 = 0,
    want_h: i16 = 0,

    pub fn alert(self: *Dialog, title: []const u8, msg: []const u8) void {
        self.* = .{ .active = true, .filesel = false, .title = title, .msg = msg };
        self.want_w = @max(@as(i16, @intCast(msg.len)), @as(i16, @intCast(title.len))) * 8 + 40;
        self.want_h = 62;
    }
    pub fn openFiles(self: *Dialog, title: []const u8, items: []const []const u8) void {
        self.* = .{ .active = true, .filesel = true, .title = title, .items = items };
        self.want_w = 220;
        self.want_h = @as(i16, @intCast(items.len)) * MENU_H + 52;
    }

    pub fn process(self: *Dialog, g: *Gui) DlgResult {
        if (!self.active) return .none;
        const b = Rect{ .x = @divTrunc(g.screen_w - self.want_w, 2), .y = @divTrunc(g.screen_h - self.want_h, 2), .w = self.want_w, .h = self.want_h };
        g.bevel(b, WHITE, true);
        g.rect(.{ .x = b.x + 1, .y = b.y + 1, .w = b.w - 2, .h = 9 }, LGRAY);
        g.text(self.title, b.x + 6, b.y + 2, BLACK, LGRAY);
        var res: DlgResult = .none;
        if (self.filesel) {
            for (self.items, 0..) |it, j| {
                const iy = b.y + 13 + @as(i16, @intCast(j)) * MENU_H;
                const row = Rect{ .x = b.x + 4, .y = iy, .w = b.w - 8, .h = MENU_H };
                const hover = g.hit(row);
                if (hover) g.rect(row, ACCENT);
                g.text(it, b.x + 8, iy + 2, if (hover) WHITE else BLACK, if (hover) ACCENT else WHITE);
                if (g.edge and hover) res = .{ .ok = @intCast(j) };
            }
            if (g.button(.{ .x = b.x + b.w - 60, .y = b.y + b.h - 20, .w = 52, .h = 15 }, "Cancel", false)) res = .cancel;
        } else {
            g.text(self.msg, b.x + 12, b.y + 22, BLACK, WHITE);
            if (g.button(.{ .x = b.x + @divTrunc(b.w - 40, 2), .y = b.y + b.h - 20, .w = 40, .h = 15 }, "OK", false)) res = .{ .ok = 0 };
        }
        if (res != .none) self.active = false;
        return res;
    }
};

// --------------------------------------------------------------------------
// Menu bar — GEM-style pull-down menus. Click a title to drop it, click an item
// to pick it (returns {menu,item}), click away to close. Draw it LAST each frame
// so an open drop-down overlays the windows.
// --------------------------------------------------------------------------
pub const MENU_H: i16 = 11;
pub const Menu = struct { title: []const u8, items: []const []const u8 };
pub const MenuPick = struct { menu: u8, item: u8 };

pub const MenuBar = struct {
    open: i16 = -1, // index of the dropped menu, -1 = none

    pub fn process(self: *MenuBar, g: *Gui, menus: []const Menu, bar_w: i16, locked: bool) ?MenuPick {
        if (locked) self.open = -1; // a modal dialog owns input — bar is inert
        g.rect(.{ .x = 0, .y = 0, .w = bar_w, .h = MENU_H }, WHITE);
        g.blit.fill(g.fb, 0, MENU_H, @intCast(bar_w), 1, BLACK);
        if (locked) {
            var x: i16 = 8;
            for (menus) |m| {
                g.text(m.title, x, 2, BLACK, WHITE);
                x += @as(i16, @intCast(m.title.len)) * 8 + 12 + 6;
            }
            return null;
        }

        var x: i16 = 8;
        var pick: ?MenuPick = null;
        for (menus, 0..) |m, i| {
            const w: i16 = @as(i16, @intCast(m.title.len)) * 8 + 12;
            const hot = self.open == @as(i16, @intCast(i));
            if (hot) g.rect(.{ .x = x - 4, .y = 0, .w = w, .h = MENU_H }, BLACK);
            g.text(m.title, x, 2, if (hot) WHITE else BLACK, if (hot) BLACK else WHITE);
            if (g.edge and g.px >= x - 4 and g.px < x - 4 + w and g.py < MENU_H)
                self.open = if (hot) -1 else @intCast(i);
            if (self.open == @as(i16, @intCast(i))) pick = self.drop(g, m, i, x - 4);
            x += w + 6;
        }
        // click anywhere outside the bar and the open menu closes it
        if (g.edge and self.open >= 0 and g.py >= MENU_H and pick == null and !self.overDrop(g, menus, x))
            self.open = -1;
        if (pick != null) self.open = -1;
        return pick;
    }

    fn dropWidth(m: Menu) i16 {
        var w: i16 = 0;
        for (m.items) |it| w = @max(w, @as(i16, @intCast(it.len)));
        return w * 8 + 16;
    }

    fn drop(self: *MenuBar, g: *Gui, m: Menu, mi: usize, dx: i16) ?MenuPick {
        _ = self;
        const dw = dropWidth(m);
        const dh: i16 = @as(i16, @intCast(m.items.len)) * MENU_H + 2;
        g.rect(.{ .x = dx, .y = MENU_H, .w = dw, .h = dh }, WHITE);
        g.frame(.{ .x = dx, .y = MENU_H, .w = dw, .h = dh }, BLACK);
        var pick: ?MenuPick = null;
        for (m.items, 0..) |it, j| {
            const iy = MENU_H + 1 + @as(i16, @intCast(j)) * MENU_H;
            const hover = g.px >= dx and g.px < dx + dw and g.py >= iy and g.py < iy + MENU_H;
            if (hover) g.rect(.{ .x = dx + 1, .y = iy, .w = dw - 2, .h = MENU_H }, BLACK);
            g.text(it, dx + 8, iy + 2, if (hover) WHITE else BLACK, if (hover) BLACK else WHITE);
            if (g.edge and hover) pick = .{ .menu = @intCast(mi), .item = @intCast(j) };
        }
        return pick;
    }

    // Is the pointer over the currently-open drop-down (so a click shouldn't close)?
    fn overDrop(self: *MenuBar, g: *Gui, menus: []const Menu, bar_end_x: i16) bool {
        _ = bar_end_x;
        if (self.open < 0) return false;
        var x: i16 = 8;
        for (menus, 0..) |m, i| {
            const w: i16 = @as(i16, @intCast(m.title.len)) * 8 + 12;
            if (self.open == @as(i16, @intCast(i))) {
                const dw = dropWidth(m);
                const dh: i16 = @as(i16, @intCast(m.items.len)) * MENU_H + 2;
                return g.px >= x - 4 and g.px < x - 4 + dw and g.py >= MENU_H and g.py < MENU_H + dh;
            }
            x += w + 6;
        }
        return false;
    }
};
