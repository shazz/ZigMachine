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
const glyphs = @import("gem_glyphs.zig"); // GEM window-control bitmaps (close/full/arrows/size)

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
    // A raised (or sunken) 3D bevel box (TOS 4 / MagiC look — NOT used by the
    // TOS 1.x-style chrome, kept for apps that want it).
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
    // 6x6 system font (icon labels).
    pub fn textSmall(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        self.os.printTextSmall(self.fb, s, @intCast(x), @intCast(y), ink, paper);
    }

    // Blit a GEM control gadget (a GWxGH box lifted verbatim from the ST GEM
    // reference: frame + background + symbol) opaquely at (x,y). 1 = ink, 0 = paper.
    pub fn gadget(self: *Gui, x: i16, y: i16, box: [glyphs.GH]u16, ink: u8, paper: u8) void {
        for (box, 0..) |bits, row| {
            var col: u4 = 0;
            while (col < glyphs.GW) : (col += 1) {
                const on = (bits >> @intCast(glyphs.GW - 1 - col)) & 1 != 0;
                self.fb.setPixelValue(@intCast(x + col), @intCast(y + @as(i16, @intCast(row))), if (on) ink else paper);
            }
        }
    }

    // GEM "grey" pattern fill — the title-bar mover / scrollbar track. Lifted
    // from the ST reference: one ink dot on every even row at every odd column
    // (25%), aligned to SCREEN coordinates like a VDI pattern fill.
    pub fn hatch(self: *Gui, r: Rect, ink: u8, paper: u8) void {
        self.rect(r, paper);
        var yy: i16 = r.y;
        while (yy < r.y + r.h) : (yy += 1) {
            if (yy & 1 != 0) continue;
            var xx: i16 = r.x | 1;
            while (xx < r.x + r.w) : (xx += 2)
                self.fb.setPixelValue(@intCast(xx), @intCast(yy), ink);
        }
    }

    pub fn hit(self: *Gui, r: Rect) bool {
        return inRect(r, self.px, self.py);
    }
    // A flat GEM (TOS 1.x) button: white box, 1px black border, inverse video
    // while pressed or `active` (SELECTED). Returns true on the press frame.
    pub fn button(self: *Gui, r: Rect, label: []const u8, active: bool) bool {
        return self.buttonEx(r, label, active, false);
    }
    // `default` = the GEM default exit button: a solid 2px border (the outer
    // frame plus a second frame 1px inside it).
    pub fn buttonEx(self: *Gui, r: Rect, label: []const u8, active: bool, default: bool) bool {
        const held = active or (self.down and self.hit(r));
        const ink: u8 = if (held) WHITE else BLACK;
        const paper: u8 = if (held) BLACK else WHITE;
        self.rect(r, paper);
        self.frame(r, BLACK);
        if (default) self.frame(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 }, BLACK);
        const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
        self.text(label, tx, r.y + @divTrunc(r.h - 8, 2), ink, paper);
        return self.edge and self.hit(r);
    }
    // A flat GEM button with an explicit border thickness (nested frames). GEM
    // dialogs use 1px for multi-choice buttons, 2px for a normal exit button,
    // 3px for the default (OK). Inverse-video while pressed or `active`.
    pub fn buttonThick(self: *Gui, r: Rect, label: []const u8, active: bool, border: i16) bool {
        const held = active or (self.down and self.hit(r));
        const ink: u8 = if (held) WHITE else BLACK;
        const paper: u8 = if (held) BLACK else WHITE;
        self.rect(r, paper);
        var i: i16 = 0;
        while (i < border) : (i += 1)
            self.frame(.{ .x = r.x + i, .y = r.y + i, .w = r.w - 2 * i, .h = r.h - 2 * i }, BLACK);
        const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
        self.text(label, tx, r.y + @divTrunc(r.h - 8, 2), ink, paper);
        return self.edge and self.hit(r);
    }
};

// --------------------------------------------------------------------------
// Window manager — draggable windows with a title bar, close + full boxes.
// --------------------------------------------------------------------------
// Title bar = the 12x11 gadget box height: frame line, 9 rows, frame line
// (the reference has H lines at logical rows 0 and 10). An optional info line
// (GEM "bytes used in N items") is another bar of the same height below it.
pub const TITLE_H: i16 = glyphs.GH;
pub const INFO_H: i16 = glyphs.GH - 1; // shares its top line with the title bar
pub const MAX_WIN = 7; // GEM Desktop: 7 windows

pub const Window = struct {
    r: Rect,
    title: []const u8,
    info: []const u8 = "", // info line under the title (empty = none)
    open: bool = true,
    full: bool = false, // toggled by the full box
    saved: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // rect to restore from full
};

