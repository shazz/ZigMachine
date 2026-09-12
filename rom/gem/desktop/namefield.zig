// --------------------------------------------------------------------------
// NameField — the model behind the classic TOS editable 8.3 filename box: NAME padded to 8 cells,
// '.', EXT padded to 3, blanks shown as underscores, with a caret between two
// cells. Split out of info.zig so the INFORMATION dialog stays a layout file and
// the text editor is one testable component; Show Info (rename) and New Folder
// both drive the same field. PURE data + caret logic, no drawing and no ZigOS
// import, so the editing rules are covered by native `zig test`; info.zig owns
// how the 12 cells are painted.
// --------------------------------------------------------------------------
const std = @import("std");

pub const CELLS: i16 = 12; // 8 name + '.' + 3 ext

pub const NameField = struct {
    buf: [12]u8 = [_]u8{0} ** 12,
    len: u8 = 0,
    caret: u8 = 0, // edit position in buf[0..len]; 0 = before the first character

    pub fn text(self: *const NameField) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *NameField, name: []const u8) void {
        const n = @min(name.len, self.buf.len);
        @memcpy(self.buf[0..n], name[0..n]);
        self.len = @intCast(n);
        self.caret = self.len;
    }

    // A printable key. Characters are INSERTED at the caret (not appended) so a
    // name can be corrected in the middle; TOS 8.3 is upper-case and accepts only
    // letters, digits, '.' and '_'.
    pub fn insert(self: *NameField, ch: u8) void {
        if (self.len >= self.buf.len) return;
        var c = ch;
        if (c >= 'a' and c <= 'z') c -= 32;
        if (!((c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '.' or c == '_')) return;
        var i: u8 = self.len;
        while (i > self.caret) : (i -= 1) self.buf[i] = self.buf[i - 1];
        self.buf[self.caret] = c;
        self.len += 1;
        self.caret += 1;
    }

    pub fn deleteBack(self: *NameField) void {
        if (self.caret == 0) return;
        var i: u8 = self.caret - 1;
        while (i + 1 < self.len) : (i += 1) self.buf[i] = self.buf[i + 1];
        self.len -= 1;
        self.caret -= 1;
    }

    // Left/Right arrows walk the caret along the name.
    pub fn moveCaret(self: *NameField, delta: i8) void {
        if (delta < 0) {
            if (self.caret > 0) self.caret -= 1;
        } else if (self.caret < self.len) self.caret += 1;
    }

    // Which of the 12 field cells the caret sits in. The field pads NAME out to 8
    // cells and puts EXT at cells 9..11, so a caret inside the extension has to
    // skip the padding and the '.'.
    pub fn caretCol(self: *const NameField) i16 {
        if (std.mem.lastIndexOfScalar(u8, self.text(), '.')) |d| {
            if (self.caret > d) return 9 + @as(i16, @intCast(self.caret - d - 1));
        }
        return @min(@as(i16, @intCast(self.caret)), 8);
    }

    // The 12 cells as they are displayed: NAME padded to 8 with underscores, '.',
    // EXT padded to 3. Callers draw the returned buffer and put the caret at
    // caretCol().
    pub fn cells(self: *const NameField, out: *[12]u8) []const u8 {
        var base = self.text();
        var ext: []const u8 = "";
        if (std.mem.lastIndexOfScalar(u8, self.text(), '.')) |dot| {
            base = self.buf[0..dot];
            ext = self.buf[dot + 1 .. self.len];
        }
        var i: usize = 0;
        while (i < 8) : (i += 1) out[i] = if (i < base.len) base[i] else '_';
        out[8] = '.';
        i = 0;
        while (i < 3) : (i += 1) out[9 + i] = if (i < ext.len) ext[i] else '_';
        return out;
    }
};

// --- native geometry tests (run with `zig test`; gui is a wasm module, so these
// exercise the pure text/caret logic only) ---
test "the 8.3 cells pad with underscores" {
    var f = NameField{};
    var out: [12]u8 = undefined;
    f.set("AB.C");
    try std.testing.expectEqualStrings("AB______.C__", f.cells(&out));
    f.set("");
    try std.testing.expectEqualStrings("________.___", f.cells(&out));
}

test "insert at the caret, not at the end" {
    var f = NameField{};
    f.set("ALPHA.PRG");
    try std.testing.expectEqual(@as(u8, 9), f.caret);
    f.moveCaret(-1);
    f.moveCaret(-1);
    f.moveCaret(-1);
    f.moveCaret(-1); // just before the '.'
    f.insert('x'); // lower case is folded to upper
    try std.testing.expectEqualStrings("ALPHAX.PRG", f.text());
}

test "backspace deletes before the caret" {
    var f = NameField{};
    f.set("AB.C");
    f.moveCaret(-1);
    f.deleteBack(); // removes the '.'
    try std.testing.expectEqualStrings("ABC", f.text());
    try std.testing.expectEqual(@as(u8, 2), f.caret);
}

test "caret column skips the 8.3 padding" {
    var f = NameField{};
    f.set("AB.C");
    f.caret = 1;
    try std.testing.expectEqual(@as(i16, 1), f.caretCol()); // inside NAME
    f.caret = 4;
    try std.testing.expectEqual(@as(i16, 10), f.caretCol()); // after the ext's 'C'
}

test "caret clamps at both ends" {
    var f = NameField{};
    f.set("A");
    f.moveCaret(1);
    f.moveCaret(1);
    try std.testing.expectEqual(@as(u8, 1), f.caret);
    f.moveCaret(-1);
    f.moveCaret(-1);
    try std.testing.expectEqual(@as(u8, 0), f.caret);
}

test "rejects characters TOS would not accept" {
    var f = NameField{};
    f.set("A");
    f.insert('/');
    f.insert(' ');
    try std.testing.expectEqualStrings("A", f.text());
}
