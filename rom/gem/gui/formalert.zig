// --------------------------------------------------------------------------
// form_alert's string, as a TOS program writes it: "[icon][line|line][button|button]".
//
//   icon     0 none, 1 note (!), 2 question (?), 3 stop: one digit
//   lines    up to 5, '|'-separated, 40 characters at most each (TOS's limit)
//   buttons  up to 3, '|'-separated, 10 characters at most each
//
// Parsed into slices of the caller's string (the dialog copies them in at once).
// A malformed string is null: the ROM refuses it rather than guessing, as the
// AES's own parser stopped at the first bracket it did not find.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX_LINES = 5;
pub const MAX_BUTTONS = 3;
pub const LINE_MAX = 40;
pub const BUTTON_MAX = 10;

pub const Alert = struct {
    icon: u8 = 0,
    lines: [MAX_LINES][]const u8 = [_][]const u8{""} ** MAX_LINES,
    nlines: u8 = 0,
    buttons: [MAX_BUTTONS][]const u8 = [_][]const u8{""} ** MAX_BUTTONS,
    nbuttons: u8 = 0,
};

// The text between the bracket at s[at] and its closing one, and where parsing goes on.
fn field(s: []const u8, at: usize) ?struct { body: []const u8, next: usize } {
    if (at >= s.len or s[at] != '[') return null;
    const end = std.mem.indexOfScalarPos(u8, s, at + 1, ']') orelse return null;
    return .{ .body = s[at + 1 .. end], .next = end + 1 };
}

// Split `body` on '|' into `out` (each part at most `max` long, at least one character).
fn split(body: []const u8, out: [][]const u8, max: usize) ?u8 {
    var n: u8 = 0;
    var it = std.mem.splitScalar(u8, body, '|');
    while (it.next()) |part| {
        if (n == out.len or part.len > max) return null;
        out[n] = part;
        n += 1;
    }
    return n;
}

pub fn parse(s: []const u8) ?Alert {
    var a: Alert = .{};
    const icon = field(s, 0) orelse return null;
    if (icon.body.len != 1 or icon.body[0] < '0' or icon.body[0] > '3') return null;
    a.icon = icon.body[0] - '0';
    const text = field(s, icon.next) orelse return null;
    a.nlines = split(text.body, &a.lines, LINE_MAX) orelse return null;
    const btn = field(s, text.next) orelse return null;
    a.nbuttons = split(btn.body, &a.buttons, BUTTON_MAX) orelse return null;
    for (a.buttons[0..a.nbuttons]) |b| if (b.len == 0) return null;
    return a;
}

const testing = std.testing;

test "a TOS alert string parses into icon, lines and buttons" {
    const a = parse("[2][Save changes to|NOTES.TXT?][Yes|No|Cancel]").?;
    try testing.expectEqual(@as(u8, 2), a.icon);
    try testing.expectEqual(@as(u8, 2), a.nlines);
    try testing.expectEqualStrings("NOTES.TXT?", a.lines[1]);
    try testing.expectEqual(@as(u8, 3), a.nbuttons);
    try testing.expectEqualStrings("Cancel", a.buttons[2]);
}

test "malformed strings are refused" {
    try testing.expect(parse("") == null);
    try testing.expect(parse("[4][x][OK]") == null); // no such icon
    try testing.expect(parse("[1][x]") == null); // no buttons
    try testing.expect(parse("[1][x][A|B|C|D]") == null); // four buttons
    try testing.expect(parse("[1][a|b|c|d|e|f][OK]") == null); // six lines
    try testing.expect(parse("[1][x][Toolongbutton]") == null);
    try testing.expect(parse("[1][x][OK|]") == null); // an empty button
    try testing.expect(parse("[1][x][OK") == null); // unclosed
}