pub const SCROLL: i16 = glyphs.GW; // scrollbar gutter / gadget size (matches the extracted 12px boxes)
const MIN_W: i16 = 64;
const MIN_H: i16 = 44;

fn topBarsH(w: *const Window) i16 {
    return if (w.info.len > 0) TITLE_H + INFO_H else TITLE_H;
}

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
        if (self.drag) |id| {
            if (!g.down) self.drag = null else {
                self.wins[id].r.x = @intCast(@as(i32, g.px) - self.grab_dx);
                // GEM never lets a title bar go up under the menu bar.
                self.wins[id].r.y = @max(MENU_H + 1, @as(i16, @intCast(@as(i32, g.py) - self.grab_dy)));
            }
            return true;
        }
        if (self.resize) |id| {
            if (!g.down) self.resize = null else {
                const w = &self.wins[id];
                w.r.w = @max(MIN_W, @as(i16, @intCast(@as(i32, g.px) + self.grab_dx - w.r.x)));
                w.r.h = @max(MIN_H, @as(i16, @intCast(@as(i32, g.py) + self.grab_dy - w.r.y)));
            }
            return true;
        }
        if (!g.edge) return false;
        var k: i32 = @as(i32, self.n) - 1;
        while (k >= 0) : (k -= 1) {
            const id = self.order[@intCast(k)];
            const w = &self.wins[id];
            if (!w.open) continue;
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

    // Draw a window's drop shadow + frame + title bar (close left, full right) +
    // optional info line + scrollbars + size box; returns the interior content
    // rect (inside the bars). The reference window carries a 2px black drop
    // shadow (right + bottom), offset from the top-left corner.
    pub fn drawChrome(self: *Wm, g: *Gui, id: u8, active: bool) Rect {
        const w = self.wins[id];
        g.rect(.{ .x = w.r.x + w.r.w, .y = w.r.y + 2, .w = 2, .h = w.r.h }, BLACK);
        g.rect(.{ .x = w.r.x + 2, .y = w.r.y + w.r.h, .w = w.r.w, .h = 2 }, BLACK);
        g.rect(w.r, WHITE);
        g.frame(w.r, BLACK);
        titleBar(g, &w, active);
        if (w.info.len > 0) infoLine(g, &w);
        scrollbars(g, &w);
        const top = topBarsH(&w);
        return .{ .x = w.r.x + 1, .y = w.r.y + top, .w = w.r.w - 2 - SCROLL, .h = w.r.h - top - SCROLL };
    }

    // Title bar, per the ST reference: gadget boxes at both ends, a 1px black
    // line bounding the mover on each side, the grey mover pattern (active
    // window only), and the title on a clear patch one char cell wider each side.
    fn titleBar(g: *Gui, w: *const Window, active: bool) void {
        const bar = Rect{ .x = w.r.x + glyphs.GW, .y = w.r.y + 1, .w = w.r.w - 2 * glyphs.GW, .h = TITLE_H - 2 };
        if (active) g.hatch(bar, BLACK, WHITE) else g.rect(bar, WHITE);
        g.blit.fill(g.fb, bar.x, bar.y, 1, @intCast(bar.h), BLACK); // mover left bound
        g.blit.fill(g.fb, bar.x + bar.w - 1, bar.y, 1, @intCast(bar.h), BLACK); // mover right bound
        g.blit.fill(g.fb, w.r.x, w.r.y + TITLE_H - 1, @intCast(w.r.w), 1, BLACK); // underline
        const tw: i16 = @as(i16, @intCast(w.title.len)) * 8;
        const tx = w.r.x + @divTrunc(w.r.w - tw, 2);
        g.rect(.{ .x = tx - 8, .y = bar.y, .w = tw + 16, .h = bar.h }, WHITE); // clear patch
        g.text(w.title, tx, w.r.y + 2, BLACK, WHITE);
        g.gadget(w.r.x, w.r.y, glyphs.CLOSE, BLACK, WHITE);
        g.gadget(w.r.x + w.r.w - glyphs.GW, w.r.y, glyphs.FULL, BLACK, WHITE);
    }

    // GEM info line: plain text, one char row, closed by a 1px line.
    fn infoLine(g: *Gui, w: *const Window) void {
        const y = w.r.y + TITLE_H;
        g.text(w.info, w.r.x + 2, y + 1, BLACK, WHITE); // 1px lower, like the title
        g.blit.fill(g.fb, w.r.x, y + INFO_H - 1, @intCast(w.r.w), 1, BLACK);
    }

    // Right + bottom scrollbars: real ST arrow gadgets sharing frame lines with
    // their neighbours (as in the reference), grey tracks, and white sliders
    // that fill the track (nothing scrolls yet), plus the size gadget.
    fn scrollbars(g: *Gui, w: *const Window) void {
        const rx = w.r.x + w.r.w - glyphs.GW;
        const by = w.r.y + w.r.h - glyphs.GH;
        // right gutter: up gadget shares the bar's bottom line, down gadget the size box's top line
        const uy = w.r.y + topBarsH(w) - 1;
        const dy = by - glyphs.GH + 1;
        fullSlider(g, .{ .x = rx, .y = uy + glyphs.GH - 1, .w = glyphs.GW, .h = dy - uy - glyphs.GH + 2 });
        g.gadget(rx, uy, glyphs.UP, BLACK, WHITE);
        g.gadget(rx, dy, glyphs.DOWN, BLACK, WHITE);
        // bottom gutter: left gadget shares the frame, right gadget the size box's left line
        const lx = w.r.x;
        const rrx = rx - glyphs.GW + 1;
        fullSlider(g, .{ .x = lx + glyphs.GW - 1, .y = by, .w = rrx - lx - glyphs.GW + 2, .h = glyphs.GH });
        g.gadget(lx, by, glyphs.LEFT, BLACK, WHITE);
        g.gadget(rrx, by, glyphs.RIGHT, BLACK, WHITE);
        g.gadget(rx, by, glyphs.SIZE, BLACK, WHITE);
    }

    // A scroll track whose slider box (white, 1px frame) fills it — GEM's look
    // when the content fits. The rect INCLUDES the shared frame lines of the
    // boxes at both ends, so it draws as plain white with no inner lines, as in
    // the reference. (A partial slider would sit on a hatch() grey track.)
    fn fullSlider(g: *Gui, track: Rect) void {
        g.rect(track, WHITE);
        g.frame(track, BLACK);
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

    const ROW_H: i16 = 8; // one char cell per list row (GEM item selector)
    const BTN_H: i16 = 12; // GEM alert buttons are one char row + border

    // GEM alerts have no title bar — `title` is drawn as the first text line.
    pub fn alert(self: *Dialog, title: []const u8, msg: []const u8) void {
        self.* = .{ .active = true, .filesel = false, .title = title, .msg = msg };
        self.want_w = @max(@as(i16, @intCast(msg.len)), @as(i16, @intCast(title.len))) * 8 + 32;
        self.want_h = 56;
    }
    pub fn openFiles(self: *Dialog, title: []const u8, items: []const []const u8) void {
        self.* = .{ .active = true, .filesel = true, .title = title, .items = items };
        self.want_w = 220;
        self.want_h = @as(i16, @intCast(items.len)) * ROW_H + 44;
    }

    // Box: white with a GEM double frame (outer + inner), no shadow — dialogs are
    // flat; only windows cast a drop shadow.
    fn box(g: *Gui, b: Rect) void {
        g.rect(b, WHITE);
        g.frame(b, BLACK);
        g.frame(.{ .x = b.x + 3, .y = b.y + 3, .w = b.w - 6, .h = b.h - 6 }, BLACK);
    }

    pub fn process(self: *Dialog, g: *Gui) DlgResult {
        if (!self.active) return .none;
        const b = Rect{ .x = @divTrunc(g.screen_w - self.want_w, 2), .y = @divTrunc(g.screen_h - self.want_h, 2), .w = self.want_w, .h = self.want_h };
        box(g, b);
        g.text(self.title, b.x + 8, b.y + 8, BLACK, WHITE);
        const res = if (self.filesel) self.fileList(g, b) else self.alertBody(g, b);
        if (res != .none) self.active = false;
        return res;
    }

    fn alertBody(self: *Dialog, g: *Gui, b: Rect) DlgResult {
        g.text(self.msg, b.x + 8, b.y + 20, BLACK, WHITE);
        const ok = Rect{ .x = b.x + @divTrunc(b.w - 56, 2), .y = b.y + b.h - 22, .w = 56, .h = 14 };
        return if (g.buttonThick(ok, "OK", false, 3)) .{ .ok = 0 } else .none;
    }

    // List rows: plain text, inverse video only while the button is held over
    // a row (GEM has no hover highlight); the press picks the row.
    fn fileList(self: *Dialog, g: *Gui, b: Rect) DlgResult {
        var res: DlgResult = .none;
        for (self.items, 0..) |it, j| {
            const row = Rect{ .x = b.x + 8, .y = b.y + 20 + @as(i16, @intCast(j)) * ROW_H, .w = b.w - 16, .h = ROW_H };
            const held = g.down and g.hit(row);
            if (held) g.rect(row, BLACK);
            g.text(it, row.x + 8, row.y, if (held) WHITE else BLACK, if (held) BLACK else WHITE);
            if (g.edge and held) res = .{ .ok = @intCast(j) };
        }
        const cancel = Rect{ .x = b.x + b.w - 64, .y = b.y + b.h - BTN_H - 8, .w = 56, .h = BTN_H };
        if (g.buttonThick(cancel, "Cancel", false, 2)) res = .cancel;
        return res;
    }
};

// --------------------------------------------------------------------------
// Menu bar — GEM-style pull-down menus. Click a title to drop it, click an item
// to pick it (returns {menu,item}), click away to close. Draw it LAST each frame
// so an open drop-down overlays the windows.
// --------------------------------------------------------------------------
// GEM: the bar is gl_hbox = char height + 3 = 11 rows in low/medium res —
// 10 white rows (text on row 1) closed by a black line on row MENU_H; the
// desktop work area starts at MENU_H + 1. Titles are laid out as " Desk  File "
// (one space each side), items are dense 8px char rows.
pub const MENU_H: i16 = 10;
pub const ITEM_H: i16 = 8;
const TITLE_X0: i16 = 8; // first title starts one char cell in
const PAD: i16 = 8; // one char cell each side of a title (its highlight box)
pub const Menu = struct { title: []const u8, items: []const []const u8 };
pub const MenuPick = struct { menu: u8, item: u8 };

// An item beginning with '-' is a GEM separator ("--------"): drawn, never picked.
pub fn isSeparator(item: []const u8) bool {
    return item.len > 0 and item[0] == '-';
}

pub const MenuBar = struct {
    open: i16 = -1, // index of the dropped menu, -1 = none

    fn titleBox(x: i16, m: Menu) Rect {
        return .{ .x = x - PAD, .y = 0, .w = @as(i16, @intCast(m.title.len)) * 8 + 2 * PAD, .h = MENU_H };
    }

    // GEM feel: a title drops as soon as the pointer moves over it (no click
    // needed), sliding along the bar switches menus, a click on an item picks
    // it, a click anywhere else closes the menu. Nothing drops while the button
    // is held from elsewhere (e.g. a window being dragged across the bar).
    pub fn process(self: *MenuBar, g: *Gui, menus: []const Menu, bar_w: i16, locked: bool) ?MenuPick {
        if (locked) self.open = -1; // a modal dialog owns input — bar is inert
        g.rect(.{ .x = 0, .y = 0, .w = bar_w, .h = MENU_H }, WHITE);
        g.blit.fill(g.fb, 0, MENU_H, @intCast(bar_w), 1, BLACK);

        var x: i16 = TITLE_X0;
        var pick: ?MenuPick = null;
        for (menus, 0..) |m, i| {
            const tb = titleBox(x, m);
            if (!locked and g.hit(tb) and (!g.down or g.edge)) self.open = @intCast(i);
            const hot = self.open == @as(i16, @intCast(i));
            if (hot) g.rect(tb, BLACK);
            g.text(m.title, x, 1, if (hot) WHITE else BLACK, if (hot) BLACK else WHITE);
            if (hot) pick = drop(g, m, i, tb.x);
            x += tb.w;
        }
        // a click outside the bar and the open drop-down closes it (or picks)
        if (g.edge and self.open >= 0 and g.py > MENU_H and !self.overDrop(g, menus)) self.open = -1;
        if (pick != null) self.open = -1;
        return pick;
    }

    fn dropWidth(m: Menu) i16 {
        var w: i16 = 0;
        for (m.items) |it| w = @max(w, @as(i16, @intCast(it.len)));
        return w * 8 + 2 * PAD;
    }
    fn dropRect(m: Menu, dx: i16) Rect {
        return .{ .x = dx, .y = MENU_H, .w = dropWidth(m), .h = @as(i16, @intCast(m.items.len)) * ITEM_H + 2 };
    }

    fn drop(g: *Gui, m: Menu, mi: usize, dx: i16) ?MenuPick {
        const d = dropRect(m, dx);
        g.rect(d, WHITE);
        g.frame(d, BLACK);
        var pick: ?MenuPick = null;
        for (m.items, 0..) |it, j| {
            const row = Rect{ .x = d.x + 1, .y = d.y + 1 + @as(i16, @intCast(j)) * ITEM_H, .w = d.w - 2, .h = ITEM_H };
            const hover = g.hit(row) and !isSeparator(it);
            if (hover) g.rect(row, BLACK);
            g.text(it, row.x + PAD - 1, row.y, if (hover) WHITE else BLACK, if (hover) BLACK else WHITE);
            if (g.edge and hover) pick = .{ .menu = @intCast(mi), .item = @intCast(j) };
        }
        return pick;
    }

    // Is the pointer over the currently-open drop-down (so a click shouldn't close)?
    fn overDrop(self: *MenuBar, g: *Gui, menus: []const Menu) bool {
        var x: i16 = TITLE_X0;
        for (menus, 0..) |m, i| {
            const tb = titleBox(x, m);
            if (self.open == @as(i16, @intCast(i))) return g.hit(dropRect(m, tb.x));
            x += tb.w;
        }
        return false;
    }
};
