// The help page (console > Help...): every shortcut, grouped by where it works, drawn
// from ONE table that page_help_test.zig replays against the real key handling, so a key
// the table names but no page takes (or a page renamed) fails the build, not the user.
//
//   row 0       title bar: which lines are shown, of how many
//   rows 1..14  the table, 30 wide right of the section strip; Up/Down/PgUp/PgDn scroll it
//   row 15      status
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const keymap = @import("keymap.zig");

pub const Group = enum { global, shelf, console, debug, budget, help };

/// How the test proves the key is handled where the table says.
pub const Check = union(enum) {
    menu: []const u32, // map.KEY_* events, each must do something on the group's page
    evdev: struct { code: u16, shift: bool = false }, // a hotkey App.key takes before the menu
    pad: u32, // a JOY_* bit the menu takes as a key
    shift_reset, // Shift held at a reset: app_drive.flags skips the POST
};

pub const Entry = struct { group: Group, keys: []const u8, what: []const u8, check: Check };

const K = map;
pub const table = [_]Entry{
    .{ .group = .global, .keys = "F12", .what = "open/close the OSD", .check = .{ .evdev = .{ .code = keymap.OSD_HOTKEY } } },
    .{ .group = .global, .keys = "Shift+F12", .what = "rescan shelf/floppy", .check = .{ .evdev = .{ .code = keymap.OSD_HOTKEY, .shift = true } } },
    .{ .group = .global, .keys = "F11", .what = "fps overlay on/off", .check = .{ .evdev = .{ .code = keymap.STATS_HOTKEY } } },
    .{ .group = .global, .keys = "Shift+F11", .what = "frame budget page", .check = .{ .evdev = .{ .code = keymap.STATS_HOTKEY, .shift = true } } },
    .{ .group = .global, .keys = "Pad d-pad", .what = "the arrow keys", .check = .{ .pad = K.JOY_DOWN } },
    .{ .group = .global, .keys = "Pad fire", .what = "Enter", .check = .{ .pad = K.JOY_FIRE } },
    .{ .group = .shelf, .keys = "Up/Down", .what = "select a cart", .check = .{ .menu = &.{ K.KEY_ARROW_UP, K.KEY_ARROW_DOWN } } },
    .{ .group = .shelf, .keys = "PgUp/PgDn", .what = "a screenful", .check = .{ .menu = &.{ K.KEY_PAGE_UP, K.KEY_PAGE_DOWN } } },
    .{ .group = .shelf, .keys = "Enter", .what = "insert in A + reset", .check = .{ .menu = &.{ K.KEY_ENTER, ' ' } } },
    .{ .group = .shelf, .keys = "Enter", .what = "on a folder: open", .check = .{ .menu = &.{K.KEY_ENTER} } },
    .{ .group = .shelf, .keys = "Left/Bksp", .what = "folder: back up", .check = .{ .menu = &.{ K.KEY_ARROW_LEFT, K.KEY_BACKSPACE } } },
    .{ .group = .shelf, .keys = "I / E", .what = "insert/eject A", .check = .{ .menu = &.{ 'i', 'e' } } },
    .{ .group = .shelf, .keys = "R / W", .what = "cold/warm reset", .check = .{ .menu = &.{ 'r', 'w' } } },
    .{ .group = .shelf, .keys = "Shift", .what = "+R/W/Enter: no POST", .check = .shift_reset },
    .{ .group = .shelf, .keys = "F", .what = "SD card / floppy", .check = .{ .menu = &.{'f'} } },
    .{ .group = .shelf, .keys = "Right", .what = "console page", .check = .{ .menu = &.{K.KEY_ARROW_RIGHT} } },
    .{ .group = .shelf, .keys = "Esc", .what = "close the OSD", .check = .{ .menu = &.{K.KEY_ESCAPE} } },
    .{ .group = .console, .keys = "Up/Down", .what = "select an item", .check = .{ .menu = &.{ K.KEY_ARROW_UP, K.KEY_ARROW_DOWN } } },
    .{ .group = .console, .keys = "Enter", .what = "do the item", .check = .{ .menu = &.{ K.KEY_ENTER, ' ' } } },
    .{ .group = .console, .keys = "Left/Right", .what = "volume, mute", .check = .{ .menu = &.{ K.KEY_ARROW_LEFT, K.KEY_ARROW_RIGHT } } },
    .{ .group = .console, .keys = "Esc/Bksp", .what = "back to the shelf", .check = .{ .menu = &.{ K.KEY_ESCAPE, K.KEY_BACKSPACE } } },
    .{ .group = .debug, .keys = "Right", .what = "frame budget page", .check = .{ .menu = &.{K.KEY_ARROW_RIGHT} } },
    .{ .group = .debug, .keys = "Left/Esc", .what = "back to console", .check = .{ .menu = &.{ K.KEY_ARROW_LEFT, K.KEY_ESCAPE, K.KEY_BACKSPACE } } },
    .{ .group = .budget, .keys = "Left/Esc", .what = "back to debug", .check = .{ .menu = &.{ K.KEY_ARROW_LEFT, K.KEY_ESCAPE, K.KEY_BACKSPACE } } },
    .{ .group = .help, .keys = "Up/Down", .what = "scroll", .check = .{ .menu = &.{ K.KEY_ARROW_UP, K.KEY_ARROW_DOWN } } },
    .{ .group = .help, .keys = "PgUp/PgDn", .what = "scroll a screenful", .check = .{ .menu = &.{ K.KEY_PAGE_UP, K.KEY_PAGE_DOWN } } },
    .{ .group = .help, .keys = "Left/Esc", .what = "back to console", .check = .{ .menu = &.{ K.KEY_ARROW_LEFT, K.KEY_ESCAPE, K.KEY_BACKSPACE } } },
};

