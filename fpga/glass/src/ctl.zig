// The control channel's language (docs/FPGA_GLASS.md, "The control channel"): one
// line a command, as `glass ctl ...` sends it over the socket (ctl_sock.zig). It lets
// a script on the serial console do what Matt does with the OSD and a keyboard, so
// carts can be measured with nobody at the board. Pure: app_ctl.zig runs a Cmd.
//
//   load <file.zmd> [PROGRAM]    the OSD's load; PROGRAM: run that program off the disk
//   key <name|code> [down|up|tap]  a key, as the keyboard sends it (tap: down, up 100 ms later)
//   joy <bits|up+fire...>        the joypad's bits held now (0 = none)
//   stats [SECONDS]              one ZMSTAT line (zmstat.zig), over the last SECONDS (default 5)
//   osd open|close               the menu, as F12 opens and closes it
//   quit-cart                    stop the cart CPU and bring the menu up
//   list                         the shelf: one disk a line
const std = @import("std");
const map = @import("map.zig");

pub const KeyMode = enum { down, up, tap };

pub const Cmd = union(enum) {
    load: struct { file: []const u8, program: ?[]const u8 = null },
    key: struct { code: u32, mode: KeyMode = .tap },
    joy: u32,
    stats: u32, // seconds
    osd: bool, // open
    quit_cart,
    list,
    help,
};

pub const Error = error{ Empty, UnknownCommand, MissingArgument, TooManyArguments, BadKey, BadMode, BadNumber, BadJoy };

pub const DEFAULT_STATS_S: u32 = 5;
pub const MAX_STATS_S: u32 = 50; // stats.zig keeps ~51 s of beats

pub fn parse(line: []const u8) Error!Cmd {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    const word = it.next() orelse return error.Empty;
    const a1 = it.next();
    const a2 = it.next();
    if (it.next() != null) return error.TooManyArguments;
    if (eq(word, "load")) return .{ .load = .{ .file = a1 orelse return error.MissingArgument, .program = a2 } };
    if (eq(word, "key")) return .{ .key = .{ .code = try keyCode(a1 orelse return error.MissingArgument), .mode = try mode(a2) } };
    if (a2 != null) return error.TooManyArguments;
    if (eq(word, "joy")) return .{ .joy = try joyBits(a1 orelse return error.MissingArgument) };
    if (eq(word, "stats")) return .{ .stats = try seconds(a1) };
    if (eq(word, "osd")) {
        const s = a1 orelse return error.MissingArgument;
        if (eq(s, "open")) return .{ .osd = true };
        if (eq(s, "close")) return .{ .osd = false };
        return error.BadMode;
    }
    if (a1 != null) return error.TooManyArguments;
    if (eq(word, "quit-cart")) return .quit_cart;
    if (eq(word, "list")) return .list;
    if (eq(word, "help")) return .help;
    return error.UnknownCommand;
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn mode(s: ?[]const u8) Error!KeyMode {
    return std.meta.stringToEnum(KeyMode, s orelse return .tap) orelse error.BadMode;
}

fn seconds(s: ?[]const u8) Error!u32 {
    const v = std.fmt.parseInt(u32, s orelse return DEFAULT_STATS_S, 10) catch return error.BadNumber;
    if (v == 0 or v > MAX_STATS_S) return error.BadNumber;
    return v;
}

const Named = struct { []const u8, u32 };
const names = [_]Named{
    .{ "esc", map.KEY_ESCAPE },        .{ "escape", map.KEY_ESCAPE },      .{ "enter", map.KEY_ENTER },
    .{ "return", map.KEY_ENTER },      .{ "space", ' ' },                  .{ "backspace", map.KEY_BACKSPACE },
    .{ "up", map.KEY_ARROW_UP },       .{ "down", map.KEY_ARROW_DOWN },    .{ "left", map.KEY_ARROW_LEFT },
    .{ "right", map.KEY_ARROW_RIGHT }, .{ "insert", map.KEY_INSERT },      .{ "delete", map.KEY_DELETE },
    .{ "undo", map.KEY_UNDO },         .{ "help", map.KEY_HELP },          .{ "alt", map.KEY_ALT },
    .{ "shift", map.KEY_SHIFT_LEFT },  .{ "rshift", map.KEY_SHIFT_RIGHT }, .{ "ctrl", map.KEY_CTRL_LEFT },
    .{ "rctrl", map.KEY_CTRL_RIGHT },
};

/// A key as the cart sees it (map.zig KEY_*): one character is itself ("1", "a", "A"),
/// a name is a named key, f1..f10 the function keys, 0x.. or two digits or more a raw code.
pub fn keyCode(s: []const u8) Error!u32 {
    if (s.len == 1) return if (std.ascii.isPrint(s[0])) s[0] else error.BadKey;
    for (names) |n| if (eq(s, n[0])) return n[1];
    if ((s[0] == 'f' or s[0] == 'F') and s.len <= 3) {
        const n = std.fmt.parseInt(u32, s[1..], 10) catch return error.BadKey;
        if (n >= 1 and n <= 10) return map.KEY_F1 + n - 1;
        return error.BadKey;
    }
    const code = std.fmt.parseInt(u32, s, 0) catch return error.BadKey;
    if (code == 0 or code > map.KEY_CODE_MASK) return error.BadKey;
    return code;
}

/// A number (0x20 = fire), or bit names joined by '+': up, down, left, right, fire.
pub fn joyBits(s: []const u8) Error!u32 {
    if (std.ascii.isDigit(s[0])) {
        const v = std.fmt.parseInt(u32, s, 0) catch return error.BadNumber;
        if (v & ~JOY_ALL != 0) return error.BadJoy;
        return v;
    }
    var bits: u32 = 0;
    var it = std.mem.splitScalar(u8, s, '+');
    while (it.next()) |n| {
        const b: u32 = if (eq(n, "up")) map.JOY_UP else if (eq(n, "down")) map.JOY_DOWN else if (eq(n, "left")) map.JOY_LEFT else if (eq(n, "right")) map.JOY_RIGHT else if (eq(n, "fire")) map.JOY_FIRE else return error.BadJoy;
        bits |= b;
    }
    return bits;
}

pub const JOY_ALL: u32 = map.JOY_UP | map.JOY_DOWN | map.JOY_LEFT | map.JOY_RIGHT | map.JOY_FIRE;

pub const HELP =
    \\load <file.zmd> [PROGRAM] | key <char|name|f1..f10|0xCODE> [down|up|tap] | joy <bits|up+fire>
    \\stats [SECONDS] | osd open|close | quit-cart | list | help
    \\
;
