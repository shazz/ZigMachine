// --------------------------------------------------------------------------
// objc_edit's ED_CHAR for a program's editable text (G_FTEXT / G_FBOXTEXT, G20):
// one key into the TEDINFO's te_ptext, at the caret, by the AES's rules. The text
// is NUL-terminated in the program's buffer (te_txtlen bytes with the NUL), at most
// as many characters as the template has underscores; "@" first is an empty field.
// te_pvalid says, per position, what may be typed (the last character repeats):
//   9 digits, A upper-case letters + space, a letters + space, N upper alnum + space,
//   n alnum + space, F a file-name character (upper case, ? *), P a path character
//   (F + \ :), p as P without the wildcards, X anything, x anything upper-cased.
// Backspace (8) rubs out the character before the caret, Delete (127) the one at it,
// Escape (27) empties the field. Pure: native tests (rom/gem/gui_obj_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Result = struct { idx: usize, changed: bool };

fn len(buf: []const u8) usize {
    if (buf.len > 0 and buf[0] == '@') return 0;
    return std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
}

fn slots(tmplt: []const u8) usize {
    return std.mem.count(u8, tmplt, "_");
}

/// `key` filtered by validation character `v`: the character to store, or null (refused).
pub fn accept(v: u8, key: u8) ?u8 {
    const up = std.ascii.toUpper(key);
    const alpha = std.ascii.isAlphabetic(key);
    const digit = std.ascii.isDigit(key);
    const file = alpha or digit or std.mem.indexOfScalar(u8, "_-!#$%&'()@^`{}~", key) != null;
    return switch (v) {
        '9' => if (digit) key else null,
        'A' => if (alpha or key == ' ') up else null,
        'a' => if (alpha or key == ' ') key else null,
        'N' => if (alpha or digit or key == ' ') up else null,
        'n' => if (alpha or digit or key == ' ') key else null,
        'F' => if (file or key == '?' or key == '*') up else null,
        'P' => if (file or key == '?' or key == '*' or key == '\\' or key == ':') up else null,
        'p' => if (file or key == '\\' or key == ':') up else null,
        'x' => if (key >= 32 and key < 127) up else null,
        else => if (key >= 32 and key < 127) key else null, // 'X' and anything unknown
    };
}

/// One key at caret `idx` into `buf` (the te_ptext buffer, its NUL included).
pub fn edit(buf: []u8, tmplt: []const u8, valid: []const u8, idx_in: usize, k: u8) Result {
    var n = len(buf);
    if (n == 0 and buf.len > 0) buf[0] = 0; // "@": the field starts empty
    const idx = @min(idx_in, n);
    const cap = @min(slots(tmplt), if (buf.len > 0) buf.len - 1 else 0);
    switch (k) {
        27 => {
            if (buf.len > 0) buf[0] = 0;
            return .{ .idx = 0, .changed = n > 0 };
        },
        8, 127 => {
            const at = if (k == 8) (if (idx == 0) return .{ .idx = 0, .changed = false } else idx - 1) else idx;
            if (at >= n) return .{ .idx = idx, .changed = false };
            std.mem.copyForwards(u8, buf[at .. n - 1], buf[at + 1 .. n]);
            n -= 1;
            buf[n] = 0;
            return .{ .idx = at, .changed = true };
        },
        else => {},
    }
    if (n >= cap) return .{ .idx = idx, .changed = false };
    const v = if (valid.len == 0) 'X' else valid[@min(idx, valid.len - 1)];
    const c = accept(v, k) orelse return .{ .idx = idx, .changed = false };
    std.mem.copyBackwards(u8, buf[idx + 1 .. n + 1], buf[idx..n]);
    buf[idx] = c;
    buf[n + 1] = 0;
    return .{ .idx = idx + 1, .changed = true };
}

const expect = std.testing.expect;

test "digits go in by the template, letters are refused, the field fills up" {
    var buf: [7]u8 = "@\x00\x00\x00\x00\x00\x00".*;
    var r = edit(&buf, "__/__/__", "999999", 0, '0');
    try expect(r.changed and r.idx == 1 and buf[0] == '0' and buf[1] == 0);
    r = edit(&buf, "__/__/__", "999999", r.idx, 'x');
    try expect(!r.changed and r.idx == 1);
    for ("91126") |c| r = edit(&buf, "__/__/__", "999999", r.idx, c);
    try expect(std.mem.eql(u8, buf[0..6], "091126") and r.idx == 6);
    r = edit(&buf, "__/__/__", "999999", r.idx, '7');
    try expect(!r.changed); // six underscores: full
}

test "backspace, delete and escape; upper-casing file names" {
    var buf: [10]u8 = "AB\x00\x00\x00\x00\x00\x00\x00\x00".*;
    var r = edit(&buf, "________", "F", 2, 8);
    try expect(r.idx == 1 and std.mem.eql(u8, buf[0..2], "A\x00"));
    r = edit(&buf, "________", "F", 0, 127);
    try expect(r.changed and buf[0] == 0);
    r = edit(&buf, "________", "F", 0, 'q');
    try expect(buf[0] == 'Q');
    r = edit(&buf, "________", "F", 1, 27);
    try expect(r.idx == 0 and buf[0] == 0);
    try expect(accept('9', 'a') == null and accept('A', 'b').? == 'B' and accept('X', '/').? == '/');
}