const KEYS_W = 11;
const headings = [_][]const u8{ "GLOBAL", "SHELF", "CONSOLE", "DEBUG", "BUDGET", "HELP" };

/// The page's lines: a ruled heading before each group, then "<keys><what>".
pub const lines = build();
pub const SHOWN = osd.ROWS - 2;
pub const MAX_TOP = lines.len -| SHOWN;

fn build() [table.len + headings.len][]const u8 {
    @setEvalBranchQuota(20_000);
    var out: [table.len + headings.len][]const u8 = undefined;
    var n = 0;
    var last: ?Group = null;
    for (table) |e| {
        if (last != e.group) {
            const h = headings[@intFromEnum(e.group)];
            out[n] = h ++ " " ++ "-" ** (osd.BODY_W - h.len - 1);
            n += 1;
            last = e.group;
        }
        if (e.keys.len >= KEYS_W or KEYS_W + e.what.len > osd.BODY_W) @compileError("help line too wide: " ++ e.keys);
        out[n] = e.keys ++ " " ** (KEYS_W - e.keys.len) ++ e.what;
        n += 1;
    }
    if (n != out.len) @compileError("the table's groups must be contiguous, in Group order");
    return out;
}

/// `top`: the first line shown (Menu.help_top, kept within MAX_TOP).
pub fn draw(o: *osd.Osd, top: usize) void {
    var bar: [osd.COLS]u8 = undefined;
    const end = @min(top + SHOWN, lines.len);
    const title = std.fmt.bufPrint(&bar, " ZIGMACHINE  HELP  {d:>2}-{d:>2}/{d:<2}  Esc", .{ top + 1, end, lines.len });
    o.line(0, title catch "", true);
    for (lines[top..end], 0..) |l, i| o.body(@intCast(1 + i), l, false);
}

/// The scroll keys: the new top, or null when `code` is not one of them.
pub fn scroll(top: usize, code: u32) ?usize {
    return switch (code) {
        map.KEY_ARROW_UP => top -| 1,
        map.KEY_ARROW_DOWN => @min(top + 1, MAX_TOP),
        map.KEY_PAGE_UP => top -| SHOWN,
        map.KEY_PAGE_DOWN => @min(top + SHOWN, MAX_TOP),
        else => null,
    };
}
