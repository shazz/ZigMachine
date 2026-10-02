// USB keyboard -> the glass's key events. Linux hands us evdev key codes
// (linux/input-event-codes.h, which are layout-blind scan positions); this
// turns them into what the browser hands a cart (docs/sealed-loader.js): the
// character a US keyboard types, or the private-use code of a named key.
//
// The keymap is US. A cart sees characters, so another layout is another
// table here, never a change in the cart (zeST does the same with its kb_*.prg).
const std = @import("std");
const map = @import("map.zig");

// evdev codes this file names (linux/input-event-codes.h).
pub const KEY_ESC = 1;
pub const KEY_BACKSPACE = 14;
pub const KEY_ENTER = 28;
pub const KEY_LEFTCTRL = 29;
pub const KEY_LEFTSHIFT = 42;
pub const KEY_RIGHTSHIFT = 54;
pub const KEY_SPACE = 57;
pub const KEY_CAPSLOCK = 58;
pub const KEY_F1 = 59; // F1..F10 = 59..68
pub const KEY_F11 = 87;
pub const KEY_F12 = 88;
pub const KEY_KPENTER = 96;
pub const KEY_RIGHTCTRL = 97;
pub const KEY_HOME = 102;
pub const KEY_UP = 103;
pub const KEY_PAGEUP = 104;
pub const KEY_LEFT = 105;
pub const KEY_RIGHT = 106;
pub const KEY_END = 107;
pub const KEY_DOWN = 108;
pub const KEY_PAGEDOWN = 109;
pub const KEY_INSERT = 110;
pub const KEY_DELETE = 111;
pub const KEY_UNDO = 131;
pub const KEY_HELP = 138;

/// The hotkey that opens and closes the OSD, MiSTer's choice; it never reaches a cart.
pub const OSD_HOTKEY = KEY_F12;

// Printable rows by evdev code: codes 2..13, 16..27, 30..41, 43..53.
const Row = struct { first: u16, plain: []const u8, shifted: []const u8 };
const rows = [_]Row{
    .{ .first = 2, .plain = "1234567890-=", .shifted = "!@#$%^&*()_+" },
    .{ .first = 16, .plain = "qwertyuiop[]", .shifted = "QWERTYUIOP{}" },
    .{ .first = 30, .plain = "asdfghjkl;'`", .shifted = "ASDFGHJKL:\"~" },
    .{ .first = 43, .plain = "\\zxcvbnm,./", .shifted = "|ZXCVBNM<>?" },
};

pub const Mods = struct {
    shift_l: bool = false,
    shift_r: bool = false,
    caps: bool = false,

    fn shifted(self: Mods, c: u8) bool {
        const letter = std.ascii.isAlphabetic(c);
        return (self.shift_l or self.shift_r) != (letter and self.caps);
    }
};

fn printable(code: u16, mods: Mods) ?u32 {
    if (code == KEY_SPACE) return ' ';
    for (rows) |row| {
        if (code < row.first or code >= row.first + row.plain.len) continue;
        const c = row.plain[code - row.first];
        return if (mods.shifted(c)) row.shifted[code - row.first] else c;
    }
    return null;
}

fn named(code: u16) ?u32 {
    if (code >= KEY_F1 and code < KEY_F1 + 10) return map.KEY_F1 + (code - KEY_F1);
    return switch (code) {
        KEY_ESC => map.KEY_ESCAPE,
        KEY_BACKSPACE => map.KEY_BACKSPACE,
        KEY_ENTER, KEY_KPENTER => map.KEY_ENTER,
        KEY_UP => map.KEY_ARROW_UP,
        KEY_DOWN => map.KEY_ARROW_DOWN,
        KEY_LEFT => map.KEY_ARROW_LEFT,
        KEY_RIGHT => map.KEY_ARROW_RIGHT,
        KEY_INSERT => map.KEY_INSERT,
        KEY_DELETE => map.KEY_DELETE,
        KEY_UNDO => map.KEY_UNDO,
        KEY_HELP => map.KEY_HELP,
        KEY_LEFTCTRL => map.KEY_CTRL_LEFT,
        KEY_RIGHTCTRL => map.KEY_CTRL_RIGHT,
        KEY_LEFTSHIFT => map.KEY_SHIFT_LEFT,
        KEY_RIGHTSHIFT => map.KEY_SHIFT_RIGHT,
        else => null,
    };
}

/// evdev value: 0 = release, 1 = press, 2 = auto-repeat.
pub fn event(code: u16, value: i32, mods: *Mods) ?u32 {
    const down = value != 0;
    switch (code) {
        KEY_LEFTSHIFT => mods.shift_l = down,
        KEY_RIGHTSHIFT => mods.shift_r = down,
        KEY_CAPSLOCK => if (value == 1) {
            mods.caps = !mods.caps;
        },
        else => {},
    }
    const c = named(code) orelse printable(code, mods.*) orelse return null;
    var e: u32 = c;
    if (down) e |= map.KEY_DOWN;
    if (value == 2) e |= map.KEY_REPEAT;
    return e;
}

test "letters, shift, caps lock and symbols type what a US keyboard types" {
    var m = Mods{};
    try std.testing.expectEqual(@as(?u32, 'q' | map.KEY_DOWN), event(16, 1, &m));
    _ = event(KEY_LEFTSHIFT, 1, &m);
    try std.testing.expectEqual(@as(?u32, 'Q' | map.KEY_DOWN), event(16, 1, &m));
    try std.testing.expectEqual(@as(?u32, '!' | map.KEY_DOWN), event(2, 1, &m));
    _ = event(KEY_LEFTSHIFT, 0, &m);
    _ = event(KEY_CAPSLOCK, 1, &m);
    try std.testing.expectEqual(@as(?u32, 'A' | map.KEY_DOWN), event(30, 1, &m));
    try std.testing.expectEqual(@as(?u32, '1' | map.KEY_DOWN), event(2, 1, &m)); // caps leaves digits
    try std.testing.expectEqual(@as(?u32, '/'), event(53, 0, &m)); // a release
    try std.testing.expectEqual(@as(?u32, ' ' | map.KEY_DOWN | map.KEY_REPEAT), event(KEY_SPACE, 2, &m));
}

test "named keys use the browser's codes; unknown keys send nothing" {
    var m = Mods{};
    try std.testing.expectEqual(@as(?u32, 0xE012 | map.KEY_DOWN), event(KEY_ESC, 1, &m));
    try std.testing.expectEqual(@as(?u32, 0xE00A | map.KEY_DOWN), event(68, 1, &m)); // F10
    try std.testing.expectEqual(@as(?u32, map.KEY_ARROW_LEFT | map.KEY_DOWN), event(KEY_LEFT, 1, &m));
    try std.testing.expectEqual(@as(?u32, 13 | map.KEY_DOWN), event(KEY_KPENTER, 1, &m));
    try std.testing.expectEqual(@as(?u32, map.KEY_SHIFT_RIGHT | map.KEY_DOWN), event(KEY_RIGHTSHIFT, 1, &m));
    try std.testing.expectEqual(@as(?u32, null), event(KEY_F11, 1, &m)); // the browser has no F11 code
    try std.testing.expectEqual(@as(?u32, null), event(KEY_CAPSLOCK, 1, &m));
    try std.testing.expectEqual(@as(?u32, null), event(240, 1, &m));
}
