// --------------------------------------------------------------------------
// NOTEPAD's document: the text (text.zig), the cursor and the selection, the
// clipboard, and what each edit touched (`touched`), which the view turns into
// the rows to redraw. Byte offsets everywhere; a column is a byte of the line
// (a TAB shows as one cell: Notepad, not an editor). No GEM, no float: native tests.
// --------------------------------------------------------------------------
const std = @import("std");
const text_mod = @import("text.zig");
pub const Text = text_mod.Text;
pub const Error = text_mod.Error;

/// Lines an edit or a cursor move changed: [lo, hi], and `to_end` when every line after
/// lo moved (a line break added or removed). The view clears it once drawn.
pub const Touched = struct {
    lo: u32 = std.math.maxInt(u32),
    hi: u32 = 0,
    to_end: bool = false,

    pub fn add(self: *Touched, a: u32, b: u32) void {
        self.lo = @min(self.lo, @min(a, b));
        self.hi = @max(self.hi, @max(a, b));
    }
    pub fn any(self: Touched) bool {
        return self.lo <= self.hi or self.to_end;
    }
};

pub const Doc = struct {
    text: Text,
    clip: []u8, // the clipboard's storage
    clip_len: u32 = 0,
    cursor: u32 = 0,
    anchor: u32 = 0, // the selection is [min, max) of anchor and cursor
    want_col: u32 = 0, // the column Up / Down keep
    modified: bool = false,
    touched: Touched = .{},

    pub fn selLo(self: *const Doc) u32 {
        return @min(self.anchor, self.cursor);
    }
    pub fn selHi(self: *const Doc) u32 {
        return @max(self.anchor, self.cursor);
    }
    pub fn hasSel(self: *const Doc) bool {
        return self.anchor != self.cursor;
    }
    pub fn line(self: *const Doc) u32 {
        return self.text.lineOf(self.cursor);
    }
    pub fn col(self: *const Doc) u32 {
        return self.cursor - self.text.lineStart(self.line());
    }

    /// Put the cursor at `pos`; `extend` keeps the anchor (Shift, a drag).
    pub fn moveTo(self: *Doc, pos: u32, extend: bool) void {
        const p = @min(pos, self.text.len);
        const before = self.text.lineOf(self.cursor);
        const sel_before = .{ self.text.lineOf(self.selLo()), self.text.lineOf(self.selHi()) };
        self.cursor = p;
        if (!extend) self.anchor = p;
        self.touched.add(before, self.text.lineOf(p));
        self.touched.add(sel_before[0], sel_before[1]);
    }
    fn moveCol(self: *Doc, pos: u32, extend: bool) void {
        self.moveTo(pos, extend);
        self.want_col = self.col();
    }

    pub fn left(self: *Doc, extend: bool) void {
        if (!extend and self.hasSel()) return self.moveCol(self.selLo(), false);
        self.moveCol(if (self.cursor > 0) self.cursor - 1 else 0, extend);
    }
    pub fn right(self: *Doc, extend: bool) void {
        if (!extend and self.hasSel()) return self.moveCol(self.selHi(), false);
        self.moveCol(@min(self.text.len, self.cursor + 1), extend);
    }
    /// Up / Down by `n` lines (PgUp / PgDn: a window's worth), at the remembered column.
    pub fn vertical(self: *Doc, down: bool, n: u32, extend: bool) void {
        const l = self.line();
        const to = if (down) @min(self.text.lines - 1, l + n) else l -| n;
        const len = self.text.lineEnd(to) - self.text.lineStart(to);
        self.moveTo(self.text.lineStart(to) + @min(self.want_col, len), extend);
    }
    pub fn home(self: *Doc, extend: bool) void {
        self.moveCol(self.text.lineStart(self.line()), extend);
    }
    pub fn end(self: *Doc, extend: bool) void {
        self.moveCol(self.text.lineEnd(self.line()), extend);
    }
    pub fn selectAll(self: *Doc) void {
        self.anchor = 0;
        self.cursor = self.text.len;
        self.touched.add(0, self.text.lines - 1);
    }

    // Replace the selection with `s` (typing, Return, a paste). On a limit nothing changes.
    pub fn replace(self: *Doc, s: []const u8) Error!void {
        const lo = self.selLo();
        const hi = self.selHi();
        if (s.len > self.text.buf.len - (self.text.len - (hi - lo))) return error.Full;
        const breaks = std.mem.count(u8, s, "\n");
        const gone = std.mem.count(u8, self.text.buf[lo..hi], "\n");
        if (self.text.lines - gone + breaks > self.text.starts.len) return error.TooManyLines;
        const l = self.text.lineOf(lo);
        self.text.delete(lo, hi - lo);
        try self.text.insert(lo, s);
        self.cursor = lo + @as(u32, @intCast(s.len));
        self.anchor = self.cursor;
        self.want_col = self.col();
        self.modified = true;
        self.touched.add(l, self.line());
        if (breaks != 0 or gone != 0) self.touched.to_end = true;
    }
    pub fn typeChar(self: *Doc, c: u8) Error!void {
        return self.replace(&.{c});
    }
    pub fn backspace(self: *Doc) void {
        if (!self.hasSel() and self.cursor > 0) self.anchor = self.cursor - 1;
        self.replace("") catch unreachable; // removing never hits a limit
    }
    pub fn deleteFwd(self: *Doc) void {
        if (!self.hasSel() and self.cursor < self.text.len) self.anchor = self.cursor + 1;
        self.replace("") catch unreachable;
    }

    pub fn copy(self: *Doc) void {
        const s = self.text.buf[self.selLo()..self.selHi()];
        const n = @min(s.len, self.clip.len);
        @memcpy(self.clip[0..n], s[0..n]);
        self.clip_len = @intCast(n);
    }
    pub fn cut(self: *Doc) void {
        if (!self.hasSel()) return;
        self.copy();
        self.replace("") catch unreachable;
    }
    pub fn paste(self: *Doc) Error!void {
        return self.replace(self.clip[0..self.clip_len]);
    }

    /// The next `needle` after the cursor (ASCII case folded), wrapping once; selected.
    pub fn find(self: *Doc, needle: []const u8) bool {
        if (needle.len == 0) return false;
        const hay = self.text.bytes();
        const from = self.selHi();
        const at = search(hay, needle, from) orelse search(hay[0..@min(hay.len, from + needle.len)], needle, 0) orelse return false;
        self.moveTo(@intCast(at), false);
        self.moveTo(@intCast(at + needle.len), true);
        self.anchor = @intCast(at);
        return true;
    }

    /// A new text (File > New, a file read): cursor at the top, nothing modified.
    pub fn reset(self: *Doc) void {
        self.cursor = 0;
        self.anchor = 0;
        self.want_col = 0;
        self.modified = false;
        self.touched = .{ .lo = 0, .hi = 0, .to_end = true };
    }
};

fn search(hay: []const u8, needle: []const u8, from: usize) ?usize {
    if (needle.len > hay.len) return null;
    var i = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return i;
    }
    return null;
}
