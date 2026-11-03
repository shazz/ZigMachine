// The OSD menu: five pages (docs/FPGA_GLASS.md, "The menu"), each in its own
// file, and the Action a key leaves for app.zig to carry out. Pure state and
// drawing: nothing here touches a register.
//
//   shelf    the carts, the selected one's details      (page_shelf.zig)
//     > console   cold/warm reset, volume, mute, debug   (page_console.zig)
//         > debug   versions, live stats, the board      (page_debug.zig)
//             > budget  where the frame goes; Shift+F11 too   (page_budget.zig)
//         > help    every shortcut, from one table       (page_help.zig)
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const config = @import("config.zig");
const page_shelf = @import("page_shelf.zig");
const page_console = @import("page_console.zig");
const page_debug = @import("page_debug.zig");
const page_budget = @import("page_budget.zig");
const page_help = @import("page_help.zig");
const strip = @import("strip.zig");

/// `settings`: volume or mute changed (apply it now); `save`: leaving the
/// console page (persist what changed).
/// `load`: Enter, insert + reset; `insert` / `eject`: drive A without a reset (app_drive.zig).
pub const Action = union(enum) { none, close, load: usize, insert: usize, eject, cold, warm, settings, save, source };
pub const Page = enum { shelf, console, debug, budget, help };

pub const HINT = "ENTER boot  I/E disk  F floppy >";
const hints = [_][]const u8{ HINT, "ENTER do  <> change  Esc back", "live  > budget       Esc back", "Shift+F11 close  < debug  Esc", "Up/Dn PgUp/PgDn scroll  Esc" };

pub const Menu = struct {
    disks: []const shelf.Disk,
    page: Page = .shelf,
    list: page_shelf.State = .{},
    console: page_console.State = .{},
    settings: config.Settings = .{},
    help_top: usize = 0, // the help page's first line shown
    loaded: ?usize = null, // the disk in the cart window, marked '*'
    drive: ?usize = null, // the disk in KOS's drive A, marked 'A' (app_drive.zig)
    floppy: bool = false, // the carts come from the floppy (app_source.zig): the title says so
    rotated: bool = false, // the PL's font has the strip's rotated letters (strip.supported)
    fps_x10: ?u32 = null, // the running cart's frame rate: the shelf's title shows it
    status: ?[]const u8 = null, // null: the page's own hint
    status_buf: [osd.COLS]u8 = undefined,

    /// A key event (map.KEY_*), down edges and repeats only.
    pub fn key(self: *Menu, ev: u32) Action {
        if (ev & map.KEY_DOWN == 0) return .none;
        const code = ev & map.KEY_CODE_MASK;
        return switch (self.page) {
            .shelf => self.shelfKey(code),
            .console => self.consoleKey(code),
            .debug => self.debugKey(code),
            .budget => self.budgetKey(code),
            .help => self.helpKey(code),
        };
    }

    fn shelfKey(self: *Menu, code: u32) Action {
        const view = self.list.view(self.disks);
        return switch (self.list.key(code, view.len())) {
            .none => .none,
            .close => .close,
            .open => self.open(view),
            .insert => if (self.cursorDisk(view)) |i| .{ .insert = i } else .none,
            .up => blk: {
                _ = self.list.leave(self.disks);
                break :blk .none;
            },
            .eject => .eject,
            .console => self.go(.console),
            .cold => .cold,
            .warm => .warm,
            .source => .source,
        };
    }

    /// Enter on the cursor's row: a cart loads, a folder opens, ".." goes back up.
    fn open(self: *Menu, view: page_shelf.View) Action {
        switch (view.at(self.list.cursor) orelse return .none) {
            .disk => |i| return .{ .load = i },
            .folder => |f| self.list.enter(f, self.disks),
            .up => {
                _ = self.list.leave(self.disks);
            },
        }
        return .none;
    }

    fn cursorDisk(self: *const Menu, view: page_shelf.View) ?usize {
        return switch (view.at(self.list.cursor) orelse return null) {
            .disk => |i| i,
            else => null,
        };
    }

    fn consoleKey(self: *Menu, code: u32) Action {
        return switch (self.console.key(code, &self.settings)) {
            .none => .none,
            .back => blk: {
                _ = self.go(.shelf);
                break :blk .save;
            },
            .cold => .cold,
            .warm => .warm,
            .settings => .settings,
            .debug => self.go(.debug),
            .help => self.go(.help),
        };
    }

    fn debugKey(self: *Menu, code: u32) Action {
        switch (code) {
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ENTER, ' ', map.KEY_ARROW_LEFT => return self.go(.console),
            map.KEY_ARROW_RIGHT => return self.go(.budget),
            else => return .none,
        }
    }

    fn helpKey(self: *Menu, code: u32) Action {
        if (page_help.scroll(self.help_top, code)) |top| {
            self.help_top = top;
            return .none;
        }
        switch (code) {
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ENTER, ' ', map.KEY_ARROW_LEFT => return self.go(.console),
            else => return .none,
        }
    }

    fn budgetKey(self: *Menu, code: u32) Action {
        switch (code) {
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ENTER, ' ', map.KEY_ARROW_LEFT => return self.go(.debug),
            else => return .none,
        }
    }

    fn go(self: *Menu, page: Page) Action {
        self.page = page;
        return .none;
    }

    /// The strip's name for the page: the shelf says where its carts come from.
    pub fn section(self: *const Menu) []const u8 {
        return switch (self.page) {
            .shelf => if (self.floppy) "FLOPPY" else "SHELF",
            .console => "CONSOLE",
            .debug => "DEBUG",
            .budget => "BUDGET",
            .help => "HELP",
        };
    }

    pub fn setStatus(self: *Menu, comptime fmt: []const u8, args: anytype) void {
        var w = std.Io.Writer.fixed(&self.status_buf);
        w.print(fmt, args) catch {}; // clipped to the row
        self.status = w.buffered();
    }

    /// `view` / `bview` are read only on the debug / budget page (the app fills them just before).
    pub fn draw(self: *const Menu, o: *osd.Osd, view: *const page_debug.View, bview: *const page_budget.View) void {
        o.clear();
        switch (self.page) {
            .shelf => self.list.draw(o, self.disks, .{ .loaded = self.loaded, .drive = self.drive, .floppy = self.floppy }, self.fps_x10),
            .console => self.console.draw(o, self.settings),
            .debug => page_debug.draw(o, view),
            .budget => page_budget.draw(o, bview),
            .help => page_help.draw(o, self.help_top),
        }
        strip.draw(o, self.section(), self.rotated);
        o.line(osd.ROWS - 1, self.status orelse hints[@intFromEnum(self.page)], false);
    }
};
