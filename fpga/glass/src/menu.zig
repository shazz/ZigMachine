// The OSD menu: three pages (docs/FPGA_GLASS.md, "The menu"), each in its own
// file, and the Action a key leaves for app.zig to carry out. Pure state and
// drawing: nothing here touches a register.
//
//   shelf    the carts, the selected one's details      (page_shelf.zig)
//     > console   cold/warm reset, volume, mute, debug   (page_console.zig)
//         > debug   versions, live stats, the board      (page_debug.zig)
//             > budget  where the frame goes; Shift+F11 too   (page_budget.zig)
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const config = @import("config.zig");
const page_shelf = @import("page_shelf.zig");
const page_console = @import("page_console.zig");
const page_debug = @import("page_debug.zig");
const page_budget = @import("page_budget.zig");

/// `settings`: volume or mute changed (apply it now); `save`: leaving the
/// console page (persist what changed).
/// `load`: Enter, insert + reset; `insert` / `eject`: drive A without a reset (app_drive.zig).
pub const Action = union(enum) { none, close, load: usize, insert: usize, eject, cold, warm, settings, save };
pub const Page = enum { shelf, console, debug, budget };

pub const HINT = "ENTER boot  I/E disk  > console";
const hints = [_][]const u8{ HINT, "ENTER do  <> change  Esc back", "live  > budget       Esc back", "Shift+F11 close  < debug  Esc" };

pub const Menu = struct {
    disks: []const shelf.Disk,
    page: Page = .shelf,
    list: page_shelf.State = .{},
    console: page_console.State = .{},
    settings: config.Settings = .{},
    loaded: ?usize = null, // the disk in the cart window, marked '*'
    drive: ?usize = null, // the disk in KOS's drive A, marked 'A' (app_drive.zig)
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
        };
    }

    fn shelfKey(self: *Menu, code: u32) Action {
        return switch (self.list.key(code, self.disks.len)) {
            .none => .none,
            .close => .close,
            .load => .{ .load = self.list.cursor },
            .insert => .{ .insert = self.list.cursor },
            .eject => .eject,
            .console => self.go(.console),
            .cold => .cold,
            .warm => .warm,
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
        };
    }

    fn debugKey(self: *Menu, code: u32) Action {
        switch (code) {
            map.KEY_ESCAPE, map.KEY_BACKSPACE, map.KEY_ENTER, ' ', map.KEY_ARROW_LEFT => return self.go(.console),
            map.KEY_ARROW_RIGHT => return self.go(.budget),
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

    pub fn setStatus(self: *Menu, comptime fmt: []const u8, args: anytype) void {
        var w = std.Io.Writer.fixed(&self.status_buf);
        w.print(fmt, args) catch {}; // clipped to the row
        self.status = w.buffered();
    }

    /// `view` / `bview` are read only on the debug / budget page (the app fills them just before).
    pub fn draw(self: *const Menu, o: *osd.Osd, view: *const page_debug.View, bview: *const page_budget.View) void {
        o.clear();
        switch (self.page) {
            .shelf => self.list.draw(o, self.disks, .{ .loaded = self.loaded, .drive = self.drive }, self.fps_x10),
            .console => self.console.draw(o, self.settings),
            .debug => page_debug.draw(o, view),
            .budget => page_budget.draw(o, bview),
        }
        o.line(osd.ROWS - 1, self.status orelse hints[@intFromEnum(self.page)], false);
    }
};
