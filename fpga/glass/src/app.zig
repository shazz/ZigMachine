// The glass program's behaviour, independent of where the registers are: the
// OSD hotkey, the menu, routing keys and the pad to the cart, loading and
// resetting, and noticing a cart that died. main.zig gives it the board's
// /dev/mem windows; app_test.zig gives it the simulated ones.
//
// While the OSD is open the cart gets NO input (MiSTer's rule): every key the
// cart saw go down is released first, so nothing stays held behind the menu.
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");
const keymap = @import("keymap.zig");
const pad = @import("pad.zig");
const osd = @import("osd.zig");
const menu = @import("menu.zig");
const shelf = @import("shelf.zig");
const loader = @import("loader.zig");

const HELD_MAX = 16;
pub const OSD_FG: u32 = 0xE0E0E0;
pub const OSD_BG: u32 = 0x202848;

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
    open: bool = true,
    current: ?usize = null,
    held: [HELD_MAX]u32 = undefined,
    n_held: usize = 0,
    opt: loader.Options = .{},

    /// Check the PL, read the shelf, and show the menu.
    pub fn init(gpa: std.mem.Allocator, io: std.Io, regs: bus.Regs, ddr: bus.Ddr, dir: []const u8) !App {
        try loader.checkGlass(regs);
        const disks = try shelf.scan(gpa, io, dir);
        var app = App{ .gpa = gpa, .io = io, .regs = regs, .ddr = ddr, .shelf_dir = dir, .disks = disks, .menu = .{ .titles = disks.titles } };
        regs.write(map.REG_OSD_FG, OSD_FG);
        regs.write(map.REG_OSD_BG, OSD_BG);
        app.setOpen(true);
        return app;
    }

    pub fn deinit(self: *App) void {
        self.disks.deinit();
    }

    fn setOpen(self: *App, open: bool) void {
        if (open) self.releaseAll();
        self.open = open;
        const ctrl = self.regs.read(map.REG_CTRL) & ~map.CTRL_OSD;
        self.regs.write(map.REG_CTRL, ctrl | (if (open) map.CTRL_OSD else 0));
        self.redraw();
    }

    pub fn redraw(self: *App) void {
        self.menu.titles = self.disks.titles;
        self.menu.draw(&self.osd);
        _ = self.osd.flush(self.regs);
    }

    /// One evdev key record (value 0 up, 1 down, 2 repeat).
    pub fn key(self: *App, code: u16, value: i32) void {
        if (code == keymap.OSD_HOTKEY) {
            if (value == 1) self.setOpen(!self.open);
            return;
        }
        const ev = keymap.event(code, value, &self.mods) orelse return;
        if (self.open) return self.act(self.menu.key(ev));
        self.track(ev);
        self.regs.write(map.REG_KEY_PUSH, ev);
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
    }

    /// One evdev pad record; `range` is the device's own stick range.
    pub fn padEvent(self: *App, ev_type: u16, code: u16, value: i32, x: pad.Range, y: pad.Range) void {
        const before = self.pad.bits;
        self.pad.x = x;
        self.pad.y = y;
        if (!self.pad.update(ev_type, code, value)) return;
        if (!self.open) return self.regs.write(map.REG_JOY, self.pad.bits);
        const pressed = self.pad.bits & ~before; // the menu takes the pad's down edges as keys
        if (pressed & map.JOY_UP != 0) self.act(self.menu.key(map.KEY_ARROW_UP | map.KEY_DOWN));
        if (pressed & map.JOY_DOWN != 0) self.act(self.menu.key(map.KEY_ARROW_DOWN | map.KEY_DOWN));
        if (pressed & map.JOY_FIRE != 0) self.act(self.menu.key(map.KEY_ENTER | map.KEY_DOWN));
    }

    fn act(self: *App, action: menu.Action) void {
        switch (action) {
            .none => {},
            .close => if (self.current != null) self.setOpen(false),
            .reset => if (self.current) |i| self.load(i),
            .load => |i| self.load(i),
        }
        self.redraw();
    }

    /// Load disk `i`; on success the OSD closes on the running cart.
    pub fn load(self: *App, i: usize) void {
        self.menu.setStatus("loading {s}...", .{self.disks.titles[i]});
        self.redraw();
        self.loadDisk(i) catch |err| {
            self.current = null;
            self.menu.setStatus("{s}: {t}", .{ self.disks.disks[i].file, err });
            std.log.warn("load {s}: {t}", .{ self.disks.disks[i].file, err });
            return self.redraw();
        };
        self.current = i;
        self.menu.setStatus("{s} running", .{self.disks.titles[i]});
        self.setOpen(false);
    }

    fn loadDisk(self: *App, i: usize) !void {
        const path = try self.disks.path(self.shelf_dir, i);
        const disk = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.gpa, .limited(shelf.MAX_DISK));
        defer self.gpa.free(disk);
        const rep = try loader.load(self.gpa, self.regs, self.ddr, disk, self.opt);
        std.log.info("{s}: {d} bytes ({d} packed), up after {d} polls", .{ path, rep.image_bytes, rep.packed_bytes, rep.polls });
    }

    /// Called a few times a second: a cart that trapped brings the menu back.
    pub fn watch(self: *App) void {
        if (self.current == null) return;
        const state = self.regs.read(map.REG_CART_STATE);
        if (state & 0xFF != map.CART_TRAPPED) return;
        _ = loader.hold(self.regs) catch {};
        self.menu.setStatus("cart trapped (code {d})", .{state >> 8});
        self.current = null;
        self.setOpen(true);
    }
};
