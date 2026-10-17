// The glass program's behaviour, independent of where the registers are: the
// OSD hotkey, the menu, routing keys and the pad to the cart. What the menu's
// actions do (loads, resets, settings, the debug page) is app_cart.zig; the
// F11 frame-rate overlay, app_stats.zig.
// main.zig gives it the board's /dev/mem windows; the tests the simulated ones.
//
// While the OSD is open the cart gets NO input (MiSTer's rule): every key,
// pad bit and mouse button the cart saw go down is released first, so nothing
// stays held behind the menu, and the pointer stays where it was.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const mouse = @import("mouse.zig");
const osd = @import("osd.zig");
const menu = @import("menu.zig");
const shelf = @import("shelf.zig");
const loader = @import("loader.zig");
const system = @import("system.zig");
const stats = @import("stats.zig");
const cart = @import("app_cart.zig");
const overlay = @import("app_stats.zig");

const HELD_MAX = 16;
pub const OSD_FG: u32 = 0xE0E0E0;
pub const OSD_BG: u32 = 0x202848;

fn noClock() i64 {
    return 0;
}

pub const App = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    regs: bus.Regs,
    ddr: bus.Ddr,
    shelf_dir: []const u8,
    disks: shelf.Shelf,
    menu: menu.Menu,
    osd: osd.Osd = .{},
    mods: keymap.Mods = .{},
    pad: pad.Pad = .{},
    mouse: mouse.Mouse = .{},
    open: bool = true,
    current: ?usize = null, // the cart running now
    held: [HELD_MAX]u32 = undefined,
    n_held: usize = 0,
    opt: loader.Options = .{},
    stats: stats.Stats = .{},
    clock: *const fn () i64 = noClock, // ms, monotonic
    /// The board makes the read-only SD card writable for a save (true) and
    /// read-only again (false); returns false if it could not. null: always writable.
    sd_writable: ?*const fn (bool) bool = null,
    settings_dirty: bool = false,
    sys_root: []const u8 = "/", // where board_info reads /proc and /sys
    pad_name: [32]u8 = undefined,
    pad_name_len: usize = 0,
    inputs: usize = 0, // evdev nodes open (main.zig)
    ticks: u32 = 0,
    pl_stats: bool = false, // the PL can draw the F11 overlay (app_stats.supported)
    req_done: bool = false, // the running cart's cart-swap request was handled (app_request.zig)
    req_polls: u32 = 0, // polls of a request whose block did not check yet

    /// Check the PL, read the shelf and glass.cfg, and show the menu.
    pub fn init(gpa: std.mem.Allocator, io: std.Io, regs: bus.Regs, ddr: bus.Ddr, dir: []const u8) !App {
        try loader.checkGlass(regs);
        const disks = try shelf.scan(gpa, io, dir);
        var app = App{ .gpa = gpa, .io = io, .regs = regs, .ddr = ddr, .shelf_dir = dir, .disks = disks, .menu = .{ .disks = disks.disks } };
        app.pl_stats = overlay.supported(regs.read(map.REG_VERSION));
        app.opt.system = system.load(gpa, io, dir); // once: every lean cart runs on it
        regs.write(map.REG_OSD_FG, OSD_FG);
        regs.write(map.REG_OSD_BG, OSD_BG);
        cart.loadSettings(&app);
        app.setOpen(true);
        return app;
    }

    pub fn deinit(self: *App) void {
        if (self.opt.system) |s| s.deinit(self.gpa);
        self.disks.deinit();
    }

    pub fn setOpen(self: *App, open: bool) void {
        if (open) self.releaseAll();
        if (!open) cart.saveSettings(self);
        self.open = open;
        overlay.place(self);
        self.redraw();
    }

    /// The menu while it is open; the frame-rate overlay (if on) while closed.
    pub fn redraw(self: *App) void {
        if (!self.open) return overlay.draw(self);
        self.menu.disks = self.disks.disks;
        self.menu.fps_x10 = if (self.current != null) self.stats.fps_x10 else null;
        const view = if (self.menu.page == .debug) cart.debugView(self) else @import("page_debug.zig").View{};
        self.menu.draw(&self.osd, &view);
        _ = self.osd.flush(self.regs);
    }

    /// One evdev key record (value 0 up, 1 down, 2 repeat).
    pub fn key(self: *App, code: u16, value: i32) void {
        if (code == keymap.OSD_HOTKEY) {
            if (value == 1 and (self.mods.shift_l or self.mods.shift_r)) return self.rescan();
            if (value == 1) self.setOpen(!self.open);
            return;
        }
        if (code == keymap.STATS_HOTKEY) {
            if (value == 1) overlay.toggle(self);
            return;
        }
        const ev = keymap.event(code, value, &self.mods) orelse return;
        if (self.open) return cart.act(self, self.menu.key(ev));
        self.track(ev);
        self.regs.write(map.REG_KEY_PUSH, ev);
    }

    /// Shift+F12: the shelf read again (app_shelf.zig), shown in the menu.
    fn rescan(self: *App) void {
        @import("app_shelf.zig").rescan(self);
        if (self.open) self.redraw() else self.setOpen(true);
    }

    // Remember what the cart holds down, so opening the OSD can let go of it.
    fn track(self: *App, ev: u32) void {
        const code = ev & map.KEY_CODE_MASK;
        for (self.held[0..self.n_held], 0..) |h, i| if (h == code) {
            if (ev & map.KEY_DOWN == 0) {
                self.held[i] = self.held[self.n_held - 1];
                self.n_held -= 1;
            }
            return;
        };
        if (ev & map.KEY_DOWN != 0 and self.n_held < HELD_MAX) {
            self.held[self.n_held] = code;
            self.n_held += 1;
        }
    }

    fn releaseAll(self: *App) void {
        for (self.held[0..self.n_held]) |code| self.regs.write(map.REG_KEY_PUSH, code);
        self.n_held = 0;
        self.regs.write(map.REG_JOY, 0);
        if (self.mouse.release()) |w| self.regs.write(map.REG_POINTER, w);
    }

    /// One evdev mouse record (mouse.isMouse); `ms` is its timestamp.
    pub fn mouseEvent(self: *App, ev_type: u16, code: u16, value: i32, ms: i64) void {
        if (!self.open) self.mouse.update(ev_type, code, value, ms);
    }

    /// SYN_REPORT: a device finished a report, so the pointer moves once per
    /// report (x and y together), as the browser's mousemove does.
    pub fn sync(self: *App) void {
        var words: [2]u32 = undefined;
        const n = self.mouse.flush(&words);
        if (self.open) return;
        for (words[0..n]) |w| self.regs.write(map.REG_POINTER, w);
    }

    /// One evdev pad record; `range` is the device's own stick range, `name`
    /// its evdev name (the debug page shows the last pad heard from).
    pub fn padEvent(self: *App, ev_type: u16, code: u16, value: i32, x: pad.Range, y: pad.Range, name: []const u8) void {
        self.pad_name_len = @min(name.len, self.pad_name.len);
        @memcpy(self.pad_name[0..self.pad_name_len], name[0..self.pad_name_len]);
        const before = self.pad.bits;
        self.pad.x = x;
        self.pad.y = y;
        if (!self.pad.update(ev_type, code, value)) return;
        if (!self.open) return self.regs.write(map.REG_JOY, self.pad.bits);
        const pressed = self.pad.bits & ~before; // the menu takes the pad's down edges as keys
        const keys = [_][2]u32{
            .{ map.JOY_UP, map.KEY_ARROW_UP },     .{ map.JOY_DOWN, map.KEY_ARROW_DOWN },
            .{ map.JOY_LEFT, map.KEY_ARROW_LEFT }, .{ map.JOY_RIGHT, map.KEY_ARROW_RIGHT },
            .{ map.JOY_FIRE, map.KEY_ENTER },
        };
        for (keys) |k| if (pressed & k[0] != 0) cart.act(self, self.menu.key(k[1] | map.KEY_DOWN));
    }

    /// Called about ten times a second (main.zig): the watchdog, the frame-rate
    /// sample, and the live parts of the OSD (the debug page, a long name
    /// scrolling, the F11 overlay).
    pub fn tick(self: *App) void {
        cart.watch(self);
        self.ticks +%= 1;
        if (!self.open) return overlay.draw(self);
        switch (self.menu.page) {
            .debug => if (self.ticks % 5 == 0) self.redraw(),
            .shelf => if (self.ticks % 3 == 0) {
                self.menu.list.phase +%= 1;
                self.redraw();
            },
            .console => {},
        }
    }
};
