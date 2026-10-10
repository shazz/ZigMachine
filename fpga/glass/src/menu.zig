// The OSD menu: three pages (docs/FPGA_GLASS.md, "The menu"), each in its own
// file, and the Action a key leaves for app.zig to carry out. Pure state and
// drawing: nothing here touches a register.
//
//   shelf    the carts, the selected one's details      (page_shelf.zig)
//     > console   cold/warm reset, volume, mute, debug   (page_console.zig)
//         > debug   versions, live stats, the board      (page_debug.zig)
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const shelf = @import("shelf.zig");
const config = @import("config.zig");
const page_shelf = @import("page_shelf.zig");
const page_console = @import("page_console.zig");
const page_debug = @import("page_debug.zig");

/// `settings`: volume or mute changed (apply it now); `save`: leaving the
/// console page (persist what changed).
pub const Action = union(enum) { none, close, load: usize, cold, warm, settings, save };
pub const Page = enum { shelf, console, debug };

pub const HINT = "ENTER load  > console  F12 close";
const hints = [_][]const u8{ HINT, "ENTER do  <> change  Esc back", "read-only, live      Esc back" };

pub const Menu = struct {
    disks: []const shelf.Disk,
    page: Page = .shelf,
    list: page_shelf.State = .{},
    console: page_console.State = .{},
    settings: config.Settings = .{},
    loaded: ?usize = null, // the disk in the cart window, marked '*'
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
        };
    }

    fn shelfKey(self: *Menu, code: u32) Action {
        return switch (self.list.key(code, self.disks.len)) {
            .none => .none,
            .close => .close,
            .load => .{ .load = self.list.cursor },
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

    /// `view` is read only on the debug page (the app fills it just before).
    pub fn draw(self: *const Menu, o: *osd.Osd, view: *const page_debug.View) void {
        o.clear();
        switch (self.page) {
            .shelf => self.list.draw(o, self.disks, self.loaded, self.fps_x10),
            .console => self.console.draw(o, self.settings),
            .debug => page_debug.draw(o, view),
        }
        o.line(osd.ROWS - 1, self.status orelse hints[@intFromEnum(self.page)], false);
    }
};
