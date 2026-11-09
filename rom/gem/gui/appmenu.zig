// --------------------------------------------------------------------------
// A PROGRAM's menu bar (GEM 5's app API, rom/rom_app.zig): menu_bar, menu_ienable and
// menu_icheck for a cart. The desktop draws its bar every frame; a program on the
// board cannot afford that, so this one draws only when something on it changed:
//
//   - a logic pass with the Gui MUTED (clip.zig: nothing drawn) runs MenuBar.process
//     exactly as the desktop's, so the feel is the same (a title drops on hover, a
//     click on an item picks it, a click elsewhere closes);
//   - the bar and the drop-down are painted only when the open title or the hovered
//     row changed (or the program asked: menuDraw);
//   - the screen under a drop-down is SAVED and put back when it closes, as TOS's
//     AES did: the program never redraws what a menu covered.
//
// Labels are copied in (the ROM never keeps a caller's slice).
// --------------------------------------------------------------------------
const types = @import("types.zig");
const menu = @import("menu.zig");
const clip = @import("clip.zig");
const Gui = @import("core.zig").Gui;
const saveunder = @import("saveunder.zig");

pub const MAX_MENUS = 8;
pub const MAX_ITEMS = 48; // across all menus
pub const LABEL_MAX = 32;
pub const TEXT_BYTES = MAX_ITEMS * LABEL_MAX + MAX_MENUS * 16;
// A drop-down of LABEL_MAX cells and 16 rows: (32*8 + 24) x (16*8 + 2) = 36,400 bytes, in
// the program's lent scratch (rom_app.zig guiScratch).
pub const SAVE_BYTES = 36400;

pub const F_DISABLED: u32 = 1;
pub const F_CHECKED: u32 = 2;

pub const AppMenu = struct {
    text: [TEXT_BYTES]u8 = undefined,
    used: usize = 0,
    menus: [MAX_MENUS]menu.Menu = undefined,
    first: [MAX_MENUS]u8 = undefined, // each menu's first item in `items`
    items: [MAX_ITEMS]menu.MenuItem = undefined,
    nmenus: u8 = 0,
    nitems: u8 = 0,
    bar: menu.MenuBar = .{},
    shown_open: i16 = -1,
    shown_hover: i16 = -1,
    must: bool = true, // paint the bar at the next process
    under: saveunder.Box = .{}, // its buffer is lent (guiScratch); none: drawn without save-under

    pub fn reset(self: *AppMenu) void {
        self.used = 0;
        self.nmenus = 0;
        self.nitems = 0;
        self.bar = .{};
        self.shown_open = -1;
        self.shown_hover = -1;
        self.must = true;
        self.under.at = null;
    }

    fn keep(self: *AppMenu, s: []const u8) ?[]const u8 {
        const n = @min(s.len, LABEL_MAX);
        if (self.used + n > self.text.len) return null;
        @memcpy(self.text[self.used .. self.used + n], s[0..n]);
        defer self.used += n;
        return self.text[self.used .. self.used + n];
    }

    /// A new title on the bar; its items follow. False when full.
    pub fn title(self: *AppMenu, s: []const u8) bool {
        if (self.nmenus == MAX_MENUS) return false;
        const t = self.keep(s) orelse return false;
        self.first[self.nmenus] = self.nitems;
        self.menus[self.nmenus] = .{ .title = t, .items = self.items[self.nitems..self.nitems] };
        self.nmenus += 1;
        self.must = true;
        return true;
    }

    /// An item under the last title ('-' first: a separator). False when full or no title.
    pub fn item(self: *AppMenu, s: []const u8, flags: u32) bool {
        if (self.nmenus == 0 or self.nitems == MAX_ITEMS) return false;
        const l = self.keep(s) orelse return false;
        self.items[self.nitems] = .{ .label = l, .disabled = flags & F_DISABLED != 0, .tick = flags & F_CHECKED != 0 };
        self.nitems += 1;
        const m = &self.menus[self.nmenus - 1];
        m.items = self.items[self.first[self.nmenus - 1]..self.nitems];
        return true;
    }

    /// menu_ienable / menu_icheck: item `i` of menu `m`. False for no such item.
    pub fn setFlags(self: *AppMenu, m: u32, i: u32, flags: u32) bool {
        if (m >= self.nmenus or i >= self.menus[m].items.len) return false;
        const it = &self.items[self.first[m] + i];
        const was = it.*;
        it.disabled = flags & F_DISABLED != 0;
        it.tick = flags & F_CHECKED != 0;
        if (self.shown_open == @as(i16, @intCast(m)) and (was.disabled != it.disabled or was.tick != it.tick)) self.must = true;
        return true;
    }

    pub fn busy(self: *const AppMenu) bool {
        return self.bar.open >= 0;
    }

    fn plane(g: *Gui) saveunder.Plane {
        return .{ .pix = g.fb.fb, .stride = g.fb.stride, .w = g.screen.w, .h = g.screen.h };
    }

    /// One frame: the pick as (menu << 8 | item) + 1, 0 for none. `locked`: a dialog is up.
    pub fn process(self: *AppMenu, g: *Gui, locked: bool) u32 {
        const menus = self.menus[0..self.nmenus];
        const was_clip = g.clip;
        g.clip = clip.MUTED; // the logic pass: the desktop's own code, no pixel
        const pick = self.bar.process(g, menus, g.screen.w, locked);
        g.clip = was_clip;
        const open = self.bar.open;
        const hover = self.bar.hoverRow(menus, g.px, g.py);
        if (self.must or open != self.shown_open or hover != self.shown_hover) self.paint(g, menus, locked);
        return if (pick) |p| (@as(u32, p.menu) << 8 | p.item) + 1 else 0;
    }

    // The bar (and the open drop-down) as they are now: the screen under a closing
    // drop-down back first, the screen under an opening one kept first.
    fn paint(self: *AppMenu, g: *Gui, menus: []const menu.Menu, locked: bool) void {
        const p = plane(g);
        const open = self.bar.open;
        if (open != self.shown_open) self.under.restore(p);
        if (open >= 0 and self.under.at == null) {
            if (self.bar.dropBox(menus)) |d| _ = self.under.save(p, .{ .x = d.x, .y = d.y, .w = d.w, .h = d.h });
        }
        // The draw pass runs the same process again: with the same input it reaches the
        // same state (it is idempotent within a frame), and its pick is the logic pass's.
        _ = self.bar.process(g, menus, g.screen.w, locked);
        self.bar.open = open;
        self.shown_open = open;
        self.shown_hover = self.bar.hoverRow(menus, g.px, g.py);
        self.must = false;
    }
};
