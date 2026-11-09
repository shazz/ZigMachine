// --------------------------------------------------------------------------
// NOTEPAD's text: one flat buffer of bytes (lines end in LF) and a table of line
// starts kept in step with every edit. Integers only, no allocation: the buffer
// and the table are the caller's (notepad.zig takes them from the cart arena).
//
// An edit that adds or removes no line break shifts the starts after it; one
// that does rescans from its line on (Return, a paste of several lines). The
// limits are explicit errors, never a silent cut: Full (the bytes) and
// TooManyLines (the table).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Error = error{ Full, TooManyLines };

pub const Text = struct {
    buf: []u8, // capacity in bytes
    starts: []u32, // capacity in lines; starts[0] = 0 always
    len: u32 = 0,
    lines: u32 = 1,

    pub fn init(buf: []u8, starts: []u32) Text {
        starts[0] = 0;
        return .{ .buf = buf, .starts = starts };
    }

    pub fn clear(self: *Text) void {
        self.len = 0;
        self.lines = 1;
        self.starts[0] = 0;
    }

    pub fn bytes(self: *const Text) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn lineStart(self: *const Text, i: u32) u32 {
        return self.starts[i];
    }
    /// One past the line's last character (its LF, or the end of the text).
    pub fn lineEnd(self: *const Text, i: u32) u32 {
        return if (i + 1 < self.lines) self.starts[i + 1] - 1 else self.len;
    }
    pub fn line(self: *const Text, i: u32) []const u8 {
        return self.buf[self.lineStart(i)..self.lineEnd(i)];
    }

    /// The line holding byte `pos` (binary search over the starts).
    pub fn lineOf(self: *const Text, pos: u32) u32 {
        var lo: u32 = 0;
        var hi: u32 = self.lines;
        while (hi - lo > 1) {
            const mid = lo + (hi - lo) / 2;
            if (self.starts[mid] <= pos) lo = mid else hi = mid;
        }
        return lo;
    }

    pub fn insert(self: *Text, pos: u32, s: []const u8) Error!void {
        if (s.len == 0) return;
        if (s.len > self.buf.len - self.len) return error.Full;
        const breaks: u32 = @intCast(std.mem.count(u8, s, "\n"));
        if (self.lines + breaks > self.starts.len) return error.TooManyLines;
        const n: u32 = @intCast(s.len);
        std.mem.copyBackwards(u8, self.buf[pos + n .. self.len + n], self.buf[pos..self.len]);
        @memcpy(self.buf[pos .. pos + n], s);
        self.len += n;
        const at = self.lineOf(pos);
        if (breaks == 0) return self.shift(at + 1, n, true);
        self.rescan(at);
    }

    pub fn delete(self: *Text, pos: u32, n: u32) void {
        if (n == 0 or pos >= self.len) return;
        const k = @min(n, self.len - pos);
        const breaks = std.mem.count(u8, self.buf[pos .. pos + k], "\n");
        std.mem.copyForwards(u8, self.buf[pos .. self.len - k], self.buf[pos + k .. self.len]);
        self.len -= k;
        const at = self.lineOf(pos);
        if (breaks == 0) return self.shift(at + 1, k, false);
        self.rescan(at);
    }

    fn shift(self: *Text, from: u32, n: u32, up: bool) void {
        var i = from;
        while (i < self.lines) : (i += 1) self.starts[i] = if (up) self.starts[i] + n else self.starts[i] - n;
    }

    // The line starts from line `from` on, read off the bytes.
    fn rescan(self: *Text, from: u32) void {
        var l = from;
        var p = self.starts[from];
        while (p < self.len) : (p += 1) {
            if (self.buf[p] != '\n') continue;
            l += 1;
            self.starts[l] = p + 1;
        }
        self.lines = l + 1;
    }

    /// Replace everything with `s` (a file read): LF or CR LF line ends, CRs dropped.
    pub fn load(self: *Text, s: []const u8) Error!void {
        self.clear();
        var n: u32 = 0;
        for (s) |c| {
            if (c == '\r') continue;
            if (n == self.buf.len) return error.Full;
            self.buf[n] = c;
            n += 1;
        }
        self.len = n;
        if (std.mem.count(u8, self.buf[0..n], "\n") + 1 > self.starts.len) {
            self.clear();
            return error.TooManyLines;
        }
        self.rescan(0);
    }

    /// The longest line, in bytes (the horizontal scroll's bound).
    pub fn widest(self: *const Text) u32 {
        var w: u32 = 0;
        var i: u32 = 0;
        while (i < self.lines) : (i += 1) w = @max(w, self.lineEnd(i) - self.lineStart(i));
        return w;
    }
};

// --- native tests ------------------------------------------------------------
const testing = std.testing;

fn fresh(buf: []u8, st: []u32) Text {
    return Text.init(buf, st);
}

test "typing and Return keep the line table in step" {
    var b: [64]u8 = undefined;
    var s: [8]u32 = undefined;
    var t = fresh(&b, &s);
    try t.insert(0, "hello");
    try t.insert(5, "\nworld");
    try testing.expectEqual(@as(u32, 2), t.lines);
    try testing.expectEqualStrings("world", t.line(1));
    try t.insert(0, "> ");
    try testing.expectEqualStrings("> hello", t.line(0));
    try testing.expectEqualStrings("world", t.line(1));
    try testing.expectEqual(@as(u32, 1), t.lineOf(8));
    try testing.expectEqual(@as(u32, 0), t.lineOf(7));
}

test "deleting a line break joins the lines" {
    var b: [64]u8 = undefined;
    var s: [8]u32 = undefined;
    var t = fresh(&b, &s);
    try t.insert(0, "ab\ncd\nef");
    t.delete(2, 1);
    try testing.expectEqual(@as(u32, 2), t.lines);
    try testing.expectEqualStrings("abcd", t.line(0));
    try testing.expectEqualStrings("ef", t.line(1));
    t.delete(0, 99); // past the end: clipped
    try testing.expectEqual(@as(u32, 0), t.len);
    try testing.expectEqual(@as(u32, 1), t.lines);
}

test "the limits are errors and leave the text as it was" {
    var b: [8]u8 = undefined;
    var s: [2]u32 = undefined;
    var t = fresh(&b, &s);
    try t.insert(0, "abc\nde");
    try testing.expectError(error.Full, t.insert(0, "xyz"));
    try testing.expectError(error.TooManyLines, t.insert(0, "\n"));
    try testing.expectEqualStrings("abc\nde", t.bytes());
    try testing.expectError(error.TooManyLines, t.load("a\nb\nc"));
    try testing.expectEqual(@as(u32, 0), t.len);
}

test "load drops CRs and finds the widest line" {
    var b: [64]u8 = undefined;
    var s: [8]u32 = undefined;
    var t = fresh(&b, &s);
    try t.load("one\r\nthree33\r\n");
    try testing.expectEqual(@as(u32, 3), t.lines);
    try testing.expectEqualStrings("three33", t.line(1));
    try testing.expectEqualStrings("", t.line(2));
    try testing.expectEqual(@as(u32, 7), t.widest());
}
