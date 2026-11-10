// --------------------------------------------------------------------------
// The ITEM SELECTOR's Directory: line, as TOS's fsel_input keeps it: one path
// spec, `C:\FOLDER\*.TXT` (the folder, then the mask), shown over the 38-cell
// rule and edited in place. Clicking the line puts the caret there; Return or a
// click in the list re-reads it. A folder row opens it (the spec gains the
// folder), the list window's close box goes to the parent. PURE data, no drawing
// and no ZigOS import, so the rules are native `zig test`s; filesel.zig draws it.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX: usize = 64; // TOS's fsel path buffer is 64 bytes in the 1.x ROMs' callers
pub const CELLS: usize = 38; // the Directory: rule

pub const PathField = struct {
    buf: [MAX]u8 = [_]u8{0} ** MAX,
    len: u8 = 0,
    caret: u8 = 0,

    pub fn text(self: *const PathField) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *PathField, spec: []const u8) void {
        const n = @min(spec.len, MAX);
        @memcpy(self.buf[0..n], spec[0..n]);
        self.len = @intCast(n);
        self.caret = self.len;
    }

    /// A typed character at the caret: upper case; a path's characters only (TOS's fsel takes
    /// the drive's colon, the backslash and the wildcards; no spaces).
    pub fn insert(self: *PathField, ch: u8) void {
        if (self.len >= MAX) return;
        const c = std.ascii.toUpper(ch);
        const ok = std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, ":\\*?._-", c) != null;
        if (!ok) return;
        var i: u8 = self.len;
        while (i > self.caret) : (i -= 1) self.buf[i] = self.buf[i - 1];
        self.buf[self.caret] = c;
        self.len += 1;
        self.caret += 1;
    }

    pub fn deleteBack(self: *PathField) void {
        if (self.caret == 0) return;
        var i: u8 = self.caret - 1;
        while (i + 1 < self.len) : (i += 1) self.buf[i] = self.buf[i + 1];
        self.len -= 1;
        self.caret -= 1;
    }

    /// The folder `name` opened: `C:\*.TXT` becomes `C:\NAME\*.TXT`. False (unchanged) if it
    /// would not fit.
    pub fn enter(self: *PathField, name: []const u8) bool {
        var out: [MAX]u8 = undefined;
        const s = std.fmt.bufPrint(&out, "{s}{s}\\{s}", .{ dir(self.text()), name, mask(self.text()) }) catch return false;
        self.set(s);
        return true;
    }

    /// The parent folder: `C:\A\B\*.TXT` becomes `C:\A\*.TXT`. False at a drive's root.
    pub fn up(self: *PathField) bool {
        const d = dir(self.text());
        if (d.len < 2) return false;
        const cut = std.mem.lastIndexOfScalar(u8, d[0 .. d.len - 1], '\\') orelse return false;
        var out: [MAX]u8 = undefined;
        const s = std.fmt.bufPrint(&out, "{s}{s}", .{ d[0 .. cut + 1], mask(self.text()) }) catch return false;
        self.set(s);
        return true;
    }
};

/// The folder part of a spec, its last backslash included (`C:\A\`); "" when it has none.
pub fn dir(spec: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, spec, '\\') orelse return "";
    return spec[0 .. i + 1];
}

/// The mask part of a spec (after the last backslash); `*.*` when the spec ends at a folder.
pub fn mask(spec: []const u8) []const u8 {
    const m = spec[dir(spec).len..];
    return if (m.len == 0) "*.*" else m;
}

/// What the rule shows of a spec longer than its 38 cells: the END (the folder you are in and
/// the mask), as a field scrolled to its caret.
pub fn shown(spec: []const u8) []const u8 {
    return if (spec.len > CELLS) spec[spec.len - CELLS ..] else spec;
}

test "a folder opened and left again: the mask stays" {
    var p = PathField{};
    p.set("C:\\*.TXT");
    try std.testing.expect(p.enter("NET"));
    try std.testing.expectEqualStrings("C:\\NET\\*.TXT", p.text());
    try std.testing.expect(p.enter("SUB"));
    try std.testing.expectEqualStrings("C:\\NET\\SUB\\*.TXT", p.text());
    try std.testing.expect(p.up());
    try std.testing.expectEqualStrings("C:\\NET\\*.TXT", p.text());
    try std.testing.expect(p.up());
    try std.testing.expectEqualStrings("C:\\*.TXT", p.text());
    try std.testing.expect(!p.up()); // the root has no parent
    try std.testing.expectEqualStrings("C:\\*.TXT", p.text());
}

test "typing edits at the caret, upper case, path characters only" {
    var p = PathField{};
    p.set("C:\\*.TXT");
    for (0..3) |_| p.deleteBack();
    for ("*  ") |c| p.insert(c); // spaces refused
    try std.testing.expectEqualStrings("C:\\*.*", p.text());
    p.insert('/');
    try std.testing.expectEqualStrings("C:\\*.*", p.text());
    p.set("c:\\");
    p.insert('n');
    try std.testing.expectEqualStrings("c:\\N", p.text());
}

test "dir, mask and what the rule shows" {
    try std.testing.expectEqualStrings("C:\\A\\", dir("C:\\A\\*.TXT"));
    try std.testing.expectEqualStrings("*.TXT", mask("C:\\A\\*.TXT"));
    try std.testing.expectEqualStrings("*.*", mask("C:\\A\\"));
    try std.testing.expectEqualStrings("", dir("*.RAW"));
    const long = "C:\\AAAAAAAA\\BBBBBBBB\\CCCCCCCC\\DDDDDDDD\\*.TXT";
    try std.testing.expectEqual(CELLS, shown(long).len);
    try std.testing.expect(std.mem.endsWith(u8, long, shown(long)));
}

test "a folder that would overflow the buffer is refused, the spec kept" {
    var p = PathField{};
    p.set("C:\\" ++ "A" ** 50 ++ "\\*.TXT");
    try std.testing.expect(!p.enter("TOOLONGNAME"));
    try std.testing.expectEqual(@as(u8, 59), p.len);
}
