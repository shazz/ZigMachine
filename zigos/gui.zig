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
};

pub const Wm = struct {
    wins: [MAX_WIN]Window = undefined,
    order: [MAX_WIN]u8 = undefined, // back-to-front draw order (indices into wins)
    n: u8 = 0,
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,

    pub fn add(self: *Wm, w: Window) u8 {
        const id = self.n;
        self.wins[id] = w;
        self.order[id] = id;
        self.n += 1;
        return id;
    }

    fn toFront(self: *Wm, id: u8) void {
        var i: usize = 0;
        while (i < self.n and self.order[i] != id) : (i += 1) {}
        while (i + 1 < self.n) : (i += 1) self.order[i] = self.order[i + 1];
        self.order[self.n - 1] = id;
    }

    // Process pointer: start/continue/stop dragging, handle close boxes. Call
    // once per frame before drawing.
    pub fn handle(self: *Wm, g: *Gui) void {
        if (self.drag) |id| {
            if (!g.down) {
                self.drag = null;
            } else {
                self.wins[id].r.x = @intCast(@as(i32, g.px) - self.grab_dx);
                self.wins[id].r.y = @intCast(@as(i32, g.py) - self.grab_dy);
            }
            return;
        }
        if (!g.edge) return;
        // Top-most window under the pointer wins the press.
        var k: i32 = @as(i32, self.n) - 1;
        while (k >= 0) : (k -= 1) {
            const id = self.order[@intCast(k)];
            const w = &self.wins[id];
            if (!w.open) continue;
            const titleBar = Rect{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H };
            const closeBox = Rect{ .x = w.r.x + 1, .y = w.r.y + 1, .w = 10, .h = TITLE_H - 2 };
            if (inRect(closeBox, g.px, g.py)) {
                w.open = false;
                return;
            }
            if (inRect(titleBar, g.px, g.py)) {
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

    // Draw a window's frame + title bar; returns the interior content rect. Draw
    // your content into it after calling this. `active` = topmost/focused window.
    pub fn drawChrome(self: *Wm, g: *Gui, id: u8, active: bool) Rect {
        const w = self.wins[id];
        g.rect(w.r, WHITE);
        g.frame(w.r, BLACK);
        const bar = Rect{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = TITLE_H };
        g.rect(.{ .x = bar.x + 1, .y = bar.y + 1, .w = bar.w - 2, .h = bar.h - 1 }, if (active) LGRAY else WHITE);
        g.blit.fill(g.fb, bar.x, bar.y + bar.h - 1, @intCast(bar.w), 1, BLACK); // title underline
        // close box
        g.bevel(.{ .x = bar.x + 1, .y = bar.y + 1, .w = 10, .h = TITLE_H - 2 }, WHITE, true);
        g.blit.fill(g.fb, bar.x + 4, bar.y + 5, 4, 2, BLACK);
        g.text(w.title, bar.x + 16, bar.y + 3, BLACK, if (active) LGRAY else WHITE);
        return .{ .x = w.r.x + 1, .y = w.r.y + TITLE_H, .w = w.r.w - 2, .h = w.r.h - TITLE_H - 1 };
    }

    pub fn topId(self: *Wm) u8 {
        return self.order[self.n - 1];
    }
};
